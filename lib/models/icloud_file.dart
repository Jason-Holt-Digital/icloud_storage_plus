import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/src/native_payload.dart';

export 'download_status.dart' show DownloadStatus;

/// Metadata for an iCloud file or directory.
///
/// Populated from `NSMetadataQuery`, which is eventually consistent — the
/// Spotlight index may lag behind local filesystem mutations. For an
/// immediately-consistent listing after your own mutations (rename, delete,
/// copy), use `ContainerItem` via `ICloudStorage.listContents` instead.
class ICloudFile extends Equatable {
  /// Creates an object from the normalized platform-channel payload.
  ICloudFile.fromMap(Map<dynamic, dynamic> map)
      : relativePath = nativeRequireString(map, 'relativePath'),
        isDirectory = nativeReadBool(map, 'isDirectory'),
        sizeInBytes = nativeSecondsNumberToInt(
          nativeReadNullableNum(map, 'sizeInBytes'),
        ),
        creationDate = nativeSecondsNumberToDateTime(
          nativeReadNullableNum(map, 'creationDate'),
        ),
        contentChangeDate = nativeSecondsNumberToDateTime(
          nativeReadNullableNum(map, 'contentChangeDate'),
        ),
        isDownloading = nativeReadBool(map, 'isDownloading'),
        downloadStatus = parseDownloadStatus(
          nativeReadNullableString(map, 'downloadStatus'),
        ),
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

  /// Corresponding to NSMetadataItemFSSizeKey.
  /// Nullable when the platform does not provide it.
  final int? sizeInBytes;

  /// Corresponding to NSMetadataItemFSCreationDateKey.
  /// Nullable when the platform does not provide it.
  final DateTime? creationDate;

  /// Corresponding to NSMetadataItemFSContentChangeDateKey.
  /// Nullable when the platform does not provide it.
  final DateTime? contentChangeDate;

  /// Corresponding to NSMetadataUbiquitousItemIsDownloadingKey.
  final bool isDownloading;

  /// Corresponding to NSMetadataUbiquitousItemDownloadingStatusKey.
  /// Nullable when the platform does not provide it.
  final DownloadStatus? downloadStatus;

  /// Corresponding to NSMetadataUbiquitousItemIsUploadingKey.
  final bool isUploading;

  /// Corresponding to NSMetadataUbiquitousItemIsUploadedKey.
  final bool isUploaded;

  /// Corresponding to NSMetadataUbiquitousItemHasUnresolvedConflictsKey.
  final bool hasUnresolvedConflicts;

  @override
  List<Object?> get props => [
        relativePath,
        isDirectory,
        sizeInBytes,
        creationDate,
        contentChangeDate,
        isDownloading,
        downloadStatus,
        isUploading,
        isUploaded,
        hasUnresolvedConflicts,
      ];
}
