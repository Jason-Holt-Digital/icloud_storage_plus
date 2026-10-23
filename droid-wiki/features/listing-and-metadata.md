# Listing and metadata
Active contributors: Jason, Erik, vishalrao8

## Purpose

Separate metadata discovery from the current local directory view and known-path checks. Check availability first. None of these calls downloads file contents or guarantees that Apple's metadata is fresh (`lib/icloud_storage.dart`).

## Choose a query

| API | Returns | What it observes |
| --- | --- | --- |
| `gather` | `GatherResult.files`: `List<ICloudFile>` | Container-scoped metadata-index results, including document promises without local placeholders |
| `gather(onUpdate: ...)` | Initial Future result plus updated `GatherResult` snapshots | Best-effort query refreshes; every update is a full snapshot, not an added/removed delta |
| `listContents` | `List<ContainerItem>` | Direct children of the root or supplied directory via `FileManager.contentsOfDirectory` |
| `documentExists` | `bool` | `FileManager.fileExists(atPath:)` for the known container-relative path |
| `getItemMetadata` | `ICloudItemMetadata?` | URL resource values for an existing known path; `null` when the filesystem existence check fails |

Use `listContents` after an awaited local rename/delete/copy for a directory view that does not wait for the metadata index. This is immediate local filesystem enumeration, **not** a globally synchronized iCloud inventory or a recursive listing. Remote-only promises can appear in `gather` before they acquire a local representation and become listable. Existence does not imply readable bytes or `.current` status.

## Gather lifecycle

Both native plugins create `NSMetadataQuery` sessions using the ubiquitous data and documents scopes and a container-path predicate. The initial Future is completed from the finish-gathering notification. Query updates remap the complete current results. Apple controls discovery latency, batching, coalescing, and origin; an update is a refresh hint rather than evidence of a remote write.

Attach a listener synchronously in `onUpdate`; retain and cancel it when done. Without updates, the session stops after the initial snapshot. With updates, cancellation removes observers and stops the session, but canceling updates before initial gathering finishes does not abandon the initial Future: `GatherSessionLifecycle` waits for initial completion before claiming cleanup. `MetadataQuerySession` owns the query, notification tokens, and idempotent teardown.

## Local names and metadata coverage

`listContents` intentionally does not use `.skipsHiddenFiles`: `.report.txt.icloud` must first resolve to `report.txt`. It strips one leading dot and the `.icloud` suffix when there is a nonempty resolved name, then skips entries whose **resolved** name still starts with `.`. Normal/dataless filenames pass through unchanged. Returned paths remain relative to the **container root**, even when listing a subdirectory. This name resolution/filtering belongs to direct listing; do not assume gather applies the same filter.

| Model | Coverage and absent values |
| --- | --- |
| `ICloudFile` | Path, directory flag, nullable size/creation/content-change dates, nullable download status, download/upload/conflict flags |
| `ContainerItem` | Path and directory/download/upload/conflict fields; no size or date fields |
| `ICloudItemMetadata` | Known-path equivalent of the richer size/date/status fields, read from URL resource values rather than the metadata index |

Native missing boolean values become `false`; Dart also defaults **absent** boolean fields to `false`. Missing numeric/date/status values remain `null`, not zero or epoch dates. An absent flag is therefore not proof that a lifecycle state never occurred. Dart parsing rejects present booleans of the wrong type (including `null`), missing/non-string required paths, and unsupported status values. Channel list decoding fails the whole call/update instead of silently returning partial results.

`DownloadStatus` has `notDownloaded`, `downloaded`, and `current`. Native unknown statuses normalize to `null`; malformed unsupported normalized strings at the Dart boundary fail decoding. Dates are converted from native epoch seconds to Dart millisecond-resolution `DateTime`. `ContainerItem.isDownloaded` and `ICloudItemMetadata.isLocal` are derived from `downloaded`/`current` only; they are not extra native readiness checks. See [Data models](../reference/data-models.md).

## Key source files

| Path | Role / modification entry point |
| --- | --- |
| `lib/icloud_storage.dart`, `lib/icloud_storage_method_channel.dart` | Query APIs, path validation, strict result decoding |
| `lib/models/gather_result.dart`, `lib/models/icloud_file.dart` | Full metadata snapshots and entries |
| `lib/models/container_item.dart`, `lib/models/icloud_item_metadata.dart`, `lib/models/download_status.dart` | Direct-list/known-path fields and derived status |
| `lib/src/native_payload.dart` | Required/optional field and date conversion rules |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift` | Gather/list/existence/metadata handlers and placeholder-name normalization |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` | macOS counterpart |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySession.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySession.swift` | Query observer ownership and teardown |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySupport.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySupport.swift` | Query scopes, initial/update cancellation lifecycle |
| `test/icloud_storage_test.dart`, `test/icloud_storage_method_channel_test.dart` | Query delegation, nullable metadata, synchronous subscriptions, malformed snapshots |
| `test/models/icloud_file_test.dart`, `test/models/icloud_item_metadata_test.dart` | Model equality, optional values, typed field parsing |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/MetadataQuerySessionTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/MetadataQuerySessionTests.swift` | Observer cleanup and cancellation ordering |

Scoped footprint: 14 source files and 6 test files listed above, counting platform counterparts separately. `git log origin/main --` over those paths yields 6 distinct nonbot human author labels; aliases may overlap, so this is a knowledge-concentration proxy rather than a people count. These tests do not establish Apple's discovery timing or end-to-end placeholder behavior. For an existing file, consider [Document observation](document-observation.md); for native investigation, use [Debugging](../how-to-contribute/debugging.md).
