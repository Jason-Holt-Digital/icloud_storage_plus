import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class DocumentChangeObservationTests: XCTestCase {
    func testStreamDeliveryDropsOrdinaryEventsBeforeListening() {
        let delivery = StreamEventDelivery<Int>()
        var events: [Int] = []

        delivery.emit(1)
        delivery.emit(2)
        delivery.listen { events.append($0) }

        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(delivery.hasPendingEvents)
    }

    func testStreamDeliveryRetainsBoundedTerminalEvents() {
        let delivery = StreamEventDelivery<Int>()
        var events: [Int] = []

        delivery.finish([1, 2, 3])
        XCTAssertTrue(delivery.hasPendingEvents)
        delivery.finish([4])
        delivery.listen { events.append($0) }

        XCTAssertEqual(events, [2, 3])
        XCTAssertFalse(delivery.hasPendingEvents)
        delivery.emit(5)
        XCTAssertEqual(events, [2, 3])
    }

    func testStreamDeliveryCancellationWinsAgainstConcurrentEmission() {
        let delivery = StreamEventDelivery<Int>()
        let firstEventEntered = DispatchSemaphore(value: 0)
        let releaseFirstEvent = DispatchSemaphore(value: 0)
        let firstEventFinished = expectation(description: "first event finished")
        let cancelFinished = expectation(description: "cancel finished")
        let events = LockedCounter()

        delivery.listen { _ in
            events.increment()
            firstEventEntered.signal()
            releaseFirstEvent.wait()
        }

        DispatchQueue.global().async {
            delivery.emit(1)
            firstEventFinished.fulfill()
        }
        XCTAssertEqual(firstEventEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            delivery.cancel()
            cancelFinished.fulfill()
        }
        releaseFirstEvent.signal()

        wait(for: [firstEventFinished, cancelFinished], timeout: 1)
        delivery.emit(2)
        XCTAssertEqual(events.count, 1)
    }

    func testStreamDeliveryDropsPendingEventsAfterCancel() {
        let delivery = StreamEventDelivery<Int>()
        var events: [Int] = []

        delivery.finish([1, 2])
        delivery.cancel()
        delivery.listen { events.append($0) }

        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(delivery.hasPendingEvents)
    }

    func testInvalidationEventEmitsTypedPayload() throws {
        var payloads: [[String: Any]] = []
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { payloads.append($0) }
        )

        try observation.start()
        observation.emit(kind: .invalidation)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(
            payloads[0]["relativePath"] as? String,
            "Documents/journal.json"
        )
        XCTAssertEqual(payloads[0]["kind"] as? String, "invalidation")
    }

    func testCancelRemovesObserverAndSuppressesFutureEvents() throws {
        var startCount = 0
        var cancelCount = 0
        var payloads: [[String: Any]] = []
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { startCount += 1 },
            onCancel: { cancelCount += 1 },
            emit: { payloads.append($0) }
        )

        try observation.start()
        observation.cancel()
        observation.emit(kind: .invalidation)
        observation.cancel()

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertTrue(payloads.isEmpty)
    }

    func testStartIsIdempotent() throws {
        var startCount = 0
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { startCount += 1 },
            onCancel: {},
            emit: { _ in }
        )

        try observation.start()
        try observation.start()

        XCTAssertEqual(startCount, 1)
    }

    func testRecordedModificationDateSuppressesRepeatedCallbacks() throws {
        let modificationDate = Date(timeIntervalSince1970: 1_000)
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { _ in }
        )

        try observation.start()
        observation.recordReadOrWrite(modificationDate: modificationDate)

        XCTAssertFalse(
            observation.consumeContentChange(
                modificationDate: modificationDate
            )
        )
        XCTAssertFalse(
            observation.consumeContentChange(
                modificationDate: modificationDate
            )
        )
    }

    func testChangedModificationDateIsConsumedOnce() throws {
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let changedDate = Date(timeIntervalSince1970: 2_000)
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { _ in }
        )

        try observation.start()
        observation.recordReadOrWrite(modificationDate: initialDate)

        XCTAssertTrue(
            observation.consumeContentChange(modificationDate: changedDate)
        )
        XCTAssertFalse(
            observation.consumeContentChange(modificationDate: changedDate)
        )
    }

    func testSuccessfulWriteBaselineSuppressesItsQueuedCallback() throws {
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let writeDate = Date(timeIntervalSince1970: 2_000)
        let externalDate = Date(timeIntervalSince1970: 3_000)
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { _ in }
        )

        try observation.start()
        observation.recordReadOrWrite(modificationDate: initialDate)
        observation.recordReadOrWrite(modificationDate: writeDate)

        XCTAssertFalse(
            observation.consumeContentChange(modificationDate: writeDate)
        )
        XCTAssertTrue(
            observation.consumeContentChange(modificationDate: externalDate)
        )
    }

    func testCancelSuppressesModificationDateChanges() throws {
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {},
            onCancel: {},
            emit: { _ in }
        )

        try observation.start()
        observation.recordReadOrWrite(
            modificationDate: Date(timeIntervalSince1970: 1_000)
        )
        observation.cancel()

        XCTAssertFalse(
            observation.consumeContentChange(
                modificationDate: Date(timeIntervalSince1970: 2_000)
            )
        )
    }

    func testStartFailureLeavesObservationInactive() {
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 256)
        var payloads: [[String: Any]] = []
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { throw expectedError },
            onCancel: {},
            emit: { payloads.append($0) }
        )

        XCTAssertThrowsError(try observation.start()) { error in
            XCTAssertEqual(error as NSError, expectedError)
        }
        observation.emit(kind: .invalidation)

        XCTAssertTrue(payloads.isEmpty)
    }

    func testCancelBeforeStartPreventsObservationStart() throws {
        let startCount = LockedCounter()
        let cancelCount = LockedCounter()
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: { startCount.increment() },
            onCancel: { cancelCount.increment() },
            emit: { _ in }
        )

        observation.cancel()
        try observation.start()

        XCTAssertEqual(startCount.count, 0)
        XCTAssertEqual(cancelCount.count, 0)
    }

    func testCancelDuringStartPerformsOnePostStartTeardown() {
        let startEntered = DispatchSemaphore(value: 0)
        let allowStartToFinish = DispatchSemaphore(value: 0)
        let startFinished = expectation(description: "start finished")
        let startCount = LockedCounter()
        let cancelCount = LockedCounter()
        let observation = DocumentChangeObservation(
            relativePath: "Documents/journal.json",
            onStart: {
                startCount.increment()
                startEntered.signal()
                allowStartToFinish.wait()
            },
            onCancel: { cancelCount.increment() },
            emit: { _ in }
        )

        DispatchQueue.global().async {
            try? observation.start()
            startFinished.fulfill()
        }
        XCTAssertEqual(startEntered.wait(timeout: .now() + 1), .success)
        observation.cancel()
        observation.cancel()
        allowStartToFinish.signal()
        wait(for: [startFinished], timeout: 1)

        XCTAssertEqual(startCount.count, 1)
        XCTAssertEqual(cancelCount.count, 1)
    }

    func testCancelBeforeHandlerRunsOnlyFirstLateHandler() {
        let cancellation = DeferredCancellationHandler()
        var firstCount = 0
        var secondCount = 0

        XCTAssertNil(cancellation.cancel())
        cancellation.install { firstCount += 1 }?()
        cancellation.install { secondCount += 1 }?()
        XCTAssertNil(cancellation.cancel())

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)
        XCTAssertNil(cancellation.current)
    }

    func testHandlerInstalledBeforeListenRunsExactlyOnce() {
        let cancellation = DeferredCancellationHandler()
        var cancelCount = 0

        XCTAssertNil(cancellation.install { cancelCount += 1 })
        cancellation.activate()
        cancellation.cancel()?()
        cancellation.cancel()?()

        XCTAssertEqual(cancelCount, 1)
        XCTAssertNil(cancellation.current)
    }

    func testRepeatedCancelPreservesPendingCancellation() {
        let cancellation = DeferredCancellationHandler()
        var cancelCount = 0

        XCTAssertNil(cancellation.cancel())
        XCTAssertNil(cancellation.cancel())
        cancellation.install { cancelCount += 1 }?()
        XCTAssertNil(cancellation.cancel())

        XCTAssertEqual(cancelCount, 1)
    }

    func testNewListenerStartsIndependentCancellationGeneration() {
        let cancellation = DeferredCancellationHandler()
        var firstCount = 0
        var secondCount = 0

        XCTAssertNil(cancellation.install { firstCount += 1 })
        cancellation.cancel()?()
        cancellation.activate()
        XCTAssertNil(cancellation.install { secondCount += 1 })
        cancellation.cancel()?()

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
        XCTAssertNil(cancellation.current)
    }
}
