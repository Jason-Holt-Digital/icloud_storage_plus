import Foundation

/// Kinds emitted when the existing `ICloudDocument` presenter observes a
/// document change.
enum DocumentChangeKind: String {
    case remoteChange
    case conflict
    case savingError
    case editingDisabled
}

/// Listener state for the existing `ICloudDocument` presenter bridge.
///
/// This is not a file presenter and does not observe the filesystem by itself.
/// It only maps presenter callbacks from `ICloudDocument` into stable channel
/// payloads and owns deterministic teardown for the event-channel subscription.
final class DocumentChangeObservation {
    typealias Payload = [String: Any]
    typealias Emit = (Payload) -> Void

    private let relativePath: String
    private let onStart: () -> Void
    private let onCancel: () -> Void
    private let emitPayload: Emit
    private let lock = NSLock()
    private var active = false

    init(
        relativePath: String,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        emit: @escaping Emit
    ) {
        self.relativePath = relativePath
        self.onStart = onStart
        self.onCancel = onCancel
        self.emitPayload = emit
    }

    deinit {
        cancel()
    }

    func start() {
        let shouldStart: Bool = lock.withLock {
            guard !active else { return false }
            active = true
            return true
        }
        if shouldStart {
            onStart()
        }
    }

    func cancel() {
        let shouldCancel: Bool = lock.withLock {
            guard active else { return false }
            active = false
            return true
        }
        if shouldCancel {
            onCancel()
        }
    }

    func emit(kind: DocumentChangeKind) {
        let payload: Payload? = lock.withLock {
            guard active else { return nil }
            return [
                "relativePath": relativePath,
                "kind": kind.rawValue,
            ]
        }
        if let payload {
            emitPayload(payload)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
