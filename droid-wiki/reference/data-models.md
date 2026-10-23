# Data models

The facade exports typed metadata, progress events, document events, conflict versions, and operation exceptions. Models represent observed local/platform values, not plugin-owned synchronization state machines (`lib/icloud_storage.dart`).

## Metadata

| Type | Obtained from | Fields and purpose | Source |
| --- | --- | --- | --- |
| `GatherResult` | `gather` and updates | Complete `files` list, not a delta | `lib/models/gather_result.dart` |
| `ICloudFile` | Gather snapshots | Relative path, directory flag, nullable size/dates/status, download/upload/conflict flags | `lib/models/icloud_file.dart` |
| `ContainerItem` | `listContents` | Relative path, directory/status and activity/conflict flags; no size/date fields | `lib/models/container_item.dart` |
| `ICloudItemMetadata` | `getItemMetadata` | Known-path metadata with nullable size/dates/status and activity/conflict flags | `lib/models/icloud_item_metadata.dart` |
| `DownloadStatus` | Metadata fields | `notDownloaded`, `downloaded`, `current` | `lib/models/download_status.dart` |

`ContainerItem.isDownloaded` and `ICloudItemMetadata.isLocal` are computed from `downloaded` or `current`. They do not force reads or establish future freshness. An unknown/missing status remains null; callers should not turn that absence into a synthetic operation failure.

Metadata equality uses `Equatable` for all three item types. `GatherResult` is a simple wrapper and does not implement the same equality machinery. See [Listing and metadata](../features/listing-and-metadata.md) for differences in data sources.

## Events and versions

| Type | Meaning | Source |
| --- | --- | --- |
| `ICloudTransferProgress` | Progress event with a percent, or terminal `done` data event | `lib/models/transfer_progress.dart` |
| `ICloudTransferProgressType` | `progress` and `done` | `lib/models/transfer_progress.dart` |
| `ICloudDocumentChange` | Relative path and typed invalidation/document-state kind | `lib/models/icloud_document_change.dart` |
| `ICloudDocumentChangeKind` | `invalidation`, `conflict`, `savingError`, `editingDisabled` | `lib/models/icloud_document_change.dart` |
| `ICloudVersion` | Opaque version identifier and nullable modification date | `lib/models/icloud_version.dart` |

Transfer failures use the stream's error channel, not an error-valued progress event. Document saving-error and editing-disabled kinds are iOS-specific observations; they are not equivalent macOS states. Events are hints, not reliable evidence that another device authored a change.

Pass a version identifier back unchanged to select a conflict copy. The app decides when to back up or mark versions resolved. See [Document observation](../features/document-observation.md) and [Conflict versions](../features/conflict-versions.md).

## Parsing and nullability

Shared parsing in `lib/src/native_payload.dart` requires string identifiers/paths, defaults absent Boolean fields to false, rejects present non-Boolean values, and preserves nullable numbers. Native timestamps are seconds converted to Dart milliseconds, with rounding. Numeric sizes are converted to integers.

`parseDownloadStatus` in `lib/models/download_status.dart` accepts the three supported values or null and rejects unknown strings. The channel adapter checks list entries and turns malformed results into a typed plugin-contract exception; callers never receive a deliberately partial gather snapshot (`lib/icloud_storage_method_channel.dart`).

Successful content reads are non-nullable. `getItemMetadata` and `getContainerPath` have nullable signatures; native operation failures can still throw (`lib/icloud_storage_platform_interface.dart`). These are existing typed APIs, not a new native payload specification.

## Exceptions

`InvalidArgumentException` describes facade validation or synchronous-listener misuse. It is distinct from the operation hierarchy in `lib/models/exceptions.dart`.

`ICloudOperationException` stores category, operation, retryable hint, message, and optional relative-path/native context. Subtypes cover item-not-found, container-access, explicit conflict-version failures, coordination, native invalid arguments, cancellation, initialization, and unknown native failures. Base instances also represent plugin-contract errors and unrecognized future native categories.

The internal decoder in `lib/src/platform_exception_decoder.dart` preserves supplied native domain, code, description, and underlying details. The retryable field is a hint, not an implemented retry policy. Missing plugin registrations become plugin-contract errors in the channel adapter.

Do not classify downloading, placeholders, or a non-current item as exceptions. See [Dart boundary](../systems/dart-boundary.md).
