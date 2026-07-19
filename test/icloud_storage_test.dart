import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockICloudStoragePlatform
    with MockPlatformInterfaceMixin
    implements ICloudStoragePlatform {
  final List<String> _calls = [];
  List<String> get calls => _calls;

  String _moveToRelativePath = '';
  String get moveToRelativePath => _moveToRelativePath;

  String _uploadRelativePath = '';
  String get uploadRelativePath => _uploadRelativePath;

  String _downloadRelativePath = '';
  String get downloadRelativePath => _downloadRelativePath;

  String _downloadLocalPath = '';
  String get downloadLocalPath => _downloadLocalPath;

  String _readInPlaceRelativePath = '';
  String get readInPlaceRelativePath => _readInPlaceRelativePath;

  String readInPlaceResult = 'contents';

  String _writeInPlaceRelativePath = '';
  String get writeInPlaceRelativePath => _writeInPlaceRelativePath;

  String _writeInPlaceContents = '';
  String get writeInPlaceContents => _writeInPlaceContents;

  bool documentExistsResult = true;
  ICloudItemMetadata? itemMetadataResult = ICloudItemMetadata.fromMap(const {
    'relativePath': 'Documents/test.pdf',
    'isDownloading': false,
    'isUploading': false,
    'isUploaded': false,
    'isDirectory': false,
    'sizeInBytes': 1024,
    'creationDate': 1638288000.0,
    'contentChangeDate': 1638374400.0,
    'downloadStatus': 'current',
    'hasUnresolvedConflicts': false,
  });

  @override
  Future<bool> icloudAvailable() async {
    _calls.add('icloudAvailable');
    return true;
  }

  @override
  Future<String?> getContainerPath({required String containerId}) async {
    _calls.add('getContainerPath');
    return '/mock/container/path';
  }

  @override
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    _calls.add('gather');
    return const GatherResult(files: []);
  }

  @override
  Future<void> watchDocumentChanges({
    required String containerId,
    required String relativePath,
    required StreamHandler<ICloudDocumentChange> onChange,
  }) async {
    _calls.add('watchDocumentChanges');
  }

  @override
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    _uploadRelativePath = relativePath;
    _calls.add('uploadFile');
  }

  @override
  Future<void> downloadFile({
    required String containerId,
    required String relativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    _downloadRelativePath = relativePath;
    _downloadLocalPath = localPath;
    _calls.add('downloadFile');
  }

  @override
  Future<String> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    _readInPlaceRelativePath = relativePath;
    _calls.add('readInPlace');
    return readInPlaceResult;
  }

  @override
  Future<Uint8List> readInPlaceBytes({
    required String containerId,
    required String relativePath,
  }) async {
    _readInPlaceRelativePath = relativePath;
    _calls.add('readInPlaceBytes');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    _writeInPlaceRelativePath = relativePath;
    _writeInPlaceContents = contents;
    _calls.add('writeInPlace');
  }

  @override
  Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    _writeInPlaceRelativePath = relativePath;
    _calls.add('writeInPlaceBytes');
  }

  @override
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('delete');
  }

  @override
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    _moveToRelativePath = toRelativePath;
    _calls.add('move');
  }

  @override
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    _calls.add('copy');
  }

  @override
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('documentExists');
    return documentExistsResult;
  }

  @override
  Future<ICloudItemMetadata?> getItemMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('getItemMetadata');
    return itemMetadataResult;
  }

  @override
  Future<List<ContainerItem>> listContents({
    required String containerId,
    String? relativePath,
  }) async {
    _calls.add('listContents');
    return listContentsResult;
  }

  List<ContainerItem> listContentsResult = [];

  @override
  Future<List<ICloudVersion>> enumerateUnresolvedConflictVersions({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('enumerateUnresolvedConflictVersions');
    return enumerateUnresolvedConflictVersionsResult;
  }

  List<ICloudVersion> enumerateUnresolvedConflictVersionsResult = [];

  @override
  Future<void> copyConflictVersion({
    required String containerId,
    required String relativePath,
    required String versionIdentifier,
    required String destinationPath,
  }) async {
    _calls.add('copyConflictVersion');
  }

  @override
  Future<void> markConflictResolved({
    required String containerId,
    required String relativePath,
    bool removeOtherVersions = false,
  }) async {
    _calls.add('markConflictResolved');
  }
}

void main() {
  final initialPlatform = ICloudStoragePlatform.instance;

  test('$MethodChannelICloudStorage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelICloudStorage>());
  });

  test('barrel exports DownloadStatus and ICloudItemMetadata', () {
    final metadata = ICloudItemMetadata.fromMap(const {
      'relativePath': 'Documents/test.pdf',
      'isDirectory': false,
      'isDownloading': false,
      'isUploading': false,
      'isUploaded': false,
      'hasUnresolvedConflicts': false,
      'downloadStatus': 'current',
    });

    expect(metadata.downloadStatus, DownloadStatus.current);
    expect(metadata.isLocal, isTrue);
  });

  group('ICloudStorage static functions:', () {
    const containerId = 'containerId';
    final fakePlatform = MockICloudStoragePlatform();
    ICloudStoragePlatform.instance = fakePlatform;

    setUp(() {
      fakePlatform
        ..documentExistsResult = true
        ..itemMetadataResult = ICloudItemMetadata.fromMap(const {
          'relativePath': 'Documents/test.pdf',
          'isDownloading': false,
          'isUploading': false,
          'isUploaded': false,
          'isDirectory': false,
          'sizeInBytes': 1024,
          'creationDate': 1638288000.0,
          'contentChangeDate': 1638374400.0,
          'downloadStatus': 'current',
          'hasUnresolvedConflicts': false,
        })
        ..readInPlaceResult = 'contents'
        ..listContentsResult = [];
    });

    test('gather', () async {
      final result = await ICloudStorage.gather(containerId: containerId);
      expect(result.files, isEmpty);
    });

    test('watchDocumentChanges', () async {
      await ICloudStorage.watchDocumentChanges(
        containerId: containerId,
        relativePath: 'Documents/journal.json',
        onChange: (_) {},
      );

      expect(fakePlatform.calls.last, 'watchDocumentChanges');
    });

    test('watchDocumentChanges rejects trailing slash relativePath', () async {
      expect(
        () async => ICloudStorage.watchDocumentChanges(
          containerId: containerId,
          relativePath: 'Documents/folder/',
          onChange: (_) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
    });

    test('watchDocumentChanges rejects blank relativePath', () async {
      expect(
        () async => ICloudStorage.watchDocumentChanges(
          containerId: containerId,
          relativePath: '   ',
          onChange: (_) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
    });

    test('watchDocumentChanges rejects invalid relativePath characters',
        () async {
      expect(
        () async => ICloudStorage.watchDocumentChanges(
          containerId: containerId,
          relativePath: 'Documents/journal:1.json',
          onChange: (_) {},
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
    });

    group('uploadFile tests:', () {
      test('uploadFile', () async {
        await ICloudStorage.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          relativePath: 'dest',
        );
        expect(fakePlatform.uploadRelativePath, 'dest');
        expect(fakePlatform.calls.last, 'uploadFile');
      });

      test('uploadFile rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '/dir/file',
            relativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('uploadFile with invalid localPath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '',
            relativePath: 'dest',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('uploadFile with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '/dir/file',
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('downloadFile tests:', () {
      test('downloadFile', () async {
        await ICloudStorage.downloadFile(
          containerId: containerId,
          relativePath: 'file',
          localPath: '/tmp/file',
        );
        expect(fakePlatform.downloadRelativePath, 'file');
        expect(fakePlatform.downloadLocalPath, '/tmp/file');
        expect(fakePlatform.calls.last, 'downloadFile');
      });

      test('downloadFile rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            relativePath: 'Documents/folder/',
            localPath: '/tmp/file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('downloadFile with invalid localPath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            relativePath: 'file',
            localPath: '',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('downloadFile with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            relativePath: 'dir//file',
            localPath: '/tmp/file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('readInPlace tests:', () {
      test('readInPlace', () async {
        final result = await ICloudStorage.readInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
        );
        expect(result, 'contents');
        expect(fakePlatform.readInPlaceRelativePath, 'Documents/test.json');
        expect(fakePlatform.calls.last, 'readInPlace');
      });

      test('readInPlaceBytes', () async {
        final result = await ICloudStorage.readInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
        );
        expect(result, isNotNull);
        expect(result, Uint8List.fromList([1, 2, 3]));
        expect(fakePlatform.readInPlaceRelativePath, 'Documents/data.bin');
        expect(fakePlatform.calls.last, 'readInPlaceBytes');
      });

      test('readInPlace rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlace(
            containerId: containerId,
            relativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlace with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlace(
            containerId: containerId,
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlaceBytes rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlaceBytes(
            containerId: containerId,
            relativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlaceBytes with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlaceBytes(
            containerId: containerId,
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('writeInPlace tests:', () {
      test('writeInPlace', () async {
        await ICloudStorage.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
          contents: '{"ok":true}',
        );
        expect(fakePlatform.writeInPlaceRelativePath, 'Documents/test.json');
        expect(fakePlatform.writeInPlaceContents, '{"ok":true}');
        expect(fakePlatform.calls.last, 'writeInPlace');
      });

      test('writeInPlaceBytes', () async {
        await ICloudStorage.writeInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
          contents: Uint8List.fromList([4, 5, 6]),
        );
        expect(fakePlatform.writeInPlaceRelativePath, 'Documents/data.bin');
        expect(fakePlatform.calls.last, 'writeInPlaceBytes');
      });

      test('writeInPlace rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.writeInPlace(
            containerId: containerId,
            relativePath: 'Documents/folder/',
            contents: 'data',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('writeInPlace with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.writeInPlace(
            containerId: containerId,
            relativePath: 'dir//file',
            contents: 'data',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    test('rename uses move with derived path', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'Documents/config.json',
        newName: 'renamed.json',
      );
      expect(fakePlatform.moveToRelativePath, 'Documents/renamed.json');
    });

    test('rename on directory strips trailing slash for parent', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'Documents/folder/',
        newName: 'renamedFolder',
      );
      expect(fakePlatform.moveToRelativePath, 'Documents/renamedFolder');
    });

    test('rename handles root-level files', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'config.json',
        newName: 'renamed.json',
      );
      expect(fakePlatform.moveToRelativePath, 'renamed.json');
    });

    test('documentExists', () async {
      final result = await ICloudStorage.documentExists(
        containerId: containerId,
        relativePath: 'file',
      );
      expect(result, true);
    });

    test('delete accepts trailing slash', () async {
      await ICloudStorage.delete(
        containerId: containerId,
        relativePath: 'Documents/folder/',
      );
      expect(fakePlatform.calls.last, 'delete');
    });

    test('getItemMetadata accepts trailing slash', () async {
      await ICloudStorage.getItemMetadata(
        containerId: containerId,
        relativePath: 'Documents/folder/',
      );
      expect(fakePlatform.calls.last, 'getItemMetadata');
    });

    test('getItemMetadata returns typed metadata for an existing item',
        () async {
      final metadata = await ICloudStorage.getItemMetadata(
        containerId: containerId,
        relativePath: 'Documents/test.pdf',
      );

      expect(metadata, isA<ICloudItemMetadata>());
      expect(metadata?.relativePath, 'Documents/test.pdf');
    });

    test('getItemMetadata returns null for a missing item', () async {
      fakePlatform.itemMetadataResult = null;

      final metadata = await ICloudStorage.getItemMetadata(
        containerId: containerId,
        relativePath: 'Documents/missing.pdf',
      );

      expect(metadata, isNull);
    });

    test('getItemMetadata maps NSURL download status constants', () async {
      fakePlatform.itemMetadataResult = ICloudItemMetadata.fromMap(const {
        'relativePath': 'Documents/test.pdf',
        'isDownloading': false,
        'isUploading': false,
        'isUploaded': false,
        'hasUnresolvedConflicts': false,
        'isDirectory': false,
        'downloadStatus': 'current',
      });

      final metadata = await ICloudStorage.getItemMetadata(
        containerId: containerId,
        relativePath: 'Documents/test.pdf',
      );

      expect(metadata?.downloadStatus, DownloadStatus.current);
    });

    group('listContents tests:', () {
      test('listContents returns items', () async {
        fakePlatform.listContentsResult = [
          ContainerItem.fromMap(const {
            'relativePath': 'Documents/journal1.json',
            'downloadStatus': 'current',
            'isDownloading': false,
            'isUploaded': true,
            'isUploading': false,
            'hasUnresolvedConflicts': false,
            'isDirectory': false,
          }),
        ];

        final items = await ICloudStorage.listContents(
          containerId: containerId,
        );
        expect(items, hasLength(1));
        expect(items.first.relativePath, 'Documents/journal1.json');
        expect(items.first.downloadStatus, DownloadStatus.current);
        expect(items.first.isDownloaded, isTrue);
        expect(items.first.isUploaded, isTrue);
        expect(fakePlatform.calls.last, 'listContents');
      });

      test('listContents with relativePath', () async {
        final items = await ICloudStorage.listContents(
          containerId: containerId,
          relativePath: 'Documents',
        );
        expect(items, isEmpty);
        expect(fakePlatform.calls.last, 'listContents');
      });

      test('listContents rejects invalid relativePath', () async {
        expect(
          () async => ICloudStorage.listContents(
            containerId: containerId,
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('ContainerItem.isDownloaded for downloaded status', () {
        final item = ContainerItem.fromMap(const {
          'relativePath': 'file.txt',
          'isDirectory': false,
          'isDownloading': false,
          'isUploading': false,
          'isUploaded': false,
          'hasUnresolvedConflicts': false,
          'downloadStatus': 'downloaded',
        });
        expect(item.isDownloaded, isTrue);
        expect(item.downloadStatus, DownloadStatus.downloaded);
      });

      test('ContainerItem.isDownloaded for notDownloaded status', () {
        final item = ContainerItem.fromMap(const {
          'relativePath': 'file.txt',
          'isDirectory': false,
          'isDownloading': false,
          'isUploading': false,
          'isUploaded': false,
          'hasUnresolvedConflicts': false,
          'downloadStatus': 'notDownloaded',
        });
        expect(item.isDownloaded, isFalse);
        expect(item.downloadStatus, DownloadStatus.notDownloaded);
      });

      test('ContainerItem handles null downloadStatus', () {
        final item = ContainerItem.fromMap(const {
          'relativePath': 'file.txt',
          'isDirectory': false,
          'isDownloading': false,
          'isUploading': false,
          'isUploaded': false,
          'hasUnresolvedConflicts': false,
        });
        expect(item.downloadStatus, isNull);
        expect(item.isDownloaded, isFalse);
      });
    });
  });
}
