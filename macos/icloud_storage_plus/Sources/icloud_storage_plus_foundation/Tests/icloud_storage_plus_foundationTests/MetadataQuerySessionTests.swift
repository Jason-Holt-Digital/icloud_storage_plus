import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class MetadataQuerySessionTests: XCTestCase {
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
}
