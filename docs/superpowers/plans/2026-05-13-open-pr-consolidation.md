# Open PR Consolidation Plan

Snapshot: 2026-05-13 10:29:46 CEST

Repository: `kingdomseed/icloud_storage_plus`

## Goal

Capture the live open PR review state and consolidate overlapping bot-sourced
performance changes into safe, reviewable fixes. Code quality and stability
take priority over accepting every optimization PR.

No GitHub write actions were taken while creating this document: no comments,
thread resolutions, merges, branch deletes, or PR closes. Later GitHub cleanup
actions are recorded below.

## Live PR Inventory

| PR | Branch | Status | Files | Review state | Initial verdict |
|---|---|---:|---:|---|---|
| [#30](https://github.com/kingdomseed/icloud_storage_plus/pull/30) | `perf/async-file-coordinator-move-4299254270788686612` | clean | 3 | 9 open current threads | Do not merge as-is; carry forward move idea only with coordinator errors handled. |
| [#31](https://github.com/kingdomseed/icloud_storage_plus/pull/31) | `performance-async-file-coordinator-delete-16154369131399113602` | clean | 4 | 13 open current threads | Do not merge as-is; duplicate delete work with P1 coordinator-error and path-escape concerns. |
| [#32](https://github.com/kingdomseed/icloud_storage_plus/pull/32) | `perf/async-getdocumentmetadata-1773966710348158229` | clean | 3 | 4 open current threads | Candidate after removing root benchmark artifact and deciding whether `documentExists` is in scope. |
| [#33](https://github.com/kingdomseed/icloud_storage_plus/pull/33) | `optimize-map-file-attributes-5374875045378659345` | clean | 3 | 7 open current threads | Candidate only as part of mapping consolidation; remove benchmark script and soften benchmark claims. |
| [#34](https://github.com/kingdomseed/icloud_storage_plus/pull/34) | `perf-optimize-nsmetadataquery-loops-33357472296089754` | clean | 4 | 8 open current threads | Do not merge as-is; contains macOS query-cancel ordering regression and root benchmark artifacts. |
| [#35](https://github.com/kingdomseed/icloud_storage_plus/pull/35) | `perf-dart-iteration-4503915023291417995` | clean | 1 | 5 open current threads | Low-value micro-optimization; if kept, preserve mutable empty lists. |
| [#36](https://github.com/kingdomseed/icloud_storage_plus/pull/36) | `performance/non-blocking-move-coordination-7117363535050450245` | clean | 2 | 5 open current threads | Better macOS move error handling, but incomplete platform/method coverage and possible queue reentrancy concern. |
| [#37](https://github.com/kingdomseed/icloud_storage_plus/pull/37) | `perf-move-delete-to-bg-queue-4686768747889599894` | clean | 3 | 6 open current threads | Duplicate delete work; still drops coordinator errors. |
| [#38](https://github.com/kingdomseed/icloud_storage_plus/pull/38) | `perf-cache-container-path-9742097589616377049` | clean | 3 | 6 open current threads | Plausible, but overlaps mapping work; keep only if folded into one code-only mapping PR. |
| [#39](https://github.com/kingdomseed/icloud_storage_plus/pull/39) | `jules/performance-optimization-startdownloading-14467599079261901492` | clean | 5 | 7 open current threads | Closed; do not carry forward as plugin-owned iCloud readiness work. |

## GitHub Cleanup Log

Cleanup run: 2026-05-13 10:43:48 CEST.

Closed as superseded by the coordinator-safety consolidation branch:

- [#30](https://github.com/kingdomseed/icloud_storage_plus/pull/30):
  coordinated move off-main-thread PR.
- [#31](https://github.com/kingdomseed/icloud_storage_plus/pull/31):
  coordinated delete off-main-thread PR.
- [#36](https://github.com/kingdomseed/icloud_storage_plus/pull/36):
  macOS coordinated move off-main-thread PR.
- [#37](https://github.com/kingdomseed/icloud_storage_plus/pull/37):
  duplicate coordinated delete off-main-thread PR.

Remaining open bot PRs after cleanup: #32, #33, #34, #35, #38, #39. These stay
open until their metadata, mapping, Dart micro-optimization, and
download-start buckets are either consolidated or explicitly rejected.

Cleanup run: 2026-05-17 21:35:57 CEST.

Closed the remaining bot PRs after their requested changes were captured in
this plan and the repo cleanup work moved to the consolidation branch:

- [#32](https://github.com/kingdomseed/icloud_storage_plus/pull/32):
  metadata I/O off-main-thread PR.
- [#33](https://github.com/kingdomseed/icloud_storage_plus/pull/33):
  file attribute mapping allocation PR.
- [#34](https://github.com/kingdomseed/icloud_storage_plus/pull/34):
  metadata query loop optimization PR.
- [#35](https://github.com/kingdomseed/icloud_storage_plus/pull/35):
  Dart list iteration micro-optimization PR.
- [#38](https://github.com/kingdomseed/icloud_storage_plus/pull/38):
  container path cache PR.
- [#39](https://github.com/kingdomseed/icloud_storage_plus/pull/39):
  `startDownloadingUbiquitousItem` off-main-thread PR.

Remaining open PRs after cleanup: none.

## Comment And Thread Snapshot

| PR | Conversation comments | Reviews | Review threads | Current open threads | Latest comment/review update |
|---|---:|---:|---:|---:|---|
| [#30](https://github.com/kingdomseed/icloud_storage_plus/pull/30) | 3 | 4 | 9 | 9 | 2026-05-13T07:51:47Z |
| [#31](https://github.com/kingdomseed/icloud_storage_plus/pull/31) | 3 | 4 | 13 | 13 | 2026-05-13T07:59:52Z |
| [#32](https://github.com/kingdomseed/icloud_storage_plus/pull/32) | 3 | 3 | 4 | 4 | 2026-05-13T07:51:03Z |
| [#33](https://github.com/kingdomseed/icloud_storage_plus/pull/33) | 3 | 3 | 7 | 7 | 2026-05-13T07:58:39Z |
| [#34](https://github.com/kingdomseed/icloud_storage_plus/pull/34) | 3 | 3 | 8 | 8 | 2026-05-13T07:56:15Z |
| [#35](https://github.com/kingdomseed/icloud_storage_plus/pull/35) | 3 | 4 | 5 | 5 | 2026-05-13T08:01:50Z |
| [#36](https://github.com/kingdomseed/icloud_storage_plus/pull/36) | 3 | 3 | 5 | 5 | 2026-05-13T08:02:37Z |
| [#37](https://github.com/kingdomseed/icloud_storage_plus/pull/37) | 3 | 3 | 6 | 6 | 2026-05-13T08:05:30Z |
| [#38](https://github.com/kingdomseed/icloud_storage_plus/pull/38) | 3 | 3 | 6 | 6 | 2026-05-13T08:09:35Z |
| [#39](https://github.com/kingdomseed/icloud_storage_plus/pull/39) | 3 | 4 | 7 | 7 | 2026-05-13T08:19:14Z |

## Consolidated Review Themes

## Capture Audit

Audit run: 2026-05-17.

The major requested changes from PRs #30-#39 are captured in the sections
below. This follow-up audit added the smaller items that were present in review
threads but were previously compressed into broader buckets:

- Treat `fileExists` checks around coordinated delete/move as race-prone
  preflight checks. The implementation must still map file-not-found errors
  from inside the coordinated accessor instead of relying only on a pre-check.
- If moving more `NSFileCoordinator` calls off-main, prefer a serial
  coordinator queue over a global concurrent queue to avoid reentrant
  overlapping coordination work.
- Do not reuse bot benchmark claims without validating the benchmark itself.
  Reviewers flagged silent setup failures, non-representative stubs, warm-up
  bias, unused parameters, and broken Swift string interpolation in addition to
  the files being stray artifacts.
- For metadata I/O off-main-thread work, decide explicitly whether
  `documentExists` belongs in the same scope as `getDocumentMetadata`.
- For path-cache work, avoid spreading helper allocations into non-loop call
  sites where they do not buy much, and keep comments attached to the functions
  they document.
- The download-start offload bucket was later rejected; do not carry it forward
  as plugin-owned iCloud readiness work.

No review thread found during this audit requires reopening the closed bot PRs;
the information needed for follow-up work is in this document.

### 1. Coordinator Failure Hangs Are The Highest-Risk Issue

Affected PRs: #30, #31, #36, #37.

Multiple reviewers independently flagged the same failure mode:
`NSFileCoordinator.coordinate(...)` can fail before executing the accessor
block. PRs that pass `error: nil` discard that failure, so the only
`FlutterResult` calls are skipped and the Dart `Future` can hang indefinitely.

Actionable requirements:

- Use `NSError?` out-parameters for coordinated delete and move on both iOS and
  macOS.
- Ensure every method path calls `FlutterResult` exactly once.
- Dispatch native file coordination off the main thread without making
  coordinated move/delete operations reentrant in unsafe ways.
- Preserve existing typed native error mapping.

Related non-blocking concerns:

- #31 and #37 delete PRs still leave move/copy on the main thread.
- #30 move PR still leaves delete/copy on the main thread.
- #36 fixes only macOS move and leaves iOS parity unresolved.

### 2. Path Escape Validation Needs Explicit Treatment

Affected PRs: #31 and likely the broader delete/move/copy family.

Factory Droid flagged that `relativePath` is appended to `containerURL` and
then deleted without proving the resolved URL remains under the iCloud
container. The Dart layer validates relative paths, but native APIs can still
be invoked directly through method channels, so native-side containment is a
stability/security consideration.

Actionable requirement:

- Add or reuse a native helper that resolves/standardizes a child URL and
  rejects paths outside the container before destructive operations.

### 3. Benchmark Artifacts Should Not Ship

Affected PRs: #31, #32, #33, #34, and docs in #30, #31, #33, #36, #37, #38,
#39.

Reviewers found root or script benchmark artifacts that are not part of the
plugin test infrastructure:

- `test_perf.swift`
- `benchmark.swift`
- `benchmark_results.md`
- `scripts/benchmark_delete.swift`
- `scripts/benchmark_map_file_attributes.swift`

Actionable requirements:

- Do not merge standalone benchmark files from these PRs.
- If benchmark notes are kept, keep them in docs only and avoid strict claims
  such as "guaranteed", "infinite percentage improvement", or measured output
  that was not actually measured in this environment.

### 4. Metadata Query Mapping Optimizations Overlap

Affected PRs: #33, #34, #38.

There are three overlapping attempts to reduce allocations while mapping
metadata results.

Important findings:

- #33's iOS single-pass refactor is mostly behavior-preserving, with a line
  length issue and benchmark/documentation caveats.
- #34 adds macOS parity but introduces a P1 regression: the one-shot macOS path
  can cancel the metadata query before safely mapping or snapshotting results.
- #34 weakens a private type boundary from `[NSMetadataItem]` to `[Any]`.
- #38 caches container path normalization data and is likely safe, but its
  duplicated private struct and misplaced doc comment should be cleaned up if
  adopted.

Actionable requirement:

- Create one mapping consolidation change, not three PR merges.
- Preserve the macOS one-shot ordering: snapshot/map results before canceling
  the metadata query session.
- Keep private method signatures typed where possible.
- Keep code-only improvements separate from benchmark notes.

### 5. Dart GatherResult Mutability Regression Is Small But Real

Affected PR: #35.

Returning `const GatherResult(files: [], invalidEntries: [])` creates
unmodifiable lists only for the null-input path, while the normal path returns
growable lists. Reviewers flagged that as an inconsistent behavioral surface.

Actionable requirement:

- If the null early return is kept, return
  `GatherResult(files: [], invalidEntries: [])` instead of a const instance.
- Given the optimization value is tiny, it is reasonable to skip #35 entirely.

### 6. Download-Start Offload PR Was Rejected

Affected PR: #39.

This bucket is closed. Do not revive the PR's write-helper work as a plugin
readiness layer. iCloud Drive materialization belongs to Apple; this plugin
should not build a wait-for-freshness or wait-for-localization protocol around
that lifecycle.

`startDownloadingUbiquitousItem(at:)` remains appropriate only as an explicit
Apple materialization request for transfer-style APIs. It must not become a
custom timeout, retry, or status contract in this plugin.

## Recommended Consolidation Order

1. Coordinator safety for delete and move on iOS/macOS.
2. Native containment validation for destructive operations.
3. Metadata/get-document off-main-thread cleanup, without benchmark files.
4. Metadata mapping/path-cache consolidation, preserving macOS query ordering.
5. Consider or drop the Dart list iteration micro-optimization.
6. Do not carry #39's download-start offload into this consolidation.

## Active Consolidation Plan

### Phase 1: Discovery

- [x] Refresh open PR list from GitHub.
- [x] Fetch thread-aware review data for open PRs.
- [x] Cluster duplicate review findings by behavior area.
- [x] Record findings in this durable document.

### Phase 2: Coordinator Safety Consolidation

- [x] Create scoped branch `codex/open-pr-coordinator-consolidation`.
- [x] Add a native helper or local pattern for off-main coordinated writes that
      captures coordinator errors.
- [x] Update iOS delete.
- [x] Update macOS delete.
- [x] Update iOS move.
- [x] Update macOS move.
- [x] Ensure `FlutterResult` completes exactly once.
- [x] Avoid benchmark/doc churn from source PRs.

### Phase 3: Validation

- [x] Run Dart tests.
- [x] Run Flutter analyzer.
- [x] Run available Swift/SPM tests for shared foundation code.
- [x] Compile the example app against the edited Swift plugin files.
- [ ] Re-check review thread state after pushing, if this becomes a PR update.

Validation notes:

- `flutter test`: passed, 127 tests.
- `flutter analyze`: passed, no issues.
- `swift test` in `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation`:
  passed, 52 tests.
- `swift test` in
  `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation`: passed, 54
  tests.
- `flutter build macos`: blocked by the example Runner's local iCloud
  provisioning profile requirement before code compilation completed.
- `xcodebuild` macOS Debug build with code signing disabled: passed and compiled
  `macOSICloudStoragePlugin.swift`.
- `xcodebuild` iOS simulator Debug build with code signing disabled: passed and
  compiled `iOSICloudStoragePlugin.swift`. Xcode emitted stale-file warnings for
  existing build products, but no compiler errors.

### Phase 4: Remaining PR Buckets

- [ ] Decide whether to carry #32 metadata I/O off-main-thread changes.
- [ ] Consolidate #33/#34/#38 mapping/path-cache changes or explicitly skip
      them.
- [ ] Decide whether #35's Dart micro-optimization is worth carrying.
- [x] Reject #39 download-start offload as superseded by the local iCloud Drive
      responsibility boundary.
- [x] Close superseded coordinator bot PRs #30, #31, #36, and #37 after
      explicit approval.
- [x] Close or supersede remaining bot PRs after their buckets were captured in
      this plan and moved out of standalone bot PR review.

## Open Questions

1. Should native containment checks be included in the first coordinator-safety
   branch, or should they be a second security-focused branch?
2. Should copy coordination also be moved off-main now, or deferred until
   move/delete are stable?
3. Should benchmark docs be removed entirely from `BENCHMARK.md`, or rewritten
   as a short qualitative note after validated code lands?
