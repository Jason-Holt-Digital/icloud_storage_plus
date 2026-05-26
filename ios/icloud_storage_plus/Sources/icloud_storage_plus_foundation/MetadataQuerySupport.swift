import Foundation

/// Metadata-query scopes shared by iCloud code paths.
let iCloudMetadataQuerySearchScopes: [String] = [
    NSMetadataQueryUbiquitousDataScope,
    NSMetadataQueryUbiquitousDocumentsScope,
]

/// Resume-at-most-once gate for native operations with multiple callbacks.
final class CompletionGate {
    private let queue = DispatchQueue(
        label: "icloud_storage_plus.completion_gate"
    )
    private var completed = false

    var isCompleted: Bool {
        queue.sync { completed }
    }

    func tryComplete() -> Bool {
        queue.sync {
            if completed { return false }
            completed = true
            return true
        }
    }
}
