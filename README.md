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
relativePath: 'Documents/notes.txt'

// Outside the Files app Documents/ convention
relativePath: 'cache/notes.txt'
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
    - On iOS and macOS, existing-file writes stage the complete new content and
      install it with `FileManager.replaceItemAt` under coordinated ordinary-write
      access. This preserves the destination relative path, but is not a
      crash-durability or watcher-delivery guarantee.
    - Conflict versions are not automatically resolved or deleted. iCloud Drive
      sync and document conflict behavior remain Apple's responsibility.
    - Those file-write overwrite paths still reject an existing directory
      destination instead of replacing it.
3. **File management and queries**
   - `delete`, `move`, `copy`, `rename`
   - `documentExists`, `getItemMetadata`
   - On iOS and macOS, copying onto an existing destination uses staged,
     coordinated replacement rather than remove-then-copy behavior.
   - Existing-destination `copy()` replacement is file-only on iOS and macOS:
     existing directories are rejected instead of replaced.
   - `copy()` can copy files or directories to new destinations. If you need to
     replace an existing directory tree, manage that directory explicitly rather
     than relying on overwrite replacement.
4. **Container listing** (two complementary approaches)
   - `gather` — `NSMetadataQuery`-based; can discover remote files and document
     promises and deliver updated metadata snapshots while subscribed. Update
     timing and coalescing are controlled by Apple; results remain eventually
     consistent after local mutations.
   - `listContents` — FileManager-based; immediately consistent after local
     mutations; returns download/upload status via URL resource values; only sees
     files with a local representation (including iCloud placeholders)

On iOS, when Flutter provides a background platform-channel task queue, native
filesystem work for the in-place APIs runs there so iCloud container lookup and
`UIDocument` preflight do not block the app's main thread. If that queue is not
available, Flutter falls back to its default platform-channel dispatch model.
macOS keeps the existing dispatch model.

## Migration notes for 4.0.0

- `readInPlace` and `readInPlaceBytes` now return non-nullable `String` and
  `Uint8List` values. Catch `ICloudItemNotFoundException` when a missing item is
  an optional domain outcome.
- `ICloudStoragePlatform.getItemMetadata` now returns
  `Future<ICloudItemMetadata?>`. Custom platform implementations and fakes
  should return the typed model instead of a raw channel map.
- Every public `ICloudOperationException` subtype can be constructed directly
  from normalized fields. The `PlatformException` transport decoder is internal
  to `MethodChannelICloudStorage` and is not a public API.
- Native success replies for every `Future<void>` method-channel operation must
  be `null`. Non-null replies are typed `pluginContract` failures.

## Migration notes for 2.2.0

- `readInPlace` and `readInPlaceBytes` no longer accept `idleTimeouts` or
  `retryBackoff`. Remove those named arguments from callers.
- The former timeout, item-not-downloaded, and download-in-progress exception
  and transport-code APIs were removed. Normal iCloud Drive lifecycle state is
  no longer a plugin-owned error surface.
- On iOS and macOS, `copy()` over an existing destination no longer reports
  plugin-owned readiness failures for non-current, not-downloaded, downloading,
  or conflicted iCloud metadata. It rejects existing directory destinations,
  then lets Foundation perform the local replacement and report any actual
  operation failure.

## Quick start

```dart
import 'dart:io';
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
    relativePath: notesPath,
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
    // Invalid path segment (starts with '.', contains ':', etc.).
    throw Exception(e);
  } on ICloudOperationException catch (e) {
    // Native and method/event-channel failures are typed.
    throw Exception(e);
  }
}
```

## Watching document changes

`watchDocumentChanges` observes an existing file. Create or load the document
before starting the watcher, then cancel the returned stream subscription when
it is no longer needed.

```dart
import 'dart:async';

StreamSubscription<ICloudDocumentChange>? changeSubscription;

await ICloudStorage.watchDocumentChanges(
  containerId: containerId,
  relativePath: notesPath,
  onChange: (changes) {
    changeSubscription = changes.listen((change) async {
      switch (change.kind) {
        case ICloudDocumentChangeKind.invalidation:
          // Treat this as an invalidation hint and reread coordinated state.
          await ICloudStorage.readInPlace(
            containerId: containerId,
            relativePath: notesPath,
          );
        case ICloudDocumentChangeKind.conflict:
          // Enumerate versions and apply your app's conflict policy.
          break;
        case ICloudDocumentChangeKind.savingError:
        case ICloudDocumentChangeKind.editingDisabled:
        case ICloudDocumentChangeKind.unknown:
          break;
      }
    });
  },
);

// Later, when this document is no longer observed:
await changeSubscription?.cancel();
```

Each call provides one single-subscription stream. Multiple calls may observe
the same path independently. Treat every event as an invalidation hint and
reread the current local file or metadata:

- Apple may delay, coalesce, omit, or repeat native callbacks.
- `invalidation` does not claim that another device originated the change.
- On macOS, non-conflict callbacks with the same on-disk modification date are
  suppressed. Conflict callbacks bypass that filter and may repeat.
- A successful plugin write to an existing watched macOS file records the
  resulting modification date so a matching queued callback is suppressed.
  This does not apply to iOS, creation, other processes, or arbitrary writes.
- Watching a path that does not yet exist is unsupported. Create or materialize
  the item before starting the watcher.

Conflict events are explicit and app-owned—the plugin never selects or deletes
conflict versions automatically. iCloud Drive owns cross-device propagation and
does not provide a real-time latency guarantee. This watcher reports changes
after Foundation delivers them; it is not a Google Docs-style collaboration
channel.

## Transfers with progress

Progress and successful completion are delivered as data events of type
`ICloudTransferProgress`. Failures are delivered through stream `onError` as
typed `ICloudOperationException` values.

Important: the progress stream is listener-driven; start listening immediately
in the `onProgress` callback or you may miss early events.

```dart
await ICloudStorage.uploadFile(
  containerId: containerId,
  localPath: '/absolute/path/to/local/file.pdf',
  relativePath: 'Documents/file.pdf',
  onProgress: (stream) {
    stream.listen(
      (event) {
        if (event.isProgress) {
          // 0.0 - 100.0
          final percent = event.percent!;
        } else if (event.isDone) {
          // Transfer completed successfully.
        }
      },
      onError: (Object error) {
        final exception = error as ICloudOperationException;
      },
    );
  },
);
```

## Container-relative paths

This plugin consistently uses `relativePath` for paths inside the iCloud
container, including `uploadFile` and `downloadFile`.

### Trailing slashes

Directory paths can show up with trailing slashes in metadata, so the
directory-oriented methods accept them:

- `delete`, `move`, `copy`, `rename`, `documentExists`, `getItemMetadata`

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

`gather()` returns a `GatherResult` whose `files` field contains the complete
metadata snapshot. If any native entry is malformed, the initial call or update
stream fails with a typed plugin-contract exception; partial snapshots are never
returned.

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
| Ongoing update stream | Yes; best-effort metadata snapshots with Apple-controlled timing/coalescing | No (one-shot) |
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
- **Container-wide refresh hints**: use `gather` with `onUpdate`. Treat each
  update as a reason to refresh metadata; timing, coalescing, and origin are not
  guaranteed.

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

### Native and channel failures (`ICloudOperationException`)

Native method-channel failures, event-channel failures, and malformed channel
payloads map to typed exceptions. This applies to request/response APIs such as
`icloudAvailable`, `readInPlace`, `writeInPlace`, `copy`, `getContainerPath`,
and `getItemMetadata`, plus `gather`, document-change, and transfer streams:

- `ICloudContainerAccessException`
- `ICloudItemNotFoundException`
- `ICloudConflictException`
- `ICloudCoordinationException`
- `ICloudInvalidArgumentException`
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
