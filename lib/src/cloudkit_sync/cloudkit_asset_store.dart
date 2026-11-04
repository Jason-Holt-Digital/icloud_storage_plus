import 'dart:io';

import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_channel_codec.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_records.dart';
import 'package:icloud_storage_plus/src/cloudkit_sync/cloudkit_sync_channel.dart';

/// Moves single assets to and from the CloudKit private database, outside
/// `CloudKitSyncEngine`.
///
/// Use it for large files that devices download only on demand, kept in a
/// zone the engine excludes. Requires iOS 17 or macOS 14.
final class CloudKitAssetStore {
  /// Creates a CloudKitAssetStore for [containerId].
  const CloudKitAssetStore(this.containerId);

  /// CloudKit container identifier.
  final String containerId;

  /// Whether the record [id] exists on the server. A missing zone counts as
  /// a missing record.
  Future<bool> recordExists(CloudKitRecordId id) async =>
      (await CloudKitSyncChannel.invoke<bool>('recordExists', {
        'containerId': containerId,
        'id': CloudKitChannelCodec.encodeRecordId(id),
      }))!;

  /// Saves [source] as the asset in [field] of the record [id], creating the
  /// zone when needed. The saved record holds only that asset and replaces
  /// any existing record [id].
  Future<void> uploadAsset({
    required CloudKitRecordId id,
    required String recordType,
    required String field,
    required File source,
  }) =>
      CloudKitSyncChannel.invoke<void>('uploadAsset', {
        'containerId': containerId,
        'id': CloudKitChannelCodec.encodeRecordId(id),
        'recordType': recordType,
        'field': field,
        'sourcePath': source.path,
      });

  /// Writes the asset in [field] of the record [id] to [destination],
  /// replacing any file there. [onProgress] receives the fraction of the
  /// download completed, from 0 to 1.
  Future<void> downloadAsset({
    required CloudKitRecordId id,
    required String field,
    required File destination,
    void Function(double fraction)? onProgress,
  }) async {
    final transferId = onProgress == null
        ? null
        : CloudKitSyncChannel.addProgressListener(onProgress);
    try {
      await CloudKitSyncChannel.invoke<void>('downloadAsset', {
        'containerId': containerId,
        'id': CloudKitChannelCodec.encodeRecordId(id),
        'field': field,
        'destinationPath': destination.path,
        'transferId': transferId,
      });
    } finally {
      if (transferId != null) {
        CloudKitSyncChannel.removeProgressListener(transferId);
      }
    }
  }
}
