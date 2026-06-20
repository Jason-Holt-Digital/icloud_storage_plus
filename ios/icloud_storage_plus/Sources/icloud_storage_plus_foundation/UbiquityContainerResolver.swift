import Foundation

@available(macOS 10.15, iOS 13.0, *)
struct UbiquityContainerResolver {
    typealias Execute = (
        @escaping @Sendable () -> URL?
    ) async -> URL?
    typealias ResolveContainerURL = (String) -> URL?

    let execute: Execute
    let resolveContainerURL: ResolveContainerURL

    /// Single-shot ubiquity container lookup. On failure the resolver
    /// returns `nil`; the caller (`WriteEntrypointPreflight`) throws the
    /// same typed `containerUnavailableError` with the same channel code
    /// it always has.
    func resolve(containerId: String) async -> URL? {
        await execute {
            resolveContainerURL(containerId)
        }
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension UbiquityContainerResolver {
    static let live = UbiquityContainerResolver(
        execute: { work in
            await withCheckedContinuation {
                (continuation: CheckedContinuation<URL?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: work())
                }
            }
        },
        resolveContainerURL: {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    )
}
