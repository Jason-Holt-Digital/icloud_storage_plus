import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';

const _containerAccessCode = 'E_CTR';
const _conflictCode = 'E_CONFLICT';
const _coordinationCode = 'E_COORDINATION';
const _invalidArgumentCode = 'E_ARG';
const _nativeCodeError = 'E_NAT';

Matcher _pluginContractFor(String operation) => isA<ICloudOperationException>()
    .having((error) => error.category, 'category', 'pluginContract')
    .having((error) => error.operation, 'operation', operation);

void main() {
  final platform = MethodChannelICloudStorage();
  const channel = MethodChannel('icloud_storage_plus');
  late MethodCall mockMethodCall;
  final mockMethodCalls = <MethodCall>[];
  const containerId = 'containerId';
  MockStreamHandler? mockStreamHandler;
  String? lastEventChannelName;
  Map<String, Object?> mockArguments() =>
      (mockMethodCall.arguments as Map).cast<String, Object?>();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      mockMethodCall = methodCall;
      mockMethodCalls.add(methodCall);
      switch (methodCall.method) {
        case 'createEventChannel':
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        case 'gather':
          return [
            {
              'relativePath': 'relativePath',
              'isDirectory': false,
              'sizeInBytes': 100,
              'creationDate': 1.0,
              'contentChangeDate': 1.0,
              'isDownloading': true,
              'downloadStatus': 'notDownloaded',
              'isUploading': false,
              'isUploaded': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        case 'downloadFile':
          return null;
        case 'documentExists':
          return true;
        case 'getItemMetadata':
          return {
            'relativePath': 'item.txt',
            'isDirectory': false,
            'sizeInBytes': null,
            'creationDate': null,
            'contentChangeDate': null,
            'downloadStatus': 'current',
            'isDownloading': false,
            'isUploading': false,
            'isUploaded': true,
            'hasUnresolvedConflicts': false,
          };
        case 'getContainerPath':
          return '/container/path';
        case 'listContents':
          return [
            {
              'relativePath': 'file.txt',
              'isDirectory': false,
              'downloadStatus': 'current',
              'isDownloading': false,
              'isUploaded': true,
              'isUploading': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        case 'readInPlace':
          return 'contents';
        case 'readInPlaceBytes':
          return Uint8List.fromList([1, 2, 3]);
        case 'writeInPlace':
          return null;
        case 'writeInPlaceBytes':
          return null;
        case 'enumerateUnresolvedConflictVersions':
          return [
            {'identifier': 'v1', 'modificationDate': 100.0},
            {'identifier': 'v2', 'modificationDate': 200.0},
          ];
        case 'copyConflictVersion':
          return null;
        case 'markConflictResolved':
          return null;
        case 'watchDocumentChanges':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    mockMethodCalls.clear();
    if (lastEventChannelName != null) {
      final eventChannel = EventChannel(lastEventChannelName!);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
      lastEventChannelName = null;
    }
    mockStreamHandler = null;
  });

  group('gather tests:', () {
    test('maps meta data correctly', () async {
      final result = await platform.gather(containerId: containerId);
      final file = result.files.last;
      expect(file.relativePath, 'relativePath');
      expect(file.isDirectory, false);
      expect(file.sizeInBytes, 100);
      expect(
        file.creationDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(
        file.contentChangeDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(file.isDownloading, true);
      expect(file.downloadStatus, DownloadStatus.notDownloaded);
      expect(file.isUploading, false);
      expect(file.isUploaded, false);
      expect(file.hasUnresolvedConflicts, false);
    });

    test('directory paths preserve trailing slashes', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'gather') {
          return [
            {
              'relativePath': 'Documents/folder/',
              'isDirectory': true,
              'sizeInBytes': null,
              'creationDate': null,
              'contentChangeDate': null,
              'downloadStatus': null,
              'isDownloading': false,
              'isUploading': false,
              'isUploaded': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        }
        return null;
      });

      final result = await platform.gather(containerId: containerId);
      final directory = result.files.first;

      expect(directory.isDirectory, true);
      expect(directory.relativePath, 'Documents/folder/');
      expect(
        directory.relativePath.endsWith('/'),
        true,
        reason: 'Directory paths may include trailing slashes',
      );
    });

    test('gather with update', () async {
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) => stream.listen((_) {}),
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });

    test('rejects an ignored update stream before native allocation', () async {
      await expectLater(
        platform.gather(
          containerId: containerId,
          onUpdate: (stream) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(mockMethodCalls, isEmpty);
    });

    test('rejects a delayed update listener before native allocation',
        () async {
      late Stream<GatherResult> delayedStream;
      await expectLater(
        platform.gather(
          containerId: containerId,
          onUpdate: (stream) => delayedStream = stream,
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(mockMethodCalls, isEmpty);
      await delayedStream.drain<void>();
    });

    test('concurrent gathers allocate unique event channel names', () async {
      await Future.wait(
        List.generate(
          200,
          (_) => platform.gather(
            containerId: containerId,
            onUpdate: (stream) => stream.listen((_) {}),
          ),
        ),
      );

      final createNames = mockMethodCalls
          .where((call) => call.method == 'createEventChannel')
          .map(
            (call) => (call.arguments as Map)['eventChannelName'] as String,
          )
          .toList();
      final gatherNames = mockMethodCalls
          .where((call) => call.method == 'gather')
          .map(
            (call) => (call.arguments as Map)['eventChannelName'] as String,
          )
          .toList();

      expect(createNames, hasLength(200));
      expect(createNames.toSet(), hasLength(200));
      expect(gatherNames.toSet(), createNames.toSet());
    });

    test('maps update stream platform errors to typed exceptions', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: _containerAccessCode,
            message: 'Container unavailable',
            details: {
              'category': 'containerAccess',
              'operation': 'gather',
              'retryable': false,
            },
          );
        },
      );

      late Future<void> updateExpectation;
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) {
          updateExpectation = expectLater(
            stream,
            emitsError(isA<ICloudContainerAccessException>()),
          );
        },
      );

      await updateExpectation;
    });

    test('reports malformed update events as typed contract errors', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({'not': 'a list'});
        },
      );

      late Future<void> updateExpectation;
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) {
          updateExpectation = expectLater(
            stream,
            emitsInOrder([
              emitsError(
                isA<ICloudOperationException>()
                    .having(
                      (error) => error.category,
                      'category',
                      'pluginContract',
                    )
                    .having((error) => error.operation, 'operation', 'gather'),
              ),
              emitsDone,
            ]),
          );
        },
      );

      await updateExpectation;
    });

    test('rejects a malformed initial entry as a whole-call failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'gather') {
          return [
            {
              'relativePath': 'valid.txt',
              'isDirectory': false,
              'sizeInBytes': null,
              'creationDate': null,
              'contentChangeDate': null,
              'downloadStatus': 'current',
              'isDownloading': false,
              'isUploading': false,
              'isUploaded': true,
              'hasUnresolvedConflicts': false,
            },
            {
              'relativePath': 'malformed.txt',
              'isDirectory': 'false',
            },
          ];
        }
        return null;
      });

      await expectLater(
        () => platform.gather(containerId: containerId),
        throwsA(_pluginContractFor('gather')),
      );
    });

    test('rejects a malformed update entry as a whole-update failure',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success([
            {
              'relativePath': 'valid.txt',
              'downloadStatus': 'current',
            },
            {
              'relativePath': 'malformed.txt',
              'downloadStatus': 'unsupported',
            },
          ]);
        },
      );

      late Future<void> updateExpectation;
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) {
          updateExpectation = expectLater(
            stream,
            emitsError(_pluginContractFor('gather')),
          );
        },
      );

      await updateExpectation;
    });

    test('maps structured container access failures', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'gather') {
          throw PlatformException(
            code: _containerAccessCode,
            message: 'Container unavailable',
            details: {
              'category': 'containerAccess',
              'operation': 'gather',
              'retryable': false,
            },
          );
        }
        return null;
      });

      await expectLater(
        () => platform.gather(containerId: containerId),
        throwsA(
          isA<ICloudContainerAccessException>().having(
            (error) => error.operation,
            'operation',
            'gather',
          ),
        ),
      );
    });
  });

  group('uploadFile tests:', () {
    test('uploadFile', () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['localFilePath'], '/dir/file');
      expect(args['relativePath'], 'dest');
      expect(args.keys, isNot(contains('cloudRelativePath')));
      expect(args['eventChannelName'], '');
    });

    test('uploadFile with onProgress', () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) => stream.listen((_) {}),
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });

    test('uploadFile rejects ignored progress before native allocation',
        () async {
      await expectLater(
        platform.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          relativePath: 'dest',
          onProgress: (stream) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(mockMethodCalls, isEmpty);
    });

    test('uploadFile proceeds without progress after synchronous cancel',
        () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) => stream.listen((_) {}).cancel(),
      );

      expect(mockMethodCalls.map((call) => call.method), ['uploadFile']);
      expect(mockArguments()['eventChannelName'], '');
    });

    test('uploadFile invokes event-channel teardown after allocation cancel',
        () async {
      var streamCancelled = false;
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) => streamCancelled = true,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          await Future<void>.delayed(Duration.zero);
          return null;
        }
        return null;
      });

      late StreamSubscription<ICloudTransferProgress> subscription;
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          subscription = stream.listen((_) {});
          scheduleMicrotask(subscription.cancel);
        },
      );

      expect(mockMethodCalls.map((call) => call.method), [
        'createEventChannel',
        'uploadFile',
      ]);
      expect(streamCancelled, isTrue);
    });
  });

  group('downloadFile tests:', () {
    test('downloadFile', () async {
      await platform.downloadFile(
        containerId: containerId,
        relativePath: 'file',
        localPath: '/tmp/file',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'file');
      expect(args.keys, isNot(contains('cloudRelativePath')));
      expect(args['localFilePath'], '/tmp/file');
      expect(args['eventChannelName'], '');
    });

    test('downloadFile with onProgress', () async {
      await platform.downloadFile(
        containerId: containerId,
        relativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) => stream.listen((_) {}),
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });

    test('downloadFile rejects throwing callback before native allocation',
        () async {
      await expectLater(
        platform.downloadFile(
          containerId: containerId,
          relativePath: 'file',
          localPath: '/tmp/file',
          onProgress: (stream) => throw StateError('callback failed'),
        ),
        throwsStateError,
      );
      expect(mockMethodCalls, isEmpty);
    });
  });

  group('readInPlace tests:', () {
    test('readInPlace', () async {
      final result = await platform.readInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/test.json');
      expect(result, 'contents');
    });

    test('readInPlace rejects null responses', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);

      await expectLater(
        () => platform.readInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
        ),
        throwsA(_pluginContractFor('readInPlace')),
      );
    });
  });

  group('readInPlaceBytes tests:', () {
    test('readInPlaceBytes', () async {
      final result = await platform.readInPlaceBytes(
        containerId: containerId,
        relativePath: 'Documents/data.bin',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/data.bin');
      expect(result, Uint8List.fromList([1, 2, 3]));
    });

    test('readInPlaceBytes rejects null responses', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async => null);

      await expectLater(
        () => platform.readInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
        ),
        throwsA(_pluginContractFor('readInPlaceBytes')),
      );
    });
  });

  group('writeInPlace tests:', () {
    test('writeInPlace', () async {
      await platform.writeInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
        contents: '{"ok":true}',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/test.json');
      expect(args['contents'], '{"ok":true}');
    });

    test('writeInPlace rejects non-null success responses', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlace') return true;
        return null;
      });

      await expectLater(
        () => platform.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
          contents: '{"ok":true}',
        ),
        throwsA(_pluginContractFor('writeInPlace')),
      );
    });

    test('writeInPlace maps structured invalidArgument payloads', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlace') {
          throw PlatformException(
            code: _invalidArgumentCode,
            message: 'Destination is a directory',
            details: {
              'category': 'invalidArgument',
              'operation': 'writeInPlace',
              'retryable': false,
              'relativePath': 'Documents/test.json',
            },
          );
        }
        return null;
      });

      await expectLater(
        () => platform.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
          contents: '{"ok":true}',
        ),
        throwsA(isA<ICloudInvalidArgumentException>()),
      );
    });

    test('writeInPlace preserves unknown native write enrichment', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlace') {
          throw PlatformException(
            code: _nativeCodeError,
            message: 'Native Code Error',
            details: {
              'category': 'unknownNative',
              'operation': 'writeInPlace',
              'retryable': false,
              'relativePath': 'Documents/test.json',
              'pathKind': 'temporaryReplacement',
              'nativeDomain': 'NSCocoaErrorDomain',
              'nativeCode': 640,
              'nativeDescription': 'The volume is out of space.',
            },
          );
        }
        return null;
      });

      await expectLater(
        () => platform.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
          contents: '{"ok":true}',
        ),
        throwsA(
          isA<ICloudUnknownNativeException>()
              .having(
                (error) => error.operation,
                'operation',
                'writeInPlace',
              )
              .having(
                (error) => error.pathKind,
                'pathKind',
                'temporaryReplacement',
              )
              .having(
                (error) => error.nativeDomain,
                'nativeDomain',
                'NSCocoaErrorDomain',
              )
              .having((error) => error.nativeCode, 'nativeCode', 640),
        ),
      );
    });
  });

  group('writeInPlaceBytes tests:', () {
    test('writeInPlaceBytes', () async {
      await platform.writeInPlaceBytes(
        containerId: containerId,
        relativePath: 'Documents/data.bin',
        contents: Uint8List.fromList([4, 5, 6]),
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/data.bin');
      expect(args['contents'], Uint8List.fromList([4, 5, 6]));
    });

    test('writeInPlaceBytes maps structured coordination payloads', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlaceBytes') {
          throw PlatformException(
            code: _coordinationCode,
            message: 'File coordination failed while replacing an iCloud item.',
            details: {
              'category': 'coordination',
              'operation': 'writeInPlaceBytes',
              'retryable': false,
              'relativePath': 'Documents/data.bin',
              'pathKind': 'destination',
              'nativeDomain': 'ICloudStoragePlusErrorDomain',
              'nativeCode': 5,
              'nativeDescription':
                  'File coordination failed while replacing an iCloud item.',
            },
          );
        }
        return null;
      });

      await expectLater(
        () => platform.writeInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
          contents: Uint8List.fromList([4, 5, 6]),
        ),
        throwsA(
          isA<ICloudCoordinationException>()
              .having(
                (error) => error.operation,
                'operation',
                'writeInPlaceBytes',
              )
              .having((error) => error.pathKind, 'pathKind', 'destination'),
        ),
      );
    });
  });

  group('transfer progress stream tests:', () {
    test('maps numeric events and completion', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(0.25)
            ..success(1.0)
            ..endOfStream();
        },
      );

      late Future<List<ICloudTransferProgress>> progressEvents;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressEvents = stream.toList();
        },
      );

      final events = await progressEvents;
      expect(events, hasLength(3));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.25);
      expect(events[1].isProgress, isTrue);
      expect(events[1].percent, 1.0);
      expect(events[2].isDone, isTrue);
    });

    test('maps platform errors to typed stream errors', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'downloadFile',
              'retryable': false,
              'relativePath': 'file',
            },
          );
        },
      );

      late Future<void> progressExpectation;

      await platform.downloadFile(
        containerId: containerId,
        relativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) {
          progressExpectation = expectLater(
            stream,
            emitsError(
              isA<ICloudCoordinationException>()
                  .having(
                    (error) => error.operation,
                    'operation',
                    'downloadFile',
                  )
                  .having(
                    (error) => error.relativePath,
                    'relativePath',
                    'file',
                  ),
            ),
          );
        },
      );

      await progressExpectation;
    });

    test('reports malformed data as a typed stream error', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success('invalid');
        },
      );

      late Future<void> progressExpectation;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressExpectation = expectLater(
            stream,
            emitsError(
              isA<ICloudOperationException>().having(
                (error) => error.category,
                'category',
                'pluginContract',
              ),
            ),
          );
        },
      );

      await progressExpectation;
    });

    test('paused source-only errors remain queued on the progress stream',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success('invalid');
        },
      );

      final receivedErrors = <Object>[];
      final streamDone = Completer<void>();
      late StreamSubscription<ICloudTransferProgress> subscription;
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          subscription = stream.listen(
            (_) {},
            onError: receivedErrors.add,
            onDone: streamDone.complete,
          )..pause();
        },
      );

      expect(receivedErrors, isEmpty);
      subscription.resume();
      await streamDone.future;
      expect(receivedErrors.single, _pluginContractFor('transferProgress'));
      await subscription.cancel();
    });

    test('a source-only error does not hide a later transfer failure',
        () async {
      final sourceErrorReceived = Completer<void>();
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success('invalid');
        },
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          await sourceErrorReceived.future;
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      final receivedErrors = <Object>[];
      await expectLater(
        () => platform.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          relativePath: 'dest',
          onProgress: (stream) {
            stream.listen(
              (_) {},
              onError: (Object error) {
                receivedErrors.add(error);
                if (!sourceErrorReceived.isCompleted) {
                  sourceErrorReceived.complete();
                }
              },
            );
          },
        ),
        throwsA(isA<ICloudCoordinationException>()),
      );

      expect(receivedErrors.single, _pluginContractFor('transferProgress'));
    });

    test('delivers events after listener attaches', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(0.1)
            ..endOfStream();
        },
      );

      late Future<List<ICloudTransferProgress>> progressEvents;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressEvents = stream.toList();
        },
      );

      final events = await progressEvents;
      expect(events, hasLength(2));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.1);
      expect(events[1].isDone, isTrue);
    });

    test('progress-enabled transfer reports failure through the stream only',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      late Future<void> progressExpectation;

      // The method Future must complete normally when a progress listener is
      // attached; the failure surfaces on the stream, not on both channels.
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressExpectation = expectLater(
            stream,
            emitsError(isA<ICloudCoordinationException>()),
          );
        },
      );

      await progressExpectation;
    });

    test('waits for the stream error before suppressing its method fallback',
        () async {
      final listenReady = Completer<MockStreamHandlerEventSink>();
      final transferFailed = Completer<void>();
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) => listenReady.complete(events),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          transferFailed.complete();
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      late Future<void> progressExpectation;
      var transferCompleted = false;
      final transfer = platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressExpectation = expectLater(
            stream,
            emitsError(isA<ICloudCoordinationException>()),
          );
        },
      );
      final completion = transfer.whenComplete(() => transferCompleted = true);

      final events = await listenReady.future;
      await transferFailed.future;
      await Future<void>.delayed(Duration.zero);
      expect(transferCompleted, isFalse);

      events
        ..error(
          code: _coordinationCode,
          message: 'Boom',
          details: {
            'category': 'coordination',
            'operation': 'uploadFile',
            'retryable': false,
            'relativePath': 'dest',
          },
        )
        ..endOfStream();

      await completion;
      await progressExpectation;
    });

    test('paused progress errors fall back to the transfer Future', () async {
      final listenReady = Completer<MockStreamHandlerEventSink>();
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) => listenReady.complete(events),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          final events = await listenReady.future;
          events
            ..error(
              code: _coordinationCode,
              message: 'Boom',
              details: {
                'category': 'coordination',
                'operation': 'uploadFile',
                'retryable': false,
                'relativePath': 'dest',
              },
            )
            ..endOfStream();
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      final receivedErrors = <Object>[];
      late StreamSubscription<ICloudTransferProgress> subscription;
      await expectLater(
        () => platform.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          relativePath: 'dest',
          onProgress: (stream) {
            subscription = stream.listen(
              (_) {},
              onError: receivedErrors.add,
            )..pause();
          },
        ),
        throwsA(isA<ICloudCoordinationException>()),
      );

      expect(receivedErrors, isEmpty);
      await subscription.cancel();
    });

    test('propagates transfer failure after in-flight progress cancellation',
        () async {
      final transferStarted = Completer<void>();
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {},
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          transferStarted.complete();
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      late StreamSubscription<ICloudTransferProgress> subscription;
      final transfer = platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          subscription = stream.listen((_) {});
        },
      );

      await transferStarted.future;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      // Native has acknowledged that stream delivery is no longer possible,
      // so its method-channel failure remains the transfer's fallback.
      await expectLater(
        transfer,
        throwsA(
          isA<ICloudCoordinationException>()
              .having((error) => error.operation, 'operation', 'uploadFile'),
        ),
      );
      expect(
        mockMethodCalls.map((call) => call.method),
        ['createEventChannel', 'uploadFile'],
      );
    });

    test('does not rethrow when cancelOnError cancels after a stream failure',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        },
      );

      final streamErrorReceived = Completer<void>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          // Native emits the transfer failure on the event channel before
          // returning the same method-channel error. Fail the method channel
          // only after the caller has received the stream error and
          // cancelOnError has auto-cancelled the subscription.
          await streamErrorReceived.future;
          throw PlatformException(
            code: _coordinationCode,
            message: 'Boom',
            details: {
              'category': 'coordination',
              'operation': 'uploadFile',
              'retryable': false,
              'relativePath': 'dest',
            },
          );
        }
        return null;
      });

      final receivedErrors = <Object>[];

      // Automatic cancellation after a delivered stream error must not be
      // treated as an explicit early cancellation, so the method Future
      // completes normally instead of rethrowing the same failure.
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          stream.listen(
            (_) {},
            onError: (Object error) {
              receivedErrors.add(error);
              if (!streamErrorReceived.isCompleted) {
                streamErrorReceived.complete();
              }
            },
            cancelOnError: true,
          );
        },
      );

      expect(receivedErrors, hasLength(1));
      expect(receivedErrors.single, isA<ICloudCoordinationException>());
    });

    test(
        'propagates a pluginContract failure from a progress-enabled '
        'transfer', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {},
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'uploadFile') {
          throw MissingPluginException('not registered');
        }
        return null;
      });

      // A missing plugin is a method-channel contract violation that native
      // never delivers through the progress stream, so it must surface from
      // the method Future rather than being demoted to a successful transfer.
      late Future<void> progressExpectation;
      await expectLater(
        () => platform.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          relativePath: 'dest',
          onProgress: (stream) {
            progressExpectation = expectLater(
              stream,
              emitsInOrder([
                emitsError(_pluginContractFor('uploadFile')),
                emitsDone,
              ]),
            );
          },
        ),
        throwsA(_pluginContractFor('uploadFile')),
      );
      await progressExpectation;
    });
  });

  test('delete', () async {
    await platform.delete(
      containerId: containerId,
      relativePath: 'file',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['relativePath'], 'file');
  });

  test('move', () async {
    await platform.move(
      containerId: containerId,
      fromRelativePath: 'file',
      toRelativePath: 'file2',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['atRelativePath'], 'file');
    expect(args['toRelativePath'], 'file2');
  });

  test('copy', () async {
    await platform.copy(
      containerId: containerId,
      fromRelativePath: 'file',
      toRelativePath: 'file2',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['fromRelativePath'], 'file');
    expect(args['toRelativePath'], 'file2');
  });

  group('version exposure tests:', () {
    test(
        'enumerateUnresolvedConflictVersions sends method + args and '
        'decodes typed model', () async {
      final versions = await platform.enumerateUnresolvedConflictVersions(
        containerId: containerId,
        relativePath: 'Documents/file',
      );
      expect(
        mockMethodCall.method,
        'enumerateUnresolvedConflictVersions',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/file');

      expect(versions, hasLength(2));
      expect(versions[0], isA<ICloudVersion>());
      expect(versions[0].identifier, 'v1');
      expect(
        versions[0].modificationDate,
        DateTime.fromMillisecondsSinceEpoch(100000),
      );
      expect(versions[1].identifier, 'v2');
      expect(
        versions[1].modificationDate,
        DateTime.fromMillisecondsSinceEpoch(200000),
      );
    });

    test('enumerateUnresolvedConflictVersions rejects malformed entries',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'enumerateUnresolvedConflictVersions') {
          return [
            {'identifier': 'v1', 'modificationDate': 100.0},
            {'identifier': 2, 'modificationDate': 200.0},
          ];
        }
        return null;
      });

      await expectLater(
        () => platform.enumerateUnresolvedConflictVersions(
          containerId: containerId,
          relativePath: 'Documents/file',
        ),
        throwsA(
          _pluginContractFor('enumerateUnresolvedConflictVersions'),
        ),
      );
    });

    test(
        'enumerateUnresolvedConflictVersions returns empty list when '
        'native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'enumerateUnresolvedConflictVersions') {
          return null;
        }
        return null;
      });

      final versions = await platform.enumerateUnresolvedConflictVersions(
        containerId: containerId,
        relativePath: 'Documents/file',
      );

      expect(versions, isEmpty);
    });

    test('createEventChannel rejects non-null success responses', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'createEventChannel') return 'unexpected';
        return null;
      });

      late Future<void> updateExpectation;
      await expectLater(
        () => platform.gather(
          containerId: containerId,
          onUpdate: (stream) {
            updateExpectation = expectLater(
              stream,
              emitsInOrder([
                emitsError(_pluginContractFor('createEventChannel')),
                emitsDone,
              ]),
            );
          },
        ),
        throwsA(_pluginContractFor('createEventChannel')),
      );
      await updateExpectation;
    });

    test('copyConflictVersion sends method + args', () async {
      await platform.copyConflictVersion(
        containerId: containerId,
        relativePath: 'Documents/file',
        versionIdentifier: 'v1',
        destinationPath: '/tmp/backup-v1.json',
      );
      expect(mockMethodCall.method, 'copyConflictVersion');
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/file');
      expect(args['versionIdentifier'], 'v1');
      expect(args['destinationPath'], '/tmp/backup-v1.json');
    });

    test(
        'markConflictResolved sends method + args including '
        'removeOtherVersions', () async {
      await platform.markConflictResolved(
        containerId: containerId,
        relativePath: 'Documents/file',
        removeOtherVersions: true,
      );
      expect(mockMethodCall.method, 'markConflictResolved');
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/file');
      expect(args['removeOtherVersions'], true);
    });

    test('markConflictResolved defaults removeOtherVersions to false',
        () async {
      await platform.markConflictResolved(
        containerId: containerId,
        relativePath: 'Documents/file',
      );
      final args = mockArguments();
      expect(args['removeOtherVersions'], false);
    });

    test('version-exposure failures map to ICloudConflictException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'copyConflictVersion') {
          throw PlatformException(
            code: 'E_CONFLICT',
            message: 'version not found',
            details: {
              'category': 'conflict',
              'operation': 'copyConflictVersion',
              'retryable': false,
              'relativePath': 'Documents/file',
            },
          );
        }
        return null;
      });

      await expectLater(
        platform.copyConflictVersion(
          containerId: containerId,
          relativePath: 'Documents/file',
          versionIdentifier: 'missing',
          destinationPath: '/tmp/backup.json',
        ),
        throwsA(isA<ICloudConflictException>()),
      );
    });
  });

  group('document change stream tests:', () {
    test('watchDocumentChanges rejects ignored stream before native allocation',
        () async {
      await expectLater(
        platform.watchDocumentChanges(
          containerId: containerId,
          relativePath: 'Documents/journal.json',
          onChange: (stream) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(mockMethodCalls, isEmpty);
    });

    test('watchDocumentChanges sends method args and maps typed payload',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success({
              'relativePath': 'Documents/journal.json',
              'kind': 'invalidation',
            })
            ..success({
              'relativePath': 'Documents/journal.json',
              'kind': 'conflict',
            })
            ..success({
              'relativePath': 'Documents/journal.json',
              'kind': 'savingError',
            })
            ..success({
              'relativePath': 'Documents/journal.json',
              'kind': 'editingDisabled',
            })
            ..endOfStream();
        },
      );

      late Future<List<ICloudDocumentChange>> changeEvents;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeEvents = stream.toList();
        },
      );

      expect(mockMethodCalls.map((call) => call.method), [
        'createEventChannel',
        'watchDocumentChanges',
      ]);
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/journal.json');
      expect(args['eventChannelName'], lastEventChannelName);

      final events = await changeEvents;
      expect(events, [
        const ICloudDocumentChange(
          relativePath: 'Documents/journal.json',
          kind: ICloudDocumentChangeKind.invalidation,
        ),
        const ICloudDocumentChange(
          relativePath: 'Documents/journal.json',
          kind: ICloudDocumentChangeKind.conflict,
        ),
        const ICloudDocumentChange(
          relativePath: 'Documents/journal.json',
          kind: ICloudDocumentChangeKind.savingError,
        ),
        const ICloudDocumentChange(
          relativePath: 'Documents/journal.json',
          kind: ICloudDocumentChangeKind.editingDisabled,
        ),
      ]);
    });

    test('watchDocumentChanges skips native start after allocation cancel',
        () async {
      var streamCancelled = false;
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {},
        onCancel: (arguments) => streamCancelled = true,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          await Future<void>.delayed(Duration.zero);
          return null;
        }
        return null;
      });

      late StreamSubscription<ICloudDocumentChange> subscription;
      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          subscription = stream.listen((_) {});
          scheduleMicrotask(subscription.cancel);
        },
      );

      expect(
        mockMethodCalls.map((call) => call.method),
        ['createEventChannel'],
      );
      expect(streamCancelled, isTrue);
    });

    test('watchDocumentChanges maps stream errors to typed exceptions',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: _coordinationCode,
            message: 'Document observation failed',
            details: {
              'category': 'coordination',
              'operation': 'watchDocumentChanges',
              'retryable': false,
              'relativePath': 'Documents/journal.json',
            },
          );
        },
      );

      late Future<void> changeExpectation;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeExpectation = expectLater(
            stream,
            emitsError(isA<ICloudCoordinationException>()),
          );
        },
      );

      await changeExpectation;
    });

    test('watchDocumentChanges closes stream when native start fails',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        mockMethodCall = methodCall;
        mockMethodCalls.add(methodCall);
        if (methodCall.method == 'createEventChannel') {
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        }
        if (methodCall.method == 'watchDocumentChanges') {
          throw PlatformException(
            code: _containerAccessCode,
            message: 'iCloud container unavailable',
            details: {
              'category': 'containerAccess',
              'operation': 'watchDocumentChanges',
              'retryable': true,
              'relativePath': 'Documents/journal.json',
            },
          );
        }
        return null;
      });

      late Future<void> changeExpectation;

      await expectLater(
        platform.watchDocumentChanges(
          containerId: containerId,
          relativePath: 'Documents/journal.json',
          onChange: (stream) {
            changeExpectation = expectLater(
              stream,
              emitsInOrder([
                emitsError(isA<ICloudContainerAccessException>()),
                emitsDone,
              ]),
            );
          },
        ),
        throwsA(isA<ICloudContainerAccessException>()),
      );

      await changeExpectation;
      expect(mockMethodCalls.map((call) => call.method), [
        'createEventChannel',
        'watchDocumentChanges',
      ]);
    });

    test('watchDocumentChanges surfaces malformed payloads as typed errors',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({'relativePath': 'Documents/journal.json'});
        },
      );

      late Future<void> changeExpectation;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeExpectation = expectLater(
            stream,
            emitsInOrder([
              emitsError(
                isA<ICloudOperationException>()
                    .having(
                      (error) => error.category,
                      'category',
                      'pluginContract',
                    )
                    .having(
                      (error) => error.operation,
                      'operation',
                      'watchDocumentChanges',
                    ),
              ),
              emitsDone,
            ]),
          );
        },
      );

      await changeExpectation;
    });

    test('watchDocumentChanges surfaces unsupported kinds as typed errors',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({
            'relativePath': 'Documents/journal.json',
            'kind': 'newKind',
          });
        },
      );

      late Future<void> changeExpectation;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeExpectation = expectLater(
            stream,
            emitsInOrder([
              emitsError(
                isA<ICloudOperationException>()
                    .having(
                      (error) => error.category,
                      'category',
                      'pluginContract',
                    )
                    .having(
                      (error) => error.operation,
                      'operation',
                      'watchDocumentChanges',
                    ),
              ),
              emitsDone,
            ]),
          );
        },
      );

      await changeExpectation;
    });

    test('ICloudDocumentChange.fromMap rejects missing relativePath', () {
      expect(
        () => ICloudDocumentChange.fromMap(const {'kind': 'invalidation'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('ICloudDocumentChange.fromMap rejects missing kind', () {
      expect(
        () => ICloudDocumentChange.fromMap(const {
          'relativePath': 'Documents/journal.json',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('ICloudDocumentChange.fromMap rejects unsupported kinds', () {
      expect(
        () => ICloudDocumentChange.fromMap(const {
          'relativePath': 'Documents/journal.json',
          'kind': 'newKind',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('documentExists', () async {
    final exists = await platform.documentExists(
      containerId: containerId,
      relativePath: 'file',
    );
    expect(exists, true);
  });

  test('getItemMetadata returns mapped metadata', () async {
    final metadata = await platform.getItemMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(metadata?.relativePath, 'item.txt');
    expect(metadata?.isDirectory, isFalse);
    expect(metadata?.downloadStatus, DownloadStatus.current);
  });

  test('getItemMetadata rejects unsupported downloadStatus values', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getItemMetadata') {
        return {
          'relativePath': 'item.txt',
          'isDirectory': false,
          'downloadStatus': 'unsupported',
        };
      }
      return null;
    });

    await expectLater(
      () => platform.getItemMetadata(
        containerId: containerId,
        relativePath: 'file',
      ),
      throwsA(
        isA<ICloudOperationException>()
            .having(
              (error) => error.category,
              'category',
              'pluginContract',
            )
            .having(
              (error) => error.operation,
              'operation',
              'getItemMetadata',
            ),
      ),
    );
  });

  test('getItemMetadata returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      mockMethodCall = methodCall;
      mockMethodCalls.add(methodCall);
      if (methodCall.method == 'getItemMetadata') {
        return null;
      }
      return null;
    });

    final metadata = await platform.getItemMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(metadata, isNull);
  });

  test('getItemMetadata maps structured conflict payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getItemMetadata') {
        throw PlatformException(
          code: _conflictCode,
          message: 'Conflict detected',
          details: {
            'category': 'conflict',
            'operation': 'getItemMetadata',
            'retryable': false,
            'relativePath': 'file',
          },
        );
      }
      return null;
    });

    await expectLater(
      () => platform.getItemMetadata(
        containerId: containerId,
        relativePath: 'file',
      ),
      throwsA(isA<ICloudConflictException>()),
    );
  });

  test('getContainerPath', () async {
    final path = await platform.getContainerPath(containerId: containerId);
    expect(path, '/container/path');
  });

  test('listContents maps results correctly', () async {
    final results = await platform.listContents(containerId: containerId);
    expect(results, hasLength(1));
    final item = results.first;
    expect(item.relativePath, 'file.txt');
    expect(item.isDirectory, false);
    expect(item.isDownloaded, true);
    expect(item.isUploaded, true);
  });

  test('listContents rejects a malformed element as a whole-call failure',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'listContents') {
        return [
          {
            'relativePath': 'valid.txt',
            'isDirectory': false,
            'downloadStatus': 'current',
            'isDownloading': false,
            'isUploaded': true,
            'isUploading': false,
            'hasUnresolvedConflicts': false,
          },
          'malformed',
        ];
      }
      return null;
    });

    await expectLater(
      () => platform.listContents(containerId: containerId),
      throwsA(_pluginContractFor('listContents')),
    );
  });

  test('icloudAvailable rejects wrong response type without leaking TypeError',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') return 'yes';
      return null;
    });

    await expectLater(
      platform.icloudAvailable,
      throwsA(_pluginContractFor('icloudAvailable')),
    );
  });

  test('missing native plugin maps to typed pluginContract exception',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      throw MissingPluginException('not registered');
    });

    await expectLater(
      () => platform.getContainerPath(containerId: containerId),
      throwsA(_pluginContractFor('getContainerPath')),
    );
  });

  test('icloudAvailable maps PlatformException to typed exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Native failure',
          details: {
            'category': 'unknownNative',
            'operation': 'icloudAvailable',
            'retryable': false,
          },
        );
      }
      return null;
    });

    await expectLater(
      platform.icloudAvailable,
      throwsA(
        isA<ICloudUnknownNativeException>().having(
          (error) => error.operation,
          'operation',
          'icloudAvailable',
        ),
      ),
    );
  });

  test('cancelled native categories map to dedicated exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Download cancelled',
          details: {
            'category': 'cancelled',
            'operation': 'icloudAvailable',
            'retryable': false,
          },
        );
      }
      return null;
    });

    await expectLater(
      platform.icloudAvailable,
      throwsA(isA<ICloudCancelledException>()),
    );
  });

  test('initialization categories map to dedicated exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Plugin not initialized',
          details: {
            'category': 'initialization',
            'operation': 'icloudAvailable',
            'retryable': false,
          },
        );
      }
      return null;
    });

    await expectLater(
      platform.icloudAvailable,
      throwsA(isA<ICloudInitializationException>()),
    );
  });

  test('future native categories preserve their category', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Future native failure',
          details: {
            'category': 'futureCategory',
            'operation': 'icloudAvailable',
            'retryable': false,
          },
        );
      }
      return null;
    });

    await expectLater(
      platform.icloudAvailable,
      throwsA(
        isA<ICloudOperationException>()
            .having((error) => error.category, 'category', 'futureCategory')
            .having(
              (error) => error is ICloudUnknownNativeException,
              'is ICloudUnknownNativeException',
              isFalse,
            ),
      ),
    );
  });

  test(
    'getContainerPath maps request response PlatformException '
    'to ICloudContainerAccessException',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        throw PlatformException(
          code: _containerAccessCode,
          message: 'Container unavailable',
          details: {
            'category': 'containerAccess',
            'operation': 'getContainerPath',
            'retryable': false,
          },
        );
      });

      await expectLater(
        () => platform.getContainerPath(containerId: containerId),
        throwsA(isA<ICloudContainerAccessException>()),
      );
    },
  );

  test('documentExists maps structured container access payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'documentExists') {
        throw PlatformException(
          code: _containerAccessCode,
          message: 'Container unavailable',
          details: {
            'category': 'containerAccess',
            'operation': 'documentExists',
            'retryable': false,
            'relativePath': 'file',
          },
        );
      }
      return null;
    });

    await expectLater(
      () => platform.documentExists(
        containerId: containerId,
        relativePath: 'file',
      ),
      throwsA(
        isA<ICloudContainerAccessException>()
            .having(
              (error) => error.operation,
              'operation',
              'documentExists',
            )
            .having((error) => error.relativePath, 'relativePath', 'file'),
      ),
    );
  });

  test('writeInPlace maps structured container access payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'writeInPlace') {
        throw PlatformException(
          code: _containerAccessCode,
          message: 'Container unavailable',
          details: {
            'category': 'containerAccess',
            'operation': 'writeInPlace',
            'retryable': false,
            'relativePath': 'file',
          },
        );
      }
      return null;
    });

    await expectLater(
      () => platform.writeInPlace(
        containerId: containerId,
        relativePath: 'file',
        contents: 'contents',
      ),
      throwsA(
        isA<ICloudContainerAccessException>()
            .having(
              (error) => error.operation,
              'operation',
              'writeInPlace',
            )
            .having((error) => error.relativePath, 'relativePath', 'file'),
      ),
    );
  });

  test('details-less request failures map to typed unknown exceptions',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      throw PlatformException(
        code: _containerAccessCode,
        message: 'Container failure',
      );
    });

    await expectLater(
      () => platform.getContainerPath(containerId: containerId),
      throwsA(
        isA<ICloudUnknownNativeException>()
            .having((error) => error.operation, 'operation', 'unknown')
            .having((error) => error.message, 'message', 'Container failure'),
      ),
    );
  });

  test('request response APIs use typed mapping', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'readInPlace') {
        throw PlatformException(
          code: _conflictCode,
          message: 'Conflict detected',
          details: {
            'category': 'conflict',
            'operation': 'readInPlace',
            'retryable': false,
            'relativePath': 'Documents/test.json',
          },
        );
      }
      return null;
    });

    await expectLater(
      () => platform.readInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
      ),
      throwsA(isA<ICloudConflictException>()),
    );
  });

  test('details-less listContents failures map to typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'listContents') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Native failure',
        );
      }
      return null;
    });

    await expectLater(
      () => platform.listContents(containerId: containerId),
      throwsA(isA<ICloudUnknownNativeException>()),
    );
  });

  test('transfer progress stream errors are typed stream errors', () async {
    mockStreamHandler = MockStreamHandler.inline(
      onListen: (arguments, events) {
        events.error(
          code: _nativeCodeError,
          message: 'Native failure',
          details: {
            'category': 'unknownNative',
            'operation': 'downloadFile',
            'retryable': false,
          },
        );
      },
    );

    late Future<void> progressExpectation;

    await platform.downloadFile(
      containerId: containerId,
      relativePath: 'file',
      localPath: '/tmp/file',
      onProgress: (stream) {
        progressExpectation = expectLater(
          stream,
          emitsError(
            isA<ICloudUnknownNativeException>().having(
              (error) => error.operation,
              'operation',
              'downloadFile',
            ),
          ),
        );
      },
    );

    await progressExpectation;
  });

  test('transfer failure is not duplicated when native reports stream delivery',
      () async {
    mockStreamHandler = MockStreamHandler.inline(
      onListen: (arguments, events) {
        events.error(
          code: _nativeCodeError,
          message: 'Native failure',
          details: {
            'category': 'unknownNative',
            'operation': 'downloadFile',
            'retryable': false,
          },
        );
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      mockMethodCall = methodCall;
      mockMethodCalls.add(methodCall);
      if (methodCall.method == 'createEventChannel') {
        final args = mockArguments();
        lastEventChannelName = args['eventChannelName'] as String?;
        if (lastEventChannelName != null && mockStreamHandler != null) {
          final eventChannel = EventChannel(lastEventChannelName!);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockStreamHandler(eventChannel, mockStreamHandler);
        }
        return null;
      }
      if (methodCall.method == 'downloadFile') {
        throw PlatformException(
          code: _nativeCodeError,
          message: 'Native failure',
          details: {
            'category': 'unknownNative',
            'operation': 'downloadFile',
            'retryable': false,
          },
        );
      }
      return null;
    });

    late Future<void> progressExpectation;
    await platform.downloadFile(
      containerId: containerId,
      relativePath: 'file',
      localPath: '/tmp/file',
      onProgress: (stream) {
        progressExpectation = expectLater(
          stream,
          emitsError(isA<ICloudUnknownNativeException>()),
        );
      },
    );

    await progressExpectation;
  });

  test('transfer setup failure reaches stream and Future', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'createEventChannel') return 'unexpected';
      return null;
    });

    late Future<void> progressExpectation;
    await expectLater(
      () => platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          progressExpectation = expectLater(
            stream,
            emitsInOrder([
              emitsError(_pluginContractFor('createEventChannel')),
              emitsDone,
            ]),
          );
        },
      ),
      throwsA(_pluginContractFor('createEventChannel')),
    );
    await progressExpectation;
  });

  test('paused listener does not block setup failure Future', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'createEventChannel') return 'unexpected';
      return null;
    });

    late StreamSubscription<ICloudTransferProgress> subscription;
    await expectLater(
      () => platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        relativePath: 'dest',
        onProgress: (stream) {
          subscription = stream.listen((_) {}, onError: (_) {})..pause();
        },
      ),
      throwsA(_pluginContractFor('createEventChannel')),
    ).timeout(const Duration(seconds: 1));

    await subscription.cancel();
  });
}
