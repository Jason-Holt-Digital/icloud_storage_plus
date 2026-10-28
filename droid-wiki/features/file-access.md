# File access
Active contributors: Jason, Erik

## Purpose

Move bytes between local paths or read/write small contents inside the ubiquity container. Check `ICloudStorage.icloudAvailable()` before operating. The plugin performs local file operations; Apple schedules any subsequent iCloud propagation (`lib/icloud_storage.dart`, `README.md`).

## Choose the data path

| Workflow | Public methods | Native path |
| --- | --- | --- |
| Large-file copy-in | `uploadFile(localPath: ..., relativePath: ...)` | Local source → container document; native buffered I/O |
| Large-file copy-out | `downloadFile(relativePath: ..., localPath: ...)` | Requests materialization, then copies container bytes to the local destination |
| Small UTF-8 file | `readInPlace`, `writeInPlace` | Whole-file `String` contents cross the channel |
| Small binary file | `readInPlaceBytes`, `writeInPlaceBytes` | Whole-file `Uint8List` contents cross the channel |
| Many small files | `readInPlaceBytesMany` | One coordinated read for all paths; a `Map<String, Uint8List>` of the files that exist crosses the channel |

Transfers pass paths rather than bytes through `lib/icloud_storage_method_channel.dart`. The documents in `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, plus `ios/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift`, use 64 KiB buffers for path-only copies. In-place reads do a plain coordinated read (`NSFileCoordinator` plus `Data(contentsOf:)`) off the main thread instead of opening a `UIDocument` or `NSDocument`, which made a 242-file copy on an iPad about four times faster. They load complete contents into memory; successful reads return non-null contents, and empty files remain valid empty values. Invalid UTF-8 is an actual read failure, not a nullable result. In-place writes still use the document classes.

`readInPlaceBytesMany(containerId:, relativePaths:)` reads a list of files under one `NSFileCoordinator` batch (`coordinate(with:queue:byAccessor:)`, one reading intent per file). The result maps each relative path, exactly as passed, to its bytes. A path with no file is left out of the map. Any other failure (coordination, permission, a directory path, a download error) fails the whole call with the same typed exceptions `readInPlaceBytes` throws, and names the failing path when the failure belongs to one file. Paths are validated like `readInPlaceBytes`, and an empty list returns an empty map without calling native code. All the files are held in memory at once, so use it for many small files.

Upload copies the source; it does not keep that source synchronized with the container file. Download creates a separate local copy rather than handing the caller a live document handle. File-centric transfers and in-place operations reject trailing-slash paths in `lib/icloud_storage.dart`.

## Local completion and progress

1. Native handlers resolve the container and prepare destination parents where needed.
2. New files use the platform document create/write path. Existing-file writes stage complete contents and install them with coordinated `FileManager.replaceItemAt`.
3. The transfer Future completes for the local copy-in/copy-out operation, not for network delivery. In particular, upload progress monitoring can remain active after the upload Future succeeds.

`UbiquitousItemMaterializer.requestMaterializationIfNeeded` in `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` makes a request for non-current items that iCloud has; it does not wait for `.current`, and an item that is not in iCloud (such as a file a write is about to create) gets no request. `downloadFile` directly requests downloading before its document copy-out. Reads use available local bytes, including offline bytes, and actual Foundation operations determine failures when bytes are absent. There are no plugin-owned freshness waits, sync timeouts, or network-completion guarantees.

When supplying `onProgress`, attach `.listen(...)` synchronously inside the callback and retain the subscription. Events are `ICloudTransferProgress.progress(percent)` and `ICloudTransferProgress.done()`; failures use the stream's error channel. Native progress includes an initial marker and metadata-query percentages, so it is not a byte-exact local-copy meter. Upload observation ends when Apple reports 100%; download observation ends after local copy-out. A `done` event is not proof of delivery to other devices.

An actively delivered native transfer failure is not duplicated on the returned Future. If the progress listener is paused when that failure arrives, canceled before delivery, or absent, the Future carries the failure instead. Setup/contract failures can still fail the Future; handle both the Future and stream errors. Canceling the progress subscription stops observation, **not the transfer** (`lib/icloud_storage_method_channel.dart`, `lib/src/synchronous_stream_bridge.dart`).

## Mutations and replacement

| Operation | Local behavior |
| --- | --- |
| `rename` | Dart derives a sibling destination and delegates to `move`; directory trailing slashes are normalized first |
| `move` | Coordinates both endpoints, creates the destination parent if needed, then calls `FileManager.moveItem`; not an overwrite/merge API |
| `delete` | Coordinates deletion and removes the item; missing local entries fail |
| `createDirectory` | Coordinated write that creates the directory and missing parents; succeeds when it already exists |
| `moveIntoContainer` | `FileManager.setUbiquitous(true, ...)` on a background queue; moves a local file or directory in, creating missing parents; the destination must not exist; works offline and iCloud uploads later |
| `moveOutOfContainer` | `FileManager.setUbiquitous(false, ...)`; moves an item to a local path and removes it from iCloud on every device; use `downloadFile` to keep the iCloud copy |
| `copy` to a new destination | Coordinates source/destination and uses `FileManager.copyItem`; files and directories are supported |
| `copy` to an existing destination | Stages the source and coordinates replacement; existing directory destinations are rejected, not recursively merged or replaced |
| Upload/in-place overwrite | `CoordinatedReplaceWriter` rejects directory destinations, prepares a replacement file, then performs an ordinary coordinated write/replace |

Mutation lanes serialize same-path writes and protect both endpoints of cross-path operations. Replacement preserves the destination path but is not a crash-durability or watcher-delivery guarantee. It neither chooses conflict winners nor resolves/deletes versions. See [Conflict versions](conflict-versions.md) for explicit version actions, [Listing and metadata](listing-and-metadata.md) for post-mutation enumeration, and [native files](../systems/native-files/index.md) for coordination internals.

## Key source files

| Path | Role / modification entry point |
| --- | --- |
| `lib/icloud_storage.dart` | Public paths, content/transfer/mutation methods |
| `lib/icloud_storage_method_channel.dart` | Transfer Future/stream failure arbitration |
| `lib/models/transfer_progress.dart` | Progress and completion data events |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift` | iOS transfer/content/mutation handlers |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` | macOS counterpart |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` | Streaming and whole-content document write paths |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift` | Coordinated read bridges, including the `readFilesIfPresent` batch read |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift` | Buffered copy and staged content writers |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift` | File-only overwrite decisions and installation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` | Request-only materialization seam |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMover.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMover.swift` | `setUbiquitous` moves into and out of the container |
| `test/icloud_storage_test.dart`, `test/icloud_storage_method_channel_test.dart` | Argument/path checks, content decoding, progress cancellation/failure races |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift` | Local replacement, directory rejection, coordinated URLs, error propagation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquitousItemMaterializerTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquitousItemMaterializerTests.swift` | Request decisions without lifecycle deadlines |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedBatchReadTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedBatchReadTests.swift` | Batch read with real files: order, missing files, a directory failing the batch |

Scoped footprint: the table lists 15 source files and 8 test files; the additionally cited stream bridge is shared infrastructure. These are file counts, not test-case totals. History over the 19 original table paths on `origin/main` has 7 distinct nonbot human author labels; aliases may overlap, so this is only a knowledge-concentration proxy. Tests cover plugin/local-operation decisions, not cross-device synchronization; see [Testing](../how-to-contribute/testing.md).
