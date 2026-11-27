import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

/// Each failure that reaches Flutter as the same `NSCocoaErrorDomain` 256
/// must produce a different error chain.
final class NativeErrorChainTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeErrorChainTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// The text read path: one coordinated `Data(contentsOf:)`, then UTF-8.
    private func readTextFailure(at url: URL) async -> NSError? {
        do {
            let data = try await CoordinatedIO.coordinateReadingReturning(
                at: url,
                options: []
            ) { coordinatedURL in
                try Data(contentsOf: coordinatedURL)
            }
            _ = try decodeUTF8Text(data)
            return nil
        } catch CoordinateBridgeError.coordination(let error) {
            return error as NSError
        } catch CoordinateBridgeError.accessor(let error) {
            return error as NSError
        } catch {
            return error as NSError
        }
    }

    private func links(_ error: NSError) -> [String] {
        nativeErrorChain(error).map { entry in
            let domain = entry["domain"] as! String
            let code = entry["code"] as! Int
            let reason = entry["pluginReason"] as? String
            return reason.map { "\(domain) \(code) \($0)" } ?? "\(domain) \(code)"
        }
    }

    func testInvalidUTF8FileIsMarkedAsPluginBuilt() async throws {
        let file = directory.appendingPathComponent("bad.json")
        try Data([0x7B, 0xFF, 0xFE, 0x7D]).write(to: file)

        let failure = await readTextFailure(at: file)
        let error = try XCTUnwrap(failure)

        XCTAssertEqual(error.domain, NSCocoaErrorDomain)
        XCTAssertEqual(error.code, NSFileReadUnknownError)
        XCTAssertEqual(links(error), ["NSCocoaErrorDomain 256 invalidUTF8Text"])
    }

    func testUTF16FileIsMarkedAsPluginBuilt() async throws {
        let file = directory.appendingPathComponent("utf16.json")
        try XCTUnwrap("{}".data(using: .utf16)).write(to: file)

        let failure = await readTextFailure(at: file)
        let error = try XCTUnwrap(failure)

        XCTAssertEqual(links(error), ["NSCocoaErrorDomain 256 invalidUTF8Text"])
    }

    func testDirectoryAtPathKeepsFoundationsNestedPOSIXCode() async throws {
        let folder = directory.appendingPathComponent("folder.json")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: false
        )

        let failure = await readTextFailure(at: folder)
        let error = try XCTUnwrap(failure)

        XCTAssertEqual(error.domain, NSCocoaErrorDomain)
        XCTAssertEqual(error.code, NSFileReadUnknownError)
        XCTAssertEqual(
            links(error),
            ["NSCocoaErrorDomain 256", "NSPOSIXErrorDomain 21"]
        )
    }

    func testMissingFileKeepsFoundationsNestedPOSIXCode() async throws {
        let file = directory.appendingPathComponent("missing.json")

        let failure = await readTextFailure(at: file)
        let error = try XCTUnwrap(failure)

        XCTAssertEqual(
            links(error),
            ["NSCocoaErrorDomain 260", "NSPOSIXErrorDomain 2"]
        )
    }

    /// Foundation reports a failed read of a dataless iCloud file as 256 with
    /// the POSIX errno nested under it: 11 when materialization is off, 60
    /// when the download times out. Those need a real iCloud placeholder, so
    /// this builds the error in the shape `Data(contentsOf:)` throws.
    func testNestedPOSIXCodesStayDistinctUnderTheSameCocoaCode() {
        func foundationReadError(errno: Int32) -> NSError {
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [
                    NSFilePathErrorKey: "/private/var/mobile/Journal.json",
                    NSUnderlyingErrorKey: NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errno)
                    ),
                ]
            )
        }

        let chains = [EDEADLK, ETIMEDOUT, EIO].map {
            links(foundationReadError(errno: $0))
        }

        XCTAssertEqual(chains, [
            ["NSCocoaErrorDomain 256", "NSPOSIXErrorDomain 11"],
            ["NSCocoaErrorDomain 256", "NSPOSIXErrorDomain 60"],
            ["NSCocoaErrorDomain 256", "NSPOSIXErrorDomain 5"],
        ])
    }

    func testPluginBuiltDocumentErrorsCarryTheirReason() {
        let reasons: [PluginErrorReason] = [
            .documentOpenFailed,
            .invalidUTF8TextInFileWrapper,
            .unsupportedDocumentContents,
        ]

        let chains = reasons.map {
            links(PluginError.make($0, code: NSFileReadUnknownError, description: "x"))
        }

        XCTAssertEqual(chains, [
            ["NSCocoaErrorDomain 256 documentOpenFailed"],
            ["NSCocoaErrorDomain 256 invalidUTF8TextInFileWrapper"],
            ["NSCocoaErrorDomain 256 unsupportedDocumentContents"],
        ])
    }

    func testChainHoldsNoDescriptionsOrPaths() async throws {
        let folder = directory.appendingPathComponent("Secret Journal.json")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: false
        )
        let failure = await readTextFailure(at: folder)
        let error = try XCTUnwrap(failure)

        for entry in nativeErrorChain(error) {
            XCTAssertTrue(Set(entry.keys).isSubset(of: ["domain", "code", "pluginReason"]))
            for value in entry.values {
                XCTAssertFalse("\(value)".contains("Secret"))
            }
        }
    }

    func testDeeplyNestedErrorStopsAtTheDepthLimit() {
        var chainError = NSError(domain: "Loop", code: 1)
        for _ in 0..<20 {
            chainError = NSError(
                domain: "Loop",
                code: 1,
                userInfo: [NSUnderlyingErrorKey: chainError]
            )
        }

        XCTAssertEqual(nativeErrorChain(chainError).count, 8)
    }
}
