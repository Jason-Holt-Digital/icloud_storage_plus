import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

/// `NSLock`-guarded ordered event log + counter for lane timing assertions.
private final class LockedEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func append(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _events.removeAll()
    }
}

/// `NSLock`-guarded tracker for concurrent in-flight coordinated-body
/// executions, used by the cooperative-pool stress test to assert that
/// cross-path ops overlap and that no op starves.
private final class OverlapTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var maxConcurrent = 0
    private var completed = 0

    var maxConcurrentValue: Int {
        lock.lock(); defer { lock.unlock() }
        return maxConcurrent
    }

    var completedValue: Int {
        lock.lock(); defer { lock.unlock() }
        return completed
    }

    func enter() {
        lock.lock()
        inFlight += 1
        if inFlight > maxConcurrent { maxConcurrent = inFlight }
        lock.unlock()
    }

    func exit() {
        lock.lock()
        inFlight -= 1
        completed += 1
        lock.unlock()
    }
}

private enum LaneTestTimeout: Error {
    case timedOut
}

private func awaitTaskValue<T: Sendable>(
    _ task: Task<T, Never>,
    timeoutNanoseconds: UInt64
) async throws -> T {
    // Resolve the continuation from whichever fires first: the task result
    // or the timeout. A withThrowingTaskGroup alternative hangs because the
    // group must await ALL children before it can throw — so a stuck
    // task.value child blocks the timeout from propagating.
    final class Resolver<V: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var settled = false
        private let continuation: CheckedContinuation<V, Error>
        init(_ continuation: CheckedContinuation<V, Error>) {
            self.continuation = continuation
        }
        func settle(_ result: Result<V, Error>) {
            lock.lock()
            let first = !settled
            if first { settled = true }
            lock.unlock()
            if first { continuation.resume(with: result) }
        }
    }
    return try await withCheckedThrowingContinuation { continuation in
        let resolver = Resolver(continuation)
        Task { resolver.settle(.success(await task.value)) }
        Task {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            task.cancel()
            resolver.settle(.failure(LaneTestTimeout.timedOut))
        }
    }
}

final class PerPathMutationLaneTests: XCTestCase {
    private func makeLane() -> PerPathMutationLane {
        PerPathMutationLane()
    }

    /// VAL-MUT-023: same normalized path → mutations serialized in
    /// submission order (no interleaving).
    func testSamePathSerializedInSubmissionOrder() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let url = URL(fileURLWithPath: "/tmp/container/file.json")

        async let op1: Void = lane.withLane(for: url) {
            log.append("op1.start")
            try await Task.sleep(nanoseconds: 50_000_000)
            log.append("op1.end")
        }
        // Tiny delay so op1 is submitted first.
        try await Task.sleep(nanoseconds: 5_000_000)
        async let op2: Void = lane.withLane(for: url) {
            log.append("op2.start")
            log.append("op2.end")
        }

        _ = try await (op1, op2)

        let events = log.events
        XCTAssertEqual(events.first, "op1.start")
        let op1EndIndex = try XCTUnwrap(events.firstIndex(of: "op1.end"))
        let op2StartIndex = try XCTUnwrap(events.firstIndex(of: "op2.start"))
        XCTAssertLessThan(
            op1EndIndex, op2StartIndex,
            "op2 must not start until op1 completes (no interleaving)"
        )
    }

    /// VAL-MUT-025: different normalized paths → concurrent (including
    /// mixed op types).
    func testDifferentPathsProceedConcurrently() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let urlA = URL(fileURLWithPath: "/tmp/container/a.json")
        let urlB = URL(fileURLWithPath: "/tmp/container/b.json")

        let aStarted = DispatchSemaphore(value: 0)
        let releaseA = DispatchSemaphore(value: 0)

        async let opA: Void = lane.withLane(for: urlA) {
            log.append("a.start")
            aStarted.signal()
            releaseA.wait()
            log.append("a.end")
        }
        // Wait until A is in its critical section.
        aStarted.wait()
        log.append("b.submit")

        async let opB: Void = lane.withLane(for: urlB) {
            log.append("b.start")
            log.append("b.end")
        }

        // Give B a chance to start. Because A and B are different paths,
        // B must enter its critical section while A is still in flight.
        try await Task.sleep(nanoseconds: 30_000_000)
        let eventsBeforeRelease = log.events
        releaseA.signal()
        _ = try await (opA, opB)

        XCTAssertTrue(
            eventsBeforeRelease.contains("b.start"),
            "B must start concurrently with in-flight A (different paths): "
                + "\(eventsBeforeRelease)"
        )
    }

    /// VAL-MUT-028: equivalent path strings map to the SAME lane.
    /// Normalization key = standardized path with trailing slash
    /// collapsed.
    func testEquivalentPathsSerializeOnSameLane() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        // Trailing-slash vs no-trailing-slash normalize to the same key.
        let urlWithSlash =
            URL(fileURLWithPath: "/tmp/container/folder/")
        let urlWithoutSlash =
            URL(fileURLWithPath: "/tmp/container/folder")

        XCTAssertEqual(
            PerPathMutationLane.normalizationKey(for: urlWithSlash),
            PerPathMutationLane.normalizationKey(for: urlWithoutSlash),
            "trailing-slash equivalence must map to the same lane"
        )

        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)

        async let op1: Void = lane.withLane(for: urlWithSlash) {
            log.append("op1.start")
            firstStarted.signal()
            releaseFirst.wait()
            log.append("op1.end")
        }
        firstStarted.wait()

        async let op2: Void = lane.withLane(for: urlWithoutSlash) {
            log.append("op2.start")
            log.append("op2.end")
        }

        // op2 must NOT start while op1 is in flight (same lane).
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(
            log.events.contains("op2.start"),
            "equivalent path must serialize on the same lane"
        )
        releaseFirst.signal()
        _ = try await (op1, op2)

        let op1EndIndex = try XCTUnwrap(log.events.firstIndex(of: "op1.end"))
        let op2StartIndex = try XCTUnwrap(log.events.firstIndex(of: "op2.start"))
        XCTAssertLessThan(op1EndIndex, op2StartIndex)
    }

    /// VAL-MUT-029: mixed-type mutations on the same path serialize on
    /// one lane (write/delete/move-equivalent all non-overlapping).
    func testMixedTypesOnSamePathSerialize() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let url = URL(fileURLWithPath: "/tmp/container/file.json")

        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)

        async let op1: Void = lane.withLane(for: url) {
            log.append("write.start")
            firstStarted.signal()
            releaseFirst.wait()
            log.append("write.end")
        }
        firstStarted.wait()

        async let op2: Void = lane.withLane(for: url) {
            log.append("delete.start")
            log.append("delete.end")
        }
        async let op3: Void = lane.withLane(for: url) {
            log.append("copy.start")
            log.append("copy.end")
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(
            log.events, ["write.start"],
            "no other op may overlap the in-flight write on the same path"
        )
        releaseFirst.signal()
        _ = try await (op1, op2, op3)

        let writeEnd = try XCTUnwrap(log.events.firstIndex(of: "write.end"))
        for subsequent in ["delete.start", "copy.start"] {
            let idx = try XCTUnwrap(log.events.firstIndex(of: subsequent))
            XCTAssertLessThan(writeEnd, idx)
        }
    }

    /// VAL-MUT-041: cross-path op serializes against BOTH endpoint lanes.
    func testCrossPathSerializesAgainstBothEndpoints() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let urlA = URL(fileURLWithPath: "/tmp/container/a.json")
        let urlB = URL(fileURLWithPath: "/tmp/container/b.json")

        let moveStarted = DispatchSemaphore(value: 0)
        let releaseMove = DispatchSemaphore(value: 0)

        async let move: Void = lane.withLanes(for: urlA, and: urlB) {
            log.append("move.start")
            moveStarted.signal()
            releaseMove.wait()
            log.append("move.end")
        }
        moveStarted.wait()

        let writeAStarted = DispatchSemaphore(value: 0)
        let deleteBStarted = DispatchSemaphore(value: 0)

        async let writeA: Void = lane.withLane(for: urlA) {
            log.append("writeA.start")
            writeAStarted.signal()
            log.append("writeA.end")
        }
        async let deleteB: Void = lane.withLane(for: urlB) {
            log.append("deleteB.start")
            deleteBStarted.signal()
            log.append("deleteB.end")
        }

        // Neither endpoint op should enter its critical section while the
        // cross-path move holds both lanes.
        try await Task.sleep(nanoseconds: 40_000_000)
        let eventsBeforeRelease = log.events
        XCTAssertFalse(
            eventsBeforeRelease.contains("writeA.start"),
            "write on A must not overlap the cross-path move: \(eventsBeforeRelease)"
        )
        XCTAssertFalse(
            eventsBeforeRelease.contains("deleteB.start"),
            "delete on B must not overlap the cross-path move: \(eventsBeforeRelease)"
        )

        releaseMove.signal()
        _ = try await (move, writeA, deleteB)

        let moveEnd = try XCTUnwrap(log.events.firstIndex(of: "move.end"))
        let writeAStart = try XCTUnwrap(log.events.firstIndex(of: "writeA.start"))
        let deleteBStart =
            try XCTUnwrap(log.events.firstIndex(of: "deleteB.start"))
        XCTAssertLessThan(moveEnd, writeAStart)
        XCTAssertLessThan(moveEnd, deleteBStart)
    }

    /// VAL-MUT-047: N>2 queued same-path mutations execute FIFO with no
    /// starvation.
    func testFifoOrderingForManyQueuedOps() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let url = URL(fileURLWithPath: "/tmp/container/file.json")
        let count = 6

        // Submit sequentially so submission order is deterministic.
        for index in 0..<count {
            _ = try? await lane.withLane(for: url) {
                log.append("op\(index).start")
                try await Task.sleep(nanoseconds: 5_000_000)
                log.append("op\(index).end")
            }
        }

        let startOrder = log.events
            .filter { $0.hasSuffix(".start") }
            .map { String($0.dropLast(".start".count)) }
        XCTAssertEqual(
            startOrder,
            (0..<count).map { "op\($0)" },
            "start order must match submission order (FIFO, no starvation)"
        )
        // Every op completed.
        XCTAssertEqual(
            log.events.filter { $0.hasSuffix(".end") }.count,
            count
        )
    }

    /// VAL-MUT-048: idle lanes are cleaned up (no unbounded growth).
    func testIdleLanesAreCleanedUp() async throws {
        let lane = makeLane()
        let distinctPaths = 10

        for index in 0..<distinctPaths {
            _ = try? await lane.withLane(for: URL(
                fileURLWithPath: "/tmp/container/file-\(index).json"
            )) {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        // Poll for quiescence: releaseLane runs slightly after the body
        // resumes the caller, so allow a brief window for the final
        // release to land.
        let deadline = Date().addingTimeInterval(2.0)
        while lane.laneMapSize > 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertLessThan(
            lane.laneMapSize, distinctPaths,
            "idle lanes must be reclaimed (got \(lane.laneMapSize), "
                + "touched \(distinctPaths) distinct paths)"
        )
        XCTAssertEqual(
            lane.laneMapSize, 0,
            "after full quiescence the lane map should be empty"
        )
    }

    /// VAL-MUT-049: a lane remains usable after an op throws; one lane's
    /// exception does not stall others.
    func testLaneUsableAfterThrowAndOthersUnaffected() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let urlP = URL(fileURLWithPath: "/tmp/container/p.json")
        let urlQ = URL(fileURLWithPath: "/tmp/container/q.json")

        struct Boom: Error {}

        do {
            _ = try await lane.withLane(for: urlP) {
                log.append("op1.start")
                throw Boom()
            }
            XCTFail("expected op1 to throw")
        } catch {
            // expected
        }

        // op2 on the same path (P) must still run after op1 threw.
        async let op2: Void = lane.withLane(for: urlP) {
            log.append("op2.start")
            log.append("op2.end")
        }
        // op on a different path (Q) must complete independently.
        async let opQ: Void = lane.withLane(for: urlQ) {
            log.append("opQ.start")
            log.append("opQ.end")
        }

        _ = try await (op2, opQ)

        XCTAssertTrue(log.events.contains("op2.start"))
        XCTAssertTrue(log.events.contains("opQ.start"))
        XCTAssertTrue(log.events.contains("op2.end"))
        XCTAssertTrue(log.events.contains("opQ.end"))
    }

    /// M8 hardening: a task cancelled while suspended in an
    /// `AsyncMutex` waiter queue is removed immediately instead of
    /// lingering until normal FIFO hand-off reaches it.
    func testCancelledWaiterIsRemovedBeforeLaneRelease() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let url = URL(fileURLWithPath: "/tmp/container/cancelled.json")

        let blockerStarted = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)

        let blocker = Task {
            try await lane.withLane(for: url) {
                log.append("blocker.start")
                blockerStarted.signal()
                releaseBlocker.wait()
                log.append("blocker.end")
            }
        }
        defer {
            releaseBlocker.signal()
            blocker.cancel()
        }
        blockerStarted.wait()

        let waiter = Task<Result<Void, Error>, Never> {
            do {
                try await lane.withLane(for: url) {
                    log.append("cancelled.body")
                }
                return .success(())
            } catch {
                log.append("cancelled.error")
                return .failure(error)
            }
        }
        defer { waiter.cancel() }

        // Give the waiter a deterministic chance to suspend behind the
        // blocker, then cancel while it is still queued.
        try await Task.sleep(nanoseconds: 30_000_000)
        waiter.cancel()

        let waiterResult: Result<Void, Error>
        do {
            waiterResult = try await awaitTaskValue(
                waiter,
                timeoutNanoseconds: 1_000_000_000
            )
        } catch {
            XCTFail("cancelled waiter did not complete until lane release")
            waiterResult = .success(())
        }

        switch waiterResult {
        case .failure(let error):
            XCTAssertTrue(
                error is CancellationError,
                "expected CancellationError, got \(error)"
            )
        case .success:
            XCTFail("cancelled waiter unexpectedly acquired the lane")
        }
        XCTAssertFalse(
            log.events.contains("cancelled.body"),
            "cancelled waiter must not run the lane body"
        )

        let follower = Task {
            try await lane.withLane(for: url) {
                log.append("follower.start")
            }
        }
        releaseBlocker.signal()
        _ = try await blocker.value
        _ = try await follower.value

        XCTAssertTrue(log.events.contains("blocker.end"))
        XCTAssertTrue(log.events.contains("follower.start"))
        XCTAssertFalse(
            log.events.contains("cancelled.body"),
            "cancelled waiter must stay removed after blocker release"
        )
    }

    /// VAL-MUT-027: bulk (multi-distinct-path) and interactive mutations
    /// to unrelated paths run concurrently on separate lanes.
    func testBulkAndInteractiveRunOnSeparateLanes() async throws {
        let lane = makeLane()
        let log = LockedEventLog()
        let interactiveURL =
            URL(fileURLWithPath: "/tmp/container/interactive.json")

        let bulkStarted = DispatchSemaphore(value: 0)
        let releaseBulk = DispatchSemaphore(value: 0)

        // Bulk batch: several slow writes to distinct paths.
        let bulkTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<4 {
                    group.addTask {
                        _ = try? await lane.withLane(for: URL(
                            fileURLWithPath: "/tmp/container/bulk-\(index).json"
                        )) {
                            bulkStarted.signal()
                            releaseBulk.wait()
                        }
                    }
                }
            }
        }
        // Wait until at least one bulk op is in flight.
        bulkStarted.wait()
        log.append("bulk.inflight")

        // Interactive mutation to an unrelated path must proceed
        // concurrently (separate lane).
        async let interactive: Void = lane.withLane(for: interactiveURL) {
            log.append("interactive.start")
            log.append("interactive.end")
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(
            log.events.contains("interactive.start"),
            "interactive op on an unrelated path must not wait for the "
                + "bulk batch: \(log.events)"
        )

        // Release all blocked bulk ops (signal enough times).
        for _ in 0..<4 {
            releaseBulk.signal()
        }
        _ = try await interactive
        _ = await bulkTask.value
    }

    /// Cooperative-pool / libdispatch-worker stress test
    /// (VAL-MUT-052): fans out WELL BEYOND core-count concurrent
    /// distinct-path delete/move ops with a REAL (non-instant)
    /// coordinated body and asserts:
    ///   - no starvation: every op completes,
    ///   - cross-path overlap: at least two distinct ops are in their
    ///     coordinated accessor concurrently,
    ///   - genuine concurrency: total elapsed is well under the serial
    ///     sum (ops run in parallel, not serially).
    ///
    /// The existing suite uses fast injected closures and never
    /// exercises cooperative-pool/worker saturation. This test drives
    /// the real `CoordinatedIO` hop (blocking `NSFileCoordinator`
    /// coordinate on a `DispatchQueue.global` worker, not on a
    /// cooperative-pool thread) combined with the non-blocking async
    /// lane, so a burst of distinct-path coordinated ops cannot starve
    /// other Swift async work or exhaust the libdispatch worker pool.
    func testStressBeyondCoreCountNoStarvationAndCrossPathOverlap() async throws {
        let cores = ProcessInfo.processInfo.processorCount
        // Well beyond core-count.
        let count = max(cores * 4, 32)
        let lane = PerPathMutationLane()
        let tracker = OverlapTracker()

        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "lane-stress-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tmpRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        var urls: [URL] = []
        for index in 0..<count {
            let url = tmpRoot.appendingPathComponent("file-\(index).json")
            try "seed-\(index)".write(
                to: url, atomically: true, encoding: .utf8
            )
            urls.append(url)
        }

        // Each coordinated body is non-instant (~20ms inside the
        // accessor). The serial sum is the time if every op ran one at
        // a time; genuine cross-path concurrency must beat it by a wide
        // margin.
        let perBodySeconds: Double = 0.02
        let serialSum = Double(count) * perBodySeconds

        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                let url = urls[index]
                if index.isMultiple(of: 2) {
                    // "delete" verb: single-lane coordinated write.
                    group.addTask {
                        _ = try? await lane.withLane(for: url) {
                            try await CoordinatedIO.coordinateWriting(
                                at: url,
                                options: .forReplacing
                            ) { coordinatedURL in
                                tracker.enter()
                                Thread.sleep(forTimeInterval: perBodySeconds)
                                try "updated-\(index)".write(
                                    to: coordinatedURL,
                                    atomically: true,
                                    encoding: .utf8
                                )
                                tracker.exit()
                            }
                        }
                    }
                } else {
                    // "move" verb: cross-path (two-lane) coordinated
                    // write against a distinct second endpoint.
                    let other = urls[(index + 1) % count]
                    group.addTask {
                        _ = try? await lane.withLanes(for: url, and: other) {
                            try await CoordinatedIO.coordinateWritingTwo(
                                writingAt: url, options: .forMoving,
                                writingAt: other, options: .forReplacing
                            ) { _, _ in
                                tracker.enter()
                                Thread.sleep(forTimeInterval: perBodySeconds)
                                tracker.exit()
                            }
                        }
                    }
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        // No starvation: every op completed.
        XCTAssertEqual(
            tracker.completedValue, count,
            "all \(count) ops must complete (no starvation)"
        )
        // Cross-path overlap: at least two ops were in their coordinated
        // accessor concurrently.
        XCTAssertGreaterThanOrEqual(
            tracker.maxConcurrentValue, 2,
            "cross-path ops must overlap (maxConcurrent="
                + "\(tracker.maxConcurrentValue))"
        )
        // Genuine concurrency: elapsed well under the serial sum.
        XCTAssertLessThan(
            elapsed, serialSum,
            "ops must run concurrently (elapsed=\(elapsed)s, "
                + "serialSum=\(serialSum)s)"
        )
    }
}
