import Foundation

/// Kinds emitted when the existing `ICloudDocument` presenter observes a
/// document change.
enum DocumentChangeKind: String {
    case invalidation
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

    private enum Lifecycle {
        case pending
        case starting
        case active
        case cancelled
    }

    private let relativePath: String
    private let onStart: () throws -> Void
    private let onCancel: () -> Void
    private let emitPayload: Emit
    private let lock = NSLock()
    private var lifecycle = Lifecycle.pending
    private var lastReadOrWriteModificationDate: Date?

    init(
        relativePath: String,
        onStart: @escaping () throws -> Void,
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

    func start() throws {
        let shouldStart: Bool = lock.withLock {
            guard case .pending = lifecycle else { return false }
            lifecycle = .starting
            return true
        }
        guard shouldStart else { return }

        do {
            try onStart()
        } catch {
            lock.withLock {
                if case .starting = lifecycle {
                    lifecycle = .pending
                }
                lastReadOrWriteModificationDate = nil
            }
            throw error
        }

        let shouldCancel: Bool = lock.withLock {
            switch lifecycle {
            case .starting:
                lifecycle = .active
                return false
            case .cancelled:
                return true
            case .pending, .active:
                return false
            }
        }
        if shouldCancel {
            onCancel()
        }
    }

    func cancel() {
        let shouldCancel: Bool = lock.withLock {
            lastReadOrWriteModificationDate = nil
            switch lifecycle {
            case .pending, .starting:
                lifecycle = .cancelled
                return false
            case .active:
                lifecycle = .cancelled
                return true
            case .cancelled:
                return false
            }
        }
        if shouldCancel {
            onCancel()
        }
    }

    func recordReadOrWrite(modificationDate: Date) {
        lock.withLock {
            guard isObserving else { return }
            lastReadOrWriteModificationDate = modificationDate
        }
    }

    func consumeContentChange(modificationDate: Date) -> Bool {
        lock.withLock {
            guard isObserving else { return false }
            guard modificationDate != lastReadOrWriteModificationDate else {
                return false
            }

            lastReadOrWriteModificationDate = modificationDate
            return true
        }
    }

    func emit(kind: DocumentChangeKind) {
        let payload: Payload? = lock.withLock {
            guard isObserving else { return nil }
            return [
                "relativePath": relativePath,
                "kind": kind.rawValue,
            ]
        }
        if let payload {
            emitPayload(payload)
        }
    }

    private var isObserving: Bool {
        switch lifecycle {
        case .starting, .active:
            return true
        case .pending, .cancelled:
            return false
        }
    }
}

/// Non-thread-safe cancellation state owned by `StreamHandler.stateQueue`.
final class DeferredCancellationHandler {
    typealias Handler = () -> Void

    private enum State {
        case active
        case cancelledAwaitingHandler
        case cancelledDelivered
    }

    private var state = State.active
    private var handler: Handler?

    var current: Handler? {
        handler
    }

    func activate() {
        state = .active
    }

    func install(_ newHandler: Handler?) -> Handler? {
        switch state {
        case .active:
            handler = newHandler
            return nil
        case .cancelledAwaitingHandler:
            guard let newHandler else { return nil }
            state = .cancelledDelivered
            return newHandler
        case .cancelledDelivered:
            return nil
        }
    }

    func cancel() -> Handler? {
        guard case .active = state else { return nil }

        let handlerToRun = handler
        handler = nil
        state = handlerToRun == nil
            ? .cancelledAwaitingHandler
            : .cancelledDelivered
        return handlerToRun
    }
}

/// Linearizes stream delivery against cancellation without invoking the
/// listener while holding the separate handler-state queue. Events produced
/// before the first listener are retained so early terminal failures can be
/// delivered when Dart begins listening.
final class StreamEventDelivery<Event> {
    typealias Listener = (Event) -> Void

    private let lock = NSRecursiveLock()
    private var listener: Listener?
    private var pendingEvents: [Event] = []
    private var cancelled = false

    var hasPendingEvents: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pendingEvents.isEmpty
    }

    func listen(_ newListener: @escaping Listener) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }

        listener = newListener
        let events = pendingEvents
        pendingEvents.removeAll()
        for event in events {
            guard !cancelled else { return }
            newListener(event)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        listener = nil
        pendingEvents.removeAll()
        lock.unlock()
    }

    func emit(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }

        guard let listener else {
            pendingEvents.append(event)
            return
        }
        listener(event)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
