import 'dart:async';

import 'package:icloud_storage_plus/models/exceptions.dart';

/// Exposes a stream callback before native allocation and requires the caller
/// to attach a listener synchronously.
final class SynchronousStreamBridge<T> {
  /// Creates a listener-gated stream bridge for [operation].
  SynchronousStreamBridge({
    required this.operation,
    this.fallbackErrorWhenPaused = false,
    this.sourceErrorHasMethodFallback,
    this.onSourceErrorDelivered,
    this.onSourceErrorFallback,
  }) {
    _controller = StreamController<T>(
      sync: true,
      onListen: () => _listening = true,
      onPause: () => _paused = true,
      onResume: () => _paused = false,
      onCancel: () {
        _cancelled = true;
        return _sourceSubscription?.cancel();
      },
    );
  }

  /// Operation name used in argument failures.
  final String operation;

  /// Routes source errors to the operation Future while the listener is paused.
  final bool fallbackErrorWhenPaused;

  /// Identifies source errors that have a matching method-channel fallback.
  final bool Function(Object error)? sourceErrorHasMethodFallback;

  /// Runs before a source error is delivered to an unpaused listener.
  final void Function()? onSourceErrorDelivered;

  /// Runs when a source error must fall back to the operation Future.
  final void Function()? onSourceErrorFallback;

  late final StreamController<T> _controller;
  StreamSubscription<T>? _sourceSubscription;
  bool _listening = false;
  bool _paused = false;
  bool _cancelled = false;

  /// Whether the exposed subscription was cancelled before native setup.
  bool get isCancelled => _cancelled;

  /// Invokes [handler] and requires a listener before it returns.
  void expose(void Function(Stream<T>) handler) {
    try {
      handler(_controller.stream);
    } catch (_) {
      unawaited(_controller.close());
      rethrow;
    }
    if (_listening) return;

    unawaited(_controller.close());
    throw InvalidArgumentException(
      '$operation callback must attach a stream listener synchronously',
    );
  }

  /// Connects [source] after native event-channel allocation succeeds.
  Future<void> attach(Stream<T> source) async {
    final subscription = source.listen(
      (event) {
        if (!_cancelled && !_controller.isClosed) {
          _controller.add(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final hasMethodFallback =
            sourceErrorHasMethodFallback?.call(error) ?? false;
        if (_cancelled || _controller.isClosed) {
          if (hasMethodFallback) onSourceErrorFallback?.call();
          return;
        }
        if (hasMethodFallback && fallbackErrorWhenPaused && _paused) {
          onSourceErrorFallback?.call();
          _closeWithoutWaiting();
          return;
        }

        if (hasMethodFallback) onSourceErrorDelivered?.call();
        _controller.addError(error, stackTrace);
      },
      onDone: () {
        if (!_controller.isClosed) {
          unawaited(_controller.close());
        }
      },
    );
    _sourceSubscription = subscription;
    if (_cancelled) {
      await subscription.cancel();
    }
  }

  /// Delivers a setup failure without waiting for the listener to resume.
  Future<void> fail(Object error, StackTrace stackTrace) async {
    await _sourceSubscription?.cancel();
    if (!_cancelled && !_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
    _closeWithoutWaiting();
  }

  void _closeWithoutWaiting() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}
