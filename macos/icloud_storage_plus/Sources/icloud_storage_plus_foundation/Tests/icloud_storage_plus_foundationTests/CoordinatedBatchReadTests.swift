import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class CoordinatedBatchReadTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordinatedBatchReadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReadsPresentFilesInInputOrderAndOmitsMissingOnes() async throws {
        let first = directory.appendingPathComponent("first.json")
        let missing = directory.appendingPathComponent("missing.json")
        let second = directory.appendingPathComponent("nested/second.bin")
        try FileManager.default.createDirectory(
            at: second.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: first)
        try Data([0, 1, 2, 255]).write(to: second)

        let contents = try await CoordinatedIO.readFilesIfPresent(
            at: [first, missing, second]
        )

        XCTAssertEqual(contents, [Data("first".utf8), nil, Data([0, 1, 2, 255])])
    }

    func testEmptyFileReadsAsEmptyData() async throws {
        let empty = directory.appendingPathComponent("empty.txt")
        try Data().write(to: empty)

        let contents = try await CoordinatedIO.readFilesIfPresent(at: [empty])

        XCTAssertEqual(contents, [Data()])
    }

    func testUnreadableItemFailsTheBatchAndNamesItsIndex() async throws {
        let present = directory.appendingPathComponent("present.json")
        try Data("present".utf8).write(to: present)
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        do {
            _ = try await CoordinatedIO.readFilesIfPresent(at: [present, folder])
            XCTFail("Reading a directory as a file must fail the batch")
        } catch let failure as CoordinatedBatchReadFailure {
            XCTAssertEqual(failure.index, 1)
            let nsError = failure.error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
            XCTAssertNotEqual(nsError.code, NSFileReadNoSuchFileError)
            XCTAssertNotEqual(nsError.code, NSFileNoSuchFileError)
        }
    }
}
