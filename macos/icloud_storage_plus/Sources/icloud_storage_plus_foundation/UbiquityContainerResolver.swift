import Foundation

@available(macOS 10.15, iOS 13.0, *)
struct UbiquityContainerResolver {
    typealias Execute = (
        @escaping @Sendable () -> URL?
    ) async -> URL?
    typealias ResolveContainerURL = (String) -> URL?
    typealias Delay = (TimeInterval) async -> Void

    static let maxAttempts = 2
    static let maximumRetryDelay: TimeInterval = 0.15

    let execute: Execute
    let resolveContainerURL: ResolveContainerURL
    let delay: Delay
    let retryDelay: TimeInterval

    func resolve(containerId: String) async -> URL? {
        for attempt in 0..<Self.maxAttempts {
            if let containerURL = await execute({
                resolveContainerURL(containerId)
            }) {
                return containerURL
            }

            if attempt < Self.maxAttempts - 1 {
                await delay(clampedRetryDelay)
            }
        }

        return nil
    }

    private var clampedRetryDelay: TimeInterval {
        max(0, min(retryDelay, Self.maximumRetryDelay))
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
        },
        delay: { delay in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        retryDelay: maximumRetryDelay
    )
}
