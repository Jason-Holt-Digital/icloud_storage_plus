import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_records.dart';

/// Something `CKSyncEngine` reported. Each subtype mirrors one
/// `CKSyncEngine.Event` case.
sealed class CloudKitSyncEvent {
  const CloudKitSyncEvent();
}

/// The engine state changed. Save [stateSerialization] together with the
/// changes already handled and pass it to the next
/// `CloudKitSyncEngine.start`.
final class CloudKitStateUpdate extends CloudKitSyncEvent {
  /// Creates a CloudKitStateUpdate.
  const CloudKitStateUpdate(this.stateSerialization);

  /// Opaque serialized engine state.
  final String stateSerialization;
}

/// How the device's iCloud account changed.
enum CloudKitAccountChangeType {
  /// An account signed in.
  signIn,

  /// The account signed out.
  signOut,

  /// A different account signed in.
  switchAccounts,
}

/// The device's iCloud account changed.
final class CloudKitAccountChange extends CloudKitSyncEvent {
  /// Creates a CloudKitAccountChange.
  const CloudKitAccountChange({
    required this.type,
    this.previousUserRecordName,
    this.currentUserRecordName,
  });

  /// Kind of change.
  final CloudKitAccountChangeType type;

  /// User record name of the account before the change; null for
  /// [CloudKitAccountChangeType.signIn].
  final String? previousUserRecordName;

  /// User record name of the account after the change; null for
  /// [CloudKitAccountChangeType.signOut].
  final String? currentUserRecordName;
}

/// Why a zone was deleted.
enum CloudKitZoneDeletionReason {
  /// The zone was deleted, for example by another device.
  deleted,

  /// The user removed the app's data from iCloud.
  purged,

  /// The account's encryption keys were reset, which discards encrypted data
  /// on the server.
  encryptedDataReset,

  /// A reason added in a later OS version.
  unknown,
}

/// One zone deletion.
final class CloudKitZoneDeletion {
  /// Creates a CloudKitZoneDeletion.
  const CloudKitZoneDeletion({required this.zoneName, required this.reason});

  /// Deleted zone.
  final String zoneName;

  /// Why the zone was deleted.
  final CloudKitZoneDeletionReason reason;
}

/// Zones changed or were deleted.
final class CloudKitFetchedDatabaseChanges extends CloudKitSyncEvent {
  /// Creates a CloudKitFetchedDatabaseChanges.
  const CloudKitFetchedDatabaseChanges({
    required this.modifiedZoneNames,
    required this.deletions,
  });

  /// Zones with changes.
  final List<String> modifiedZoneNames;

  /// Zones deleted from the server.
  final List<CloudKitZoneDeletion> deletions;
}

/// A record deleted on the server.
final class CloudKitRecordDeletion {
  /// Creates a CloudKitRecordDeletion.
  const CloudKitRecordDeletion({required this.id, required this.recordType});

  /// Deleted record.
  final CloudKitRecordId id;

  /// Type of the deleted record.
  final String recordType;
}

/// One batch of record changes fetched from the server.
final class CloudKitFetchedRecordZoneChanges extends CloudKitSyncEvent {
  /// Creates a CloudKitFetchedRecordZoneChanges.
  const CloudKitFetchedRecordZoneChanges({
    required this.modifications,
    required this.deletions,
  });

  /// Records created or changed on the server.
  final List<CloudKitRecord> modifications;

  /// Records deleted on the server.
  final List<CloudKitRecordDeletion> deletions;
}

/// A CloudKit error for one record or zone.
final class CloudKitItemError {
  /// Creates a CloudKitItemError.
  const CloudKitItemError({
    required this.code,
    required this.message,
    this.serverRecord,
  });

  /// `CKError.Code` raw value; see [CloudKitErrorCode].
  final int code;

  /// CloudKit's description of the error.
  final String message;

  /// Current server copy, for [CloudKitErrorCode.serverRecordChanged]. Its
  /// asset values are null because CloudKit does not download them.
  final CloudKitRecord? serverRecord;
}

/// `CKError.Code` raw values that an app acts on. Compare any other code
/// with its raw value from Apple's `CKError.Code` documentation.
abstract final class CloudKitErrorCode {
  /// The record does not exist on the server.
  static const unknownItem = 11;

  /// The server holds a newer copy than the one the save was based on.
  static const serverRecordChanged = 14;

  /// The user's iCloud storage is full.
  static const quotaExceeded = 25;

  /// The zone does not exist on the server.
  static const zoneNotFound = 26;
}

/// A zone save or delete that failed.
final class CloudKitFailedZoneChange {
  /// Creates a CloudKitFailedZoneChange.
  const CloudKitFailedZoneChange({required this.zoneName, required this.error});

  /// Zone that was not changed.
  final String zoneName;

  /// Why it failed.
  final CloudKitItemError error;
}

/// Results of sending zone changes.
final class CloudKitSentDatabaseChanges extends CloudKitSyncEvent {
  /// Creates a CloudKitSentDatabaseChanges.
  const CloudKitSentDatabaseChanges({
    required this.savedZoneNames,
    required this.failedZoneSaves,
    required this.deletedZoneNames,
    required this.failedZoneDeletes,
  });

  /// Zones the server saved.
  final List<String> savedZoneNames;

  /// Zone saves that failed.
  final List<CloudKitFailedZoneChange> failedZoneSaves;

  /// Zones the server deleted.
  final List<String> deletedZoneNames;

  /// Zone deletes that failed.
  final List<CloudKitFailedZoneChange> failedZoneDeletes;
}

/// A record save that failed.
final class CloudKitFailedRecordSave {
  /// Creates a CloudKitFailedRecordSave.
  const CloudKitFailedRecordSave({required this.record, required this.error});

  /// Record that was not saved, as sent.
  final CloudKitRecord record;

  /// Why it failed.
  final CloudKitItemError error;
}

/// A record delete that failed.
final class CloudKitFailedRecordDelete {
  /// Creates a CloudKitFailedRecordDelete.
  const CloudKitFailedRecordDelete({required this.id, required this.error});

  /// Record that was not deleted.
  final CloudKitRecordId id;

  /// Why it failed.
  final CloudKitItemError error;
}

/// Results of sending one [CloudKitRecordZoneChangeBatch].
final class CloudKitSentRecordZoneChanges extends CloudKitSyncEvent {
  /// Creates a CloudKitSentRecordZoneChanges.
  const CloudKitSentRecordZoneChanges({
    required this.savedRecords,
    required this.failedRecordSaves,
    required this.deletedRecordIds,
    required this.failedRecordDeletes,
  });

  /// Records the server saved, with their new system fields.
  final List<CloudKitRecord> savedRecords;

  /// Record saves that failed, including ones the engine retries itself.
  final List<CloudKitFailedRecordSave> failedRecordSaves;

  /// Records the server deleted.
  final List<CloudKitRecordId> deletedRecordIds;

  /// Record deletes that failed.
  final List<CloudKitFailedRecordDelete> failedRecordDeletes;
}
