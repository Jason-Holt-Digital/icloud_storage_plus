import Foundation

/// Distinctly surfaces coordinator failures vs inner-IO failures across
/// the `DispatchQueue.global`-bridged continuation so callers can map
/// each kind to the appropriate stable channel error (R14:
/// coordinator-error vs inner-IO-error, never collapsed, never a silent
/// null/false success).
enum CoordinateBridgeError: Error {
    /// `NSFileCoordinator.coordinate(...)` reported a coordination
    /// failure; the accessor closure never ran.
    case coordination(NSError)
    /// The accessor closure threw an inner IO error.
    case accessor(Error)
}

/// Async bridges for `NSFileCoordinator.coordinate(...)` (synchronous,
/// blocking) that hop the blocking call onto a `DispatchQueue.global`
/// worker via a single-resume continuation, so the Swift cooperative
/// pool is never blocked by coordination.
///
/// This is the SAME deadlock-free pattern as
/// `CoordinatedReplaceWriter.liveCoordinateReplace`: the accessor runs
/// synchronously on the dispatch worker per Apple's contract; no
/// `DispatchSemaphore`, no inner `Task`, no cooperative-pool starvation
/// surface. The cooperative-pool task suspends at the continuation
/// while coordination runs on a libdispatch worker, so even a burst of
/// concurrent coordinated delete/move/copy ops cannot starve other
/// Swift async work.
///
/// Failures are surfaced as `CoordinateBridgeError` so callers can
/// distinguish coordination failure from inner-IO failure and map them
/// to distinct stable channel codes/messages byte-for-byte.
enum CoordinatedIO {
    /// Bridges `coordinate(writingItemAt:options:error:byAccessor:)`.
    static func coordinateWriting(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        qos: DispatchQoS.QoSClass = .userInitiated,
        accessor: @escaping @Sendable (URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: qos).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var accessError: Error?

                coordinator.coordinate(
                    writingItemAt: url,
                    options: options,
                    error: &coordinationError
                ) { coordinatedURL in
                    do {
                        try accessor(coordinatedURL)
                    } catch {
                        accessError = error
                    }
                }

                Self.resume(continuation, coordination: coordinationError, access: accessError)
            }
        }
    }

    /// Bridges
    /// `coordinate(writingItemAt:options:writingItemAt:options:error:byAccessor:)`
    /// (two writing endpoints — used for coordinated move).
    static func coordinateWritingTwo(
        writingAt firstURL: URL,
        options firstOptions: NSFileCoordinator.WritingOptions,
        writingAt secondURL: URL,
        options secondOptions: NSFileCoordinator.WritingOptions,
        qos: DispatchQoS.QoSClass = .userInitiated,
        accessor: @escaping @Sendable (URL, URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: qos).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var accessError: Error?

                coordinator.coordinate(
                    writingItemAt: firstURL,
                    options: firstOptions,
                    writingItemAt: secondURL,
                    options: secondOptions,
                    error: &coordinationError
                ) { firstCoordinatedURL, secondCoordinatedURL in
                    do {
                        try accessor(firstCoordinatedURL, secondCoordinatedURL)
                    } catch {
                        accessError = error
                    }
                }

                Self.resume(continuation, coordination: coordinationError, access: accessError)
            }
        }
    }

    /// Bridges `coordinate(readingItemAt:options:error:byAccessor:)`
    /// and returns a value computed inside the accessor (used for the
    /// copy overwrite-pre-check, which reports whether an existing
    /// destination was overwritten).
    static func coordinateReadingReturning<T: Sendable>(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        qos: DispatchQoS.QoSClass = .userInitiated,
        accessor: @escaping @Sendable (URL) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: qos).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var accessError: Error?
                var result: T?

                coordinator.coordinate(
                    readingItemAt: url,
                    options: options,
                    error: &coordinationError
                ) { coordinatedURL in
                    do {
                        result = try accessor(coordinatedURL)
                    } catch {
                        accessError = error
                    }
                }

                if let coordinationError {
                    continuation.resume(throwing: CoordinateBridgeError.coordination(coordinationError))
                    return
                }
                if let accessError {
                    continuation.resume(throwing: CoordinateBridgeError.accessor(accessError))
                    return
                }
                guard let result else {
                    continuation.resume(throwing: CoordinateBridgeError.accessor(
                        NSError(
                            domain: CoordinatedReplaceWriter.replaceStateErrorDomain,
                            code: CoordinatedReplaceWriter.coordinationReplaceStateCode,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Coordinated read accessor returned no value.",
                            ]
                        )
                    ))
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Bridges
    /// `coordinate(readingItemAt:options:writingItemAt:options:error:byAccessor:)`
    /// (read source + write destination — used for coordinated copy).
    static func coordinateReadingAndWriting(
        readingAt readingURL: URL,
        readingOptions: NSFileCoordinator.ReadingOptions,
        writingAt writingURL: URL,
        writingOptions: NSFileCoordinator.WritingOptions,
        qos: DispatchQoS.QoSClass = .userInitiated,
        accessor: @escaping @Sendable (URL, URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: qos).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var accessError: Error?

                coordinator.coordinate(
                    readingItemAt: readingURL,
                    options: readingOptions,
                    writingItemAt: writingURL,
                    options: writingOptions,
                    error: &coordinationError
                ) { readingCoordinatedURL, writingCoordinatedURL in
                    do {
                        try accessor(readingCoordinatedURL, writingCoordinatedURL)
                    } catch {
                        accessError = error
                    }
                }

                Self.resume(continuation, coordination: coordinationError, access: accessError)
            }
        }
    }

    /// Resumes the Void continuation exactly once, prioritizing the
    /// coordination error (the accessor never ran) over the inner-IO
    /// error, matching the original synchronous helper ordering.
    private static func resume(
        _ continuation: CheckedContinuation<Void, Error>,
        coordination: NSError?,
        access: Error?
    ) {
        if let coordination {
            continuation.resume(throwing: CoordinateBridgeError.coordination(coordination))
            return
        }
        if let access {
            continuation.resume(throwing: CoordinateBridgeError.accessor(access))
            return
        }
        continuation.resume()
    }
}
