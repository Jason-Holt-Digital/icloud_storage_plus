import Foundation

private final class FilePresenterReference: @unchecked Sendable {
    let value: NSFilePresenter?

    init(_ value: NSFilePresenter?) {
        self.value = value
    }
}

struct CoordinatedReplaceWriter {
    typealias FileExists = (String) -> Bool
    typealias VerifyDestination = (URL) throws -> Void
    typealias CreateReplacementDirectory = (URL) throws -> URL
    /// Outer is `async throws` so the live binding can bridge
    /// `NSFileCoordinator.coordinate` (sync, blocking) into the
    /// caller's async context. Inner accessor is sync to honor Apple's
    /// documented contract that the coordinator's accessor closure
    /// runs synchronously on the calling thread — and to avoid the
    /// `DispatchSemaphore`-bridged async accessor that could deadlock
    /// the Swift cooperative thread pool under load.
    typealias CoordinateReplace = (
        URL,
        @escaping @Sendable (URL) throws -> Void
    ) async throws -> Void
    typealias ReplaceItem = (URL, URL) throws -> Void
    typealias RemoveItem = (URL) throws -> Void

    let fileExists: FileExists
    let verifyDestination: VerifyDestination
    let createReplacementDirectory: CreateReplacementDirectory
    let coordinateReplace: CoordinateReplace
    let replaceItem: ReplaceItem
    let removeItem: RemoveItem

    /// Performs a coordinated LOCAL REPLACE ONLY of an existing file.
    ///
    /// Conflict policy is app-owned: this writer performs no conflict
    /// resolution and deletes no `NSFileVersion`s. The app enumerates
    /// unresolved versions, copies losing versions out, and marks
    /// resolved via the dedicated `VersionExposure` primitives.
    func overwriteExistingItem(
        at destinationURL: URL,
        prepareReplacementFile: (URL) throws -> Void
    ) async throws -> Bool {
        guard fileExists(destinationURL.path) else {
            return false
        }

        try verifyDestination(destinationURL)

        let replacementDirectory = try createReplacementDirectory(destinationURL)
        let replacementURL = replacementDirectory
            .appendingPathComponent(destinationURL.lastPathComponent)

        do {
            try prepareReplacementFile(replacementURL)
            let replaceItem = self.replaceItem
            try await coordinateReplace(destinationURL) {
                [replacementURL] coordinatedURL in
                // Local replace only — no resolve/version-removal step.
                // The coordinated URL is honored per Apple's contract.
                try replaceItem(coordinatedURL, replacementURL)
            }
        } catch {
            try? removeItem(replacementDirectory)
            throw error
        }

        try? removeItem(replacementDirectory)
        return true
    }
}

extension CoordinatedReplaceWriter {
    static let replaceStateErrorDomain = "ICloudStoragePlusErrorDomain"
    /// Repurposed for version-exposure failures (enumerate/copy-out/
    /// mark-resolved) produced by `VersionExposure`. The auto-resolve
    /// producer that previously emitted this code has been removed.
    static let conflictReplaceStateCode = 1
    static let directoryReplaceStateCode = 4
    static let coordinationReplaceStateCode = 5

    static func fileDestinationError(isDirectory: Bool) -> NSError? {
        guard isDirectory else {
            return nil
        }

        return NSError(
            domain: replaceStateErrorDomain,
            code: directoryReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace an existing directory with file content.",
            ]
        )
    }

    static func coordinationError(underlying: NSError) -> NSError {
        NSError(
            domain: replaceStateErrorDomain,
            code: coordinationReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "File coordination failed while replacing an iCloud item.",
                NSUnderlyingErrorKey: underlying,
            ]
        )
    }

    /// Directory-only pre-flight for the writeInPlace path. iCloud Drive
    /// download/current state is Apple-owned lifecycle, not a plugin
    /// write precondition.
    static func verifyOverwriteDestinationIsFile(
        at destinationURL: URL
    ) throws {
        let values = try destinationURL.resourceValues(forKeys: [.isDirectoryKey])

        if let destinationError = fileDestinationError(
            isDirectory: values.isDirectory == true
        ) {
            throw destinationError
        }
    }

    /// Bridges synchronous file coordination into the async caller.
    /// Coordination always runs on a background dispatch queue so a slow
    /// iCloud/File Provider write never blocks the presenter's operation
    /// queue (or the main thread). Passing the presenter to
    /// `NSFileCoordinator` still suppresses self-notifications for
    /// presenter-owned writes.
    static func makeLiveCoordinateReplace(
        filePresenter: NSFilePresenter?
    ) -> CoordinateReplace {
        let presenterReference = FilePresenterReference(filePresenter)
        return { destinationURL, accessor in
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                let coordinate: @Sendable () -> Void = {
                    let coordinator = NSFileCoordinator(
                        filePresenter: presenterReference.value
                    )
                    var coordinationError: NSError?
                    var accessError: Error?

                    coordinator.coordinate(
                        writingItemAt: destinationURL,
                        options: [],
                        error: &coordinationError
                    ) { coordinatedURL in
                        do {
                            try accessor(coordinatedURL)
                        } catch {
                            accessError = error
                        }
                    }

                    if let coordinationError {
                        continuation.resume(throwing: Self.coordinationError(
                            underlying: coordinationError
                        ))
                        return
                    }
                    if let accessError {
                        continuation.resume(throwing: accessError)
                        return
                    }
                    continuation.resume()
                }

                DispatchQueue.global(qos: .userInitiated).async(
                    execute: coordinate
                )
            }
        }
    }

    static let liveCoordinateReplace = makeLiveCoordinateReplace(
        filePresenter: nil
    )

    static func makeLive(
        filePresenter: NSFilePresenter?,
        afterSuccessfulReplace: @escaping (URL) -> Void = { _ in }
    ) -> CoordinatedReplaceWriter {
        CoordinatedReplaceWriter(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            verifyDestination: { destinationURL in
                try verifyOverwriteDestinationIsFile(at: destinationURL)
            },
            createReplacementDirectory: { destinationURL in
                try FileManager.default.url(
                    for: .itemReplacementDirectory,
                    in: .userDomainMask,
                    appropriateFor: destinationURL,
                    create: true
                )
            },
            coordinateReplace: makeLiveCoordinateReplace(
                filePresenter: filePresenter
            ),
            replaceItem: { destinationURL, replacementURL in
                let resultingURL = try FileManager.default.replaceItemAt(
                    destinationURL,
                    withItemAt: replacementURL
                ) ?? destinationURL
                afterSuccessfulReplace(resultingURL)
            },
            removeItem: { url in
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        )
    }

    static let live = makeLive(filePresenter: nil)
}
