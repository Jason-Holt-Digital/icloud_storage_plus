import Foundation

@available(macOS 10.15, iOS 13.0, *)
struct WriteEntrypointPreflight {
    typealias Execute = (
        @escaping @Sendable () throws -> URL
    ) async throws -> URL
    typealias CreateDirectory = (URL) throws -> Void

    let execute: Execute
    let ubiquityContainerResolver: UbiquityContainerResolver
    let createDirectory: CreateDirectory

    func containerURL(containerId: String) async throws -> URL {
        guard let containerURL = await ubiquityContainerResolver.resolve(
            containerId: containerId
        ) else {
            throw Self.containerUnavailableError()
        }

        return containerURL
    }

    func itemURL(
        containerId: String,
        relativePath: String,
        createParentDirectory: Bool
    ) async throws -> URL {
        let containerURL = try await containerURL(containerId: containerId)
        let fileURL = containerURL.appendingPathComponent(relativePath)

        if createParentDirectory {
            try createDirectory(fileURL.deletingLastPathComponent())
        }

        return fileURL
    }

    func prepare(
        containerId: String,
        relativePath: String
    ) async throws -> URL {
        let containerURL = try await containerURL(containerId: containerId)
        return try await execute {
            let fileURL = containerURL.appendingPathComponent(relativePath)
            try createDirectory(fileURL.deletingLastPathComponent())
            return fileURL
        }
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension WriteEntrypointPreflight {
    static let errorDomain = "ICloudStoragePlusWriteEntrypointPreflight"
    static let containerUnavailableErrorCode = 1

    static func containerUnavailableError() -> NSError {
        NSError(
            domain: errorDomain,
            code: containerUnavailableErrorCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unable to access the requested iCloud container.",
            ]
        )
    }

    static func isContainerUnavailableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == errorDomain
            && nsError.code == containerUnavailableErrorCode
    }

    static let live = WriteEntrypointPreflight(
        execute: { work in
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<URL, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try work())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        },
        ubiquityContainerResolver: .live,
        createDirectory: { directoryURL in
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    )
}
