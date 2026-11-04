import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_channel_codec.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_records.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_channel.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_events.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_exception.dart';

/// Receives a [CloudKitSyncEngine]'s events and supplies the records it
/// sends.
abstract interface class CloudKitSyncDelegate {
  /// Handles one event.
  ///
  /// The engine waits for the returned future before it delivers the next
  /// event. If it completes with an error, the engine stops so that the
  /// unhandled changes are delivered again after the next start; calls then
  /// throw [CloudKitSyncException.engineNotRunning].
  Future<void> handleEvent(CloudKitSyncEvent event);

  /// Builds the records for the next request the engine sends.
  ///
  /// [pendingChanges] lists up to 250 changes in the request's scope. Return
  /// records for some or all of them. Null or an empty batch ends the send,
  /// and so does an error; the changes stay pending.
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
/// an engine replaces the running one.
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
    CloudKitSyncChannel.attach(delegate);
    await CloudKitSyncChannel.invoke<void>('start', {
      'containerId': containerId,
      'stateSerialization': stateSerialization,
      'excludedZoneNames': excludedZoneNames,
    });
  }

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
