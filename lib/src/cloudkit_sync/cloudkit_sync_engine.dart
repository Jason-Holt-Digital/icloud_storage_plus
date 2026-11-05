import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_channel_codec.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_records.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_channel.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_events.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_exception.dart';

/// The iCloud account status of a container, mirroring `CKAccountStatus`.
enum CloudKitAccountStatus {
  /// The device is signed in to an iCloud account the app can use.
  available,

  /// The device is not signed in to iCloud.
  noAccount,

  /// Parental controls or device management deny access to the account.
  restricted,

  /// The account is signed in but cannot be used yet, for example until the
  /// user re-enters their password in Settings.
  temporarilyUnavailable,

  /// CloudKit could not determine the status. Also used for a status added
  /// in a later OS version.
  couldNotDetermine,
}

/// Receives a [CloudKitSyncEngine]'s events and supplies the records it
/// sends.
abstract interface class CloudKitSyncDelegate {
  /// Handles one event.
  ///
  /// The engine waits for the returned future before it delivers the next
  /// event. If it completes with an error, the engine stops so that the
  /// unhandled changes are delivered again after the next start; calls then
  /// throw [CloudKitSyncException.engineNotRunning].
  ///
  /// Do not call [CloudKitSyncEngine.fetchChanges] or
  /// [CloudKitSyncEngine.sendChanges] here. `CKSyncEngine` does not support
  /// starting a fetch or send while it delivers an event, and both complete
  /// only after their own events are handled.
  Future<void> handleEvent(CloudKitSyncEvent event);

  /// Builds the records for the next request the engine sends.
  ///
  /// [pendingChanges] lists up to 250 changes in the request's scope. Return
  /// records for some or all of them. Null or an empty batch ends the send,
  /// and so does an error; the changes stay pending. For a change whose
  /// record no longer exists locally, call
  /// [CloudKitSyncEngine.removePendingRecordZoneChanges] so the engine stops
  /// asking for it.
  ///
  /// If the native side cannot read the returned batch, the engine stops and
  /// later calls throw [CloudKitSyncException.engineNotRunning] with the
  /// reason.
  Future<CloudKitRecordZoneChangeBatch?> nextRecordZoneChangeBatch(
    List<CloudKitPendingRecordZoneChange> pendingChanges,
  );
}

/// Syncs the CloudKit private database of a container through Apple's
/// `CKSyncEngine`.
///
/// The engine schedules fetches and sends, retries, pages, and listens for
/// push notifications and account changes. The app decides what to send,
/// how to apply fetched records, and how to resolve conflicts.
///
/// Requires iOS 17 or macOS 14. The app runs one engine at a time; starting
/// an engine replaces the running one. Every method other than [start] acts
/// on that one running native engine, whatever this instance's
/// [containerId] is.
final class CloudKitSyncEngine {
  /// Creates a CloudKitSyncEngine for [containerId], such as
  /// `iCloud.com.example.app`.
  const CloudKitSyncEngine(this.containerId);

  /// CloudKit container identifier.
  final String containerId;

  /// Starts the engine from [stateSerialization], the latest
  /// [CloudKitStateUpdate] the app saved, or from scratch when it is null.
  ///
  /// The engine never fetches the zones in [excludedZoneNames]. Use this for
  /// a zone whose records the app transfers with `CloudKitAssetStore`.
  Future<void> start({
    required CloudKitSyncDelegate delegate,
    required String? stateSerialization,
    List<String> excludedZoneNames = const [],
  }) async {
    await CloudKitSyncChannel.start(delegate, {
      'containerId': containerId,
      'stateSerialization': stateSerialization,
      'excludedZoneNames': excludedZoneNames,
    });
  }

  /// The current iCloud account status of [containerId], from
  /// `CKContainer.accountStatus()`.
  ///
  /// Unlike the other methods, this asks CloudKit about this instance's
  /// container and works whether or not an engine is running. Listen for
  /// [CloudKitAccountChange] events to learn when the account changes.
  Future<CloudKitAccountStatus> accountStatus() async =>
      CloudKitAccountStatus.values.byName(
        (await CloudKitSyncChannel.invoke<String>(
          'accountStatus',
          {'containerId': containerId},
        ))!,
      );

  /// Stops the engine and cancels its operations.
  Future<void> stop() => CloudKitSyncChannel.invoke<void>('stop', {});

  /// Marks [changes] as pending, so a later send asks for their records.
  Future<void> addPendingRecordZoneChanges(
    List<CloudKitPendingRecordZoneChange> changes,
  ) =>
      _pendingRecordZoneChanges('addPendingRecordZoneChanges', changes);

  /// Removes [changes] that no longer need sending.
  Future<void> removePendingRecordZoneChanges(
    List<CloudKitPendingRecordZoneChange> changes,
  ) =>
      _pendingRecordZoneChanges('removePendingRecordZoneChanges', changes);

  Future<void> _pendingRecordZoneChanges(
    String method,
    List<CloudKitPendingRecordZoneChange> changes,
  ) =>
      CloudKitSyncChannel.invoke<void>(method, {
        'changes': changes
            .map(CloudKitChannelCodec.encodePendingRecordZoneChange)
            .toList(),
      });

  /// Marks zone saves or deletes as pending.
  Future<void> addPendingDatabaseChanges(
    List<CloudKitPendingDatabaseChange> changes,
  ) =>
      CloudKitSyncChannel.invoke<void>('addPendingDatabaseChanges', {
        'changes': changes
            .map(CloudKitChannelCodec.encodePendingDatabaseChange)
            .toList(),
      });

  /// Fetches changes now rather than waiting for the engine's schedule.
  /// Completes after the fetched events are handled.
  Future<void> fetchChanges() =>
      CloudKitSyncChannel.invoke<void>('fetchChanges', {});

  /// Sends pending changes now rather than waiting for the engine's schedule.
  /// Completes after the sent events are handled.
  Future<void> sendChanges() =>
      CloudKitSyncChannel.invoke<void>('sendChanges', {});
}
