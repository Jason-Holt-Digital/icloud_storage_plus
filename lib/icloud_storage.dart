import 'dart:typed_data';

import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/container_item.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_document_change.dart';
import 'package:icloud_storage_plus/models/icloud_item_metadata.dart';
import 'package:icloud_storage_plus/models/icloud_version.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';

export 'models/container_item.dart';
export 'models/download_status.dart';
export 'models/exceptions.dart';
export 'models/gather_result.dart';
export 'models/icloud_document_change.dart';
export 'models/icloud_file.dart';
export 'models/icloud_item_metadata.dart';
export 'models/icloud_version.dart';
export 'models/transfer_progress.dart';

/// The main class for the plugin. Provides streaming, file-path-only access
/// to files in an iCloud Drive ubiquity container using Apple's document APIs.
///
/// iCloud Drive sync, freshness, materialization, and conflict handling are
/// owned by Apple. This plugin performs local file operations against the
/// ubiquity container.
///
/// ## Transfer API (path-only)
/// For large files, prefer [uploadFile] and [downloadFile]. These methods pass
/// only file paths over the platform channel (no file bytes), which avoids
/// memory spikes and IPC limits.
///
/// ## In-place content API (small files)
/// For small text/binary files you can read/write in place using
/// [readInPlace]/[readInPlaceBytes] and [writeInPlace]/[writeInPlaceBytes].
/// These methods transfer the full contents over the platform channel and load
/// the whole file in memory.
///
/// ## Document IO Tier Rationale
/// The plugin uses the URL-tier document APIs (`UIDocument`/`NSDocument`) so
/// reads and writes are coordinated with iCloud and can stream efficiently
/// for large files.
///
/// ## Files app visibility
/// Use the literal `Documents/` path prefix for files that should be visible
/// in the Files app. Other container-relative paths remain app-managed iCloud
/// Drive content and may still sync.
///
/// ## Error Contract
/// Native and channel failures surface as typed [ICloudOperationException]
/// values. Dart-side argument validation throws [InvalidArgumentException].
/// Transfer failures use the stream error channel with the same typed error
/// hierarchy.
class ICloudStorage {
  /// Check if iCloud is available and user is logged in.
  static Future<bool> icloudAvailable() async {
    return ICloudStoragePlatform.instance.icloudAvailable();
  }

  /// Get all file metadata from the iCloud container.
  ///
  /// When [onUpdate] is provided, the update stream stays active until the
  /// subscription is canceled. Callers should dispose listeners when done.
  static Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    return ICloudStoragePlatform.instance.gather(
      containerId: containerId,
      onUpdate: onUpdate,
    );
  }

  /// Watch document invalidation and state events for an existing document.
  ///
  /// Each call provides one single-subscription stream. Cancel that Dart
  /// subscription when finished; cancellation tears down native observation
  /// even when presenter registration is still starting.
  ///
  /// Treat events as invalidation hints and reread the document through a
  /// coordinated API. Foundation may coalesce callbacks, and iCloud Drive owns
  /// cross-device delivery latency. A `conflict` event requires app-owned
  /// conflict policy; the plugin never resolves versions automatically.
  ///
  /// On iOS, a single native state callback can emit more than one typed event
  /// when multiple document-state flags are active. Debounce or coalesce the
  /// stream if your caller requires one event per native transition.
  static Future<void> watchDocumentChanges({
    required String containerId,
    required String relativePath,
    required StreamHandler<ICloudDocumentChange> onChange,
  }) async {
    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.watchDocumentChanges(
      containerId: containerId,
      relativePath: relativePath,
      onChange: onChange,
    );
  }

  /// Get the absolute path to the iCloud container.
  static Future<String?> getContainerPath({
    required String containerId,
  }) async {
    return ICloudStoragePlatform.instance.getContainerPath(
      containerId: containerId,
    );
  }

  /// Copy a local file into the iCloud container (copy-in).
  ///
  /// [localPath] is the absolute path to a local file to copy.
  /// [relativePath] is the path within the iCloud container.
  /// Use 'Documents/' prefix for Files app visibility.
  ///
  /// This does not keep the local file in sync. After the copy completes,
  /// iCloud uploads the container file automatically in the background.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// If [onProgress] is provided, attach a listener immediately inside the
  /// callback. Progress streams are listener-driven (not buffered), so delaying
  /// `listen()` may miss early progress events. Failures use the stream error
  /// channel with typed [ICloudOperationException] values.
  static Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    // Transfers are file-centric (UIDocument/NSDocument). A trailing slash
    // indicates a directory path and would be ambiguous or fail natively.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException(
        'invalid relativePath: $relativePath',
      );
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: $relativePath',
      );
    }

    await ICloudStoragePlatform.instance.uploadFile(
      containerId: containerId,
      localPath: localPath,
      relativePath: relativePath,
      onProgress: onProgress,
    );
  }

  /// Download a file from iCloud, then copy it out to a local path.
  ///
  /// [relativePath] is the path within the iCloud container.
  /// [localPath] is the absolute destination path to write a local copy.
  ///
  /// This is not in-place access. Use [readInPlace] for coordinated reads
  /// inside the container.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// If [onProgress] is provided, attach a listener immediately inside the
  /// callback. Progress streams are listener-driven (not buffered), so delaying
  /// `listen()` may miss early progress events. Failures use the stream error
  /// channel with typed [ICloudOperationException] values.
  static Future<void> downloadFile({
    required String containerId,
    required String relativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    // Transfers are file-centric (UIDocument/NSDocument). A trailing slash
    // indicates a directory path and would be ambiguous or fail natively.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException(
        'invalid relativePath: $relativePath',
      );
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: $relativePath',
      );
    }

    await ICloudStoragePlatform.instance.downloadFile(
      containerId: containerId,
      relativePath: relativePath,
      localPath: localPath,
      onProgress: onProgress,
    );
  }

  /// Read a file in place from the iCloud container using coordinated access.
  ///
  /// [relativePath] is the path within the iCloud container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access loads the full contents into memory. Text is decoded
  /// as UTF-8; use [readInPlaceBytes] for binary formats.
  ///
  /// Returns the local file contents as a String when Apple has local bytes
  /// available for the document.
  ///
  /// Throws on file-not-found and other failures.
  static Future<String> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    // Reads are file-centric; reject directory paths.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.readInPlace(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Read a file in place as bytes from the iCloud container using coordinated
  /// access.
  ///
  /// [relativePath] is the path within the iCloud container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access loads the full contents into memory. Use for small
  /// files.
  ///
  /// Returns the local file contents as bytes when Apple has local bytes
  /// available for the document.
  ///
  /// Throws on file-not-found and other failures.
  static Future<Uint8List> readInPlaceBytes({
    required String containerId,
    required String relativePath,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.readInPlaceBytes(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Write a file in place inside the iCloud container using coordinated
  /// access.
  ///
  /// [relativePath] is the path within the iCloud container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric.
  ///
  /// Existing-file overwrites on Darwin stage the complete new content and
  /// install it with `FileManager.replaceItemAt` under coordinated
  /// ordinary-write access. Conflict versions are not automatically resolved
  /// or deleted. Use for small text/JSON files.
  static Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    // Writes are file-centric; reject directory paths.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.writeInPlace(
      containerId: containerId,
      relativePath: relativePath,
      contents: contents,
    );
  }

  /// Write a file in place as bytes inside the iCloud container using
  /// coordinated access.
  ///
  /// [relativePath] is the path within the iCloud container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric.
  ///
  /// Existing-file overwrites on Darwin stage the complete new content and
  /// install it with `FileManager.replaceItemAt` under coordinated
  /// ordinary-write access. Conflict versions are not automatically resolved
  /// or deleted. Use for small files.
  static Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.writeInPlaceBytes(
      containerId: containerId,
      relativePath: relativePath,
      contents: contents,
    );
  }

  /// Delete a file from the iCloud container.
  ///
  /// Trailing slashes are allowed here because directory paths can include
  /// them in metadata and FileManager operations handle directories.
  static Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.delete(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Move a file within the iCloud container.
  ///
  /// Trailing slashes are allowed for directory paths (from metadata), but both
  /// paths must resolve to valid filesystem entries.
  static Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    if (!_validateRelativePath(fromRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (from) $fromRelativePath',
      );
    }

    if (!_validateRelativePath(toRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (to) $toRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.move(
      containerId: containerId,
      fromRelativePath: fromRelativePath,
      toRelativePath: toRelativePath,
    );
  }

  /// Rename a file in the iCloud container.
  ///
  /// Trailing slashes are allowed in [relativePath] for directory entries and
  /// are normalized before deriving the new path.
  static Future<void> rename({
    required String containerId,
    required String relativePath,
    required String newName,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateFileName(newName)) {
      throw InvalidArgumentException('invalid newName: $newName');
    }

    final normalizedPath = relativePath.endsWith('/')
        ? relativePath.substring(0, relativePath.length - 1)
        : relativePath;

    final lastSlash = normalizedPath.lastIndexOf('/');
    final directory =
        lastSlash == -1 ? '' : normalizedPath.substring(0, lastSlash + 1);

    await move(
      containerId: containerId,
      fromRelativePath: relativePath,
      toRelativePath: '$directory$newName',
    );
  }

  /// Copy a file within the iCloud container.
  ///
  /// Trailing slashes are allowed for directory paths (from metadata), but both
  /// paths must resolve to valid filesystem entries.
  static Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    if (!_validateRelativePath(fromRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (from) $fromRelativePath',
      );
    }

    if (!_validateRelativePath(toRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (to) $toRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.copy(
      containerId: containerId,
      fromRelativePath: fromRelativePath,
      toRelativePath: toRelativePath,
    );
  }

  /// Check if a file or directory exists without downloading.
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  static Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.documentExists(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Get typed metadata for a file or directory without downloading content.
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
  /// Native and channel failures map to typed [ICloudOperationException]
  /// subclasses.
  static Future<ICloudItemMetadata?> getItemMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.getItemMetadata(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// List files in the iCloud container using the filesystem directly.
  ///
  /// Unlike [gather], which queries the Spotlight metadata index (eventually
  /// consistent), this method uses `FileManager.contentsOfDirectory` and is
  /// **immediately consistent** after local mutations (rename, delete, copy).
  ///
  /// Each returned [ContainerItem] includes download/upload status from URL
  /// resource values — no `NSMetadataQuery` required.
  ///
  /// [relativePath] scopes the listing to a subdirectory (e.g. `Documents`).
  /// When omitted, lists the container root.
  ///
  /// ## When to use this vs [gather]
  ///
  /// - **After your own mutations**: use `listContents` for immediate truth.
  /// - **Container metadata updates**: use `gather` with `onUpdate` as a
  ///   best-effort refresh signal. Timing, coalescing, and origin are not
  ///   guaranteed.
  /// - **Initial device sync**: `gather` discovers document promises (files
  ///   not yet placeholder'd locally); `listContents` only sees files with
  ///   a local filesystem representation.
  static Future<List<ContainerItem>> listContents({
    required String containerId,
    String? relativePath,
  }) async {
    if (relativePath != null && !_validateRelativePath(relativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: $relativePath',
      );
    }

    return ICloudStoragePlatform.instance.listContents(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Enumerate unresolved `NSFileVersion` conflict versions for an item.
  ///
  /// [relativePath] is the path within the iCloud container.
  ///
  /// Returns a list of [ICloudVersion] descriptors (identifier +
  /// modificationDate). An item with no unresolved versions returns an
  /// empty list — never an error.
  ///
  /// The plugin only EXPOSES versions; it never auto-resolves or deletes
  /// losing versions. The app owns conflict policy: enumerate, copy out
  /// losing versions to badged backups, then mark resolved.
  static Future<List<ICloudVersion>> enumerateUnresolvedConflictVersions({
    required String containerId,
    required String relativePath,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    final versions = await ICloudStoragePlatform.instance
        .enumerateUnresolvedConflictVersions(
      containerId: containerId,
      relativePath: relativePath,
    );

    return versions;
  }

  /// Copy a specific losing conflict version's bytes to a caller-provided
  /// local destination, leaving the live iCloud file untouched.
  ///
  /// [relativePath] is the path of the conflicted item within the iCloud
  /// container. [versionIdentifier] is the opaque identifier from
  /// [enumerateUnresolvedConflictVersions]. [destinationPath] is the
  /// absolute local path to write the version's bytes to (the app owns
  /// this path, typically a badged backup under `Documents/backups/`).
  ///
  /// On failure a typed exception is thrown and no partial file is left
  /// at [destinationPath].
  static Future<void> copyConflictVersion({
    required String containerId,
    required String relativePath,
    required String versionIdentifier,
    required String destinationPath,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (versionIdentifier.trim().isEmpty) {
      throw InvalidArgumentException(
        'invalid versionIdentifier: $versionIdentifier',
      );
    }

    if (destinationPath.trim().isEmpty) {
      throw InvalidArgumentException(
        'invalid destinationPath: $destinationPath',
      );
    }

    await ICloudStoragePlatform.instance.copyConflictVersion(
      containerId: containerId,
      relativePath: relativePath,
      versionIdentifier: versionIdentifier,
      destinationPath: destinationPath,
    );
  }

  /// Mark unresolved conflict versions resolved.
  ///
  /// [relativePath] is the path of the conflicted item within the iCloud
  /// container. When [removeOtherVersions] is true, the other (losing)
  /// versions are removed after being marked resolved; when false (the
  /// default) only `isResolved` is set.
  ///
  /// This is invoked ONLY on explicit app request, after the app has
  /// confirmed all losing versions are backed up. It is idempotent and a
  /// no-op when nothing is unresolved.
  static Future<void> markConflictResolved({
    required String containerId,
    required String relativePath,
    bool removeOtherVersions = false,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.markConflictResolved(
      containerId: containerId,
      relativePath: relativePath,
      removeOtherVersions: removeOtherVersions,
    );
  }

  /// Validate relative path segments.
  static bool _validateRelativePath(String path) {
    final fileOrDirNames = path.split('/');
    if (fileOrDirNames.isEmpty) return false;

    if (fileOrDirNames.length > 1 && fileOrDirNames.last.isEmpty) {
      fileOrDirNames.removeLast();
    }

    return fileOrDirNames.every(_validateFileName);
  }

  static final RegExp _fileNameRegex = RegExp(r'([:/]+)|(^[.].*$)');

  /// Validate a single file or directory name.
  static bool _validateFileName(String name) =>
      !(name.isEmpty || name.length > 255 || _fileNameRegex.hasMatch(name));
}
