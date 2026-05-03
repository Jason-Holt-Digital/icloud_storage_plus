import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

/// `NSLock`-guarded counter the sync seam closures can mutate.
/// Replaces the previous `actor`-based bookkeeping that required
/// `await` inside seam closures — those closures are now sync per
/// the Slice B/C/D architectural correction.
private final class LockedCallbacks: @unchecked Sendable {
    private let lock = NSLock()
    private var _ensureDownloadCount = 0
    private var _verifyDestinationCount = 0
    private var _resolveConflictsCount = 0
    private var _replaceItemCount = 0

    var ensureDownloadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _ensureDownloadCount
    }
    var verifyDestinationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _verifyDestinationCount
    }
    var resolveConflictsCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _resolveConflictsCount
    }
    var replaceItemCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _replaceItemCount
    }

    func bumpEnsure() {
        lock.lock(); defer { lock.unlock() }
        _ensureDownloadCount += 1
    }
    func bumpVerify() {
        lock.lock(); defer { lock.unlock() }
        _verifyDestinationCount += 1
    }
    func bumpResolve() {
        lock.lock(); defer { lock.unlock() }
        _resolveConflictsCount += 1
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

    func testHelperSourceDoesNotKeepRedundantNonCurrentGuard() throws {
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
            helperSource.contains("if downloadStatus != .current"),
            "replaceReadyStateError should not keep a non-current guard after "
                + "the earlier .current return."
        )
    }

    func testIOSCopyPropagatesSourceReadCoordinationErrors() throws {
        let pluginSource = try String(
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

        XCTAssertTrue(
            pluginSource.contains("var sourceCoordinationError: NSError?"),
            "copy() should capture read coordination failures before "
                + "falling through to destination handling."
        )
        XCTAssertTrue(
            pluginSource.contains("error: &sourceCoordinationError"),
            "copy() should pass a read coordination error pointer instead "
                + "of discarding coordination failures."
        )
        XCTAssertTrue(
            pluginSource.contains("if let sourceCoordinationError"),
            "copy() should surface a failed source read coordination "
                + "instead of continuing silently."
        )
        XCTAssertTrue(
            pluginSource.contains("var copyCoordinationError: NSError?"),
            "copy() should also capture read/write coordination failures in "
                + "the non-overwrite path."
        )
        XCTAssertTrue(
            pluginSource.contains("error: &copyCoordinationError"),
            "copy() should not discard the combined read/write "
                + "coordination error."
        )
        XCTAssertTrue(
            pluginSource.contains("if let copyCoordinationError"),
            "copy() should surface a failed combined coordination instead "
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

    func testOverwriteExistingItemThrowsWhenDestinationHasUnresolvedConflicts() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in
                throw NSError(
                    domain: "ICloudStoragePlusErrorDomain",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace an iCloud item with unresolved conflict versions.",
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
            resolveConflicts: { _ in
                XCTFail("should not resolve conflicts")
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
            XCTFail("expected conflict error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an iCloud item with unresolved conflict versions."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testOverwriteExistingItemThrowsWhenDestinationIsNotFullyLocal() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in
                throw NSError(
                    domain: "ICloudStoragePlusErrorDomain",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
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
            resolveConflicts: { _ in
                XCTFail("should not resolve conflicts")
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
            XCTFail("expected not-downloaded error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace a nonlocal iCloud item until it is fully downloaded."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testReplaceReadyStateErrorReturnsDistinctDownloadInProgressCode() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: false,
            isUbiquitousItem: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.downloaded,
            isDownloading: true
        ) as NSError?

        XCTAssertEqual(error?.domain, "ICloudStoragePlusErrorDomain")
        XCTAssertEqual(error?.code, 3)
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace an iCloud item while it is downloading."
        )
    }

    func testReplaceReadyStateErrorRejectsDownloadedButNotCurrentItems() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: false,
            isUbiquitousItem: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.downloaded,
            isDownloading: false
        ) as NSError?

        XCTAssertEqual(error?.domain, "ICloudStoragePlusErrorDomain")
        XCTAssertEqual(error?.code, 2)
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace a nonlocal iCloud item until it is fully downloaded."
        )
    }

    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() async throws {
        var preparedReplacement = false
        var verifiedDestinationState = false
        var ensuredDownload = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
            ensureDownloaded: { _ in ensuredDownload = true },
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
            resolveConflicts: { _ in
                XCTFail("should not resolve conflicts")
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
        XCTAssertFalse(ensuredDownload)
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            resolveConflicts: { _ in },
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

    // MARK: - Phase 2: auto-download + auto-resolve behavior

    private func makeWriter(
        fileExists: @escaping CoordinatedReplaceWriter.FileExists = { _ in true },
        ensureDownloaded: @escaping CoordinatedReplaceWriter.EnsureDownloaded = { _ in },
        verifyDestination: @escaping CoordinatedReplaceWriter.VerifyDestination = { _ in
            XCTFail("verifyDestination should not fire in happy path")
        },
        coordinateReplace: @escaping CoordinatedReplaceWriter.CoordinateReplace = {
            url, accessor in try accessor(url)
        },
        resolveConflicts: @escaping CoordinatedReplaceWriter.ResolveConflicts = { _ in },
        replaceItem: @escaping CoordinatedReplaceWriter.ReplaceItem = { _, _ in },
        createReplacementDirectory: @escaping CoordinatedReplaceWriter.CreateReplacementDirectory
            = { _ in URL(fileURLWithPath: "/tmp/replacement") },
        removeItem: @escaping CoordinatedReplaceWriter.RemoveItem = { _ in }
    ) -> CoordinatedReplaceWriter {
        CoordinatedReplaceWriter(
            fileExists: fileExists,
            ensureDownloaded: ensureDownloaded,
            verifyDestination: verifyDestination,
            createReplacementDirectory: createReplacementDirectory,
            coordinateReplace: coordinateReplace,
            resolveConflicts: resolveConflicts,
            replaceItem: replaceItem,
            removeItem: removeItem
        )
    }

    func testHappyPathDoesNotReinvokePreFlight() async throws {
        let callbacks = LockedCallbacks()

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in callbacks.bumpEnsure() },
            verifyDestination: { _ in callbacks.bumpVerify() },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/r") },
            coordinateReplace: { url, accessor in try accessor(url) },
            resolveConflicts: { _ in callbacks.bumpResolve() },
            replaceItem: { _, _ in callbacks.bumpReplace() },
            removeItem: { _ in }
        )

        let handled = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertTrue(handled)
        XCTAssertEqual(
            callbacks.ensureDownloadCount, 1,
            "ensureDownloaded must run exactly once"
        )
        XCTAssertEqual(
            callbacks.resolveConflictsCount, 1,
            "resolveConflicts must run exactly once"
        )
    }

    func testEnsureDownloadedRunsBeforeVerifyDestination() async throws {
        let log = LockedCallLog()

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in log.append("ensureDownloaded") },
            verifyDestination: { _ in log.append("verifyDestination") },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/r") },
            coordinateReplace: { url, accessor in
                log.append("coordinateReplace")
                try accessor(url)
            },
            resolveConflicts: { _ in log.append("resolveConflicts") },
            replaceItem: { _, _ in log.append("replaceItem") },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(
            log.events,
            [
                "ensureDownloaded",
                "verifyDestination",
                "coordinateReplace",
                "resolveConflicts",
                "replaceItem",
            ],
            "step order must match spec: download → pre-flight → coord → resolve → replace"
        )
    }

    func testEnsureDownloadedFailurePreventsWrite() async {
        let failure = NSError(
            domain: "ICloudStorageTimeout",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Download idle timeout"]
        )

        let writer = makeWriter(
            ensureDownloaded: { _ in throw failure },
            verifyDestination: { _ in
                XCTFail("verifyDestination must not run after ensureDownloaded throws")
            },
            resolveConflicts: { _ in
                XCTFail("resolveConflicts must not run after ensureDownloaded throws")
            },
            replaceItem: { _, _ in
                XCTFail("replaceItem must not run after ensureDownloaded throws")
            }
        )

        do {
            _ = try await writer.overwriteExistingItem(
                at: URL(fileURLWithPath: "/tmp/file.json")
            ) { _ in
                XCTFail("prepareReplacementFile must not run after ensureDownloaded throws")
            }
            XCTFail("expected ensureDownloaded failure to bubble")
        } catch {
            XCTAssertEqual((error as NSError).domain, "ICloudStorageTimeout")
        }
    }

    func testResolveConflictsFailureBubblesAndBlocksReplace() async {
        let failure = NSError(
            domain: "ICloudStoragePlusErrorDomain",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace an iCloud item: auto-resolution failed — disk full",
            ]
        )
        var replaceItemInvoked = false

        let writer = makeWriter(
            verifyDestination: { _ in },
            resolveConflicts: { _ in throw failure },
            replaceItem: { _, _ in replaceItemInvoked = true }
        )

        do {
            _ = try await writer.overwriteExistingItem(
                at: URL(fileURLWithPath: "/tmp/file.json")
            ) { _ in }
            XCTFail("expected resolveConflicts failure to bubble")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "ICloudStoragePlusErrorDomain")
            XCTAssertEqual(nsError.code, 1)
            XCTAssertTrue(
                nsError.localizedDescription.contains(
                    CoordinatedReplaceWriter.autoResolveFailedDescriptionMarker
                ),
                "localized description must distinguish auto-resolve from "
                    + "the old pre-flight refusal."
            )
        }
        XCTAssertFalse(replaceItemInvoked)
    }

    func testResolveConflictsIsNoOpWhenNoConflictsExist() async throws {
        var resolveConflictsCount = 0
        var replaceItemCount = 0

        let writer = makeWriter(
            verifyDestination: { _ in },
            resolveConflicts: { _ in resolveConflictsCount += 1 },
            replaceItem: { _, _ in replaceItemCount += 1 }
        )

        let handled = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertTrue(handled)
        XCTAssertEqual(resolveConflictsCount, 1)
        XCTAssertEqual(replaceItemCount, 1)
    }

    // MARK: - Slice A: pre-flight reduction

    func testLiveWriterDoesNotInvokeFullLegacyPreflight() throws {
        let writerSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        // The `live` binding's verifyDestination must be the new
        // directory-only helper, NOT the legacy full pre-flight that
        // refuses on hasConflicts. Auto-resolve runs inside the
        // coordinator block; pre-flight refusal would fire first and
        // make the auto-resolve seam unreachable.
        XCTAssertFalse(
            writerSource.contains("verifyFileDestinationCanBeOverwritten"),
            "live.verifyDestination must NOT route through "
                + "verifyFileDestinationCanBeOverwritten — that helper "
                + "transitively refuses on hasConflicts and would block "
                + "auto-resolution before it can run."
        )
        XCTAssertTrue(
            writerSource.contains("verifyOverwriteDestinationIsFile"),
            "live.verifyDestination must use the directory-only "
                + "verifyOverwriteDestinationIsFile helper introduced by "
                + "Slice A of the PR #25 architectural correction."
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

    func testLegacyFullPreflightStillExistsForCopyPath() {
        // Copy() in iOSICloudStoragePlugin / macOSICloudStoragePlugin
        // continues to call the legacy full pre-flight. This Slice A
        // change must NOT delete or alter that helper.
        let directoryURL = URL(fileURLWithPath: "/tmp/dir-\(UUID().uuidString)")
        // Just confirm the symbol is callable — the behavior under
        // real conflicts is exercised by existing copy-path tests.
        XCTAssertNoThrow(
            try? CoordinatedReplaceWriter
                .verifyExistingDestinationCanBeReplaced(at: directoryURL)
        )
    }

    func testLiveAutoResolveConflictErrorPreservesCoordinationDomain() {
        let underlying = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError,
            userInfo: [NSLocalizedDescriptionKey: "no disk space"]
        )

        let wrapped = CoordinatedReplaceWriter.autoResolveConflictError(
            underlying: underlying
        )

        XCTAssertEqual(
            wrapped.domain,
            CoordinatedReplaceWriter.replaceStateErrorDomain,
            "wrapping must keep the domain Dart consumers map to ICloudConflictException."
        )
        XCTAssertEqual(
            wrapped.code,
            CoordinatedReplaceWriter.conflictReplaceStateCode
        )
        XCTAssertTrue(
            wrapped.localizedDescription.contains(
                CoordinatedReplaceWriter.autoResolveFailedDescriptionMarker
            )
        )
        // Slice D: explicit `as NSError` cast guarantees the value
        // round-trips as NSError for downstream consumers (Dart-side
        // `details["underlying"]`, Sentry breadcrumbs, os_log).
        XCTAssertTrue(
            wrapped.userInfo[NSUnderlyingErrorKey] is NSError,
            "NSUnderlyingErrorKey value must be an NSError, not a "
                + "Swift Error wrapper, so userInfo bridges cleanly."
        )
        XCTAssertEqual(
            (wrapped.userInfo[NSUnderlyingErrorKey] as? NSError)?.code,
            NSFileWriteOutOfSpaceError,
            "Underlying NSError code must be reachable via userInfo "
                + "lookup without re-bridging."
        )
        XCTAssertEqual(
            wrapped.userInfo[NSUnderlyingErrorKey] as? NSError,
            underlying
        )
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
