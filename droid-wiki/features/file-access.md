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

Transfers pass paths rather than bytes through `lib/icloud_storage_method_channel.dart`. The documents in `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, plus `ios/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift`, use 64 KiB buffers for path-only copies. In-place text/binary document classes load complete contents into memory; successful reads return non-null contents, and empty files remain valid empty values. Invalid UTF-8 is an actual read failure, not a nullable result.

Upload copies the source; it does not keep that source synchronized with the container file. Download creates a separate local copy rather than handing the caller a live document handle. File-centric transfers and in-place operations reject trailing-slash paths in `lib/icloud_storage.dart`.

## Local completion and progress

1. Native handlers resolve the container and prepare destination parents where needed.
2. New files use the platform document create/write path. Existing-file writes stage complete contents and install them with coordinated `FileManager.replaceItemAt`.
3. The transfer Future completes for the local copy-in/copy-out operation, not for network delivery. In particular, upload progress monitoring can remain active after the upload Future succeeds.

`UbiquitousItemMaterializer.requestMaterializationIfNeeded` in `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` makes a request for non-current items; it does not wait for `.current`. `downloadFile` directly requests downloading before its document copy-out. Reads use available local bytes, including offline bytes, and actual Foundation operations determine failures when bytes are absent. There are no plugin-owned freshness waits, sync timeouts, or network-completion guarantees.

When supplying `onProgress`, attach `.listen(...)` synchronously inside the callback and retain the subscription. Events are `ICloudTransferProgress.progress(percent)` and `ICloudTransferProgress.done()`; failures use the stream's error channel. Native progress includes an initial marker and metadata-query percentages, so it is not a byte-exact local-copy meter. Upload observation ends when Apple reports 100%; download observation ends after local copy-out. A `done` event is not proof of delivery to other devices.

An actively delivered native transfer failure is not duplicated on the returned Future. If the progress listener is paused when that failure arrives, canceled before delivery, or absent, the Future carries the failure instead. Setup/contract failures can still fail the Future; handle both the Future and stream errors. Canceling the progress subscription stops observation, **not the transfer** (`lib/icloud_storage_method_channel.dart`, `lib/src/synchronous_stream_bridge.dart`).

## Mutations and replacement

| Operation | Local behavior |
| --- | --- |
| `rename` | Dart derives a sibling destination and delegates to `move`; directory trailing slashes are normalized first |
| `move` | Coordinates both endpoints, creates the destination parent if needed, then calls `FileManager.moveItem`; not an overwrite/merge API |
| `delete` | Coordinates deletion and removes the item; missing local entries fail |
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
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` | Streaming and whole-content document paths |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/FileWriteHelpers.swift` | Buffered copy and staged content writers |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift` | File-only overwrite decisions and installation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` | Request-only materialization seam |
| `test/icloud_storage_test.dart`, `test/icloud_storage_method_channel_test.dart` | Argument/path checks, content decoding, progress cancellation/failure races |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift` | Local replacement, directory rejection, coordinated URLs, error propagation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquitousItemMaterializerTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquitousItemMaterializerTests.swift` | Request decisions without lifecycle deadlines |

Scoped footprint: the table lists 13 source files and 6 test files; the additionally cited stream bridge is shared infrastructure. These are file counts, not test-case totals. History over the 19 table paths on `origin/main` has 7 distinct nonbot human author labels; aliases may overlap, so this is only a knowledge-concentration proxy. Tests cover plugin/local-operation decisions, not cross-device synchronization; see [Testing](../how-to-contribute/testing.md).
