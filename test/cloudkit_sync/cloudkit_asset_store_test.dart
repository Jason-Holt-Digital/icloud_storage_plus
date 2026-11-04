import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/cloudkit_sync.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = CloudKitAssetStore('iCloud.com.example.app');
  const id = CloudKitRecordId(zoneName: 'Blobs', recordName: 'abc123');
  const idMap = {'zoneName': 'Blobs', 'recordName': 'abc123'};

  test('recordExists returns the native answer', () async {
    final calls = mockNative((_) async => true);

    expect(await store.recordExists(id), isTrue);
    expect(calls.single.arguments, {
      'containerId': 'iCloud.com.example.app',
      'id': idMap,
    });
  });

  test('uploadAsset passes the record, field, and source path', () async {
    final calls = mockNative();

    await store.uploadAsset(
      id: id,
      recordType: 'Blob',
      field: 'data',
      source: File('/tmp/book.pdf'),
    );

    expect(calls.single.method, 'uploadAsset');
    expect(calls.single.arguments, {
      'containerId': 'iCloud.com.example.app',
      'id': idMap,
      'recordType': 'Blob',
      'field': 'data',
      'sourcePath': '/tmp/book.pdf',
    });
  });

  test(
      'download progress reaches only its own listener while the download '
      'runs', () async {
    final progress = <double>[];
    late int transferId;
    mockNative((call) async {
      transferId = (call.arguments as Map)['transferId'] as int;
      await callFromNative('downloadProgress', {
        'transferId': transferId,
        'fraction': 0.5,
      });
      await callFromNative('downloadProgress', {
        'transferId': transferId + 1,
        'fraction': 0.9,
      });
      return null;
    });

    await store.downloadAsset(
      id: id,
      field: 'data',
      destination: File('/tmp/out.pdf'),
      onProgress: progress.add,
    );
    await callFromNative('downloadProgress', {
      'transferId': transferId,
      'fraction': 1.0,
    });

    expect(progress, [0.5]);
  });

  test('a download without a progress listener sends no transfer ID', () async {
    final calls = mockNative();

    await store.downloadAsset(
      id: id,
      field: 'data',
      destination: File('/tmp/out.pdf'),
    );

    expect((calls.single.arguments as Map)['transferId'], isNull);
  });

  test('a missing asset fails with its code', () async {
    mockNative((_) async {
      throw PlatformException(code: 'missingAsset', message: 'No asset');
    });

    await expectLater(
      store.downloadAsset(
        id: id,
        field: 'data',
        destination: File('/tmp/out.pdf'),
      ),
      throwsA(
        isA<CloudKitSyncException>().having(
          (e) => e.code,
          'code',
          CloudKitSyncException.missingAsset,
        ),
      ),
    );
  });
}
