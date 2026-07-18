import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/src/native_payload.dart';

/// Typed metadata for a known iCloud item path.
class ICloudItemMetadata extends Equatable {
  /// Creates metadata from a normalized platform-channel payload.
  ICloudItemMetadata.fromMap(Map<dynamic, dynamic> map)
      : relativePath = nativeRequireString(map, 'relativePath'),
        isDirectory = nativeReadBool(map, 'isDirectory'),
        sizeInBytes = nativeNumToInt(
          nativeReadNullableNum(map, 'sizeInBytes'),
        ),
        creationDate = nativeSecondsNumberToDateTime(
          nativeReadNullableNum(map, 'creationDate'),
        ),
        contentChangeDate = nativeSecondsNumberToDateTime(
          nativeReadNullableNum(map, 'contentChangeDate'),
        ),
        downloadStatus = parseDownloadStatus(
          nativeReadNullableString(map, 'downloadStatus'),
        ),
        isDownloading = nativeReadBool(map, 'isDownloading'),
        isUploading = nativeReadBool(map, 'isUploading'),
        isUploaded = nativeReadBool(map, 'isUploaded'),
        hasUnresolvedConflicts = nativeReadBool(
          map,
          'hasUnresolvedConflicts',
        );

  /// File path relative to the iCloud container.
  final String relativePath;

  /// True when the item represents a directory.
  final bool isDirectory;

  /// Nullable when the platform does not provide it.
  final int? sizeInBytes;

  /// Nullable when the platform does not provide it.
  final DateTime? creationDate;

  /// Nullable when the platform does not provide it.
  final DateTime? contentChangeDate;

  /// Nullable when the platform does not provide it.
  final DownloadStatus? downloadStatus;

  /// Whether the system is actively downloading this item.
  final bool isDownloading;

  /// Whether the system is actively uploading this item.
  final bool isUploading;

  /// Whether this item has been uploaded to iCloud.
  final bool isUploaded;

  /// Whether this item has unresolved version conflicts.
  final bool hasUnresolvedConflicts;

  /// Whether the item has local content available.
  bool get isLocal =>
      downloadStatus == DownloadStatus.downloaded ||
      downloadStatus == DownloadStatus.current;

  @override
  List<Object?> get props => [
        relativePath,
        isDirectory,
        sizeInBytes,
        creationDate,
        contentChangeDate,
        downloadStatus,
        isDownloading,
        isUploading,
        isUploaded,
        hasUnresolvedConflicts,
      ];
}
