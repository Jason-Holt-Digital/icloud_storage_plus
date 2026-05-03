import Foundation

/// Owns an NSMetadataQuery and its NotificationCenter observer tokens for
/// the full query lifecycle.
final class MetadataQuerySession {
    typealias ID = UUID
    typealias Cleanup = (MetadataQuerySession) -> Void
    typealias Observer = (
        MetadataQuerySession,
        NSMetadataQuery,
        Notification
    ) -> Void

    let id = ID()
    let query: NSMetadataQuery

    private let stateQueue = DispatchQueue(
        label: "icloud_storage_plus.metadata_query_session"
    )
    private var observerTokens: [NSObjectProtocol] = []
    private var cancelled = false
    private var cleanupFinished = false
    private let onCleanup: Cleanup

    var isCancelled: Bool {
        stateQueue.sync { cancelled }
    }

    init(
        query: NSMetadataQuery,
        onCleanup: @escaping Cleanup
    ) {
        self.query = query
        self.onCleanup = onCleanup
    }

    @discardableResult
    func addObserver(
        name: Notification.Name,
        using observer: @escaping Observer
    ) -> Bool {
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: query,
            queue: query.operationQueue
        ) { [weak self] notification in
            guard let self else { return }
            observer(self, self.query, notification)
        }

        let shouldKeepToken = stateQueue.sync {
            guard !cancelled else { return false }
            observerTokens.append(token)
            return true
        }

        if !shouldKeepToken {
            NotificationCenter.default.removeObserver(token)
        }
        return shouldKeepToken
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.query.start()
        }
    }

    func cancel() {
        let tokens = stateQueue.sync { () -> [NSObjectProtocol]? in
            guard !cancelled else { return nil }
            cancelled = true
            let tokens = observerTokens
            observerTokens.removeAll()
            return tokens
        }

        guard let tokens else { return }
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }

        let stopAndFinish = { [self] in
            if query.isStarted {
                query.stop()
            }
            finishCleanup()
        }

        if Thread.isMainThread {
            stopAndFinish()
        } else {
            DispatchQueue.main.async(execute: stopAndFinish)
        }
    }

    private func finishCleanup() {
        let shouldCleanup = stateQueue.sync { () -> Bool in
            guard !cleanupFinished else { return false }
            cleanupFinished = true
            return true
        }

        if shouldCleanup {
            onCleanup(self)
        }
    }
}
