import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_channel_codec.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_engine.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_exception.dart';

/// The Dart end of the CloudKit sync bridge's method channel.
///
/// The native side runs one engine, so one delegate receives its calls.
abstract final class CloudKitSyncChannel {
  static const _channel = MethodChannel('icloud_storage_plus/cloudkit_sync');

  static CloudKitSyncDelegate? _delegate;
  static final _progressListeners = <int, void Function(double)>{};
  static int _nextTransferId = 0;

  /// Makes [delegate] the receiver of engine calls.
  static void attach(CloudKitSyncDelegate delegate) {
    _delegate = delegate;
    _channel.setMethodCallHandler(_handle);
  }

  /// Registers [onProgress] for a download and returns its transfer ID.
  static int addProgressListener(void Function(double fraction) onProgress) {
    _channel.setMethodCallHandler(_handle);
    final transferId = _nextTransferId++;
    _progressListeners[transferId] = onProgress;
    return transferId;
  }

  /// Unregisters the listener for [transferId].
  static void removeProgressListener(int transferId) =>
      _progressListeners.remove(transferId);

  /// Calls [method] on the native side, converting its failures to
  /// [CloudKitSyncException].
  static Future<T?> invoke<T>(String method, Map<String, Object?> arguments) {
    return _channel.invokeMethod<T>(method, arguments).catchError(
          (Object error) => throw CloudKitSyncException.fromPlatformException(
            error as PlatformException,
          ),
          test: (error) => error is PlatformException,
        );
  }

  static Future<Object?> _handle(MethodCall call) async {
    final arguments = call.arguments as Map<Object?, Object?>;
    if (call.method == 'downloadProgress') {
      _progressListeners[arguments['transferId']! as int]?.call(
        arguments['fraction']! as double,
      );
      return null;
    }
    // The native side calls the delegate only after start attached one.
    final delegate = _delegate!;
    try {
      switch (call.method) {
        case 'handleEvent':
          await delegate.handleEvent(
            CloudKitChannelCodec.decodeEvent(arguments),
          );
          return null;
        case 'nextRecordZoneChangeBatch':
          final batch = await delegate.nextRecordZoneChangeBatch(
            (arguments['pendingChanges']! as List<Object?>)
                .map(CloudKitChannelCodec.decodePendingRecordZoneChange)
                .toList(),
          );
          return batch == null ? null : CloudKitChannelCodec.encodeBatch(batch);
        default:
          throw MissingPluginException(call.method);
      }
    } on Object catch (error, stackTrace) {
      // Nothing on the Dart side awaits these calls, so report the failure
      // where the app sees uncaught framework errors before replying with it.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'icloud_storage_plus',
          context: ErrorDescription('while handling CloudKit ${call.method}'),
        ),
      );
      throw PlatformException(code: 'delegateError', message: '$error');
    }
  }
}
