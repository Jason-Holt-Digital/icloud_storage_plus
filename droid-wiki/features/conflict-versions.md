# Conflict versions
Active contributors: Jason, Erik

## Purpose

Expose unresolved `NSFileVersion` versions for an app's explicit preservation and resolution workflow. The plugin does not choose winners, merge content, automatically mark versions resolved, or delete losing versions during ordinary writes. Apple owns conflict discovery and freshness (`lib/icloud_storage.dart`, `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift`).

## Explicit workflow

Check `icloudAvailable()` first, then use a validated file-relative path without a trailing slash.

| Step | API | Result / effect |
| --- | --- | --- |
| Inspect what is currently exposed | `enumerateUnresolvedConflictVersions` | `List<ICloudVersion>`; no unresolved versions gives an empty list |
| Preserve a selected version | `copyConflictVersion(versionIdentifier: ..., destinationPath: ...)` | Copies the selected version to the caller's local destination |
| Mark the exposed conflicts resolved | `markConflictResolved(removeOtherVersions: false)` | Sets `isResolved` on the currently unresolved native versions |
| Explicitly request removal too | `markConflictResolved(removeOtherVersions: true)` | Marks resolved, then calls `NSFileVersion.removeOtherVersionsOfItem(at:)` |

Enumeration exposes only an opaque `identifier` and nullable `modificationDate`, not the version's bytes or a proposed winner. Pass the identifier back unchanged; do not parse it, sort by it, or treat it as a revision/freshness token. Native code archives the persistent identifier to a string and re-enumerates candidates when copying, matching their serialized identifiers. A no-longer-matching version produces an actual version-selection failure, surfaced as a typed conflict exception.

After preserving the versions required by its policy, the app decides how to update the live file, if at all, using [File access](file-access.md). `markConflictResolved` does not install a chosen version into that file and does not accept a winner identifier. It acts on the unresolved set visible **at that call**, not a frozen enumeration transaction. `removeOtherVersions` defaults to **false** throughout Dart and native handling; `true` requests removal of other versions, not selective deletion of just the descriptors previously listed.

## Destination trust and completion

`destinationPath` is an app-controlled local output path, not a container-relative path. The Dart facade checks that it and `versionIdentifier` are nonblank; it does not enforce a backup directory, absolute-path syntax, or separation from the live item. Native handlers construct a file URL directly, create missing parent directories, and invoke the selected version's `replaceItem(at:options:)`.

Choose a **distinct, trusted absolute destination**, and treat any existing content at that destination as replaceable. The intended copy-out leaves the live item untouched because the app supplies a different URL; the plugin does not enforce that separation. Do not feed an untrusted path or the live file's own path into this operation.

Enumeration is a view of what Foundation exposes now, not proof that all device versions have arrived. Copy-out completion concerns that local destination; marking/removal completion concerns the native calls. Neither is a promise of cross-device freshness or network completion. Calling mark-resolved when nothing is unresolved is intended to be a no-op; there is no plugin-owned sync wait around it.

## Key source files

| Path | Role / modification entry point |
| --- | --- |
| `lib/icloud_storage.dart` | Three explicit APIs, file path/identifier/destination validation, removal default |
| `lib/icloud_storage_method_channel.dart` | Typed descriptor decoding and operation failure translation |
| `lib/models/icloud_version.dart` | Opaque identifier and optional modification date |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` | Container routing, caller destination creation, native failure translation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift` | Enumeration, identifier matching, copy-out and explicit mark/remove bindings |
| `test/icloud_storage_method_channel_test.dart` | Descriptor decoding, malformed lists, destination forwarding, default `false`, typed version-selection failure |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/VersionExposureTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/VersionExposureTests.swift` | Injected exposure operations and identifier archive round-trips |

Scoped footprint: 7 source files and 3 test files above, counting platform counterparts separately. History over these paths on `origin/main` has 7 distinct nonbot human author labels; aliases may overlap, so this is a knowledge-concentration proxy, not a people count.

The native tests inject version-operation closures and use stand-in archive objects; they do not construct live iCloud-conflicted `NSFileVersion` instances. In particular, a test whose injected copy throws before writing is not proof of rollback/no-partial-output behavior for every Foundation failure. See [Testing](../how-to-contribute/testing.md), [Document observation](document-observation.md) for conflict hints, and [Data models](../reference/data-models.md) for descriptor fields.
