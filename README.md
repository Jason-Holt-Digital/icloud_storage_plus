# iCloud Storage Plus

[![Pub Version](https://img.shields.io/pub/v/icloud_storage_plus)](https://pub.dev/packages/icloud_storage_plus)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/kingdomseed/icloud_storage_plus)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![shorebird ci](https://api.shorebird.dev/api/v1/github/kingdomseed/icloud_storage_plus/badge.svg)](https://console.shorebird.dev/ci)
[![Publisher](https://img.shields.io/badge/publisher-jasonholtdigital.com-2b7cff)](https://pub.dev/publishers/jasonholtdigital.com)

Flutter plugin for local file access inside an iCloud Drive ubiquity container
on iOS and macOS, with coordinated file operations and optional Files app
visibility.

Hosted reference docs are available on DeepWiki:
https://deepwiki.com/kingdomseed/icloud_storage_plus

This package operates inside your app's local iCloud ubiquity container. Apple
owns iCloud Drive sync, materialization, freshness, and document conflict
behavior; this plugin performs local file operations against the container path.

## Platform support

| Platform | Minimum version |
|----------|-----------------|
| iOS | 13.0 |
| macOS | 10.15 |

## Installation

```bash
flutter pub add icloud_storage_plus
```

### Swift Package Manager (optional)

This plugin supports Flutter’s Swift Package Manager integration for iOS/macOS
projects (requires Flutter `>= 3.24`). To enable SwiftPM in your app:

```bash
flutter config --enable-swift-package-manager
```

## Before you start (Xcode / entitlements)

1. Create an iCloud Container ID (example: `iCloud.com.yourapp.container`)
2. Enable iCloud for your App ID and assign that container
3. In Xcode → your target → Signing & Capabilities:
   - Add **iCloud**
   - Enable **iCloud Documents**
   - Select your container

### Files app integration (optional)

To make items visible in the Files app under “iCloud Drive”, you typically need
to declare your container under `NSUbiquitousContainers` in your `Info.plist`.

Files are only visible in Files/iCloud Drive when they live under the
`Documents/` prefix.

```dart
// Visible in Files app
cloudRelativePath: 'Documents/notes.txt'

// Not visible in Files app (still syncs)
cloudRelativePath: 'cache/notes.txt'
```

Note: your app’s folder won’t appear in Files/iCloud Drive until at least one
file exists under `Documents/`.

## Choosing the right API

There are four “tiers” of API in this plugin:

1. **Path-only transfers** for large files (no bytes returned to Dart)
   - `uploadFile` (local → iCloud)
   - `downloadFile` (iCloud → local)
2. **In-place content** for small files (bytes/strings cross the platform
   channel; loads full contents in memory)
    - `readInPlace`, `readInPlaceBytes`
    - `writeInPlace`, `writeInPlaceBytes`
    - On iOS and macOS, existing-file writes use coordinated atomic replacement so the
      destination path stays stable during overwrite.
    - On iOS and macOS, file-write overwrite paths use coordinated local
      replacement. iCloud Drive sync and document conflict behavior remain
      Apple's responsibility.
    - Those file-write overwrite paths still reject an existing directory
      destination instead of replacing it.
3. **File management and queries**
   - `delete`, `move`, `copy`, `rename`
   - `documentExists`, `getItemMetadata`, `getDocumentMetadata`
   - On iOS and macOS, copying onto an existing destination also uses coordinated
     atomic replacement rather than remove-then-copy behavior.
   - Existing-destination `copy()` replacement is file-only on iOS and macOS:
     existing directories are rejected instead of replaced.
   - `copy()` can copy files or directories to new destinations. If you need to
     replace an existing directory tree, manage that directory explicitly rather
     than relying on overwrite replacement.
4. **Container listing** (two complementary approaches)
   - `gather` — NSMetadataQuery-based; sees remote files and document promises;
     provides real-time change notifications and download progress; eventually
     consistent after local mutations
   - `listContents` — FileManager-based; immediately consistent after local
     mutations; returns download/upload status via URL resource values; only sees
     files with a local representation (including iCloud placeholders)

On iOS, when Flutter provides a background platform-channel task queue, native
filesystem work for the in-place APIs runs there so iCloud container lookup and
`UIDocument` preflight do not block the app's main thread. If that queue is not
available, Flutter falls back to its default platform-channel dispatch model.
macOS keeps the existing dispatch model.

## Migration notes for 2.2.0

- `readInPlace` and `readInPlaceBytes` no longer accept `idleTimeouts` or
  `retryBackoff`. Remove those named arguments from callers.
- `ICloudTimeoutException`, `ICloudItemNotDownloadedException`,
  `ICloudDownloadInProgressException`, `PlatformExceptionCode.timeout`,
  `PlatformExceptionCode.itemNotDownloaded`, and
  `PlatformExceptionCode.downloadInProgress` were removed. Normal iCloud Drive
  lifecycle state is no longer a plugin-owned error surface.
- On iOS and macOS, `copy()` over an existing destination no longer reports
  plugin-owned readiness failures for non-current, not-downloaded, downloading,
  or conflicted iCloud metadata. It rejects existing directory destinations,
  then lets Foundation perform the local replacement and report any actual
  operation failure.

## Quick start

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';

const containerId = 'iCloud.com.yourapp.container';
const notesPath = 'Documents/notes.txt';

Future<void> example() async {
  final available = await ICloudStorage.icloudAvailable();
  if (!available) {
    // Not signed into iCloud, iCloud Drive disabled, etc.
    return;
  }

  // 1) Write a text file *in place* (recommended for JSON/text).
  await ICloudStorage.writeInPlace(
    containerId: containerId,
    relativePath: notesPath,
    contents: 'Hello from iCloud',
  );

  final contents = await ICloudStorage.readInPlace(
    containerId: containerId,
    relativePath: notesPath,
  );

  // 2) Copy-out to local storage (useful for large files / sharing / etc).
  final localCopy = '${Directory.systemTemp.path}/notes.txt';
  await ICloudStorage.downloadFile(
    containerId: containerId,
    cloudRelativePath: notesPath,
    localPath: localCopy,
  );

  // 3) Typed metadata / listing.
  final metadata = await ICloudStorage.getItemMetadata(
    containerId: containerId,
    relativePath: notesPath,
  );
  if (metadata != null && !metadata.isDirectory) {
    final size = metadata.sizeInBytes;
  }

  try {
    // Example: path validation happens in Dart before calling native.
    await ICloudStorage.readInPlace(
      containerId: containerId,
      relativePath: 'Documents/.hidden.txt',
    );
  } on InvalidArgumentException catch (e) {
    // Invalid path segment (starts with '.', contains ':', etc.)
    // This is a Dart-side exception (not a PlatformException).
    throw Exception(e);
  } on ICloudOperationException catch (e) {
    // Structured request/response failures are typed.
    throw Exception(e);
  } on PlatformException catch (e) {
    // Legacy unstructured native failures stay raw PlatformException values.
    throw Exception(e);
  }
}
```

## Transfers with progress

Progress is delivered via an `EventChannel` as *data events* of type
`ICloudTransferProgress`. Failures are **not** delivered via stream `onError`.
Transfer-progress failures still carry raw `PlatformException` objects in
`event.exception` even though structured request/response APIs map to typed
Dart exceptions.

Important: the progress stream is listener-driven; start listening immediately
in the `onProgress` callback or you may miss early events.

```dart
await ICloudStorage.uploadFile(
  containerId: containerId,
  localPath: '/absolute/path/to/local/file.pdf',
  cloudRelativePath: 'Documents/file.pdf',
  onProgress: (stream) {
    stream.listen((event) {
      if (event.isProgress) {
        // 0.0 - 100.0
        final percent = event.percent!;
      } else if (event.isError) {
        final exception = event.exception!;
      }
    });
  },
);
```

## Paths: `cloudRelativePath` vs `relativePath`

This plugin always works in terms of paths *inside* the iCloud container:

- `cloudRelativePath`: used by `uploadFile` / `downloadFile`
- `relativePath`: used by the rest of the API

These are the same kind of value; the naming difference exists for historical
reasons.

### Trailing slashes

Directory paths can show up with trailing slashes in metadata, so the
directory-oriented methods accept them:

- `delete`, `move`, `copy`, `rename`, `documentExists`, `getItemMetadata`,
  `getDocumentMetadata`

File-centric operations reject trailing slashes (they require a file path):

- `uploadFile`, `downloadFile`
- `readInPlace`, `readInPlaceBytes`, `writeInPlace`, `writeInPlaceBytes`

On iOS and macOS, file-centric overwrite operations reject an existing directory
destination instead of replacing it. Existing-destination `copy()` replacement
does the same; `copy()` can still copy a directory when the destination does not
already exist.

### Path validation

Many methods validate path segments in Dart and throw `InvalidArgumentException`
for invalid values (empty segments, segments starting with `.`, segments that
contain `:` or `/`, etc).

## Listing / watching with `gather`

`gather()` returns a `GatherResult`:

- `files`: parsed metadata entries
- `invalidEntries`: entries that could not be parsed into `ICloudFile`

When `onUpdate` is provided, the update stream stays active until the
subscription is canceled. (Dispose listeners when done.)

```dart
final initial = await ICloudStorage.gather(
  containerId: containerId,
  onUpdate: (stream) {
    stream.listen((update) {
      // Full file list on every update.
      final files = update.files;
    });
  },
);
```

## Immediate listing with `listContents`

`listContents()` returns `List<ContainerItem>` — an immediately-consistent
snapshot of the container (or a subdirectory) using `FileManager` rather than
`NSMetadataQuery`.

```dart
final items = await ICloudStorage.listContents(
  containerId: containerId,
  relativePath: 'Documents/', // optional; defaults to container root
);

for (final item in items) {
  print('${item.relativePath} — ${item.downloadStatus}');
  if (item.isDirectory) print('  (directory)');
  if (item.hasUnresolvedConflicts) print('  ⚠ conflicts');
}
```

### `gather` vs `listContents`

| Capability | `gather` | `listContents` |
|---|---|---|
| Consistency after mutations | Eventually consistent (Spotlight index lag) | **Immediately consistent** |
| Sees remote-only files | Yes (document promises) | No |
| Real-time change notifications | Yes (via `onUpdate` stream) | No (one-shot) |
| Download/upload progress % | Yes | No |
| Download/upload status | Yes | Yes |
| Conflict detection | Yes | Yes |
| Hidden files (`.DS_Store`, etc.) | Excluded by Spotlight | Filtered by resolved-name prefix |
| Underlying mechanism | `NSMetadataQuery` (Spotlight) | `FileManager` + URL resource values |

**When to use which:**

- **After your own mutations** (rename, delete, copy, write): use `listContents`
  for an immediate, accurate listing.
- **Initial sync on a new device**: use `gather` to discover document promises
  (remote files not yet represented locally).
- **Live monitoring**: use `gather` with `onUpdate` for real-time change
  notifications from other devices.

## iCloud placeholder files

iCloud uses placeholder files to represent items that exist in iCloud but have
not been fully downloaded to the local device. There are two eras:

- **iOS and pre-Sonoma macOS**: stub files named `.originalName.icloud` (~192
  bytes) that stand in for the real file.
- **macOS Sonoma+**: APFS dataless files that keep the real filename and logical
  size; the actual content is fetched on demand.

Both `gather` and `listContents` handle this transparently — they resolve
placeholder names and report download status so you don't need to parse
`.icloud` filenames yourself.

`listContents` also filters out system hidden files (`.DS_Store`, `.Trash`,
`.DocumentRevisions-V100`, etc.) by skipping any entry whose resolved name
starts with `.`. Files whose real name starts with `.` will not appear in
`listContents` results. `gather` excludes most of these naturally via
Spotlight's indexing scope.

To check if a file has local content available:

```dart
// With ContainerItem (from listContents)
if (item.isDownloaded) {
  // File has local content (downloadStatus is .downloaded or .current)
}

// With ICloudFile (from gather)
if (file.downloadStatus == DownloadStatus.current) {
  // Fully up-to-date local copy
}
```

## Metadata models

### `ICloudItemMetadata` (from `getItemMetadata`)

Populated from the known-path metadata request API. This is the typed metadata
model for request/response use.

```dart
class ICloudItemMetadata {
  final String relativePath;
  final bool isDirectory;

  final int? sizeInBytes;
  final DateTime? creationDate;
  final DateTime? contentChangeDate;

  final bool isDownloading;
  final DownloadStatus? downloadStatus;
  final bool isUploading;
  final bool isUploaded;
  final bool hasUnresolvedConflicts;

  /// Whether the item has local content available.
  // bool get isLocal => <computed>;
}
```

### `ICloudFile` (from `gather`)

Populated from `NSMetadataQuery`. Eventually consistent — the Spotlight index
may lag behind local filesystem mutations.

```dart
class ICloudFile {
  final String relativePath;
  final bool isDirectory;

  final int? sizeInBytes;
  final DateTime? creationDate;
  final DateTime? contentChangeDate;

  final bool isDownloading;
  final DownloadStatus? downloadStatus;
  final bool isUploading;
  final bool isUploaded;
  final bool hasUnresolvedConflicts;
}
```

### `ContainerItem` (from `listContents`)

Populated from `FileManager.contentsOfDirectory` with URL resource values.
Immediately consistent after local mutations.

```dart
class ContainerItem {
  final String relativePath;
  final bool isDirectory;

  final DownloadStatus? downloadStatus;
  final bool isDownloading;
  final bool isUploaded;
  final bool isUploading;
  final bool hasUnresolvedConflicts;

  /// Whether the item has local content available.
  // bool get isDownloaded => <computed>;
}
```

`ContainerItem` does not include `sizeInBytes`, `creationDate`, or
`contentChangeDate` — these require `NSMetadataQuery` or additional URL resource
key lookups that are not part of the current implementation.

## Error handling

### Dart-side validation (`InvalidArgumentException`)

Thrown when you pass an invalid path/name to the Dart API (before calling
native code).

### Structured request/response failures (`ICloudOperationException`)

Structured native failures from request/response APIs such as `readInPlace`,
`writeInPlace`, `copy`, `getContainerPath`, and `getItemMetadata` map to typed
exceptions:

- `ICloudContainerAccessException`
- `ICloudItemNotFoundException`
- `ICloudConflictException`
- `ICloudCoordinationException`
- `ICloudUnknownNativeException`

For iOS and macOS file-write overwrite operations, trying to overwrite an existing
directory target is treated as an invalid argument rather than as a successful
replacement.

These exceptions expose `operation`, `retryable`, `relativePath`, and native
error context when the platform provides it.

`ICloudCoordinationException` is reserved for structured coordination failures.
Current iOS and macOS native implementations still classify some lower-level
coordination problems as `ICloudUnknownNativeException` when they do not yet
emit an explicit `coordination` category.

Normal iCloud Drive lifecycle states such as not-current, not-downloaded, or
downloading are not typed plugin exceptions. Metadata APIs can still report
those states as metadata, but request/response operations no longer manufacture
timeout/readiness failures from them.

### Raw `PlatformException` cases

`PlatformException` is still the contract for:

- legacy unstructured request/response failures
- `getDocumentMetadata()`
- transfer-progress stream error events (`event.exception`)

`PlatformExceptionCode` contains constants:

- `E_CTR` (iCloud container/permission issues)
- `E_CONFLICT` (structured conflict failures)
- `E_FNF` (file not found)
- `E_FNF_READ` (file not found during read)
- `E_FNF_WRITE` (file not found during write)
- `E_NAT` (native error)
- `E_ARG` (invalid arguments passed to native)
- `E_READ` (read failure)
- `E_CANCEL` (operation canceled)
- `E_INIT` (plugin not properly initialized)
- `E_PLUGIN_INTERNAL` (internal plugin error)
- `E_INVALID_EVENT` (invalid event from native layer)

## Troubleshooting / gotchas

- Prefer testing on physical devices. iCloud sync is unreliable in iOS
  Simulator.
- `documentExists()` checks the filesystem path in the container; it does not
  force a download.
- If Files app visibility matters, ensure paths start with `Documents/` and
  your container is configured under `NSUbiquitousContainers`.
- After a rename/move/delete, `gather()` may still return stale results for a
  few seconds while the Spotlight index catches up. Use `listContents()` for
  immediate consistency.

## Documentation

- Hosted DeepWiki reference: https://deepwiki.com/kingdomseed/icloud_storage_plus
- Local notes index: `doc/README.md`

## License

MIT License - see [LICENSE](LICENSE).

## Credits

Forked from [icloud_storage](https://github.com/deansyd/icloud_storage) by
[deansyd](https://github.com/deansyd).

Upstream is referenced for attribution only. This repository is not intended to
track upstream changes.
