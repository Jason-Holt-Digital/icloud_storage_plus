import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class MetadataQuerySessionTests: XCTestCase {
    func testCompletionGateCompletesOnlyOnce() {
        let gate = CompletionGate()

        XCTAssertFalse(gate.isCompleted)
        XCTAssertTrue(gate.tryComplete())
        XCTAssertTrue(gate.isCompleted)
        XCTAssertFalse(gate.tryComplete())
    }

    func testCancelRemovesObserversAndRunsCleanupOnce() {
        let query = NSMetadataQuery()
        let notificationName = Notification.Name(
            "MetadataQuerySessionTests.cancel"
        )
        let cleanup = expectation(description: "cleanup")
        var cleanupCount = 0
        var notificationCount = 0

        let session = MetadataQuerySession(query: query) { _ in
            cleanupCount += 1
            cleanup.fulfill()
        }
        session.addObserver(name: notificationName) { _, _, _ in
            notificationCount += 1
        }

        NotificationCenter.default.post(name: notificationName, object: query)
        XCTAssertEqual(notificationCount, 1)

        session.cancel()
        session.cancel()

        wait(for: [cleanup], timeout: 1.0)
        NotificationCenter.default.post(name: notificationName, object: query)

        XCTAssertTrue(session.isCancelled)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(notificationCount, 1)
    }

    func testAddObserverAfterCancelIsImmediatelyRemoved() {
        let query = NSMetadataQuery()
        let notificationName = Notification.Name(
            "MetadataQuerySessionTests.addAfterCancel"
        )
        let cleanup = expectation(description: "cleanup")
        var notificationCount = 0

        let session = MetadataQuerySession(query: query) { _ in
            cleanup.fulfill()
        }
        session.cancel()
        wait(for: [cleanup], timeout: 1.0)

        let wasAdded = session.addObserver(name: notificationName) { _, _, _ in
            notificationCount += 1
        }
        NotificationCenter.default.post(name: notificationName, object: query)

        XCTAssertFalse(wasAdded)
        XCTAssertEqual(notificationCount, 0)
    }

    func testGatherCancellationWaitsForInitialCompletion() {
        let lifecycle = GatherSessionLifecycle()

        XCTAssertFalse(lifecycle.updatesDidCancel())
        XCTAssertTrue(lifecycle.initialGatherDidComplete())
        XCTAssertFalse(lifecycle.initialGatherDidComplete())
    }

    func testGatherCancellationAfterInitialCompletionIsImmediate() {
        let lifecycle = GatherSessionLifecycle()

        XCTAssertFalse(lifecycle.initialGatherDidComplete())
        XCTAssertTrue(lifecycle.updatesDidCancel())
        XCTAssertFalse(lifecycle.updatesDidCancel())
    }

    func testConcurrentGatherLifecycleClaimsCancellationOnce() {
        let lifecycle = GatherSessionLifecycle()
        let queue = DispatchQueue(
            label: "MetadataQuerySessionTests.gatherLifecycle",
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let lock = NSLock()
        var claimCount = 0

        for index in 0..<100 {
            group.enter()
            queue.async {
                let claimed = index.isMultiple(of: 2)
                    ? lifecycle.initialGatherDidComplete()
                    : lifecycle.updatesDidCancel()
                if claimed {
                    lock.lock()
                    claimCount += 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 1.0), .success)
        XCTAssertEqual(claimCount, 1)
    }
}
