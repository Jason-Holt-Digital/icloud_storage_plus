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

/// Keeps optional gather updates alive until the initial snapshot completes.
final class GatherSessionLifecycle {
    private let queue = DispatchQueue(
        label: "icloud_storage_plus.gather_session_lifecycle"
    )
    private var initialGatherCompleted = false
    private var updatesCancelled = false
    private var cancellationClaimed = false

    func initialGatherDidComplete() -> Bool {
        queue.sync {
            initialGatherCompleted = true
            return claimCancellationIfReady()
        }
    }

    func updatesDidCancel() -> Bool {
        queue.sync {
            updatesCancelled = true
            return claimCancellationIfReady()
        }
    }

    private func claimCancellationIfReady() -> Bool {
        guard initialGatherCompleted,
              updatesCancelled,
              !cancellationClaimed else {
            return false
        }
        cancellationClaimed = true
        return true
    }
}
