import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class WriteEntrypointPreflightTests: XCTestCase {
    func testLivePrepareRunsBlockingWorkOffMainThread() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let expectedDirectory = temporaryDirectory
            .appendingPathComponent("nested", isDirectory: true)
        let expectedFileURL = expectedDirectory.appendingPathComponent("file.txt")
        let expectation = expectation(description: "preflight work ran")
        expectation.expectedFulfillmentCount = 2
        let lock = NSLock()
        var observedMainThreadStates: [Bool] = []

        let preflight = WriteEntrypointPreflight(
            execute: WriteEntrypointPreflight.live.execute,
            ubiquityContainerResolver: UbiquityContainerResolver(
                execute: UbiquityContainerResolver.live.execute,
                resolveContainerURL: { _ in
                    lock.lock()
                    observedMainThreadStates.append(Thread.isMainThread)
                    lock.unlock()
                    expectation.fulfill()
                    return temporaryDirectory
                }
            ),
            createDirectory: { directoryURL in
                lock.lock()
                observedMainThreadStates.append(Thread.isMainThread)
                lock.unlock()
                expectation.fulfill()
                XCTAssertEqual(directoryURL.path, expectedDirectory.path)
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }
        )

        let fileURL = try await preflight.prepare(
            containerId: "container",
            relativePath: "nested/file.txt"
        )

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(fileURL.path, expectedFileURL.path)
        XCTAssertEqual(observedMainThreadStates, [false, false])
    }

    func testPrepareThrowsTypedContainerUnavailableError() async {
        let preflight = WriteEntrypointPreflight(
            execute: { work in try work() },
            ubiquityContainerResolver: UbiquityContainerResolver(
                execute: { work in work() },
                resolveContainerURL: { _ in nil }
            ),
            createDirectory: { _ in XCTFail("should not create directory") }
        )

        do {
            _ = try await preflight.prepare(
                containerId: "missing",
                relativePath: "nested/file.txt"
            )
            XCTFail("expected prepare to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, WriteEntrypointPreflight.errorDomain)
            XCTAssertEqual(
                nsError.code,
                WriteEntrypointPreflight.containerUnavailableErrorCode
            )
        }
    }

    func testItemURLWithoutParentDirectoryCreationSkipsCreateDirectory()
        async throws
    {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var createDirectoryCalled = false
        let preflight = WriteEntrypointPreflight(
            execute: { work in try work() },
            ubiquityContainerResolver: UbiquityContainerResolver(
                execute: { work in work() },
                resolveContainerURL: { _ in temporaryDirectory }
            ),
            createDirectory: { _ in createDirectoryCalled = true }
        )

        let fileURL = try await preflight.itemURL(
            containerId: "container",
            relativePath: "nested/file.txt",
            createParentDirectory: false
        )

        XCTAssertEqual(
            fileURL.path,
            temporaryDirectory
                .appendingPathComponent("nested/file.txt")
                .path
        )
        XCTAssertFalse(createDirectoryCalled)
    }

    func testContainerURLRunsOffMainThread() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let expectation = expectation(description: "container lookup ran")
        var observedMainThreadState: Bool?
        let preflight = WriteEntrypointPreflight(
            execute: WriteEntrypointPreflight.live.execute,
            ubiquityContainerResolver: UbiquityContainerResolver(
                execute: UbiquityContainerResolver.live.execute,
                resolveContainerURL: { _ in
                    observedMainThreadState = Thread.isMainThread
                    expectation.fulfill()
                    return temporaryDirectory
                }
            ),
            createDirectory: { _ in XCTFail("should not create directory") }
        )

        let containerURL = try await preflight.containerURL(
            containerId: "container"
        )

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(containerURL.path, temporaryDirectory.path)
        XCTAssertEqual(observedMainThreadState, false)
    }

    /// VAL-INV-006: the resolver is single-shot, so a nil container
    /// lookup is terminal — `prepare` throws the same typed
    /// container-unavailable error (same domain + code) it always has
    /// after a single lookup, with no directory creation.
    func testPrepareThrowsContainerUnavailableErrorWhenLookupIsNil() async {
        var lookupCount = 0
        let preflight = WriteEntrypointPreflight(
            execute: { work in try work() },
            ubiquityContainerResolver: UbiquityContainerResolver(
                execute: { work in work() },
                resolveContainerURL: { _ in
                    lookupCount += 1
                    return nil
                }
            ),
            createDirectory: { _ in XCTFail("should not create directory") }
        )

        do {
            _ = try await preflight.prepare(
                containerId: "container",
                relativePath: "nested/file.txt"
            )
            XCTFail("expected prepare to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, WriteEntrypointPreflight.errorDomain)
            XCTAssertEqual(
                nsError.code,
                WriteEntrypointPreflight.containerUnavailableErrorCode
            )
        }

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
