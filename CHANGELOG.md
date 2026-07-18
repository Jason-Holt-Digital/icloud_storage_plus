# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [4.0.0] - 2026-07-18

### Breaking

- Removed `getDocumentMetadata`; use `getItemMetadata` for typed metadata.
- Removed the public `PlatformExceptionCode` constants. Match typed
  `ICloudOperationException` subclasses and fields instead of transport codes.
- Raw plugin `PlatformException` failures now map to typed
  `ICloudOperationException` values, including details-less native failures and
  malformed method/event-channel contracts.
- Transfer failures now arrive through the progress stream's `onError` callback
  as typed exceptions. Remove `ICloudTransferProgressType.error`, `isError`, and
  `event.exception` handling; data events are only `progress` and `done`.
- Renamed the `uploadFile` and `downloadFile` named argument and method-channel
  key from `cloudRelativePath` to `relativePath`.
- Renamed `ICloudDocumentChangeKind.remoteChange` and its native wire value to
  `ICloudDocumentChangeKind.invalidation` / `"invalidation"`. Treat it as a
  refresh hint and reread coordinated state.
- Removed `GatherInvalidEntry` and `GatherResult.invalidEntries`; malformed
  gather payloads now fail the whole initial call or update stream.
- Removed `ICloudStorage.documentsDirectory` and `dataDirectory`. Use the
  literal `Documents/` path convention for Files app visibility.
- Download-status payloads now accept only `null`, `notDownloaded`,
  `downloaded`, or `current`.
- `readInPlace` and `readInPlaceBytes` now return non-nullable `String` and
  `Uint8List` values. Missing items throw `ICloudItemNotFoundException` instead
  of returning `null`.
- `ICloudStoragePlatform.getItemMetadata` now returns
  `Future<ICloudItemMetadata?>`; method-channel payloads are decoded exactly
  once by the default platform implementation.
- Every advertised `ICloudOperationException` subtype now has a public
  constructor accepting normalized failure fields. The raw `PlatformException`
  mapper is internal to the method-channel implementation and is no longer part
  of the public API.
- Method and list responses now validate channel types explicitly and map
  malformed payloads or missing native plugin implementations to typed
  `pluginContract` exceptions. All `Future<void>` channel operations require a
  strictly `null` success response, including event-channel creation/start,
  mutations, transfers, and conflict operations.

### Fixed

- iOS and macOS existing-file content writes now use ordinary write
  coordination (`NSFileCoordinator.WritingOptions` empty) instead of
  replacement-intent (`.forReplacing`) coordination. Complete content is still
  staged outside the container and installed with `FileManager.replaceItemAt`;
  unresolved conflict versions remain app-owned.
- macOS document observation now uses a passive file-presenter path instead of
  `NSDocument` reload/revert handling. Non-conflict content callbacks are
  de-duplicated using the on-disk modification date; conflict callbacks bypass
  that filter and may repeat while unresolved.
- Successful plugin writes to existing watched macOS files refresh every active
  same-path watcher baseline, so matching queued callbacks are suppressed.
- Canceling a change subscription while native observation is starting now
  prevents late presenter registration and tears the watcher down exactly once.

### Documentation

- Clarified that document-change and `gather(onUpdate:)` streams are best-effort
  invalidation/update signals, not real-time or exactly-once change logs.
- Clarified that watching a missing future path is unsupported.

## [3.0.0] - 2026-06-24

Major release for the app-owned preserve-both conflict model and the final
MYT-1321 publish cutover.

### Breaking
- Removed the legacy native conflict auto-resolution contract completely.
  `ConflictResolver`, write-path auto-resolve, and document-observer
  auto-resolve no longer exist. The plugin never silently marks or deletes
  losing `NSFileVersion`s.
- Consumers must use the explicit version-exposure API
  (`enumerateUnresolvedConflictVersions`, `copyConflictVersion`, and
  `markConflictResolved`) to implement their own conflict policy.
  The plugin exposes primitives only; apps own preserve-both copy-out and
  resolution sequencing.
- Removed compatibility shims and old readiness/conflict behavior from the
  public Dart surface. This release has one forward contract rather than
  dual old/new APIs.

### Added
- iOS and macOS expose unresolved `NSFileVersion` descriptors, caller-chosen
  conflict-version copy-out, and explicit mark-resolved operations over the
  Dart API.
- Per-normalized-path mutation lanes serialize same-path mutations in FIFO
  order while allowing different paths to proceed concurrently.
- `AsyncMutex.acquire()` now removes a queued waiter immediately when the
  waiting task is cancelled, preventing cancelled waiters from lingering in a
  lane until normal FIFO hand-off reaches them.

### Changed
- iOS and macOS podspec versions now match the plugin `pubspec.yaml` version.
  This reconciles the previous podspec `2.1.3` versus pubspec `2.2.0` drift
  before publishing the new major.
- `Package.swift` manifests remain source-list only, with no semantic version
  field. The package source lists reference only files that are still present.

## [2.2.0] - 2026-05-26

Corrective release for the readiness/error-reporting API introduced in
`2.0.0`. That surface treated normal iCloud Drive lifecycle state as
plugin-owned failures; this release removes it and restores the intended local
file-operation boundary.

### Breaking
- Removed the read-side timeout/backoff parameters from `readInPlace` and
  `readInPlaceBytes`. Reads now perform local iCloud Drive file access instead
  of waiting for Apple metadata to report a fresh remote state.
- Removed exported typed exceptions and platform-code constants for plugin-owned
  iCloud readiness failures. Normal iCloud Drive lifecycle state is no longer a
  plugin error surface.
- Changed existing-destination `copy()` behavior on iOS and macOS: the copy
  path no longer preflights iCloud download/current/conflict metadata or emits
  retired readiness errors before replacement. Existing directory destinations
  are rejected; placeholder, freshness, and conflict lifecycle states are left
  to Foundation, and any actual replacement failure is surfaced from the local
  operation.

### Changed
- iOS and macOS reads no longer wait for `.current` before opening the local
  document.
- iOS and macOS writes no longer run a plugin-owned wait before coordinated
  replacement. iCloud Drive sync lifecycle remains Apple's responsibility.
- Copy-over-existing-destination now uses the same local-file boundary: it
  rejects directory replacements, then lets Foundation perform the copy/replace
  rather than preflighting iCloud download/current metadata.

### Removed
- Removed the internal iCloud readiness helper and its synthetic timeout error
  path.

## [2.1.3] - 2026-05-03

### Fixed
- iOS and macOS container operations now route through a shared
  `UbiquityContainerResolver`, including `gather`, so transient
  `FileManager.url(forUbiquityContainerIdentifier:)` nil responses retry
  before surfacing a container-access failure.
- Container resolution retry delays now preserve `Task.sleep` cancellation
  instead of swallowing it, so cancelled calls stop before issuing an
  unnecessary second container lookup.
- Native iOS and macOS metadata query sessions are retained for their full
  query lifetimes, preventing observers from being released before
  `NSMetadataQuery` completes.
- Native write failures now preserve structured path and native error context
  for Dart typed exceptions without exposing full local filesystem paths.

## [2.1.2] - 2026-04-23

### Fixed
- iOS `readInPlace` and `readInPlaceBytes` now marshal the post-materialization
  continuation back onto the main actor before invoking
  `readInPlaceDocument` / `readInPlaceBinaryDocument`. The `2.1.0` async
  rewrite of the previous readiness helper inadvertently removed the
  `DispatchQueue.main` hop that the callback-based helper guaranteed,
  letting `UIDocument.open(completionHandler:)` be called from the Swift
  cooperative pool. This restores the `1.2.2` invariant that `UIDocument`
  work runs under the main queue per Apple's completion-handler contract
  and avoids the `_os_object_retain` "Resurrection of an object" crash
  that motivated that fix.
- macOS `uploadFile`, `readInPlace`, `readInPlaceBytes`, `writeInPlace`,
  and `writeInPlaceBytes` now run their `Task` bodies on the main actor.
  Because the macOS `FlutterMethodChannel` is registered without a
  background task queue, `FlutterResult` must be invoked on the main
  thread; the previous `Task { [self] in ... }` blocks resumed on the
  cooperative pool after `await`, causing `result(...)` to be called
  off-main in preflight error paths.

## [2.1.1] - 2026-04-22

### Fixed
- Added `WriteEntrypointPreflight.swift` to the explicit iOS plugin
  `Package.swift` source list so consumer builds that rely on the plugin's
  Swift package manifest can compile the `2.1.x` write-path preflight helper.
- This is a packaging hotfix only. The Dart API and native write-path behavior
  introduced in `2.1.0` are unchanged.

## [2.1.0] - 2026-04-22

Non-breaking behavior upgrade: `writeInPlace` becomes symmetric with
`readInPlace` by proactively preparing existing iCloud items before the
coordinated replace.
Public Dart API unchanged.

### Added
- Shared `WriteEntrypointPreflight` helpers and foundation tests on iOS and
  macOS to move write-path container lookup and parent-directory creation off
  the entry thread before coordinated writes begin.
- Typed Dart mapping for native `invalidArgument` write failures via
  `ICloudInvalidArgumentException`.

### Changed
- `writeInPlace` and the binary / streaming overwrite paths now proactively
  prepare existing ubiquitous destinations before the coordinated replace.
- Inside the coordinator write block, the overwrite path now calls
  Apple's canonical conflict-resolution pattern
  (`NSFileVersion.unresolvedConflictVersionsOfItem` → `replaceItem` →
  `isResolved = true` → `removeOtherVersionsOfItem`) before invoking
  `replaceItemAt`, symmetric with the existing `readInPlace` behavior.
- Pre-flight conflict errors now fire only as last-resort signals when
  automatic conflict handling itself fails. Auto-resolution failures surface
  with a localized description containing "auto-resolution failed" while still
  mapping to `ICloudConflictException` on the Dart side.
- Internal refactor: unified the four textual copies of
  `CoordinatedReplaceWriter.swift` into a single source of truth per
  platform (iOS and macOS) shared via SPM `target.sources`.
- Internal refactor: extracted shared async helpers for readiness handling and
  unresolved-conflict resolution.
- `ICloudDocument.resolveConflicts()` (iOS) and the equivalent macOS
  observer both call the shared resolver; the duplicate implementation
  on iOS has been removed.
- `listContents` on iOS and macOS now does less repeated work inside the
  directory-enumeration loop by reusing the key set, reusing the parent
  relative path, and skipping hidden files before metadata lookup.
- README, package metadata, and publish/package wiring were updated to match
  the shipped 2.1.x source layout and write-path contract.

### Fixed
- iOS and macOS overwrite-path completion handlers now preserve structured
  native failure details instead of degrading to generic native failures.
- CocoaPods packaging now explicitly includes the shared foundation sources
  needed by the coordinated overwrite implementation.

## [2.0.0] - 2026-04-09

Breaking release that hardens the Dart API contract around known-path metadata,
typed request/response failures, and coordinated overwrite behavior on iOS and
macOS.

### BREAKING CHANGES
- Removed the old typed `getMetadata()` API in favor of `getItemMetadata()`.
- Structured native request/response failures now map to typed
  `ICloudOperationException` subclasses across the Dart API.
- `getDocumentMetadata()` remains the raw metadata escape hatch and preserves
  raw `PlatformException` behavior.

### Added
- `ICloudItemMetadata` as the typed known-path metadata model returned by
  `getItemMetadata()`.
- Typed request/response exception mapping for structured native payloads,
  including container access, not found, conflict, download-in-progress, item
  not downloaded, and timeout cases.

### Changed
- README, example code, and public Dart doc comments now document the `2.0.0`
  contract explicitly, including the separation between `ICloudItemMetadata`,
  `ICloudFile`, and raw `getDocumentMetadata()` payloads.
- Transfer-progress streams continue to emit `PlatformException`-based error
  payloads in `2.0.0`; only request/response APIs use the new typed exception
  mapping.
- README, changelog, and public Dart doc comments now describe the final iOS
  and macOS coordinated replacement behavior for existing-destination writes
  and copies.
- On iOS and macOS, file-write overwrite APIs and `copy()` now document
  separate existing-destination semantics: file writes target files only,
  while `copy()` preserves file-or-directory copy behavior.
- The iOS and macOS coordinated replacement logic now has standalone
  Foundation-level Swift test seams, with helper XCTest coverage for overwrite
  and existing-destination copy replacement behavior.
- Repository documentation now points to the hosted DeepWiki site instead of
  keeping a checked-in export under `doc/deepwiki/`.

### Fixed
- iOS and macOS existing-file `writeDocument`, `writeInPlace`, and
  `writeInPlaceBytes` now stage replacement content outside the ubiquity
  container and replace the destination through coordinated atomic replacement.
- iOS and macOS keep the `1.2.2` document-open completion fix that dispatches
  `UIDocument` completion back onto `DispatchQueue.main`, avoiding the
  `_os_object_retain` resurrection crash from short-lived local queues.
- On iOS and macOS, file-write overwrite APIs now reject existing directory
  destinations instead of replacing them.
- On iOS and macOS, existing ubiquitous-item replacement semantics were
  tightened in this release.
- iOS and macOS `copy()` now keep existing destinations inside coordinated
  atomic replacement flows instead of removing the destination before copying.

## [1.2.2] - 2026-03-30

### Fixed
- iOS and macOS document-open completion no longer uses a local
  `DispatchQueue`. The short-lived queue could be deallocated before
  `UIDocument.openWithCompletionHandler:` finished retaining it (via the
  deprecated `dispatch_get_current_queue` call in UIKit internals), causing
  an `_os_object_retain` crash with "API MISUSE: Resurrection of an object".
  Completion is now dispatched on `DispatchQueue.main`, which is consistent
  with UIDocument's own completion-handler contract.

## [1.2.1] - 2026-03-27

### Changed
- iOS method-channel filesystem work now uses Flutter's background task queue
  when that queue is available. Container lookup, iCloud path preflight, and
  `UIDocument` initialization stay coordinated but no longer block the UI
  thread during in-place reads and writes on supported runtimes.

### Fixed
- iOS and macOS metadata query update handling no longer depends on
  `DispatchQueue.main.sync` for event-channel state checks, reducing deadlock
  risk when iCloud change notifications arrive while other native work is in
  flight.
- Event stream state on iOS and macOS is now synchronized for cross-queue
  access, which avoids races between cancellation, progress delivery, and
  metadata updates.
- iOS download watchdog startup now schedules its initial timeout on the main
  run loop even when the method channel handler starts on a background task
  queue, preventing stalled in-place reads from hanging indefinitely.
- iOS and macOS download completion/cancellation paths now use a synchronized
  single-fire completion gate, preventing double `FlutterResult` delivery when
  cancellation races with native completion.

## [1.2.0] - 2026-03-09

### Added
- `listContents()` API for immediately-consistent container listings using
  `FileManager.contentsOfDirectory` with URL resource values. Unlike `gather()`
  (which reads the Spotlight metadata index), `listContents()` reflects
  filesystem mutations (rename, delete, copy) immediately.
- `ContainerItem` model with `relativePath`, `downloadStatus`, `isDownloading`,
  `isUploaded`, `isUploading`, `hasUnresolvedConflicts`, `isDirectory`, and a
  convenience `isDownloaded` getter.
- iCloud placeholder file resolution: both iOS (`.originalName.icloud` stubs)
  and macOS Sonoma+ (APFS dataless files) are handled transparently —
  `listContents` returns the real filename and accurate download status.
- Hidden file filtering: `listContents` suppresses system files (`.DS_Store`,
  `.Trash`, etc.) by filtering entries whose resolved name starts with `.`.

### Changed
- `ICloudFile` dartdoc now cross-references `ContainerItem` and explains the
  eventual-consistency distinction.
- `GatherResult` dartdoc expanded to describe `invalidEntries` purpose.
- Fixed typo in `InvalidArgumentException` doc comment ("ued" → "used").
- README expanded with `listContents` documentation, `gather` vs `listContents`
  comparison table, iCloud placeholder files section, and `ContainerItem` model
  reference.

## [1.1.1] - 2026-02-14

### Fixed
- GitHub Actions automated publishing trigger for tags like `1.2.3` (no `v`
  prefix).
- Remove example ephemeral LLDB helper files that were causing `dart pub publish`
  validation warnings.

## [1.1.0] - 2026-02-13

### Added
- Swift Package Manager support for iOS and macOS (Flutter 3.24+ opt-in).

### Changed
- Native iOS/macOS sources are now packaged under `Sources/icloud_storage_plus/`
  for SwiftPM compatibility (CocoaPods support remains via the podspecs).
- Example apps now use Flutter's SwiftPM plugin integration (no CocoaPods
  `Podfile`s in the example projects).

## [1.0.1] - 2026-02-11

### Fixed
- Avoid reading `NSMetadataItem` off the query thread by running `NSMetadataQuery`
  on a dedicated operation queue and disabling updates during snapshot reads.
- Ensure `relativePath` generation is path-boundary-aware (avoid prefix-collision
  edge cases).

### Changed
- Clarify benchmark documentation around `standardizedFileURL` behavior.

## [1.0.0] - 2026-02-04

Major API update with path-based transfers for large files, coordinated in-place
read/write APIs for small files, and a documentation overhaul.

### BREAKING CHANGES

#### Transfer API: file-path based for large files
Byte-based transfer APIs have been removed in favor of file-path methods. Large
file content is no longer sent over platform channels.

**Removed:** `upload()`, `download()`, and related byte/JSON helpers.

**New:** `uploadFile()` and `downloadFile()` using local paths plus
`cloudRelativePath`.

**Migration:**
1. Write data to a local file in Dart.
2. Call `uploadFile(localPath, cloudRelativePath)`.
3. To read, call `downloadFile(cloudRelativePath, localPath)` and read the
   local file in Dart.

#### gather() now returns GatherResult
`gather()` now returns a `GatherResult` containing:
- `files`: parsed `ICloudFile` entries
- `invalidEntries`: entries that could not be parsed (helps debug malformed
  metadata payloads)

#### ICloudFile metadata shape and nullability
`ICloudFile` now:
- includes `isDirectory: bool` (directories are returned by metadata APIs)
- may return `null` for some fields when iCloud metadata is unavailable or the
  entry represents a directory (for example `sizeInBytes`)

#### Directory detection behavior
`documentExists()` and `getMetadata()` return true/non-null for both files and
directories. Filter directories explicitly if your code expects only files.

#### Platform requirements updated
Minimum deployment targets match Flutter 3.10+:
- **iOS**: 13.0
- **macOS**: 10.15

#### Internal channel name change
The native method channel name is `icloud_storage_plus` (was `icloud_storage`).

#### Linting package change
Dev linting moved to `very_good_analysis`.

### Added

- File-path transfer methods:
  - `uploadFile()` (local → iCloud container)
  - `downloadFile()` (iCloud container → local)
- Coordinated in-place access for small files:
  - `readInPlace()` / `writeInPlace()` (String, UTF-8)
  - `readInPlaceBytes()` / `writeInPlaceBytes()` (Uint8List)
  - Former optional read readiness tuning parameters were available in this
    release and have since been removed.
- Convenience `rename()` API (implemented in Dart via `move()`).
- Additional iCloud sync-state fields on `ICloudFile`:
  - `downloadStatus`, `isDownloading`
  - `isUploading`, `isUploaded`
  - `hasUnresolvedConflicts`
- New public error code constants:
  - `PlatformExceptionCode.initializationError` (`E_INIT`)
- Documentation overhaul:
  - README updated to match the real API surface and semantics
  - DeepWiki badge added to the README
  - DeepWiki exported into `doc/` for GitHub navigation
  - Added `scripts/fix_deepwiki_links.py` to keep exported docs linkable
  - Old `doc/` research/plans removed (replaced by short notes under
    `doc/notes/`)

### Changed

- Structural operations (`delete`, `move`, `copy`) use coordinated file URL
  operations (NSFileCoordinator) rather than relying on metadata queries.
- Existence and metadata (`documentExists`, `getDocumentMetadata`) use direct
  filesystem checks (FileManager / URL resource values) rather than metadata
  queries.
- `documentExists()` is a filesystem existence check; it does not force a
  download. Use `gather()` for a remote-aware view of container contents.
- Transfer progress streams deliver failures as `ICloudTransferProgressType.error`
  data events (not stream `onError`).

### Fixed

- `gather()` now verifies the event channel handler exists before registering
  query observers (prevents leaked observers on early-return).
- `getDocumentMetadata()` now serializes download status keys as strings
  (`.rawValue`) for correct transport to Dart.
- Dart relative-path validation accepts trailing slashes so directory paths from
  metadata can be reused directly in operations like `delete()`, `move()`,
  `rename()`, etc.
- `uploadFile()` / `downloadFile()` reject `cloudRelativePath` values that end
  with `/` (directory-style paths).
- macOS streaming writes use `.saveOperation` for existing files to avoid
  unintended “Save As” behavior.

### Migration Guide (2.x → 1.0.0)

1. Replace byte-based reads/writes with local files + `uploadFile()` /
   `downloadFile()`.
2. For small JSON/text stored in iCloud Drive, consider switching to in-place
   access (`readInPlace`/`writeInPlace`) for “transparent sync”.
3. Update call sites to handle directories via `ICloudFile.isDirectory` and
   add null checks for optional metadata fields.
4. If you use transfer progress, attach a listener immediately inside
   `onProgress` (streams are listener-driven and may miss early events).
5. Run `flutter analyze` to address any `very_good_analysis` lint findings.

---

## Previous Releases

For history prior to 1.0.0 (including the upstream lineage), see git history
and the upstream repository: https://github.com/deansyd/icloud_storage
