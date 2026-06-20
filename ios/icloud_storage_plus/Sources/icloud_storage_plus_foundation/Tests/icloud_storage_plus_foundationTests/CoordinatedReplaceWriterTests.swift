import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

/// `NSLock`-guarded counter the sync seam closures can mutate.
/// Replaces the previous `actor`-based bookkeeping that required
/// `await` inside seam closures — those closures are now sync per
/// the Slice B/C/D architectural correction.
private final class LockedCallbacks: @unchecked Sendable {
    private let lock = NSLock()
    private var _verifyDestinationCount = 0
    private var _replaceItemCount = 0

    var verifyDestinationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _verifyDestinationCount
    }
    var replaceItemCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _replaceItemCount
    }

    func bumpVerify() {
        lock.lock(); defer { lock.unlock() }
        _verifyDestinationCount += 1
    }
    func bumpReplace() {
        lock.lock(); defer { lock.unlock() }
        _replaceItemCount += 1
    }
}

/// `NSLock`-guarded ordered event log for step-order assertions.
private final class LockedCallLog: @unchecked Sendable {
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
}

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testProductionSourceIsNotDuplicated() throws {
        let productionPath = #filePath
            .replacingOccurrences(
                of: "/Sources/icloud_storage_plus_foundation/Tests/"
                    + "icloud_storage_plus_foundationTests/"
                    + "CoordinatedReplaceWriterTests.swift",
                with: "/Sources/icloud_storage_plus/"
                    + "CoordinatedReplaceWriter.swift"
            )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: productionPath),
            "CoordinatedReplaceWriter.swift must live only in the "
                + "icloud_storage_plus_foundation module; the plugin target "
                + "references it via SPM target.sources sharing."
        )
    }

    func testHelperSourceDoesNotExposeCopyOverwriteEntryPoint() throws {
        let helperSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        XCTAssertFalse(helperSource.contains("copyItemOverwritingExistingItem"))
    }

    /// VAL-MUT-014: the coordinated replace path performs the LOCAL
    /// REPLACE ONLY and references no version-removal primitive.
    func testHelperSourceDoesNotRemoveOtherVersions() throws {
        let helperSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        XCTAssertFalse(
            helperSource.contains("removeOtherVersionsOfItem"),
            "CoordinatedReplaceWriter must not delete NSFileVersions; "
                + "conflict policy is app-owned."
        )
    }

    func testIOSCopyPropagatesSourceReadCoordinationErrors() throws {
        let pluginSource = try iOSPluginSource()

        // The M1 CoordinatedIO refactor replaced the pre-CoordinatedIO
        // `var X: NSError?` / `error: &X` / `if let X` surfacing in the
        // copy channel block with `CoordinateBridgeError` enum-pattern
        // surfacing. These assertions verify the CURRENT source surfaces
        // the source-read coordination failure distinctly (R14).
        XCTAssertTrue(
            pluginSource.contains("case .coordination(let sourceCoordinationError):"),
            "copy() should surface a failed source read coordination via "
                + "the CoordinateBridgeError.coordination enum case instead "
                + "of continuing silently."
        )
        XCTAssertTrue(
            pluginSource.contains("sourceCoordinationError.localizedDescription"),
            "copy() should inspect the surfaced source-read coordination "
                + "error instead of discarding it."
        )
        XCTAssertTrue(
            pluginSource.contains("case .accessor(let overwriteError):"),
            "copy() should surface the source-read inner IO failure "
                + "distinctly from the coordination failure (R14)."
        )
        XCTAssertTrue(
            pluginSource.contains("case .coordination(let copyCoordinationError):"),
            "copy() should surface a failed combined read/write "
                + "coordination via the CoordinateBridgeError.coordination "
                + "enum case in the non-overwrite path."
        )
        XCTAssertTrue(
            pluginSource.contains("copyCoordinationError.localizedDescription"),
            "copy() should inspect the surfaced combined coordination "
                + "error instead of discarding it."
        )
        XCTAssertTrue(
            pluginSource.contains("case .accessor(let copyIOError):"),
            "copy() should surface the combined-path inner IO failure "
                + "distinctly from the coordination failure (R14) instead "
                + "of leaving the Flutter call without a result."
        )
    }

    func testLiveWriterReplacesExistingLocalFile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("old".utf8).write(to: destinationURL)

        let handled = try await CoordinatedReplaceWriter.live.overwriteExistingItem(
            at: destinationURL
        ) { replacementURL in
            try Data("new".utf8).write(to: replacementURL)
        }

        XCTAssertTrue(handled)
        XCTAssertEqual(try String(contentsOf: destinationURL), "new")
    }

    func testLiveWriterRejectsExistingDirectoryDestination() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent(
            "folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        do {
            _ = try await CoordinatedReplaceWriter.live.overwriteExistingItem(
                at: destinationURL
            ) { replacementURL in
                try Data("new".utf8).write(to: replacementURL)
            }
            XCTFail("expected directory-rejection error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an existing directory with file content."
            )
        }
    }

    /// VAL-MUT-006: a verifyDestination failure against an existing file
    /// throws a typed error and never reaches staging/replace.
    func testOverwriteExistingItemThrowsWhenVerifyDestinationFails() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in
                throw NSError(
                    domain: "ICloudStoragePlusErrorDomain",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace an existing directory with file content.",
                    ]
                )
            },
            createReplacementDirectory: { _ in
                XCTFail("should not create replacement directory")
                return URL(fileURLWithPath: "/tmp/replacement")
            },
            coordinateReplace: { _, _ in
                XCTFail("should not coordinate replace")
            },
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { _ in
                preparedReplacement = true
            }
            XCTFail("expected verifyDestination failure to bubble")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an existing directory with file content."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() async throws {
        var preparedReplacement = false
        var verifiedDestinationState = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
            verifyDestination: { _ in
                verifiedDestinationState = true
            },
            createReplacementDirectory: { _ in
                XCTFail("should not create replacement directory")
                return URL(fileURLWithPath: "/tmp")
            },
            coordinateReplace: { _, _ in
                XCTFail("should not coordinate replace")
            },
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        let handled = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in
            preparedReplacement = true
        }

        XCTAssertFalse(handled)
        XCTAssertFalse(preparedReplacement)
        XCTAssertFalse(verifiedDestinationState)
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in throw expectedError },
            removeItem: { cleanedURL = $0 }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { url in
                XCTAssertEqual(
                    url.deletingLastPathComponent().path,
                    replacementDirectory.path
                )
            }
            XCTFail("expected replace failure to bubble")
        } catch {
            XCTAssertEqual((error as NSError).code, expectedError.code)
        }

        XCTAssertNotNil(cleanedURL)
    }

    // MARK: - Phase 2: coordinated overwrite behavior

    private func makeWriter(
        fileExists: @escaping CoordinatedReplaceWriter.FileExists = { _ in true },
        verifyDestination: @escaping CoordinatedReplaceWriter.VerifyDestination = { _ in
            XCTFail("verifyDestination should not fire in happy path")
        },
        coordinateReplace: @escaping CoordinatedReplaceWriter.CoordinateReplace = {
            url, accessor in try accessor(url)
        },
        replaceItem: @escaping CoordinatedReplaceWriter.ReplaceItem = { _, _ in },
        createReplacementDirectory: @escaping CoordinatedReplaceWriter.CreateReplacementDirectory
            = { _ in URL(fileURLWithPath: "/tmp/replacement") },
        removeItem: @escaping CoordinatedReplaceWriter.RemoveItem = { _ in }
    ) -> CoordinatedReplaceWriter {
        CoordinatedReplaceWriter(
            fileExists: fileExists,
            verifyDestination: verifyDestination,
            createReplacementDirectory: createReplacementDirectory,
            coordinateReplace: coordinateReplace,
            replaceItem: replaceItem,
            removeItem: removeItem
        )
    }

    func testHappyPathDoesNotReinvokePreFlight() async throws {
        let callbacks = LockedCallbacks()

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in callbacks.bumpVerify() },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/r") },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in callbacks.bumpReplace() },
            removeItem: { _ in }
        )

        let handled = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertTrue(handled)
        XCTAssertEqual(
            callbacks.replaceItemCount, 1,
            "replaceItem must run exactly once"
        )
    }

    /// VAL-MUT-016: step order is now
    /// `verifyDestination → coordinateReplace → replaceItem` (no resolve step).
    func testVerifyDestinationRunsBeforeCoordinateReplace() async throws {
        let log = LockedCallLog()

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in log.append("verifyDestination") },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/r") },
            coordinateReplace: { url, accessor in
                log.append("coordinateReplace")
                try accessor(url)
            },
            replaceItem: { _, _ in log.append("replaceItem") },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(
            log.events,
            [
                "verifyDestination",
                "coordinateReplace",
                "replaceItem",
            ],
            "step order must match spec: pre-flight → coord → replace "
                + "(no resolve step)"
        )
    }

    /// VAL-MUT-001: replaceItem targets the coordinator-yielded URL.
    func testReplaceItemUsesCoordinatedURL() async throws {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let coordinatedURL = URL(fileURLWithPath: "/tmp/coordinated-file.json")
        var capturedReplaceDestination: URL?

        let writer = makeWriter(
            verifyDestination: { _ in },
            coordinateReplace: { _, accessor in try accessor(coordinatedURL) },
            replaceItem: { target, _ in capturedReplaceDestination = target }
        )

        _ = try await writer.overwriteExistingItem(
            at: destinationURL
        ) { _ in }

        XCTAssertEqual(
            capturedReplaceDestination, coordinatedURL,
            "replaceItem must run against the closure-provided URL, not the input URL."
        )
    }

    /// VAL-MUT-005 case A: a coordinator failure yields a coordination-domain
    /// error and never attempts the inner replace.
    func testCoordinatorFailureSurfacesAsCoordinationError() async {
        let coordinationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError
        )
        var replaceInvoked = false

        let writer = makeWriter(
            verifyDestination: { _ in },
            coordinateReplace: { _, _ in throw coordinationError },
            replaceItem: { _, _ in replaceInvoked = true }
        )

        do {
            _ = try await writer.overwriteExistingItem(
                at: URL(fileURLWithPath: "/tmp/file.json")
            ) { _ in }
            XCTFail("expected coordination error")
        } catch {
            XCTAssertEqual((error as NSError), coordinationError)
        }

        XCTAssertFalse(replaceInvoked)
    }

    /// VAL-MUT-005 case B: a successful coordinator + throwing replaceItem
    /// yields the inner IO error preserved.
    func testInnerReplaceFailureSurfacesAsIOError() async {
        let ioError = NSError(domain: NSCocoaErrorDomain, code: 512)

        let writer = makeWriter(
            verifyDestination: { _ in },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in throw ioError }
        )

        do {
            _ = try await writer.overwriteExistingItem(
                at: URL(fileURLWithPath: "/tmp/file.json")
            ) { _ in }
            XCTFail("expected IO error")
        } catch {
            XCTAssertEqual((error as NSError), ioError)
        }
    }

    /// VAL-MUT-040: a mid-stage replace failure leaves the destination
    /// intact and cleans the staged temp directory.
    func testAtomicReplaceLeavesDestinationIntactAndCleansTempOnFailure() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("original".utf8).write(to: destinationURL)

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in
                try FileManager.default.url(
                    for: .itemReplacementDirectory,
                    in: .userDomainMask,
                    appropriateFor: destinationURL,
                    create: true
                )
            },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in
                throw NSError(domain: NSCocoaErrorDomain, code: 512)
            },
            removeItem: { url in
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        )

        do {
            _ = try await writer.overwriteExistingItem(
                at: destinationURL
            ) { replacementURL in
                try Data("new".utf8).write(to: replacementURL)
            }
            XCTFail("expected replace failure")
        } catch {
            // expected
        }

        XCTAssertEqual(
            try String(contentsOf: destinationURL), "original",
            "destination must be unchanged after a mid-stage failure"
        )

        let tempRoot = FileManager.default.temporaryDirectory.path
        let tempContents = (try? FileManager.default.contentsOfDirectory(
            atPath: tempRoot
        )) ?? []
        let leftoverTemps = tempContents.filter {
            $0.contains("itemReplacementDirectory")
                || $0.contains("( iCloud Documents )")
        }
        XCTAssertTrue(
            leftoverTemps.isEmpty,
            "no staged itemReplacementDirectory temp should leak: \(leftoverTemps)"
        )
    }

    func testVerifyOverwriteDestinationIsFileRejectsDirectory() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let nestedDirectory = temporaryDirectory
            .appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try CoordinatedReplaceWriter
                .verifyOverwriteDestinationIsFile(at: nestedDirectory)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an existing directory with file content."
            )
        }
    }

    func testVerifyOverwriteDestinationIsFileAcceptsRegularFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("payload".utf8).write(to: fileURL)

        // Must not throw — directory-only check, no conflict / download
        // refusal logic.
        try CoordinatedReplaceWriter
            .verifyOverwriteDestinationIsFile(at: fileURL)
    }

    func testCoordinationErrorPreservesUnderlyingNativeSignature() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "coordination failed"]
        )

        let wrapped = CoordinatedReplaceWriter.coordinationError(
            underlying: underlying
        )

        XCTAssertEqual(
            wrapped.domain,
            CoordinatedReplaceWriter.replaceStateErrorDomain
        )
        XCTAssertEqual(
            wrapped.code,
            CoordinatedReplaceWriter.coordinationReplaceStateCode
        )
        XCTAssertEqual(
            wrapped.userInfo[NSUnderlyingErrorKey] as? NSError,
            underlying
        )
    }

    // MARK: - Slice C: deadlock-free coord bridge contract

    private func iOSPluginSource() throws -> String {
        try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Sources/icloud_storage_plus_foundation/Tests/"
                        + "icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/Sources/icloud_storage_plus/"
                        + "iOSICloudStoragePlugin.swift"
                ),
            encoding: .utf8
        )
    }

    func testLiveCoordinateReplaceDoesNotStarveCooperativePool() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let concurrency = max(
            ProcessInfo.processInfo.activeProcessorCount * 2,
            8
        )

        // Pre-populate destination files so NSFileCoordinator has
        // something concrete to coordinate against.
        let destinations: [URL] = (0..<concurrency).map { index in
            let url = temporaryDirectory.appendingPathComponent("file-\(index).bin")
            try? Data("seed-\(index)".utf8).write(to: url)
            return url
        }

        let started = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in destinations {
                group.addTask {
                    try await CoordinatedReplaceWriter.liveCoordinateReplace(url) {
                        coordinatedURL in
                        // Synthetic accessor: write 1 KB inline, sync.
                        // No NSFileVersion, no async hops — exactly
                        // matches the production accessor's shape.
                        try Data(repeating: 0xAB, count: 1024)
                            .write(to: coordinatedURL)
                    }
                }
            }
            try await group.waitForAll()
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed, 5.0,
            "liveCoordinateReplace must not starve the Swift cooperative "
                + "pool. \(concurrency) concurrent coords completed in "
                + "\(String(format: "%.2f", elapsed))s; a DispatchSemaphore-based "
                + "bridge would deadlock here under load."
        )

        // Sanity: every destination got the new content.
        for url in destinations {
            let data = try Data(contentsOf: url)
            XCTAssertEqual(data.count, 1024)
        }
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
