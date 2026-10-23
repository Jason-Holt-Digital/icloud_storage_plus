# Repository lore

The surviving history runs from **2021-03-04** to **2026-10-23**, ending at `e219229725d8da3616d57e5086b6701ef326a531` on `main`. It records a file-access plugin growing a document-based native core, briefly taking on readiness/conflict policy, and then explicitly returning those responsibilities to Apple and callers. Dates and changes below come from reachable commits, release tags, `CHANGELOG.md`, and selected line history.

For the current contract, start with the [overview](overview/index.md) and [architecture](overview/architecture.md). For caller changes rather than historical context, see [migrations](background/migrations.md).

## Eight dated eras

### 1. 2021-03 to 2024-07: the inherited file-operation core

The initial commit, **2021-03-04** (`af68a2d`), already contains `ICloudStorage`, container initialization, listing/watching names, and local-path upload/download methods in `lib/icloud_storage.dart`. Delete follows on **2021-03-05** (`3f0214b`), null safety on **2021-04-22** (`3adc968`), and richer `gatherFiles`, move, and rename APIs on **2022-03-24** (`7645af3`).

On **2022-10-15**, `c2b2b84` introduces the static facade/platform-interface structure and a macOS implementation alongside iOS. Evidence includes `lib/icloud_storage.dart`, `lib/icloud_storage_platform_interface.dart`, `lib/icloud_storage_method_channel.dart`, and the native source trees in that commit. Updates continue through **2023-01-06** (`be06aa5`), **2024-06-25** (`2ad0be0`), and **2024-07-23** (`aa38d6f`).

`CHANGELOG.md` explicitly sends readers to upstream history for the period before the current package's `1.0.0`. Thus an old commit subject such as `1.0.0` in March 2022 is not the February 2026 release with the same version label.

### 2. 2025-03 to 2025-12: Apple document coordination and conveniences

An explicit `icloudAvailable()` check arrives on **2025-03-17** (`2e4ce52`, `lib/icloud_storage.dart`). On **2025-06-25**, upload/download gain `NSFileCoordinator` coordination (`ed3287e`); `UIDocument`/`NSDocument` wrappers follow (`2e010a1`), as does automatic conflict resolution (`2958c5b`).

That June series also adds Files-app-oriented convenience methods and copy support (`68028eb`, `lib/icloud_storage.dart`). The native document wrappers survive today as `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, although later commits substantially change their responsibilities.

**Interpretation:** this era expands from transport-like file access toward a document-oriented native layer. The commits establish the additions; they do not establish that automatic conflict policy was necessary or correct. That policy is explicitly removed in June 2026.

### 3. 2026-01 to 2026-03: path-only transfers, in-place access, and packaging

The **2026-01-24** refactor (`b41ccb3`) renames the transfer entry points to `uploadFile`/`downloadFile` and removes older byte/JSON/convenience API surface from `lib/icloud_storage.dart`. Coordinated string in-place access arrives on **2026-02-02** (`e7c1b11`); byte in-place access follows on **2026-02-03** (`956a318`). The current-package **1.0.0 release on 2026-02-04** consolidates the path-only transfer contract and documents the migration in `CHANGELOG.md` (`c4eb277` tag target).

SwiftPM support is implemented on **2026-02-05** (`7e76210`) and released as **1.1.0 on 2026-02-13**. That implementation relocates native sources into `ios/icloud_storage_plus/Sources/icloud_storage_plus/` and `macos/icloud_storage_plus/Sources/icloud_storage_plus/`, retains CocoaPods specifications, and removes CocoaPods wiring from the example projects.

On **2026-03-09**, `listContents()` and `ContainerItem` arrive (`96db39f`, `lib/icloud_storage.dart`, `lib/models/container_item.dart`). This gives callers a direct directory-enumeration path distinct from `gather()`'s metadata-query view. Background task-queue work is corrected on **2026-03-27** (`c3e64e6`), followed by removal of short-lived document completion queues on **2026-03-30** (`5f7e944`); `CHANGELOG.md` records these as 1.2.1/1.2.2 fixes.

### 4. 2026-04: overwrite safety and a broader error/policy surface

The **2.0.0 release on 2026-04-09** combines coordinated replacements with typed known-path metadata and structured request/response failures. Evidence: `ba90360`, `e14d33b`, `5072199`, and the `2.0.0` tag at `b2b23e9`; affected Dart sources include `lib/models/icloud_item_metadata.dart` and `lib/models/exceptions.dart`.

This release is **not yet** the uniform v4 boundary: `CHANGELOG.md` says raw `getDocumentMetadata()` and older transfer failure behavior still existed. It also records readiness-related failure categories that are removed the following month.

The **2026-04-17** series (`915b589`, `fecdfef`) extracts shared overwrite/readiness helpers and adds write-path auto-download/auto-resolution behavior. Follow-up changes ship in **2.1.0 on 2026-04-22**, followed by manifest and actor/thread fixes in **2.1.1 on 2026-04-22** and **2.1.2 on 2026-04-23** (`b69727c`, `be1a224`, `e411822`). These are historical behaviors, not recommendations for the present API.

### 5. 2026-05: readiness stops being a plugin-owned policy

Container resolver/query-session fixes land on **2026-05-03** (`a4ccdf3`, `ee44346`), documented as 2.1.3. Its changelog date is May 3; the `2.1.3` tag is dated **2026-05-04**. At that time the resolver still retries container lookup; June changes supersede that behavior.

The decisive correction is **2026-05-26**, `346b08a`, released the same day as **2.2.0** (`ecb9295`). It deletes both native readiness-wait helpers and their tests, removes read timeout/backoff parameters and readiness exceptions, and stops gating local reads/writes on metadata becoming `.current`. The removed files are visible in the [removal diff](https://github.com/Jason-Holt-Digital/icloud_storage_plus/commit/346b08a).

The reason is **explicitly documented**, not inferred: `CHANGELOG.md` says the removed layer treated normal iCloud Drive lifecycle state as plugin-owned failures. `AGENTS.md` and `docs/plan/2026-05-26-fix-remove-icloud-readiness-timeout-layer-plan.md` preserve the local-file-operation ownership boundary. Apple controls synchronization and freshness; actual Foundation operations determine local success or failure.

### 6. 2026-06: explicit versions, mutation lanes, and document invalidation

On **2026-06-19**, `938e5a5` deletes the automatic conflict resolver and exposes unresolved version descriptors, caller-chosen copy-out, and explicit mark-resolved operations instead. It adds `lib/models/icloud_version.dart` and native helpers including `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift` and `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/PerPathMutationLane.swift`, with corresponding macOS copies. Subsequent same-day changes harden identifiers and move blocking coordination away from the cooperative pool (`6c11b57`, `1a3b25d`).

On **2026-06-20**, `46af351` replaces resolver retries with a single off-main container lookup in `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift`.

On **2026-06-22**, `f9515d7` introduces `watchDocumentChanges`, `lib/models/icloud_document_change.dart`, `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift`, and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift`. **3.0.0 ships on 2026-06-24** (`084ea51`) with the explicit version-exposure model. Conflict selection/copy-out/resolution policy belongs to callers; notifications do not promise an exactly-once change log.

### 7. 2026-07: the strict 4.0.0 Dart boundary

**4.0.0 ships on 2026-07-19**, `150174f`. It adds `lib/src/native_payload.dart`, `lib/src/platform_exception_decoder.dart`, and `lib/src/synchronous_stream_bridge.dart`; removes raw `getDocumentMetadata()` and public transport-code constants; uses typed stream errors; requires synchronous listener attachment; and makes in-place reads nonnullable. `CHANGELOG.md` enumerates the breaking changes rather than retaining compatibility APIs.

The same release changes existing-file writes to ordinary write coordination, updates macOS observation to passive file-presenter behavior with modification-date filtering, and renames the document-change hint to `invalidation`. Evidence remains in `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`, and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift`.

### 8. 2026-08 to 2026-10: verification guidance and delivery automation

**2026-08-29**, `7860064`, tightens `AGENTS.md` against tests that merely repeat their own setup; **2026-09-05**, `01ac70d`, simplifies the agent guidance and verification scope.

Three commits on **2026-10-23** complete the delivery automation. `292477b` adds `.github/workflows/factory-review.yml`, `.github/workflows/factory-mentions.yml`, `.github/workflows/factory-triage.yml`, `.github/workflows/droid-wiki-refresh.yml`, and `.github/workflows/publish-approval-canary.yml`. `92ae5da` configures Release Please (`.github/workflows/release-please.yml`, `release-please-config.json`, `.release-please-manifest.json`, and operator documentation in `.github/RELEASES.md`) so versions, changelogs, and plain-number tags derive from conventional commits on `main`. The current tip, `e219229`, removes the legacy `.github/workflows/droid.yml` and `.github/workflows/droid-review.yml`; its commit message explains that those unpinned workflows would duplicate reviews and replies once the opt-in replacements are enabled. This is repository delivery automation, not a new plugin runtime capability. These five commits are the entire reachable 90-date activity window ending October 23; see [by the numbers](by-the-numbers.md).

## Old operations that still have descendants

These are API lineages, **not unchanged implementations or unchanged contracts**. Counts below are commits returned by Git's current-range line history, including the introducing commit; they are not a semantic count of behavior changes.

| Current operation | Earliest verified capability | Current-range history commits | Evidence |
| --- | --- | ---: | --- |
| `uploadFile` | `startUpload`, 2021-03-04 | 18 | `af68a2d`; current name introduced by `b41ccb3`, 2026-01-24; `lib/icloud_storage.dart` lines 144-174 at the recorded HEAD |
| `downloadFile` | `startDownload`, 2021-03-04 | 20 | `af68a2d`; current name introduced by `b41ccb3`, 2026-01-24; `lib/icloud_storage.dart` lines 195-225 |
| `delete` | `delete`, 2021-03-05 | 6 | `3f0214b`; `lib/icloud_storage.dart` lines 378-390 |
| `gather` | richer `gatherFiles`, 2022-03-24 | 4 | `7645af3`; static `gather` name in `c2b2b84`, 2022-10-15; `lib/icloud_storage.dart` lines 66-74 |
| `copy` | `copy`, 2025-06-25 | 3 | `68028eb`; `lib/icloud_storage.dart` lines 456-478 |

Method: `git log HEAD -L <start>,<end>:lib/icloud_storage.dart --format='%h %ad %s' --date=short --no-patch`. Ranges select each current declaration through its closing brace, excluding preceding documentation. Git follows textual ancestry and may attribute moved/rewritten lines to older neighbors; direct snapshots verify the introduction dates independently. For example, a naive `move` range trace reaches 2021 even though the inspected 2021 API lacks `move`; that false origin is not used.

Selected `git blame` checks add useful granularity:

- `lib/icloud_storage.dart` lines 378-390: the static delete signature and platform delegation survive from `c2b2b84` (**2022-10-15**); its relative-path validation condition dates to `7645af3` (**2022-03-24**), while the current diagnostic text dates to `7ab5f2c` (**2025-03-17**).
- `lib/icloud_storage.dart` lines 195-225: line history connects the download operation to `af68a2d` (**2021-03-04**), but the current `localPath` guard text and current method name are from `b41ccb3` (**2026-01-24**). The oldest blamed lines are mostly delimiters, not evidence of untouched download semantics.
- `lib/icloud_storage.dart` lines 66-74: the required `containerId` argument/delegation includes lines from `c2b2b84` (**2022-10-15**), while the `GatherResult` signature is from `8a1aa64` (**2026-01-25**).

## Removed or replaced branches of the design

| Date | Retired behavior/surface | Replacement and trace |
| --- | --- | --- |
| 2026-01-24; released 2026-02-04 | Older byte/JSON transfer helpers and Files-app convenience wrappers | Path-only `uploadFile`/`downloadFile`; `b41ccb3`, `CHANGELOG.md` 1.0.0, `lib/icloud_storage.dart` |
| 2026-04-09 | Old typed `getMetadata()` | `getItemMetadata()` / `ICloudItemMetadata`; `5072199`, `lib/models/icloud_item_metadata.dart` |
| 2026-05-26 | Plugin readiness waits, timeout/backoff knobs, synthetic readiness failures | Local coordinated operations; deleted helpers and tests in [commit 346b08a](https://github.com/Jason-Holt-Digital/icloud_storage_plus/commit/346b08a) |
| 2026-06-19 | Automatic conflict winner selection/resolution | Explicit version exposure and caller policy; deleted resolver helpers in [commit 938e5a5](https://github.com/Jason-Holt-Digital/icloud_storage_plus/commit/938e5a5); added `lib/models/icloud_version.dart` |
| 2026-06-20 | Retrying container resolver introduced in May | Single off-main lookup; `46af351`; both platform resolver paths listed above |
| 2026-07-19 | Raw metadata escape hatch, public platform-code constants, error-as-progress-data, nullable reads, permissive payload fallbacks | One strict typed Dart boundary; `150174f`, `CHANGELOG.md` 4.0.0, `lib/icloud_storage_method_channel.dart`, `lib/src/platform_exception_decoder.dart` |

Historical plans under `ai_specs/` and `docs/` document earlier designs, not current API obligations. Current source and `AGENTS.md` override them; do not restore readiness loops or automatic conflict handling by copying an old plan.

## Growth was not a straight line

Snapshots use `git ls-tree -r --name-only <commit>`. Implementation counts select `.dart` under `lib/` and `.swift` under `ios/`/`macos/`, excluding SwiftPM manifests and native `/Tests/`; tests select Dart under `test/` plus Swift under native `/Tests/`. Example code is excluded from both columns. Total tracked files include documentation, assets, and any generated files tracked at that historical revision.

| Snapshot date / commit | Tracked files | Implementation files | Test files | Capability marker |
| --- | ---: | ---: | ---: | --- |
| 2021-03-04 / `af68a2d` | 64 | 2 | 1 | Initial iOS file-access plugin |
| 2022-10-15 / `c2b2b84` | 111 | 7 | 2 | Dart platform boundary and macOS implementation |
| 2025-06-25 / `2e010a1` | 139 | 9 | 2 | Document wrappers |
| 2026-02-04 / `c4eb277` | 158 | 11 | 3 | Current-package 1.0.0 contract |
| 2026-05-26 / `346b08a` | 165 | 30 | 15 | Readiness layer removed; Foundation seams retained |
| 2026-06-24 / `084ea51` | 181 | 40 | 21 | Explicit versions, lanes, observation |
| 2026-07-19 / `150174f` | 201 | 43 | 21 | Strict typed boundary |
| 2026-10-23 / `292477b` | 206 | 43 | 21 | Delivery automation |
| 2026-10-23 / `e219229` | 208 | 43 | 21 | Release Please automation; legacy Droid workflows removed |

These are net snapshot sizes, not cumulative files written. The **2026-01-24** simplification alone records **842 insertions and 3,229 deletions across 16 files** (`git show --stat b41ccb3`), demonstrating that reducing API surface can precede later capability growth. The unchanged 43 implementation / 21 test file counts from July to October do not imply an unchanged repository: October changes only automation and release tooling files.

## Evidence and interpretation rules

- The scope is ancestors of `HEAD`, not every locally present branch. Inspect with `git log HEAD --reverse --date=short --format='%h %ad %s'`.
- Dates in commit references above are recorded author dates; release dates come from `CHANGELOG.md` and local tags inspected with `git for-each-ref refs/tags --sort=creatordate`. Implementation and release dates are distinguished when they differ.
- Historical source means `git show <hash>:<full-repository-path>`, especially `lib/icloud_storage.dart`; current paths may differ after the **2026-02-05** SwiftPM relocation (`7e76210`).
- Statements labeled interpretation summarize the visible trajectory. Explicit ownership corrections are supported by `CHANGELOG.md` and `AGENTS.md`, rather than inferred motivations.
- Git names are labels, not distinct people. `Jason Holt` and `kingdomseed` share an author email; other differing labels are not automatically merged or counted as people. No contributor leaderboard is derived from the history.

For the corresponding measurements and their exact exclusions, see [by the numbers](by-the-numbers.md). For how the present native/Dart layers fit together, see [architecture](overview/architecture.md).
