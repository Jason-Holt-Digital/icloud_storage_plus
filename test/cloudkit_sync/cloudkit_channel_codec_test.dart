import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/cloudkit_sync.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_channel_codec.dart';

import 'helpers.dart';

void main() {
  const id = CloudKitRecordId(zoneName: 'Library', recordName: 'book-1');
  const idMap = {'zoneName': 'Library', 'recordName': 'book-1'};
  final error = {
    'code': CloudKitErrorCode.serverRecordChanged,
    'message': 'Newer',
  };

  T decode<T extends CloudKitSyncEvent>(Map<String, Object?> payload) =>
      CloudKitChannelCodec.decodeEvent(payload) as T;

  test('decodes received records with assets and system fields', () {
    final record = CloudKitChannelCodec.decodeRecord({
      ...recordMap(fields: {'title': 'Tome', 'pages': 320}),
      'assets': {'cover': '/cache/cover.png'},
    });

    expect(record.id, id);
    expect(record.recordType, 'Book');
    expect(record.fields, {'title': 'Tome', 'pages': 320});
    expect(record.assets['cover']!.path, '/cache/cover.png');
    expect(record.systemFields, Uint8List.fromList([1, 2, 3]));
  });

  test('keeps an asset that was not downloaded as a null value', () {
    final record = CloudKitChannelCodec.decodeRecord({
      ...recordMap(),
      'assets': {'cover': null},
    });

    expect(record.assets, {'cover': null});
  });

  test('decodes account changes', () {
    final change = decode<CloudKitAccountChange>({
      'type': 'accountChange',
      'changeType': 'switchAccounts',
      'previousUserRecordName': '_old',
      'currentUserRecordName': '_new',
    });

    expect(change.type, CloudKitAccountChangeType.switchAccounts);
    expect(change.previousUserRecordName, '_old');
    expect(change.currentUserRecordName, '_new');
  });

  test('decodes zone deletions, including reasons from later OS versions', () {
    final changes = decode<CloudKitFetchedDatabaseChanges>({
      'type': 'fetchedDatabaseChanges',
      'modifiedZoneNames': ['Library'],
      'deletions': [
        {'zoneName': 'Library', 'reason': 'encryptedDataReset'},
        {'zoneName': 'Old', 'reason': 'unknown'},
      ],
    });

    expect(changes.modifiedZoneNames, ['Library']);
    expect(changes.deletions.map((d) => (d.zoneName, d.reason)), [
      ('Library', CloudKitZoneDeletionReason.encryptedDataReset),
      ('Old', CloudKitZoneDeletionReason.unknown),
    ]);
  });

  test('decodes fetched record changes', () {
    final changes = decode<CloudKitFetchedRecordZoneChanges>({
      'type': 'fetchedRecordZoneChanges',
      'modifications': [recordMap()],
      'deletions': [
        {'id': idMap, 'recordType': 'Bookmark'},
      ],
    });

    expect(changes.modifications.single.id, id);
    expect(changes.deletions.single.id, id);
    expect(changes.deletions.single.recordType, 'Bookmark');
  });

  test('decodes sent record changes with failures and server records', () {
    final sent = decode<CloudKitSentRecordZoneChanges>({
      'type': 'sentRecordZoneChanges',
      'savedRecords': [recordMap()],
      'failedRecordSaves': [
        {
          'record': recordMap(),
          'error': {...error, 'serverRecord': recordMap()},
        },
      ],
      'deletedRecordIDs': [idMap],
      'failedRecordDeletes': [
        {
          'id': idMap,
          'error': {
            'code': CloudKitErrorCode.zoneNotFound,
            'message': 'No zone',
          },
        },
      ],
    });

    expect(sent.savedRecords.single.id, id);
    final failedSave = sent.failedRecordSaves.single;
    expect(failedSave.error.code, CloudKitErrorCode.serverRecordChanged);
    expect(failedSave.error.serverRecord!.id, id);
    expect(sent.deletedRecordIds, [id]);
    final failedDelete = sent.failedRecordDeletes.single;
    expect(failedDelete.error.code, CloudKitErrorCode.zoneNotFound);
    expect(failedDelete.error.serverRecord, isNull);
  });

  test('decodes sent zone changes', () {
    final sent = decode<CloudKitSentDatabaseChanges>({
      'type': 'sentDatabaseChanges',
      'savedZoneNames': ['Library'],
      'failedZoneSaves': [
        {'zoneName': 'Blobs', 'error': error},
      ],
      'deletedZoneNames': ['Old'],
      'failedZoneDeletes': <Object?>[],
    });

    expect(sent.savedZoneNames, ['Library']);
    expect(sent.failedZoneSaves.single.zoneName, 'Blobs');
    expect(sent.deletedZoneNames, ['Old']);
    expect(sent.failedZoneDeletes, isEmpty);
  });

  test('accepts every supported field value type when encoding', () {
    final encoded = CloudKitChannelCodec.encodeRecord(
      CloudKitRecord(
        id: id,
        recordType: 'Book',
        fields: {
          'string': 'a',
          'int': 1,
          'double': 1.5,
          'bytes': Uint8List.fromList([7, 8]),
          'list': [1, 2],
          'removed': null,
        },
      ),
    );

    expect(encoded['systemFields'], isNull);
    expect(encoded['fields'], {
      'string': 'a',
      'int': 1,
      'double': 1.5,
      'bytes': isA<Uint8List>().having((b) => b.toList(), 'bytes', [7, 8]),
      'list': [1, 2],
      'removed': null,
    });
  });

  test('rejects a saved asset without a file', () {
    expect(
      () => CloudKitChannelCodec.encodeRecord(
        const CloudKitRecord(
          id: id,
          recordType: 'Book',
          assets: {'cover': null},
        ),
      ),
      throwsA(
        isA<ArgumentError>().having((e) => e.name, 'name', 'assets[cover]'),
      ),
    );
  });

  test('rejects unsupported field values when encoding', () {
    for (final value in [
      true,
      DateTime(2026),
      [
        [1],
      ],
      {'a': 1},
    ]) {
      expect(
        () => CloudKitChannelCodec.encodeRecord(
          CloudKitRecord(id: id, recordType: 'Book', fields: {'f': value}),
        ),
        throwsArgumentError,
        reason: '$value',
      );
    }
  });
}
