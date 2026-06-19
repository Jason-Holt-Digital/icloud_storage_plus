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
/// Implementation: each normalized path owns a cooperative async mutex
/// (a `withCheckedContinuation`-based binary semaphore with a FIFO
/// waiter queue). The calling async task SUSPENDS cooperatively (it
/// does NOT block any thread) while waiting for its lane turn, then
/// runs the (possibly async) body on the Swift cooperative pool. No
/// `DispatchSemaphore` is used to bridge the body, and no libdispatch
/// worker thread is blocked for the body's full duration — so
/// high-fan-out bulk mutations cannot exhaust the libdispatch worker
/// pool, and a burst of concurrent distinct-path ops cannot starve
/// other Swift async work.
///
/// The blocking `NSFileCoordinator.coordinate(...)` call itself is
/// never run on a cooperative-pool thread: the coordinated
/// delete/move/copy helpers hop it onto a `DispatchQueue.global`
/// worker via a continuation (see `CoordinatedIO` and
/// `CoordinatedReplaceWriter.liveCoordinateReplace`), so coordination
/// blocks a libdispatch worker, not a cooperative-pool thread. With
/// both the cooperative lane acquisition and the coordinated hop, there
/// is no `DispatchSemaphore.wait()` held for a body's duration and no
/// cooperative-pool starvation surface.
///
/// A counting-semaphore bound on in-flight lanes was considered and
/// rejected: on a per-path serial-`DispatchQueue` design a global
/// in-flight bound either fails to reduce blocked worker threads (the
/// thread is claimed when the block is dispatched, before the bound is
/// checked) or, if acquired before dispatch, lets a burst of same-path
/// ops exhaust the bound and starve unrelated cross-path work
/// (violating no-starvation). Eliminating the per-body thread blocking
/// entirely (this async-mutex design) bounds thread usage by
/// construction without breaking the per-path-serial /
/// cross-path-concurrent / FIFO / no-starvation invariants.
///
/// Idle lanes (no queued and no in-flight op) are reclaimed so the lane
/// map does not grow unbounded over a long session.
final class PerPathMutationLane: @unchecked Sendable {
    static let shared = PerPathMutationLane()

    private let lock = NSLock()
    private var lanes: [String: Lane] = [:]
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
        let lane = acquireLane(key)
        await lane.mutex.acquire()
        do {
            let value = try await body()
            releaseLane(key)
            lane.mutex.release()
            return value
        } catch {
            releaseLane(key)
            lane.mutex.release()
            throw error
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
        let laneFirst = acquireLane(first)
        await laneFirst.mutex.acquire()
        let laneSecond = acquireLane(second)
        await laneSecond.mutex.acquire()
        do {
            let value = try await body()
            releaseLane(second)
            laneSecond.mutex.release()
            releaseLane(first)
            laneFirst.mutex.release()
            return value
        } catch {
            releaseLane(second)
            laneSecond.mutex.release()
            releaseLane(first)
            laneFirst.mutex.release()
            throw error
        }
    }

    // MARK: - Private

    private func acquireLane(_ key: String) -> Lane {
        lock.lock()
        defer { lock.unlock() }
        pending[key, default: 0] += 1
        if let existing = lanes[key] { return existing }
        let lane = Lane()
        lanes[key] = lane
        return lane
    }

    /// Decrements the pending count for `key` and reclaims the lane
    /// when no op is queued or in flight on it. The mutex itself is
    /// released separately (by the caller) so its FIFO hand-off to the
    /// next waiter is preserved; a lane is only reclaimed when pending
    /// hits zero (no waiters), which is the only safe moment to drop
    /// the mutex from the map.
    private func releaseLane(_ key: String) {
        lock.lock()
        let next = (pending[key] ?? 0) - 1
        if next <= 0 {
            pending.removeValue(forKey: key)
            lanes.removeValue(forKey: key)
        } else {
            pending[key] = next
        }
        lock.unlock()
    }

    /// Per-path lane state: a cooperative async mutex.
    private final class Lane: @unchecked Sendable {
        let mutex = AsyncMutex()
    }
}

/// Cooperative binary mutex with FIFO waiter ordering. Acquisition
/// SUSPENDS the calling async task (it does NOT block any thread);
/// release hands off to the earliest waiter or marks the mutex
/// available. Cancelled tasks are removed from the waiter queue
/// promptly so they do not delay subsequent waiters. Used by
/// `PerPathMutationLane` to serialize per path without occupying a
/// libdispatch worker for a body's duration.
private final class AsyncMutex: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true
    private var waiters: [Waiter] = []

    func acquire() async {
        // Each caller allocates its own Waiter so the cancellation
        // handler can identify and remove exactly this entry by
        // object identity. The availability check and waiter
        // registration happen atomically under `lock` inside the
        // synchronous continuation closure, so no `release()` can
        // sneak in between and lose the hand-off.
        let waiter = Waiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation {
                (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                waiter.continuation = cont
                if available {
                    available = false
                    waiter.continuation = nil
                    lock.unlock()
                    cont.resume()
                } else {
                    waiters.append(waiter)
                    lock.unlock()
                }
            }
        } onCancel: {
            // Fires when the task is cancelled while suspended in the
            // waiter queue. Removes this waiter immediately and resumes
            // its continuation so the caller wakes up as the mutex
            // holder, runs body() — which propagates CancellationError
            // quickly — and releases. Without this, a cancelled task
            // stalls every subsequent waiter on this path until
            // release() reaches it in normal turn order.
            lock.lock()
            if let idx = waiters.firstIndex(where: { $0 === waiter }),
               let cont = waiter.continuation
            {
                waiter.continuation = nil
                waiters.remove(at: idx)
                lock.unlock()
                cont.resume()
            } else {
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        if let next = waiters.first {
            waiters.removeFirst()
            let cont = next.continuation
            next.continuation = nil
            lock.unlock()
            // Hand-off: the resumed waiter becomes the holder; the
            // mutex stays unavailable so a new acquirer queues behind.
            cont?.resume()
        } else {
            available = true
            lock.unlock()
        }
    }
}

/// Holds the pending continuation for one `AsyncMutex` waiter.
/// All accesses must be protected by the owning `AsyncMutex`'s lock.
private final class Waiter: @unchecked Sendable {
    var continuation: CheckedContinuation<Void, Never>?
}
