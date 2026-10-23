# Glossary

These terms distinguish local plugin operations from the iCloud lifecycle. Definitions follow the public facade and repository ownership rules (`lib/icloud_storage.dart`, `AGENTS.md`).

| Term | Meaning and source |
| --- | --- |
| Ubiquity container | Apple-managed local directory resolved for a container identifier; `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift` |
| Container-relative path | Path inside that directory, validated by the facade; `lib/icloud_storage.dart` |
| Documents prefix | Literal `Documents/` convention used for optional Files app visibility; `README.md` |
| Copy-in / copy-out | Local path-only transfers exposed as `uploadFile` and `downloadFile`; `lib/icloud_storage_platform_interface.dart` |
| In-place content | Whole-file text or bytes crossing the platform channel; `lib/icloud_storage.dart` |
| Coordination | Foundation-mediated local document access, not synchronization with another device; `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift` |
| Mutation lane | Async serialization for a standardized path, with two lanes for cross-path operations; `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/PerPathMutationLane.swift` |
| Materialization request | A request to Apple to obtain local content, without a plugin-owned deadline; `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift` |
| Download status | `notDownloaded`, `downloaded`, or `current`, when supplied; `lib/models/download_status.dart` |
| Gather snapshot | Complete metadata-query results, optionally followed by full updated snapshots; `lib/models/gather_result.dart` |
| Document promise | An item discoverable through metadata that may lack a local filesystem representation; `README.md` |
| Placeholder | A local representation of an item whose contents may not be materialized; `README.md` |
| Invalidation hint | A document event that tells callers to reread local coordinated state, not proof of remote authorship; `lib/models/icloud_document_change.dart` |
| Conflict version | An unresolved `NSFileVersion` exposed for explicit app decisions; `lib/models/icloud_version.dart` |
| Plugin-contract error | An unexpected native/channel result rather than an Apple sync state; `lib/models/exceptions.dart` |
| Synchronous listener | A stream subscription attached before its callback returns; `lib/src/synchronous_stream_bridge.dart` |

See [Architecture](architecture.md), [Listing and metadata](../features/listing-and-metadata.md), and [Conflict versions](../features/conflict-versions.md) for the operational context.
