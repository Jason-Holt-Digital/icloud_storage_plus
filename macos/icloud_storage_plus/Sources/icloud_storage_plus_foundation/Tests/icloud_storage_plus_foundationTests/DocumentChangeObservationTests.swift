import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class DocumentChangeObservationTests: XCTestCase {
    func testRemoteChangeEventEmitsTypedPayload() {
        var payloads: [[String: Any]] = []
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { payloads.append($0) }
        )

        observation.start()
        observation.emit(kind: .remoteChange)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(
            payloads[0]["relativePath"] as? String,
            "Documents/journal.json"
        )
        XCTAssertEqual(payloads[0]["kind"] as? String, "remoteChange")
    }

    func testCancelRemovesObserverAndSuppressesFutureEvents() {
        var startCount = 0
        var cancelCount = 0
        var payloads: [[String: Any]] = []
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { startCount += 1 },
            onCancel: { cancelCount += 1 },
            emit: { payloads.append($0) }
        )

        observation.start()
        observation.cancel()
        observation.emit(kind: .remoteChange)
        observation.cancel()

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertTrue(payloads.isEmpty)
    }

    func testStartIsIdempotent() {
        var startCount = 0
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { startCount += 1 },
            onCancel: {},
            emit: { _ in }
        )

        observation.start()
        observation.start()

        XCTAssertEqual(startCount, 1)
    }
}
