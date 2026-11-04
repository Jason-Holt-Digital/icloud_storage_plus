import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Identity of a CloudKit record in a zone of the private database.
final class CloudKitRecordId extends Equatable {
  /// Creates a CloudKitRecordId.
  const CloudKitRecordId({required this.zoneName, required this.recordName});

  /// Name of the record zone that holds the record.
  final String zoneName;

  /// Record name, unique within the zone.
  final String recordName;

  @override
  List<Object> get props => [zoneName, recordName];

  @override
  String toString() => '$zoneName/$recordName';
}

/// A CloudKit record as it crosses the bridge.
final class CloudKitRecord {
  /// Creates a CloudKitRecord.
  const CloudKitRecord({
    required this.id,
    required this.recordType,
    this.fields = const {},
    this.assets = const {},
    this.systemFields,
  });

  /// Record identity.
  final CloudKitRecordId id;

  /// CloudKit record type.
  final String recordType;

  /// Field values: `String`, `int`, `double`, `Uint8List`, or a `List` of
  /// those. When saving, a null value removes the field from the server copy.
  /// A received record never holds null values.
  ///
  /// Saving a record built from [systemFields] sends only these fields; fields
  /// left out keep their server values.
  ///
  /// The bridge cannot deliver a received record with any other field type,
  /// such as a date, a boolean, a reference, or a location. Receiving one
  /// stops the engine, and later calls throw
  /// `CloudKitSyncException.engineNotRunning` with a message that names the
  /// record type, record, and field. The engine stays stopped across starts
  /// until that record no longer holds the value.
  final Map<String, Object?> fields;

  /// Files carried as CloudKit assets, keyed by field name.
  ///
  /// A received asset file belongs to CloudKit. It stays readable only until
  /// the call that delivered it completes, so copy what you need to keep. A
  /// received value is null when the server has an asset in that field but
  /// CloudKit did not download it, as in the `serverRecord` of a
  /// `CloudKitItemError`.
  ///
  /// A record being saved must give a file for every asset, and the file must
  /// stay in place until the save is reported.
  final Map<String, File?> assets;

  /// CloudKit's archived system fields from the last server copy, or null for
  /// a record the server has never stored. Pass them back unchanged when
  /// saving, so the server can reject a save based on an older copy.
  final Uint8List? systemFields;
}

/// A record change for the engine to send.
sealed class CloudKitPendingRecordZoneChange extends Equatable {
  const CloudKitPendingRecordZoneChange(this.id);

  /// Record the change applies to.
  final CloudKitRecordId id;

  @override
  List<Object> get props => [id];
}

/// Save the record with [id].
final class CloudKitPendingRecordSave extends CloudKitPendingRecordZoneChange {
  /// Creates a CloudKitPendingRecordSave.
  const CloudKitPendingRecordSave(super.id);
}

/// Delete the record with [id].
final class CloudKitPendingRecordDelete
    extends CloudKitPendingRecordZoneChange {
  /// Creates a CloudKitPendingRecordDelete.
  const CloudKitPendingRecordDelete(super.id);
}

/// A zone change for the engine to send.
sealed class CloudKitPendingDatabaseChange extends Equatable {
  const CloudKitPendingDatabaseChange(this.zoneName);

  /// Zone the change applies to.
  final String zoneName;

  @override
  List<Object> get props => [zoneName];
}

/// Create the zone, or keep it when it exists.
final class CloudKitPendingZoneSave extends CloudKitPendingDatabaseChange {
  /// Creates a CloudKitPendingZoneSave.
  const CloudKitPendingZoneSave(super.zoneName);
}

/// Delete the zone and every record in it.
final class CloudKitPendingZoneDelete extends CloudKitPendingDatabaseChange {
  /// Creates a CloudKitPendingZoneDelete.
  const CloudKitPendingZoneDelete(super.zoneName);
}

/// The records for one request the engine sends.
final class CloudKitRecordZoneChangeBatch {
  /// Creates a CloudKitRecordZoneChangeBatch.
  const CloudKitRecordZoneChangeBatch({
    this.recordsToSave = const [],
    this.recordIdsToDelete = const [],
  });

  /// Records to save, each answering a [CloudKitPendingRecordSave].
  final List<CloudKitRecord> recordsToSave;

  /// Records to delete, each answering a [CloudKitPendingRecordDelete].
  final List<CloudKitRecordId> recordIdsToDelete;
}
