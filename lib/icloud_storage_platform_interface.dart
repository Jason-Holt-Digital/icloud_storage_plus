import 'dart:typed_data';

import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/container_item.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A function-type alias that receives a stream of values.
typedef StreamHandler<T> = void Function(Stream<T>);

/// Platform interface for iCloud storage implementations.
///
/// Structured request/response failures are surfaced as typed Dart exceptions by
/// the default method-channel implementation. Transfer-progress event streams
/// intentionally keep `PlatformException` payloads in `2.0.0`.
abstract class ICloudStoragePlatform extends PlatformInterface {
  /// Constructs a ICloudStoragePlatform.
  ICloudStoragePlatform() : super(token: _token);

  static final Object _token = Object();

  static ICloudStoragePlatform _instance = MethodChannelICloudStorage();

  /// The default instance of [ICloudStoragePlatform] to use.
  ///
  /// Defaults to [MethodChannelICloudStorage].
  static ICloudStoragePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ICloudStoragePlatform] when
  /// they register themselves.
  static set instance(ICloudStoragePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  Future<bool> icloudAvailable() async {
    throw UnimplementedError('icloudAvailable() has not been implemented.');
  }

  /// Gather all the files' meta data from iCloud container.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [onUpdate] is an optional paramater can be used as a call back every time
  /// when the list of files are updated. It won't be triggered when the
  /// function initially returns the list of files.
  ///
  /// When [onUpdate] is provided, the update stream stays active until the
  /// subscription is canceled. Callers should dispose listeners when done.
  ///
  /// The function returns a [GatherResult] containing parsed files and any
  /// invalid entries.
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    throw UnimplementedError('gather() has not been implemented.');
  }

  /// Watch remote-change/document-state events for one open document.
  ///
  /// The native implementation reuses the existing `ICloudDocument` presenter.
  /// It does not create a new presenter type. The stream stays active until
  /// the Dart subscription is canceled, which tears down native observation.
  Future<void> watchDocumentChanges({
    required String containerId,
    required String relativePath,
    required StreamHandler<ICloudDocumentChange> onChange,
  }) async {
    throw UnimplementedError(
      'watchDocumentChanges() has not been implemented.',
    );
  }

  /// Get the local path to the iCloud container root, if available.
  ///
  /// Returns the local container path when available.
  ///
  /// The default Darwin method-channel implementation may instead throw a typed
  /// `ICloudContainerAccessException` when the native layer returns a
  /// structured container-access failure. Older or unstructured platform
  /// failures may still surface as raw `PlatformException`s.
  /// Implementations may return `null` when the container is simply
  /// unavailable.
  Future<String?> getContainerPath({
    required String containerId,
  }) async {
    throw UnimplementedError('getContainerPath() has not been implemented.');
  }

  /// Copy a local file into the iCloud container (copy-in).
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [localPath] is the full path of the local file to copy.
  ///
  /// [cloudRelativePath] is the relative path inside the iCloud container.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// [onProgress] is an optional callback to track the progress of the upload.
  /// It receives a Stream&lt;ICloudTransferProgress&gt; that emits:
  /// - progress events with [ICloudTransferProgress.percent]
  /// - terminal `done` events
  /// - terminal `error` events (data events, not stream `onError`)
  ///
  /// Error events keep raw `PlatformException` payloads in
  /// [ICloudTransferProgress.exception].
  ///
  /// The returned future completes once the copy finishes; iCloud uploads the
  /// file automatically in the background. The local file is not kept in sync.
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    throw UnimplementedError('uploadFile() has not been implemented.');
  }

  /// Download a file from iCloud, then copy it out to a local path.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [cloudRelativePath] is the relative path of the file in the container.

  /// [localPath] is the full path where the local copy should be written.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// download. It receives a Stream&lt;ICloudTransferProgress&gt; that emits:
  /// - progress events with [ICloudTransferProgress.percent]
  /// - terminal `done` events
  /// - terminal `error` events (data events, not stream `onError`)
  ///
  /// Error events keep raw `PlatformException` payloads in
  /// [ICloudTransferProgress.exception].
  ///
  /// The returned future completes once the copy-out finishes (not when iCloud
  /// completes any background sync). This is not in-place access.
  Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    throw UnimplementedError('downloadFile() has not been implemented.');
  }

  /// Read a file in place from the iCloud container using coordinated access.
  ///
  /// [containerId] is the iCloud Container Id.
  /// [relativePath] is the relative path to the file inside the container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric.
  ///
  /// Returns the local file contents as a String when Apple has local bytes
  /// available for the document. Coordinated access uses UIDocument/NSDocument
  /// and loads the full contents into memory. Text is decoded as UTF-8; use
  /// [readInPlaceBytes] for binary formats.
  ///
  /// Throws on file-not-found and other failures.
  ///
  Future<String?> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('readInPlace() has not been implemented.');
  }

  /// Read a file in place as bytes from the iCloud container using coordinated
  /// access.
  ///
  /// [containerId] is the iCloud Container Id.
  /// [relativePath] is the relative path to the file inside the container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric.
  ///
  /// Returns the local file contents as bytes when Apple has local bytes
  /// available for the document. Coordinated access uses UIDocument/NSDocument
  /// and loads the full contents into memory. Use for small files.
  ///
  /// Throws on file-not-found and other failures.
  Future<Uint8List?> readInPlaceBytes({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('readInPlaceBytes() has not been implemented.');
  }

  /// Write a file in place inside the iCloud container using coordinated
  /// access.
  ///
  /// [containerId] is the iCloud Container Id.
  /// [relativePath] is the relative path to the file inside the container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric.
  /// Coordinated access writes the full contents as a single operation.
  /// Existing-file overwrites on Darwin use coordinated atomic replacement.
  /// Use for small text/JSON files.
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    throw UnimplementedError('writeInPlace() has not been implemented.');
  }

  /// Write a file in place as bytes inside the iCloud container using
  /// coordinated access.
  ///
  /// [containerId] is the iCloud Container Id.
  /// [relativePath] is the relative path to the file inside the container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric.
  /// Coordinated access writes the full contents as a single operation.
  /// Existing-file overwrites on Darwin use coordinated atomic replacement.
  /// Use for small files.
  Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    throw UnimplementedError('writeInPlaceBytes() has not been implemented.');
  }

  /// Delete a file or directory from the iCloud container.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud, such as file1
  /// or folder/file2.
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// Structured request/response failures may map to typed
  /// `ICloudOperationException` subclasses in the default method-channel
  /// implementation. Legacy unstructured failures may still surface as raw
  /// `PlatformException`s.
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('delete() has not been implemented.');
  }

  /// Move a file or directory within the iCloud container.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [fromRelativePath] is the relative path of the source item, such as
  /// folder1/file.
  ///
  /// [toRelativePath] is the relative path to move to, such as folder2/file.
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// Structured request/response failures may map to typed
  /// `ICloudOperationException` subclasses in the default method-channel
  /// implementation. Legacy unstructured failures may still surface as raw
  /// `PlatformException`s.
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    throw UnimplementedError('move() has not been implemented.');
  }

  /// Copy a file or directory within the iCloud container.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [fromRelativePath] is the relative path of the source item.
  ///
  /// [toRelativePath] is the relative path of the destination item.
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// The destination file will be overwritten if it exists.
  /// Parent directories will be created if needed.
  ///
  /// Structured request/response failures may map to typed
  /// `ICloudOperationException` subclasses in the default method-channel
  /// implementation. Legacy unstructured failures may still surface as raw
  /// `PlatformException`s.
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    throw UnimplementedError('copy() has not been implemented.');
  }

  /// Check if a file or directory exists without downloading
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// Returns true if the file or directory exists, false otherwise
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('documentExists() has not been implemented.');
  }

  /// Get file or directory metadata without downloading content.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// Returns normalized metadata about the item, or null if it doesn't exist.
  ///
  /// Implementations should keep this method compatible with the typed
  /// `ICloudItemMetadata` contract exposed by
  /// `ICloudStorage.getItemMetadata()`. The default implementation falls back
  /// to [getDocumentMetadata] for older platform implementations.
  Future<Map<String, dynamic>?> getItemMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    return getDocumentMetadata(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Get file or directory metadata without downloading content.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  ///
  /// Returns the raw metadata payload, or null if the item doesn't exist.
  /// The map should include `isDirectory` to distinguish directories.
  ///
  /// This compatibility method preserves the raw native payload and raw
  /// `PlatformException` behavior.
  Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('getDocumentMetadata() has not been implemented.');
  }

  /// List files in the iCloud container using `FileManager.contentsOfDirectory`
  /// with URL resource values for download/upload status.
  ///
  /// Unlike [gather], this method reads the POSIX filesystem directly and is
  /// **immediately consistent** after local mutations (rename, delete, copy).
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is an optional subdirectory to list (e.g. `Documents`).
  /// When omitted, lists the container root.
  ///
  /// Returns a list of [ContainerItem] entries with resolved filenames and
  /// download/upload status from URL resource values.
  Future<List<ContainerItem>> listContents({
    required String containerId,
    String? relativePath,
  }) async {
    throw UnimplementedError('listContents() has not been implemented.');
  }

  /// Enumerate unresolved `NSFileVersion` conflict versions for an item.
  ///
  /// Returns a list of [ICloudVersion] descriptors (identifier +
  /// modificationDate). An item with no unresolved versions returns an
  /// empty list — never an error. The plugin only exposes versions; the
  /// app owns conflict policy.
  Future<List<ICloudVersion>> enumerateUnresolvedConflictVersions({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError(
      'enumerateUnresolvedConflictVersions() has not been implemented.',
    );
  }

  /// Copy a specific losing conflict version's bytes to a caller-provided
  /// local destination, leaving the live iCloud file untouched.
  ///
  /// [versionIdentifier] is the opaque identifier from
  /// [enumerateUnresolvedConflictVersions]. [destinationPath] is the
  /// absolute local path to write the version's bytes to.
  Future<void> copyConflictVersion({
    required String containerId,
    required String relativePath,
    required String versionIdentifier,
    required String destinationPath,
  }) async {
    throw UnimplementedError(
      'copyConflictVersion() has not been implemented.',
    );
  }

  /// Mark unresolved conflict versions resolved. When [removeOtherVersions]
  /// is true, losing versions are removed after being marked resolved.
  /// Invoked only on explicit app request; idempotent and a no-op when
  /// nothing is unresolved.
  Future<void> markConflictResolved({
    required String containerId,
    required String relativePath,
    bool removeOtherVersions = false,
  }) async {
    throw UnimplementedError(
      'markConflictResolved() has not been implemented.',
    );
  }
}
