import 'dart:io';
import 'dart:typed_data';

import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_records.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_events.dart';

/// Converts bridge values to and from the maps that cross the CloudKit sync
/// channel.
abstract final class CloudKitChannelCodec {
  /// Encodes a record ID.
  static Map<String, Object?> encodeRecordId(CloudKitRecordId id) => {
        'zoneName': id.zoneName,
        'recordName': id.recordName,
      };

  /// Decodes a record ID.
  static CloudKitRecordId decodeRecordId(Object? value) {
    final map = value! as Map<Object?, Object?>;
    return CloudKitRecordId(
      zoneName: map['zoneName']! as String,
      recordName: map['recordName']! as String,
    );
  }

  /// Encodes [record] for a save.
  ///
  /// Throws an [ArgumentError] for a field value CloudKit cannot store
  /// through the bridge, or for an asset without a file.
  static Map<String, Object?> encodeRecord(CloudKitRecord record) {
    for (final MapEntry(:key, :value) in record.fields.entries) {
      final supported = switch (value) {
        null => true,
        final List<Object?> list => list.every(_isScalarFieldValue),
        _ => _isScalarFieldValue(value),
      };
      if (!supported) {
        throw ArgumentError.value(
          value,
          'fields[$key]',
          'Must be a String, int, double, Uint8List, a List of those, or null',
        );
      }
    }
    for (final MapEntry(:key, :value) in record.assets.entries) {
      if (value == null) {
        throw ArgumentError.value(value, 'assets[$key]', 'Must be a file');
      }
    }
    return {
      'id': encodeRecordId(record.id),
      'recordType': record.recordType,
      'fields': record.fields,
      'assets': {
        for (final MapEntry(:key, :value) in record.assets.entries)
          key: value!.path,
      },
      'systemFields': record.systemFields,
    };
  }

  static bool _isScalarFieldValue(Object? value) =>
      value is String || value is int || value is double || value is Uint8List;

  /// Decodes a record received from CloudKit.
  static CloudKitRecord decodeRecord(Object? value) {
    final map = value! as Map<Object?, Object?>;
    return CloudKitRecord(
      id: decodeRecordId(map['id']),
      recordType: map['recordType']! as String,
      fields: {
        for (final MapEntry(:key, :value)
            in (map['fields']! as Map<Object?, Object?>).entries)
          key! as String: value,
      },
      assets: {
        for (final MapEntry(:key, :value)
            in (map['assets']! as Map<Object?, Object?>).entries)
          key! as String: value == null ? null : File(value as String),
      },
      systemFields: map['systemFields'] as Uint8List?,
    );
  }

  /// Encodes a pending record change.
  static Map<String, Object?> encodePendingRecordZoneChange(
    CloudKitPendingRecordZoneChange change,
  ) =>
      {
        'type': switch (change) {
          CloudKitPendingRecordSave() => 'save',
          CloudKitPendingRecordDelete() => 'delete',
        },
        'id': encodeRecordId(change.id),
      };

  /// Decodes a pending record change.
  static CloudKitPendingRecordZoneChange decodePendingRecordZoneChange(
    Object? value,
  ) {
    final map = value! as Map<Object?, Object?>;
    final id = decodeRecordId(map['id']);
    return switch (map['type']) {
      'save' => CloudKitPendingRecordSave(id),
      'delete' => CloudKitPendingRecordDelete(id),
      final type => throw ArgumentError.value(type, 'type'),
    };
  }

  /// Encodes a pending zone change.
  static Map<String, Object?> encodePendingDatabaseChange(
    CloudKitPendingDatabaseChange change,
  ) =>
      {
        'type': switch (change) {
          CloudKitPendingZoneSave() => 'saveZone',
          CloudKitPendingZoneDelete() => 'deleteZone',
        },
        'zoneName': change.zoneName,
      };

  /// Encodes the delegate's reply to `nextRecordZoneChangeBatch`.
  static Map<String, Object?> encodeBatch(
    CloudKitRecordZoneChangeBatch batch,
  ) =>
      {
        'recordsToSave': batch.recordsToSave.map(encodeRecord).toList(),
        'recordIDsToDelete':
            batch.recordIdsToDelete.map(encodeRecordId).toList(),
      };

  /// Decodes an engine event.
  static CloudKitSyncEvent decodeEvent(Object? value) {
    final map = value! as Map<Object?, Object?>;
    List<Object?> list(String key) => map[key]! as List<Object?>;
    List<String> strings(String key) => list(key).cast<String>();
    return switch (map['type']) {
      'stateUpdate' => CloudKitStateUpdate(
          map['stateSerialization']! as String,
        ),
      'accountChange' => CloudKitAccountChange(
          type: CloudKitAccountChangeType.values.byName(
            map['changeType']! as String,
          ),
          previousUserRecordName: map['previousUserRecordName'] as String?,
          currentUserRecordName: map['currentUserRecordName'] as String?,
        ),
      'fetchedDatabaseChanges' => CloudKitFetchedDatabaseChanges(
          modifiedZoneNames: strings('modifiedZoneNames'),
          deletions: [
            for (final deletion in list(
              'deletions',
            ).cast<Map<Object?, Object?>>())
              CloudKitZoneDeletion(
                zoneName: deletion['zoneName']! as String,
                reason: CloudKitZoneDeletionReason.values.byName(
                  deletion['reason']! as String,
                ),
              ),
          ],
        ),
      'fetchedRecordZoneChanges' => CloudKitFetchedRecordZoneChanges(
          modifications: list('modifications').map(decodeRecord).toList(),
          deletions: [
            for (final deletion in list(
              'deletions',
            ).cast<Map<Object?, Object?>>())
              CloudKitRecordDeletion(
                id: decodeRecordId(deletion['id']),
                recordType: deletion['recordType']! as String,
              ),
          ],
        ),
      'sentDatabaseChanges' => CloudKitSentDatabaseChanges(
          savedZoneNames: strings('savedZoneNames'),
          failedZoneSaves: _failedZoneChanges(list('failedZoneSaves')),
          deletedZoneNames: strings('deletedZoneNames'),
          failedZoneDeletes: _failedZoneChanges(list('failedZoneDeletes')),
        ),
      'sentRecordZoneChanges' => CloudKitSentRecordZoneChanges(
          savedRecords: list('savedRecords').map(decodeRecord).toList(),
          failedRecordSaves: [
            for (final failure in list(
              'failedRecordSaves',
            ).cast<Map<Object?, Object?>>())
              CloudKitFailedRecordSave(
                record: decodeRecord(failure['record']),
                error: _decodeItemError(failure['error']),
              ),
          ],
          deletedRecordIds:
              list('deletedRecordIDs').map(decodeRecordId).toList(),
          failedRecordDeletes: [
            for (final failure in list(
              'failedRecordDeletes',
            ).cast<Map<Object?, Object?>>())
              CloudKitFailedRecordDelete(
                id: decodeRecordId(failure['id']),
                error: _decodeItemError(failure['error']),
              ),
          ],
        ),
      final type => throw ArgumentError.value(type, 'type'),
    };
  }

  static List<CloudKitFailedZoneChange> _failedZoneChanges(
    List<Object?> failures,
  ) =>
      [
        for (final failure in failures.cast<Map<Object?, Object?>>())
          CloudKitFailedZoneChange(
            zoneName: failure['zoneName']! as String,
            error: _decodeItemError(failure['error']),
          ),
      ];

  static CloudKitItemError _decodeItemError(Object? value) {
    final map = value! as Map<Object?, Object?>;
    final serverRecord = map['serverRecord'];
    return CloudKitItemError(
      code: map['code']! as int,
      message: map['message']! as String,
      serverRecord: serverRecord == null ? null : decodeRecord(serverRecord),
    );
  }
}
