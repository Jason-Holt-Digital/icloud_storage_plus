import Foundation

/// Moves items into and out of the ubiquity container with
/// `FileManager.setUbiquitous(_:itemAt:destinationURL:)`.
///
/// `setUbiquitous` coordinates the move itself and can block while iCloud
/// works, so it must not run on the main thread or inside a file
/// coordinator block. Both moves run on a `DispatchQueue.global` worker.
/// Apple leaves creating intermediate container directories to the
/// caller; `moveIntoContainer` creates them with a coordinated write
/// before the move.
///
/// DI-via-closures (same idiom as `UbiquitousItemMaterializer`): XCTest
/// injects recording closures; `static let live` binds `FileManager`.
@available(macOS 10.15, iOS 13.0, *)
struct UbiquitousItemMover {
    typealias Execute = (
        @escaping @Sendable () throws -> Void
    ) async throws -> Void
    typealias CreateDirectory = @Sendable (URL) async throws -> Void
    typealias SetUbiquitous = @Sendable (Bool, URL, URL) throws -> Void

    let execute: Execute
    let createDirectory: CreateDirectory
    let setUbiquitous: SetUbiquitous

    /// Moves the local item at [localURL] to [destinationURL] in the
    /// container. Foundation refuses an existing destination.
    func moveIntoContainer(localURL: URL, destinationURL: URL) async throws {
        try await createDirectory(destinationURL.deletingLastPathComponent())
        let setUbiquitous = self.setUbiquitous
        try await execute {
            try setUbiquitous(true, localURL, destinationURL)
        }
    }

    /// Moves the container item at [itemURL] to the local [localURL]. The
    /// item leaves iCloud on every device.
    func moveOutOfContainer(itemURL: URL, localURL: URL) async throws {
        let setUbiquitous = self.setUbiquitous
        try await execute {
            try setUbiquitous(false, itemURL, localURL)
        }
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension UbiquitousItemMover {
    /// Creates [directoryURL] and missing parents with a coordinated write.
    /// Coordinator and IO failures surface as their native `NSError`.
    static let coordinatedCreateDirectory: CreateDirectory = { directoryURL in
        do {
            try await CoordinatedIO.coordinateWriting(
                at: directoryURL,
                options: []
            ) { coordinatedURL in
                try FileManager.default.createDirectory(
                    at: coordinatedURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        } catch let bridgeError as CoordinateBridgeError {
            switch bridgeError {
            case .coordination(let error):
                throw error
            case .accessor(let error):
                throw error
            }
        }
    }

    static let live = UbiquitousItemMover(
        execute: { work in
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try work()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        },
        createDirectory: coordinatedCreateDirectory,
        setUbiquitous: { flag, itemURL, destinationURL in
            try FileManager.default.setUbiquitous(
                flag,
                itemAt: itemURL,
                destinationURL: destinationURL
            )
        }
    )
}
