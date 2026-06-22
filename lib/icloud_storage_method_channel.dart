import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/container_item.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
import 'package:logging/logging.dart';

/// An implementation of [ICloudStoragePlatform] that uses method channels.
class MethodChannelICloudStorage extends ICloudStoragePlatform {
  static final Logger _logger = Logger('ICloudStorage');
  static final Random _random = Random();

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('icloud_storage_plus');

  @override
  Future<bool> icloudAvailable() async {
    final result = await methodChannel.invokeMethod<bool>('icloudAvailable');
    return result ?? false;
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
      await _invokeMethod<void>(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final gatherEventChannel = EventChannel(eventChannelName);
      final stream = gatherEventChannel
          .receiveBroadcastStream()
          .where((event) => event is List)
          .map<GatherResult>((event) {
        return _mapFilesFromDynamicList(event as List);
      });

      onUpdate(stream);
    }

    final mapList = await _invokeListMethod<dynamic>('gather', {
      'containerId': containerId,
      'eventChannelName': eventChannelName,
    });

    return _mapFilesFromDynamicList(mapList);
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

    await _invokeMethod<void>(
      'createEventChannel',
      {'eventChannelName': eventChannelName},
    );

    final eventChannel = EventChannel(eventChannelName);
    final eventStream = eventChannel
        .receiveBroadcastStream()
        .map<ICloudDocumentChange>(_mapDocumentChangeEvent)
        .handleError((Object error, StackTrace stackTrace) {
      // PlatformExceptions from _mapDocumentChangeEvent (malformed payload,
      // code: invalidEvent) have no structured 'category' in their details
      // and are returned unchanged by _mapStructuredPlatformException.
      // Native-originated PlatformExceptions carry a structured category and
      // are mapped to typed ICloudOperationException values. Non-Platform-
      // Exception errors are re-thrown with their original stack trace.
      if (error is PlatformException) {
        throw _mapStructuredPlatformException(error);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });

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
      await _invokeMethod<void>('watchDocumentChanges', {
        'containerId': containerId,
        'relativePath': relativePath,
        'eventChannelName': eventChannelName,
      });
    } on PlatformException catch (error, stackTrace) {
      final mapped = _mapStructuredPlatformException(error);
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
      throw PlatformException(
        code: PlatformExceptionCode.invalidEvent,
        message: 'Unexpected document change event type: '
            '${event.runtimeType}',
        details: event,
      );
    }
    if (event['relativePath'] is! String || event['kind'] is! String) {
      throw PlatformException(
        code: PlatformExceptionCode.invalidEvent,
        message: 'Malformed document change event payload',
        details: event,
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
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('uploadFile', containerId);

      await _invokeMethod<void>(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final uploadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(uploadEventChannel);

      onProgress(stream);
    }

    await _invokeMethod<void>('uploadFile', {
      'containerId': containerId,
      'localFilePath': localPath,
      'cloudRelativePath': cloudRelativePath,
      'eventChannelName': eventChannelName,
    });
  }

  @override
  Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('downloadFile', containerId);

      await _invokeMethod<void>(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final downloadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(downloadEventChannel);

      onProgress(stream);
    }

    await _invokeMethod<void>('downloadFile', {
      'containerId': containerId,
      'cloudRelativePath': cloudRelativePath,
      'localFilePath': localPath,
      'eventChannelName': eventChannelName,
    });
  }

  @override
  Future<String?> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await _invokeMethod<String>(
      'readInPlace',
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );
    return result;
  }

  @override
  Future<Uint8List?> readInPlaceBytes({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await _invokeMethod<Uint8List>(
      'readInPlaceBytes',
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );
    return result;
  }

  @override
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    await _invokeMethod<void>('writeInPlace', {
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
    await _invokeMethod<void>('writeInPlaceBytes', {
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
    await _invokeMethod<void>('delete', {
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
    await _invokeMethod<void>('move', {
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
    await _invokeMethod<void>('copy', {
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
  Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    return _invokeMetadataMethodRaw(
      'getDocumentMetadata',
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  @override
  Future<Map<String, dynamic>?> getItemMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    try {
      return await _invokeNormalizedMetadataMethod(
        'getItemMetadata',
        containerId: containerId,
        relativePath: relativePath,
      );
    } on MissingPluginException {
      return _invokeNormalizedMetadataMethod(
        'getDocumentMetadata',
        containerId: containerId,
        relativePath: relativePath,
      );
    }
  }

  Future<Map<String, dynamic>?> _invokeNormalizedMetadataMethod(
    String method, {
    required String containerId,
    required String relativePath,
  }) async {
    final metadata = await _invokeMetadataMethod(
      method,
      containerId: containerId,
      relativePath: relativePath,
    );
    if (metadata == null) return null;
    return _normalizeMetadataMap(metadata);
  }

  Future<Map<String, dynamic>?> _invokeMetadataMethod(
    String method, {
    required String containerId,
    required String relativePath,
  }) async {
    final result = await _invokeMethod<Map<dynamic, dynamic>?>(
      method,
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );

    if (result == null) return null;

    return result.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, dynamic>?> _invokeMetadataMethodRaw(
    String method, {
    required String containerId,
    required String relativePath,
  }) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>?>(
      method,
      {
        'containerId': containerId,
        'relativePath': relativePath,
      },
    );

    if (result == null) return null;

    return result.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, dynamic> _normalizeMetadataMap(Map<String, dynamic> metadata) {
    final normalized = Map<String, dynamic>.from(metadata);
    final downloadStatus = normalized['downloadStatus'];
    if (downloadStatus is String) {
      normalized['downloadStatus'] = switch (downloadStatus) {
        'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded' ||
        'NSURLUbiquitousItemDownloadingStatusNotDownloaded' =>
          'notDownloaded',
        'NSMetadataUbiquitousItemDownloadingStatusDownloaded' ||
        'NSURLUbiquitousItemDownloadingStatusDownloaded' =>
          'downloaded',
        'NSMetadataUbiquitousItemDownloadingStatusCurrent' ||
        'NSURLUbiquitousItemDownloadingStatusCurrent' =>
          'current',
        _ => downloadStatus,
      };
    }
    return normalized;
  }

  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _mapStructuredPlatformException(error);
    }
  }

  Future<List<T>?> _invokeListMethod<T>(
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await methodChannel.invokeListMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _mapStructuredPlatformException(error);
    }
  }

  Exception _mapStructuredPlatformException(PlatformException error) {
    final details = error.details;
    final category = details is Map ? details['category'] : null;
    if (category is! String) {
      return error;
    }

    return mapICloudPlatformException(error);
  }

  /// Creates a progress stream backed by the native event channel.
  ///
  /// The stream subscribes lazily when a listener attaches. Callers should
  /// listen immediately in the `onProgress` callback to avoid missing early
  /// progress events.
  ///
  /// **Note on Error Handling:**
  /// This stream does **not** emit Dart errors via `onError`. Failures are
  /// delivered as data events with `type == ICloudTransferProgressType.error`.
  /// You must check `event.isError` (or `event.type`) inside the data listener
  /// to handle failures. See [ICloudTransferProgress] for details.
  Stream<ICloudTransferProgress> _receiveTransferProgressStream(
    EventChannel eventChannel,
  ) {
    final transformer =
        StreamTransformer<Object?, ICloudTransferProgress>.fromHandlers(
      handleData: (event, sink) {
        if (event is num) {
          sink.add(ICloudTransferProgress.progress(event.toDouble()));
          return;
        }

        final exception = PlatformException(
          code: PlatformExceptionCode.invalidEvent,
          message: 'Unexpected progress event type: ${event.runtimeType}',
          details: event,
        );
        sink
          ..add(ICloudTransferProgress.error(exception))
          ..close();
      },
      handleError: (error, stackTrace, sink) {
        final exception = error is PlatformException
            ? error
            : () {
                _logger.severe(
                  'Unexpected progress stream error',
                  error,
                  stackTrace,
                );
                return PlatformException(
                  code: PlatformExceptionCode.pluginInternal,
                  message: 'Internal plugin error during progress '
                      'stream processing',
                  details: error,
                  stacktrace: stackTrace.toString(),
                );
              }();

        sink
          ..add(ICloudTransferProgress.error(exception))
          ..close();
      },
      handleDone: (sink) {
        sink
          ..add(const ICloudTransferProgress.done())
          ..close();
      },
    );

    return eventChannel.receiveBroadcastStream().transform(transformer);
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

    return [
      for (final entry in mapList)
        if (entry is Map<dynamic, dynamic>) ContainerItem.fromMap(entry),
    ];
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

    return [
      for (final entry in mapList)
        if (entry is Map<dynamic, dynamic>) ICloudVersion.fromMap(entry),
    ];
  }

  @override
  Future<void> copyConflictVersion({
    required String containerId,
    required String relativePath,
    required String versionIdentifier,
    required String destinationPath,
  }) async {
    await _invokeMethod<void>('copyConflictVersion', {
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
    await _invokeMethod<void>('markConflictResolved', {
      'containerId': containerId,
      'relativePath': relativePath,
      'removeOtherVersions': removeOtherVersions,
    });
  }

  /// Private method to convert the list of maps from platform code to a list of
  /// ICloudFile object
  GatherResult _mapFilesFromDynamicList(
    List<dynamic>? mapList,
  ) {
    final files = <ICloudFile>[];
    final invalidEntries = <GatherInvalidEntry>[];
    if (mapList != null) {
      var index = 0;
      for (final entry in mapList) {
        if (entry is! Map<dynamic, dynamic>) {
          _logger.fine(
            'Skipping malformed metadata entry: expected Map, got '
            '${entry.runtimeType}',
          );
          invalidEntries.add(
            GatherInvalidEntry(
              error: 'Expected map, got ${entry.runtimeType}',
              rawEntry: entry,
              index: index,
            ),
          );
        } else {
          try {
            files.add(ICloudFile.fromMap(entry));
          } on Exception catch (error, stackTrace) {
            _logger.fine(
              'Skipping malformed metadata entry: $error',
              error,
              stackTrace,
            );
            invalidEntries.add(
              GatherInvalidEntry(
                error: error.toString(),
                rawEntry: entry,
                index: index,
              ),
            );
          }
        }
        index++;
      }
    }
    if (invalidEntries.isNotEmpty) {
      _logger.warning(
        'Skipped ${invalidEntries.length} malformed metadata '
        '${invalidEntries.length == 1 ? 'entry' : 'entries'} during gather.',
      );
    }
    return GatherResult(files: files, invalidEntries: invalidEntries);
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
        '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(999)}',
      ].join('/');
}
