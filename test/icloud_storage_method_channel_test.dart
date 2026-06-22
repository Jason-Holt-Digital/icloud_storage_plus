import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';

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
              'downloadStatus':
                  'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
              'isUploading': false,
              'isUploaded': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        case 'downloadFile':
          return null;
        case 'documentExists':
          return true;
        case 'getDocumentMetadata':
          return {
            'relativePath': 'meta.txt',
            'isDirectory': false,
          };
        case 'getItemMetadata':
          return {
            'relativePath': 'item.txt',
            'isDirectory': false,
            'downloadStatus': 'NSURLUbiquitousItemDownloadingStatusCurrent',
          };
        case 'getContainerPath':
          return '/container/path';
        case 'listContents':
          return [
            {
              'relativePath': 'file.txt',
              'isDirectory': false,
              'downloadStatus': 'NSURLUbiquitousItemDownloadingStatusCurrent',
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
        onUpdate: (stream) {},
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });

    test('maps structured container access failures', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'gather') {
          throw PlatformException(
            code: PlatformExceptionCode.iCloudConnectionOrPermission,
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
        cloudRelativePath: 'dest',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['localFilePath'], '/dir/file');
      expect(args['cloudRelativePath'], 'dest');
      expect(args['eventChannelName'], '');
    });

    test('uploadFile with onProgress', () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  group('downloadFile tests:', () {
    test('downloadFile', () async {
      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['cloudRelativePath'], 'file');
      expect(args['localFilePath'], '/tmp/file');
      expect(args['eventChannelName'], '');
    });

    test('downloadFile with onProgress', () async {
      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
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

    test('writeInPlace maps structured invalidArgument payloads', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlace') {
          throw PlatformException(
            code: PlatformExceptionCode.argumentError,
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
            code: PlatformExceptionCode.nativeCodeError,
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
            code: PlatformExceptionCode.coordination,
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

      late Stream<ICloudTransferProgress> progressStream;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(3));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.25);
      expect(events[1].isProgress, isTrue);
      expect(events[1].percent, 1.0);
      expect(events[2].isDone, isTrue);
    });

    test('maps error events to error progress', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: 'E_TEST',
            message: 'Boom',
            details: 'details',
          );
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(1));
      final event = events.first;
      expect(event.isError, isTrue);
      expect(event.exception?.code, 'E_TEST');
      expect(event.exception?.message, 'Boom');
      expect(event.exception?.details, 'details');
    });

    test('delivers events after listener attaches', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(0.1)
            ..endOfStream();
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(2));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.1);
      expect(events[1].isDone, isTrue);
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
    test('watchDocumentChanges sends method args and maps typed payload',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success({
              'relativePath': 'Documents/journal.json',
              'kind': 'remoteChange',
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

      late Stream<ICloudDocumentChange> changeStream;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeStream = stream;
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

      final events = await changeStream.toList();
      expect(events, [
        const ICloudDocumentChange(
          relativePath: 'Documents/journal.json',
          kind: ICloudDocumentChangeKind.remoteChange,
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

    test('watchDocumentChanges maps stream errors to typed exceptions',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: PlatformExceptionCode.coordination,
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

      late Stream<ICloudDocumentChange> changeStream;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeStream = stream;
        },
      );

      await expectLater(
        changeStream,
        emitsError(isA<ICloudCoordinationException>()),
      );
    });

    test('watchDocumentChanges does not expose stream when native start fails',
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
            code: PlatformExceptionCode.iCloudConnectionOrPermission,
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

      late Stream<ICloudDocumentChange> changeStream;

      await expectLater(
        platform.watchDocumentChanges(
          containerId: containerId,
          relativePath: 'Documents/journal.json',
          onChange: (stream) {
            changeStream = stream;
          },
        ),
        throwsA(isA<ICloudContainerAccessException>()),
      );

      await expectLater(
        changeStream,
        emitsError(isA<ICloudContainerAccessException>()),
      );
      expect(mockMethodCalls.map((call) => call.method), [
        'createEventChannel',
        'watchDocumentChanges',
      ]);
    });

    test('watchDocumentChanges surfaces malformed payloads with stable code',
        () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({'relativePath': 'Documents/journal.json'});
        },
      );

      late Stream<ICloudDocumentChange> changeStream;

      await platform.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (stream) {
          changeStream = stream;
        },
      );

      await expectLater(
        changeStream,
        emitsError(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            PlatformExceptionCode.invalidEvent,
          ),
        ),
      );
    });

    test('ICloudDocumentChange.fromMap rejects missing relativePath', () {
      expect(
        () => ICloudDocumentChange.fromMap(const {'kind': 'remoteChange'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('ICloudDocumentChange.fromMap maps unknown kind fallback', () {
      final change = ICloudDocumentChange.fromMap(const {
        'relativePath': 'Documents/journal.json',
        'kind': 'newKind',
      });

      expect(change.kind, ICloudDocumentChangeKind.unknown);
    });
  });

  test('documentExists', () async {
    final exists = await platform.documentExists(
      containerId: containerId,
      relativePath: 'file',
    );
    expect(exists, true);
  });

  test('getDocumentMetadata', () async {
    final metadata = await platform.getDocumentMetadata(
      containerId: containerId,
      relativePath: 'file',
    );
    expect(metadata?['relativePath'], 'meta.txt');
  });

  test('getDocumentMetadata preserves raw native downloadStatus', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getDocumentMetadata') {
        return {
          'relativePath': 'meta.txt',
          'isDirectory': false,
          'downloadStatus': 'NSURLUbiquitousItemDownloadingStatusCurrent',
        };
      }
      return null;
    });

    final metadata = await platform.getDocumentMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(
      metadata?['downloadStatus'],
      'NSURLUbiquitousItemDownloadingStatusCurrent',
    );
  });

  test(
    'getDocumentMetadata keeps structured PlatformException behavior raw',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'getDocumentMetadata') {
          throw PlatformException(
            code: PlatformExceptionCode.conflict,
            message: 'Conflict detected',
            details: {
              'category': 'conflict',
              'operation': 'getDocumentMetadata',
              'retryable': false,
              'relativePath': 'file',
            },
          );
        }
        return null;
      });

      await expectLater(
        () => platform.getDocumentMetadata(
          containerId: containerId,
          relativePath: 'file',
        ),
        throwsA(
          isA<PlatformException>()
              .having(
                (error) => error.code,
                'code',
                PlatformExceptionCode.conflict,
              )
              .having(
                (error) => error.message,
                'message',
                'Conflict detected',
              ),
        ),
      );
    },
  );

  test('getItemMetadata returns mapped metadata', () async {
    final metadata = await platform.getItemMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(metadata?['relativePath'], 'item.txt');
    expect(metadata?['isDirectory'], isFalse);
    expect(metadata?['downloadStatus'], 'current');
  });

  test('getItemMetadata preserves unknown native downloadStatus values',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getItemMetadata') {
        return {
          'relativePath': 'item.txt',
          'isDirectory': false,
          'downloadStatus': 'NSURLUbiquitousItemDownloadingStatusMystery',
        };
      }
      return null;
    });

    final metadata = await platform.getItemMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(
      metadata?['downloadStatus'],
      'NSURLUbiquitousItemDownloadingStatusMystery',
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

  test('getItemMetadata falls back when new method is unimplemented', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      mockMethodCall = methodCall;
      mockMethodCalls.add(methodCall);
      switch (methodCall.method) {
        case 'getItemMetadata':
          throw MissingPluginException();
        case 'getDocumentMetadata':
          return {
            'relativePath': 'fallback.txt',
            'isDirectory': false,
            'downloadStatus':
                'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
          };
        default:
          return null;
      }
    });

    final metadata = await platform.getItemMetadata(
      containerId: containerId,
      relativePath: 'file',
    );

    expect(metadata?['relativePath'], 'fallback.txt');
    expect(metadata?['downloadStatus'], 'notDownloaded');
    expect(
      mockMethodCalls.map((call) => call.method),
      ['getItemMetadata', 'getDocumentMetadata'],
    );
  });

  test('getItemMetadata maps structured conflict payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getItemMetadata') {
        throw PlatformException(
          code: PlatformExceptionCode.conflict,
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

  test('icloudAvailable keeps raw PlatformException behavior', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'icloudAvailable') {
        throw PlatformException(
          code: PlatformExceptionCode.nativeCodeError,
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
      throwsA(isA<PlatformException>()),
    );
  });

  test(
    'getContainerPath maps request response PlatformException '
    'to ICloudContainerAccessException',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        throw PlatformException(
          code: PlatformExceptionCode.iCloudConnectionOrPermission,
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
          code: PlatformExceptionCode.iCloudConnectionOrPermission,
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
          code: PlatformExceptionCode.iCloudConnectionOrPermission,
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

  test(
    'legacy code only getContainerPath PlatformException is preserved',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        throw PlatformException(
          code: PlatformExceptionCode.iCloudConnectionOrPermission,
          message: 'Legacy container failure',
        );
      });

      await expectLater(
        () => platform.getContainerPath(containerId: containerId),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            PlatformExceptionCode.iCloudConnectionOrPermission,
          ),
        ),
      );
    },
  );

  test('request response APIs use typed mapping', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'readInPlace') {
        throw PlatformException(
          code: PlatformExceptionCode.conflict,
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

  test('legacy code only listContents PlatformException is preserved',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'listContents') {
        throw PlatformException(
          code: PlatformExceptionCode.nativeCodeError,
          message: 'Legacy native failure',
        );
      }
      return null;
    });

    await expectLater(
      () => platform.listContents(containerId: containerId),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          PlatformExceptionCode.nativeCodeError,
        ),
      ),
    );
  });

  test(
    'transfer progress stream errors remain PlatformException based',
    () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: PlatformExceptionCode.nativeCodeError,
            message: 'Native failure',
            details: {
              'category': 'unknownNative',
              'operation': 'downloadFile',
              'retryable': false,
            },
          );
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(1));
      expect(events.first.exception, isA<PlatformException>());
    },
  );
}
