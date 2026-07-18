import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/container_item.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/icloud_item_metadata.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
import 'package:icloud_storage_plus/src/platform_exception_decoder.dart';
import 'package:logging/logging.dart';

/// An implementation of [ICloudStoragePlatform] that uses method channels.
class MethodChannelICloudStorage extends ICloudStoragePlatform {
  static final Logger _logger = Logger('ICloudStorage');
  static final int _eventChannelSessionId =
      DateTime.now().microsecondsSinceEpoch;
  static int _nextEventChannelId = 0;

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('icloud_storage_plus');

  @override
  Future<bool> icloudAvailable() async {
    return _invokeRequiredMethod<bool>('icloudAvailable');
  }

  @override
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    final eventChannelName = onUpdate == null
        ? ''
        : _generateEventChannelName('gather', containerId);

    if (onUpdate != null) {
      await _invokeVoidMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final gatherEventChannel = EventChannel(eventChannelName);
      final stream = _receiveMappedEventStream<GatherResult>(
        eventChannel: gatherEventChannel,
        operation: 'gather',
        mapEvent: (event) {
          if (event is! List) {
            throw _channelContractError(
              operation: 'gather',
              message: 'Unexpected gather event type: ${event.runtimeType}',
              underlying: event,
            );
          }
          return _mapFilesFromDynamicList(event, operation: 'gather');
        },
      );

      onUpdate(stream);
    }

    final mapList = await _invokeListMethod<dynamic>('gather', {
      'containerId': containerId,
      'eventChannelName': eventChannelName,
    });

    return _mapFilesFromDynamicList(mapList, operation: 'gather');
  }

  @override
  Future<void> watchDocumentChanges({
    required String containerId,
    required String relativePath,
    required StreamHandler<ICloudDocumentChange> onChange,
  }) async {
    final eventChannelName = _generateEventChannelName(
      'documentChanges',
      containerId,
      relativePath,
    );

    await _invokeVoidMethod(
      'createEventChannel',
      {'eventChannelName': eventChannelName},
    );

    final eventChannel = EventChannel(eventChannelName);
    final eventStream = _receiveMappedEventStream<ICloudDocumentChange>(
      eventChannel: eventChannel,
      operation: 'watchDocumentChanges',
      mapEvent: _mapDocumentChangeEvent,
    );

    StreamSubscription<ICloudDocumentChange>? subscription;
    late final StreamController<ICloudDocumentChange> controller;
    controller = StreamController<ICloudDocumentChange>(
      onListen: () {
        subscription = eventStream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );

    onChange(controller.stream);

    try {
      await _invokeVoidMethod('watchDocumentChanges', {
        'containerId': containerId,
        'relativePath': relativePath,
        'eventChannelName': eventChannelName,
      });
    } on PlatformException catch (error, stackTrace) {
      final mapped = decodePlatformException(error);
      controller.addError(mapped, stackTrace);
      unawaited(controller.close());
      Error.throwWithStackTrace(mapped, stackTrace);
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
      unawaited(controller.close());
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  ICloudDocumentChange _mapDocumentChangeEvent(Object? event) {
    if (event is! Map) {
      throw _channelContractError(
        operation: 'watchDocumentChanges',
        message: 'Unexpected document change event type: ${event.runtimeType}',
        underlying: event,
      );
    }
    if (event['relativePath'] is! String || event['kind'] is! String) {
      throw _channelContractError(
        operation: 'watchDocumentChanges',
        message: 'Malformed document change event payload',
        underlying: event,
      );
    }
    return ICloudDocumentChange.fromMap(event);
  }

  @override
  Future<String?> getContainerPath({required String containerId}) async {
    final result = await _invokeMethod<String>(
      'getContainerPath',
      {'containerId': containerId},
    );
    return result;
  }

  @override
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';
    _TransferProgressSubscription? progressSubscription;

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('uploadFile', containerId);

      await _invokeVoidMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final uploadEventChannel = EventChannel(eventChannelName);
      progressSubscription = _TransferProgressSubscription();
      final stream = _receiveTransferProgressStream(
        uploadEventChannel,
        progressSubscription,
      );

      onProgress(stream);
    }

    await _invokeTransferMethod(
      'uploadFile',
      {
        'containerId': containerId,
        'localFilePath': localPath,
        'relativePath': relativePath,
        'eventChannelName': eventChannelName,
      },
      progressSubscription: progressSubscription,
    );
  }

  /// Runs a transfer method call, routing failures to the progress stream
  /// only when it is still delivering to the caller.
  ///
  /// When a progress stream is attached the native transfer reports failures
  /// through the stream's error channel, so this Future completes normally
  /// instead of reporting the same failure twice. If the caller has already
  /// cancelled the progress subscription, native can no longer deliver the
  /// stream error, so the method-channel failure is the only signal left and
  /// must propagate.
  Future<void> _invokeTransferMethod(
    String method,
    Map<String, Object?> arguments, {
    required _TransferProgressSubscription? progressSubscription,
  }) async {
    if (progressSubscription == null) {
      await _invokeVoidMethod(method, arguments);
      return;
    }
    try {
      await _invokeVoidMethod(method, arguments);
    } on ICloudOperationException {
      if (progressSubscription.cancelledByCaller) rethrow;
      // Otherwise the failure surfaced on the progress stream's error channel.
    }
  }

  @override
  Future<void> downloadFile({
    required String containerId,
    required String relativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';
    _TransferProgressSubscription? progressSubscription;

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('downloadFile', containerId);

      await _invokeVoidMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final downloadEventChannel = EventChannel(eventChannelName);
      progressSubscription = _TransferProgressSubscription();
      final stream = _receiveTransferProgressStream(
        downloadEventChannel,
        progressSubscription,
      );

      onProgress(stream);
    }

    await _invokeTransferMethod(
      'downloadFile',
      {
        'containerId': containerId,
        'relativePath': relativePath,
        'localFilePath': localPath,
        'eventChannelName': eventChannelName,
      },
      progressSubscription: progressSubscription,
    );
  }

  @override
  Future<String> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    return _invokeRequiredMethod<String>(
      'readInPlace',
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );
  }

  @override
  Future<Uint8List> readInPlaceBytes({
    required String containerId,
    required String relativePath,
  }) async {
    return _invokeRequiredMethod<Uint8List>(
      'readInPlaceBytes',
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );
  }

  @override
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    await _invokeVoidMethod('writeInPlace', {
      'containerId': containerId,
      'relativePath': relativePath,
      'contents': contents,
    });
  }

  @override
  Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    await _invokeVoidMethod('writeInPlaceBytes', {
      'containerId': containerId,
      'relativePath': relativePath,
      'contents': contents,
    });
  }

  @override
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    await _invokeVoidMethod('delete', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
  }

  @override
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    await _invokeVoidMethod('move', {
      'containerId': containerId,
      'atRelativePath': fromRelativePath,
      'toRelativePath': toRelativePath,
    });
  }

  @override
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    await _invokeVoidMethod('copy', {
      'containerId': containerId,
      'fromRelativePath': fromRelativePath,
      'toRelativePath': toRelativePath,
    });
  }

  @override
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await _invokeMethod<bool>('documentExists', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
    return result ?? false;
  }

  @override
  Future<ICloudItemMetadata?> getItemMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    const method = 'getItemMetadata';
    final result = await _invokeMethod<Object?>(
      method,
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );
    if (result == null) return null;
    if (result is! Map) {
      throw _unexpectedTypeError(method, 'Map or null', result);
    }
    try {
      _validateICloudFilePayload(result);
      return ICloudItemMetadata.fromMap(result);
    } on Object catch (error) {
      throw _malformedPayloadError(method, error, result);
    }
  }

  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    try {
      final result =
          await methodChannel.invokeMethod<Object?>(method, arguments);
      if (result == null || result is T) return result as T?;
      throw _unexpectedTypeError(method, _typeName<T>(), result);
    } on MissingPluginException catch (error) {
      throw _missingPluginError(method, error);
    } on PlatformException catch (error) {
      throw decodePlatformException(error);
    }
  }

  Future<T> _invokeRequiredMethod<T>(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _invokeMethod<T>(method, arguments);
    if (result != null) return result;
    throw _unexpectedTypeError(method, _typeName<T>(), null);
  }

  Future<void> _invokeVoidMethod(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _invokeMethod<Object?>(method, arguments);
    if (result != null) {
      throw _unexpectedTypeError(method, 'null', result);
    }
  }

  Future<List<T>?> _invokeListMethod<T>(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _invokeMethod<Object?>(method, arguments);
    if (result == null) return null;
    if (result is! List) {
      throw _unexpectedTypeError(method, 'List or null', result);
    }
    final values = <T>[];
    for (var index = 0; index < result.length; index++) {
      final value = result[index];
      if (value is! T) {
        throw _channelContractError(
          operation: method,
          message: 'Expected ${_typeName<T>()} at index $index, '
              'got ${value.runtimeType}',
          underlying: value,
        );
      }
      values.add(value);
    }
    return values;
  }

  ICloudOperationException _missingPluginError(
    String operation,
    MissingPluginException error,
  ) =>
      _channelContractError(
        operation: operation,
        message: 'Missing native plugin implementation for $operation',
        underlying: error,
      );

  ICloudOperationException _unexpectedTypeError(
    String operation,
    String expected,
    Object? actual,
  ) =>
      _channelContractError(
        operation: operation,
        message: 'Expected $expected, got ${actual.runtimeType}',
        underlying: actual,
      );

  ICloudOperationException _malformedPayloadError(
    String operation,
    Object error,
    Object? payload,
  ) =>
      _channelContractError(
        operation: operation,
        message: 'Malformed $operation payload: $error',
        underlying: payload,
      );

  String _typeName<T>() => T.toString();

  ICloudOperationException _channelContractError({
    required String operation,
    required String message,
    Object? underlying,
  }) {
    return ICloudOperationException.pluginContract(
      operation: operation,
      message: message,
      underlying: underlying,
    );
  }

  Stream<T> _receiveMappedEventStream<T>({
    required EventChannel eventChannel,
    required String operation,
    required T Function(Object? event) mapEvent,
  }) {
    return eventChannel.receiveBroadcastStream().transform(
          StreamTransformer<Object?, T>.fromHandlers(
            handleData: (event, sink) {
              try {
                sink.add(mapEvent(event));
              } on Object catch (error, stackTrace) {
                sink
                  ..addError(error, stackTrace)
                  ..close();
              }
            },
            handleError: (error, stackTrace, sink) {
              if (error is PlatformException) {
                sink.addError(decodePlatformException(error), stackTrace);
              } else {
                sink.addError(
                  _channelContractError(
                    operation: operation,
                    message: 'Unexpected event channel error',
                    underlying: error,
                  ),
                  stackTrace,
                );
              }
              sink.close();
            },
          ),
        );
  }

  /// Creates a progress stream backed by the native event channel.
  ///
  /// The stream subscribes lazily when a listener attaches. Callers should
  /// listen immediately in the `onProgress` callback to avoid missing early
  /// progress events.
  ///
  /// Failures are emitted through the stream error channel as typed
  /// [ICloudOperationException] values. Cancelling the returned subscription
  /// marks [subscription] so a later method-channel failure is not suppressed
  /// once the stream can no longer deliver it.
  Stream<ICloudTransferProgress> _receiveTransferProgressStream(
    EventChannel eventChannel,
    _TransferProgressSubscription subscription,
  ) {
    final transformer =
        StreamTransformer<Object?, ICloudTransferProgress>.fromHandlers(
      handleData: (event, sink) {
        if (event is num) {
          sink.add(ICloudTransferProgress.progress(event.toDouble()));
          return;
        }

        sink
          ..addError(
            _channelContractError(
              operation: 'transferProgress',
              message: 'Unexpected progress event type: ${event.runtimeType}',
              underlying: event,
            ),
          )
          ..close();
      },
      handleError: (error, stackTrace, sink) {
        if (error is PlatformException) {
          sink.addError(decodePlatformException(error), stackTrace);
        } else {
          _logger.severe(
            'Unexpected progress stream error',
            error,
            stackTrace,
          );
          sink.addError(
            _channelContractError(
              operation: 'transferProgress',
              message:
                  'Internal plugin error during progress stream processing',
              underlying: error,
            ),
            stackTrace,
          );
        }
        sink.close();
      },
      handleDone: (sink) {
        sink
          ..add(const ICloudTransferProgress.done())
          ..close();
      },
    );

    final source =
        eventChannel.receiveBroadcastStream().transform(transformer);
    final controller = StreamController<ICloudTransferProgress>.broadcast();
    StreamSubscription<ICloudTransferProgress>? sourceSubscription;
    controller
      ..onListen = () {
        sourceSubscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      }
      ..onCancel = () {
        subscription.cancelledByCaller = true;
        final cancelled = sourceSubscription?.cancel();
        sourceSubscription = null;
        return cancelled;
      };
    return controller.stream;
  }

  @override
  Future<List<ContainerItem>> listContents({
    required String containerId,
    String? relativePath,
  }) async {
    final mapList = await _invokeListMethod<dynamic>('listContents', {
      'containerId': containerId,
      if (relativePath != null) 'relativePath': relativePath,
    });

    if (mapList == null) return [];

    return _mapStrictList(
      mapList,
      operation: 'listContents',
      validateEntry: _validateContainerItemPayload,
      mapEntry: ContainerItem.fromMap,
    );
  }

  @override
  Future<List<ICloudVersion>> enumerateUnresolvedConflictVersions({
    required String containerId,
    required String relativePath,
  }) async {
    final mapList = await _invokeListMethod<dynamic>(
      'enumerateUnresolvedConflictVersions',
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );

    if (mapList == null) return [];

    return _mapStrictList(
      mapList,
      operation: 'enumerateUnresolvedConflictVersions',
      validateEntry: _validateICloudVersionPayload,
      mapEntry: ICloudVersion.fromMap,
    );
  }

  @override
  Future<void> copyConflictVersion({
    required String containerId,
    required String relativePath,
    required String versionIdentifier,
    required String destinationPath,
  }) async {
    await _invokeVoidMethod('copyConflictVersion', {
      'containerId': containerId,
      'relativePath': relativePath,
      'versionIdentifier': versionIdentifier,
      'destinationPath': destinationPath,
    });
  }

  @override
  Future<void> markConflictResolved({
    required String containerId,
    required String relativePath,
    bool removeOtherVersions = false,
  }) async {
    await _invokeVoidMethod('markConflictResolved', {
      'containerId': containerId,
      'relativePath': relativePath,
      'removeOtherVersions': removeOtherVersions,
    });
  }

  GatherResult _mapFilesFromDynamicList(
    List<dynamic>? mapList, {
    required String operation,
  }) =>
      GatherResult(
        files: _mapStrictList(
          mapList ?? const [],
          operation: operation,
          validateEntry: _validateICloudFilePayload,
          mapEntry: ICloudFile.fromMap,
        ),
      );

  List<T> _mapStrictList<T>(
    List<dynamic> entries, {
    required String operation,
    required void Function(Map<dynamic, dynamic>) validateEntry,
    required T Function(Map<dynamic, dynamic>) mapEntry,
  }) {
    final result = <T>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry is! Map<dynamic, dynamic>) {
        throw _channelContractError(
          operation: operation,
          message: 'Malformed $operation payload at index $index: '
              'expected Map, got ${entry.runtimeType}',
          underlying: entry,
        );
      }
      try {
        validateEntry(entry);
        result.add(mapEntry(entry));
      } on Object catch (error) {
        throw _channelContractError(
          operation: operation,
          message: 'Malformed $operation payload at index $index: $error',
          underlying: entry,
        );
      }
    }
    return result;
  }

  void _validateICloudFilePayload(Map<dynamic, dynamic> map) {
    _requireStringField(map, 'relativePath');
    for (final key in const [
      'isDirectory',
      'isDownloading',
      'isUploading',
      'isUploaded',
      'hasUnresolvedConflicts',
    ]) {
      _validateOptionalBoolField(map, key);
    }
    for (final key in const [
      'sizeInBytes',
      'creationDate',
      'contentChangeDate',
    ]) {
      _validateOptionalNumField(map, key);
    }
    _validateOptionalDownloadStatusField(map);
  }

  void _validateContainerItemPayload(Map<dynamic, dynamic> map) {
    _requireStringField(map, 'relativePath');
    for (final key in const [
      'isDirectory',
      'isDownloading',
      'isUploading',
      'isUploaded',
      'hasUnresolvedConflicts',
    ]) {
      _validateOptionalBoolField(map, key);
    }
    _validateOptionalDownloadStatusField(map);
  }

  void _validateICloudVersionPayload(Map<dynamic, dynamic> map) {
    _requireStringField(map, 'identifier');
    _validateOptionalNumField(map, 'modificationDate');
  }

  void _requireStringField(Map<dynamic, dynamic> map, String key) {
    if (map[key] is! String) {
      throw FormatException('$key is required and must be a String');
    }
  }

  void _validateOptionalBoolField(Map<dynamic, dynamic> map, String key) {
    if (map.containsKey(key) && map[key] is! bool) {
      throw FormatException('$key must be a bool');
    }
  }

  void _validateOptionalNumField(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value != null && value is! num) {
      throw FormatException('$key must be a num or null');
    }
  }

  void _validateOptionalDownloadStatusField(Map<dynamic, dynamic> map) {
    final value = map['downloadStatus'];
    if (value != null &&
        value != 'notDownloaded' &&
        value != 'downloaded' &&
        value != 'current') {
      throw FormatException('Unsupported downloadStatus: $value');
    }
  }

  /// Private method to generate event channel names
  String _generateEventChannelName(
    String eventType,
    String containerId, [
    String? additionalIdentifier,
  ]) =>
      [
        'icloud_storage_plus',
        'event',
        eventType,
        containerId,
        ...(additionalIdentifier == null
            ? <String>[]
            : <String>[additionalIdentifier]),
        '${_eventChannelSessionId}_${_nextEventChannelId++}',
      ].join('/');
}

/// Tracks whether the caller cancelled a transfer progress subscription.
///
/// Native reports a transfer failure through the progress stream's error
/// channel only while the caller is listening. Once the caller cancels, the
/// native event sink is gone, so a later failure can arrive only through the
/// method channel and must not be suppressed.
class _TransferProgressSubscription {
  bool cancelledByCaller = false;
}
