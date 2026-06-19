import Foundation

/// Per-normalized-path serial mutation lanes.
///
/// Mutations to the SAME normalized path execute strictly one-at-a-time
/// in submission (FIFO) order; mutations to DIFFERENT paths proceed
/// concurrently. Reads never enter a write lane. Cross-path operations
/// (move/copy) serialize against BOTH endpoint lanes for their full
/// duration.
///
/// CRITICAL: the lane lock is NEVER nested inside an
/// `NSFileCoordinator` coordination callback. The pattern is
/// acquire-lane → coordinate → release: the coordination runs INSIDE
/// the lane's serialized closure, never the reverse, so no deadlock is
/// possible.
///
/// Implementation: each normalized path owns a serial `DispatchQueue`.
/// The calling async task suspends at a single-resume continuation
/// while the lane's dispatch thread runs the (possibly async) body and
/// signals completion via a `DispatchSemaphore`. The dispatch thread is
/// NOT a Swift cooperative-pool thread, so blocking it cannot starve
/// the cooperative pool — the same deadlock-free bridging pattern used
/// by `CoordinatedReplaceWriter.liveCoordinateReplace`.
///
/// Idle lanes (no queued and no in-flight op) are reclaimed so the lane
/// map does not grow unbounded over a long session.
final class PerPathMutationLane: @unchecked Sendable {
    static let shared = PerPathMutationLane()

    private let lock = NSLock()
    private var lanes: [String: DispatchQueue] = [:]
    private var pending: [String: Int] = [:]

    /// Test/inspection hook: the number of lanes currently retained.
    var laneMapSize: Int {
        lock.lock(); defer { lock.unlock() }
        return lanes.count
    }

    /// Normalization key for a URL. Equivalent path strings (after
    /// standardizing symlinks/`.`/`..` and collapsing trailing slashes)
    /// map to the SAME lane so they serialize against one another.
    static func normalizationKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.hasSuffix("/") && path != "/" {
            return String(path.dropLast())
        }
        return path
    }

    /// Serializes `body` on the lane for `url`'s normalized path.
    /// Same path → strictly ordered, no interleaving. Different paths
    /// → concurrent. The lane survives a throwing body; one lane's
    /// exception never stalls another.
    func withLane<T: Sendable>(
        for url: URL,
        perform body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let key = Self.normalizationKey(for: url)
        let queue = acquireLane(key)
        return try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<T, Error>) in
            queue.async {
                self.runAsyncBody(body, on: key, resume: cont)
            }
        }
    }

    /// Serializes `body` against BOTH endpoint lanes (cross-path op).
    /// Acquired in canonical (sorted-key) order to avoid deadlock; both
    /// lanes are held for the body's full duration. When both endpoints
    /// normalize to the same key, a single lane is used.
    func withLanes<T: Sendable>(
        for a: URL,
        and b: URL,
        perform body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let keyA = Self.normalizationKey(for: a)
        let keyB = Self.normalizationKey(for: b)

        if keyA == keyB {
            return try await withLane(for: a, perform: body)
        }

        let (first, second) = keyA < keyB ? (keyA, keyB) : (keyB, keyA)
        let queueFirst = acquireLane(first)

        return try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<T, Error>) in
            queueFirst.async {
                // Acquire the second lane and run the body on it. The
                // first lane's thread blocks here until the body
                // completes, so BOTH lanes are held for the body's full
                // duration (cross-path serialization).
                let queueSecond = self.acquireLane(second)
                let firstDone = DispatchSemaphore(value: 0)
                queueSecond.async {
                    self.runAsyncBody(body, on: second, resume: cont) {
                        firstDone.signal()
                    }
                }
                firstDone.wait()
                self.releaseLane(first)
            }
        }
    }

    // MARK: - Private

    private func acquireLane(_ key: String) -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }
        pending[key, default: 0] += 1
        if let existing = lanes[key] { return existing }
        let queue = DispatchQueue(
            label: "icloud_storage_plus.mutation_lane.\(key)"
        )
        lanes[key] = queue
        return queue
    }

    private func releaseLane(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        let next = (pending[key] ?? 0) - 1
        if next <= 0 {
            pending.removeValue(forKey: key)
            lanes.removeValue(forKey: key)
        } else {
            pending[key] = next
        }
    }

    /// Runs an async `body` while blocking the lane's dispatch thread
    /// until completion (semaphore-bridged). The continuation is resumed
    /// exactly once from the async body's Task; the dispatch thread only
    /// performs lane bookkeeping after the body completes. `onRelease`
    /// runs after the body completes (used to release the outer lane in
    /// the cross-path case).
    private func runAsyncBody<T: Sendable>(
        _ body: @escaping @Sendable () async throws -> T,
        on key: String,
        resume cont: CheckedContinuation<T, Error>,
        onRelease: () -> Void = {}
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let value = try await body()
                cont.resume(returning: value)
            } catch {
                cont.resume(throwing: error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        releaseLane(key)
        onRelease()
    }
}
