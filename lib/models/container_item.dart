import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/src/native_payload.dart';

/// A file or directory entry from the iCloud ubiquity container, enumerated
/// via `FileManager.contentsOfDirectory` with URL resource values.
///
/// Unlike [ICloudFile] (populated from `NSMetadataQuery`), this model is
/// **immediately consistent** after local filesystem mutations (rename, delete,
/// copy). It provides download/upload status via URL resource values rather
/// than the Spotlight metadata index.
///
/// Use `ICloudStorage.listContents` to obtain these items.
///
/// ## When to use this vs [ICloudFile]
///
/// - **After your own mutations** (rename, delete, save): use `listContents`
///   for immediate consistency.
/// - **For container metadata refresh hints**: use `gather()`, whose update
///   timing, coalescing, and origin are controlled by Apple.
/// - **Initial discovery on a new device**: `gather()` discovers document
///   promises (files not yet placeholder'd locally); `listContents` only sees
///   files with a local representation.
class ContainerItem extends Equatable {
  /// Creates an item from the normalized platform-channel payload.
  ContainerItem.fromMap(Map<dynamic, dynamic> map)
      : relativePath = nativeRequireString(map, 'relativePath'),
        downloadStatus = parseDownloadStatus(
          nativeReadNullableString(map, 'downloadStatus'),
        ),
        isDownloading = nativeReadBool(map, 'isDownloading'),
        isUploaded = nativeReadBool(map, 'isUploaded'),
        isUploading = nativeReadBool(map, 'isUploading'),
        hasUnresolvedConflicts = nativeReadBool(
          map,
          'hasUnresolvedConflicts',
        ),
        isDirectory = nativeReadBool(map, 'isDirectory');

  /// File path relative to the iCloud container root, regardless of which
  /// subdirectory was passed as `relativePath` to `listContents`.
  final String relativePath;

  /// Download status from `URLUbiquitousItemDownloadingStatus`.
  ///
  /// Possible values are [DownloadStatus.notDownloaded],
  /// [DownloadStatus.downloaded], or [DownloadStatus.current].
  /// Null when the platform does not provide it.
  final DownloadStatus? downloadStatus;

  /// Whether the system is actively downloading this item.
  final bool isDownloading;

  /// Whether this item has been uploaded to iCloud.
  final bool isUploaded;

  /// Whether the system is actively uploading this item.
  final bool isUploading;

  /// Whether this item has unresolved version conflicts.
  final bool hasUnresolvedConflicts;

  /// Whether this entry represents a directory.
  final bool isDirectory;

  /// Whether the item has local content available.
  bool get isDownloaded =>
      downloadStatus == DownloadStatus.downloaded ||
      downloadStatus == DownloadStatus.current;

  @override
  List<Object?> get props => [
        relativePath,
        downloadStatus,
        isDownloading,
        isUploaded,
        isUploading,
        hasUnresolvedConflicts,
        isDirectory,
      ];
}
