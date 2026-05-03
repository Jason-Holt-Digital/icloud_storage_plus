import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class UbiquityContainerResolverTests: XCTestCase {
    func testLiveResolveRunsBlockingLookupOffMainThread() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let expectation = expectation(description: "container lookup ran")
        let lock = NSLock()
        var observedMainThreadState: Bool?
        let resolver = UbiquityContainerResolver(
            execute: UbiquityContainerResolver.live.execute,
            resolveContainerURL: { _ in
                lock.lock()
                observedMainThreadState = Thread.isMainThread
                lock.unlock()
                expectation.fulfill()
                return temporaryDirectory
            },
            delay: { _ in XCTFail("should not retry") },
            retryDelay: UbiquityContainerResolver.maximumRetryDelay
        )

        let containerURL = await resolver.resolve(containerId: "container")

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(containerURL?.path, temporaryDirectory.path)
        XCTAssertEqual(observedMainThreadState, false)
    }

    func testResolveRetriesOnceAfterNilResult() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var attempts = 0
        var delays: [TimeInterval] = []
        let resolver = UbiquityContainerResolver(
            execute: { work in work() },
            resolveContainerURL: { _ in
                attempts += 1
                if attempts == 2 {
                    return temporaryDirectory
                }
                return nil
            },
            delay: { delays.append($0) },
            retryDelay: UbiquityContainerResolver.maximumRetryDelay
        )

        let containerURL = await resolver.resolve(containerId: "container")

        XCTAssertEqual(containerURL?.path, temporaryDirectory.path)
        XCTAssertEqual(attempts, UbiquityContainerResolver.maxAttempts)
        XCTAssertEqual(
            delays,
            [UbiquityContainerResolver.maximumRetryDelay]
        )
    }

    func testResolveReturnsNilAfterPersistentNilResults() async {
        var attempts = 0
        var delays: [TimeInterval] = []
        let resolver = UbiquityContainerResolver(
            execute: { work in work() },
            resolveContainerURL: { _ in
                attempts += 1
                return nil
            },
            delay: { delays.append($0) },
            retryDelay: UbiquityContainerResolver.maximumRetryDelay
        )

        let containerURL = await resolver.resolve(containerId: "missing")

        XCTAssertNil(containerURL)
        XCTAssertEqual(attempts, UbiquityContainerResolver.maxAttempts)
        XCTAssertEqual(
            delays,
            [UbiquityContainerResolver.maximumRetryDelay]
        )
    }

    func testRetryDelayIsClampedTo150Milliseconds() async {
        var delays: [TimeInterval] = []
        let resolver = UbiquityContainerResolver(
            execute: { work in work() },
            resolveContainerURL: { _ in nil },
            delay: { delays.append($0) },
            retryDelay: 1
        )

        _ = await resolver.resolve(containerId: "missing")

        XCTAssertEqual(
            delays,
            [UbiquityContainerResolver.maximumRetryDelay]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        return temporaryDirectory
    }
}
