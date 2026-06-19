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
            _ = await try? lane.withLane(for: url) {
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
            _ = await try? lane.withLane(for: URL(
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
                        _ = await try? lane.withLane(for: URL(
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
}
