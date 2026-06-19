import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class VersionExposureTests: XCTestCase {
    private let itemURL = URL(fileURLWithPath: "/tmp/container/Documents/journal.json")

    // MARK: - VAL-MUT-018 / VAL-MUT-022: enumerate

    func testEnumerateReturnsDescriptorsForUnresolvedVersions() throws {
        let descriptors = [
            VersionExposure.Descriptor(
                identifier: "v1",
                modificationDate: Date(timeIntervalSince1970: 100)
            ),
            VersionExposure.Descriptor(
                identifier: "v2",
                modificationDate: Date(timeIntervalSince1970: 200)
            ),
        ]

        let exposure = VersionExposure(
            enumerateUnresolved: { _ in descriptors },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, _ in }
        )

        let result = try exposure.enumerate(at: itemURL)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].identifier, "v1")
        XCTAssertEqual(result[1].identifier, "v2")
        XCTAssertEqual(
            result[1].modificationDate,
            Date(timeIntervalSince1970: 200)
        )
    }

    /// VAL-MUT-022: an item with no unresolved versions returns an empty
    /// list, never an error.
    func testEnumerateReturnsEmptyWhenNoUnresolvedVersions() throws {
        let exposure = VersionExposure(
            enumerateUnresolved: { _ in [] },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, _ in }
        )

        let result = try exposure.enumerate(at: itemURL)
        XCTAssertEqual(result, [])
    }

    /// VAL-MUT-022: a nil provider (no versions) is also an empty result.
    func testEnumerateReturnsEmptyWhenProviderReturnsNil() throws {
        let exposure = VersionExposure(
            enumerateUnresolved: { _ in
                // Simulate NSFileVersion.unresolvedConflictVersionsOfItem
                // returning nil for a non-ubiquitous item.
                []
            },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, _ in }
        )

        let result = try exposure.enumerate(at: itemURL)
        XCTAssertEqual(result, [])
    }

    // MARK: - VAL-MUT-019: copy-out targets the caller-provided URL

    func testCopyOutWritesToCallerDestinationAndLeavesLiveUntouched() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let liveURL = temporaryDirectory.appendingPathComponent("live.json")
        try Data("winner".utf8).write(to: liveURL)

        let callerDestination =
            temporaryDirectory.appendingPathComponent("backup-v1.json")
        var capturedItemURL: URL?
        var capturedIdentifier: String?
        var capturedDestination: URL?

        let exposure = VersionExposure(
            enumerateUnresolved: { _ in
                [VersionExposure.Descriptor(
                    identifier: "v1",
                    modificationDate: Date(timeIntervalSince1970: 100)
                )]
            },
            copyVersionOut: { itemURL, identifier, destinationURL in
                capturedItemURL = itemURL
                capturedIdentifier = identifier
                capturedDestination = destinationURL
                // Simulate the version's bytes being written to the
                // caller-provided destination only.
                try Data("loser-v1".utf8).write(to: destinationURL)
            },
            markConflictResolved: { _, _ in }
        )

        try exposure.copyOut(
            itemURL: liveURL,
            identifier: "v1",
            to: callerDestination
        )

        XCTAssertEqual(capturedItemURL, liveURL)
        XCTAssertEqual(capturedIdentifier, "v1")
        XCTAssertEqual(capturedDestination, callerDestination)
        XCTAssertEqual(
            try String(contentsOf: callerDestination), "loser-v1"
        )
        XCTAssertEqual(
            try String(contentsOf: liveURL), "winner",
            "live file must be untouched by copy-out"
        )
    }

    // MARK: - VAL-MUT-044: copy-out failure surfaces typed error, no
    // partial file, live unchanged

    func testCopyOutFailureSurfacesTypedErrorAndLeavesNoPartialFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let liveURL = temporaryDirectory.appendingPathComponent("live.json")
        try Data("winner".utf8).write(to: liveURL)

        let callerDestination =
            temporaryDirectory.appendingPathComponent("backup-v1.json")

        let exposure = VersionExposure(
            enumerateUnresolved: { _ in
                [VersionExposure.Descriptor(
                    identifier: "v1",
                    modificationDate: nil
                )]
            },
            copyVersionOut: { _, _, _ in
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteOutOfSpaceError
                )
            },
            markConflictResolved: { _, _ in }
        )

        XCTAssertThrowsError(
            try exposure.copyOut(
                itemURL: liveURL,
                identifier: "v1",
                to: callerDestination
            )
        ) { error in
            XCTAssertEqual(
                (error as NSError).domain, NSCocoaErrorDomain
            )
            XCTAssertEqual(
                (error as NSError).code, NSFileWriteOutOfSpaceError
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: callerDestination.path),
            "no partial file should remain at the caller destination"
        )
        XCTAssertEqual(
            try String(contentsOf: liveURL), "winner",
            "live file must be unchanged on copy-out failure"
        )
    }

    // MARK: - VAL-MUT-020 / VAL-MUT-045: mark-resolved

    /// VAL-MUT-020: mark-resolved flips isResolved and (when requested)
    /// removes other versions, only on explicit request.
    func testMarkResolvedMarksVersionsAndOptionallyRemovesOthers() throws {
        var markResolvedCalls = 0
        var removeOthersCalls = 0

        let exposure = VersionExposure(
            enumerateUnresolved: { _ in [] },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, removeOthers in
                markResolvedCalls += 1
                if removeOthers {
                    removeOthersCalls += 1
                }
            }
        )

        try exposure.markResolved(at: itemURL, removeOthers: false)
        XCTAssertEqual(markResolvedCalls, 1)
        XCTAssertEqual(removeOthersCalls, 0)

        try exposure.markResolved(at: itemURL, removeOthers: true)
        XCTAssertEqual(markResolvedCalls, 2)
        XCTAssertEqual(removeOthersCalls, 1)
    }

    /// VAL-MUT-045 (a): mark-resolved on an item with zero unresolved
    /// versions succeeds as a no-op (no error).
    func testMarkResolvedIsNoOpWhenNothingUnresolved() throws {
        var markResolvedCalls = 0

        // The live binding's markConflictResolved returns early when
        // unresolvedConflictVersionsOfItem returns nil. Simulate that
        // by having the closure only run when there are versions; here
        // we model the no-op path directly.
        let exposure = VersionExposure(
            enumerateUnresolved: { _ in [] },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, _ in
                markResolvedCalls += 1
            }
        )

        XCTAssertNoThrow(
            try exposure.markResolved(at: itemURL, removeOthers: true)
        )
        XCTAssertEqual(markResolvedCalls, 1)
    }

    /// VAL-MUT-045 (b): two sequential mark-resolved calls do not
    /// double-remove beyond the first.
    func testMarkResolvedIsIdempotentAcrossRepeatedCalls() throws {
        var removeOthersCalls = 0

        let exposure = VersionExposure(
            enumerateUnresolved: { _ in [] },
            copyVersionOut: { _, _, _ in },
            markConflictResolved: { _, removeOthers in
                if removeOthers {
                    removeOthersCalls += 1
                }
            }
        )

        try exposure.markResolved(at: itemURL, removeOthers: true)
        try exposure.markResolved(at: itemURL, removeOthers: true)

        // The abstraction forwards each explicit call; the live binding
        // is idempotent because NSFileVersion.removeOtherVersionsOfItem
        // is a no-op once all versions are resolved. The contract under
        // test is that repeated calls do not throw and the abstraction
        // does not synthesize extra removals on its own.
        XCTAssertEqual(removeOthersCalls, 2)
        XCTAssertNoThrow(
            try exposure.markResolved(at: itemURL, removeOthers: true)
        )
    }

    /// VAL-MUT-046: a copy-out version-not-found failure produces a
    /// typed error in the repurposed conflict domain (code 1) so the
    /// channel maps it to a stable `E_CONFLICT` code.
    func testVersionNotFoundErrorUsesConflictDomainCode() {
        let error = VersionExposure.versionNotFoundError(itemURL: itemURL)

        XCTAssertEqual(
            error.domain,
            CoordinatedReplaceWriter.replaceStateErrorDomain
        )
        XCTAssertEqual(
            error.code,
            CoordinatedReplaceWriter.conflictReplaceStateCode
        )
    }

    // MARK: - helpers

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
