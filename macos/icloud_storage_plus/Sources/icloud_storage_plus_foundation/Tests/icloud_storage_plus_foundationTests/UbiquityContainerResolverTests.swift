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
            }
        )

        let containerURL = await resolver.resolve(containerId: "container")

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(containerURL?.path, temporaryDirectory.path)
        XCTAssertEqual(observedMainThreadState, false)
    }

    /// VAL-INV-006: the resolver performs exactly ONE ubiquity container
    /// lookup (single-shot) and returns the URL on success.
    func testResolveReturnsContainerURLOnSingleSuccessfulLookup() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var lookupCount = 0
        let resolver = UbiquityContainerResolver(
            execute: { work in work() },
            resolveContainerURL: { _ in
                lookupCount += 1
                return temporaryDirectory
            }
        )

        let containerURL = await resolver.resolve(containerId: "container")

        XCTAssertEqual(containerURL?.path, temporaryDirectory.path)
        XCTAssertEqual(lookupCount, 1, "resolver must be single-shot")
    }

    /// VAL-INV-006: a nil lookup result is terminal — the resolver
    /// performs a single lookup only and returns nil, so the caller
    /// throws the same typed container-unavailable error it always has.
    func testResolveReturnsNilAfterSingleShotNilResult() async {
        var lookupCount = 0
        let resolver = UbiquityContainerResolver(
            execute: { work in work() },
            resolveContainerURL: { _ in
                lookupCount += 1
                return nil
            }
        )

        let containerURL = await resolver.resolve(containerId: "missing")

        XCTAssertNil(containerURL)
        XCTAssertEqual(lookupCount, 1, "resolver must be single-shot")
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
