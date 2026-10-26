import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class UbiquitousItemMoverTests: XCTestCase {
    func testMoveIntoContainerCreatesParentThenMovesOffMainThread() async throws {
        let recorder = Recorder()
        let mover = UbiquitousItemMover(
            execute: UbiquitousItemMover.live.execute,
            createDirectory: { url in
                recorder.append("mkdir \(url.lastPathComponent)")
            },
            setUbiquitous: { flag, item, destination in
                recorder.append(
                    "move \(flag) \(item.lastPathComponent) "
                        + "\(destination.lastPathComponent) "
                        + "main=\(Thread.isMainThread)"
                )
            }
        )

        try await mover.moveIntoContainer(
            localURL: URL(fileURLWithPath: "/local/journals"),
            destinationURL: URL(fileURLWithPath: "/container/Documents/journals")
        )

        XCTAssertEqual(
            recorder.entries,
            ["mkdir Documents", "move true journals journals main=false"]
        )
    }

    func testMoveIntoContainerSkipsMoveWhenParentCannotBeCreated() async {
        let recorder = Recorder()
        let mover = UbiquitousItemMover(
            execute: { work in try work() },
            createDirectory: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            },
            setUbiquitous: { _, _, _ in recorder.append("move") }
        )

        do {
            try await mover.moveIntoContainer(
                localURL: URL(fileURLWithPath: "/local/journals"),
                destinationURL: URL(fileURLWithPath: "/container/Documents/journals")
            )
            XCTFail("expected the directory failure")
        } catch {
            XCTAssertEqual((error as NSError).code, NSFileWriteNoPermissionError)
        }
        XCTAssertEqual(recorder.entries, [])
    }

    func testMoveOutOfContainerPassesFalseWithoutCreatingDirectories() async throws {
        let recorder = Recorder()
        let mover = UbiquitousItemMover(
            execute: { work in try work() },
            createDirectory: { _ in recorder.append("mkdir") },
            setUbiquitous: { flag, item, destination in
                recorder.append(
                    "move \(flag) \(item.path) \(destination.path)"
                )
            }
        )

        try await mover.moveOutOfContainer(
            itemURL: URL(fileURLWithPath: "/container/Documents/journals"),
            localURL: URL(fileURLWithPath: "/local/journals")
        )

        XCTAssertEqual(
            recorder.entries,
            ["move false /container/Documents/journals /local/journals"]
        )
    }

    func testCoordinatedCreateDirectoryCreatesMissingParents() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b", isDirectory: true)

        try await UbiquitousItemMover.coordinatedCreateDirectory(nested)
        try await UbiquitousItemMover.coordinatedCreateDirectory(nested)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: nested.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ entry: String) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }
}
