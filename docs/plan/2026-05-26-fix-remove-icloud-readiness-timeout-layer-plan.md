---
title: "fix: remove iCloud readiness timeout layer"
type: fix
date: 2026-05-26
---

# fix: remove iCloud readiness timeout layer

## Premise

iCloud Drive is a local ubiquity folder. Apple owns sync scheduling,
materialization, freshness, upload/download progress, metadata propagation, and
document conflicts. This plugin should perform local file operations against
that folder using Foundation APIs.

The bug is not that the plugin needs a better readiness model. The bug is that
the plugin currently manufactures errors for normal iCloud Drive lifecycle
states, especially when metadata does not become `.current` before a
plugin-owned timeout expires.

## Goal

Delete the plugin-owned wait-for-current timeout layer and the public API/docs
that make callers treat normal iCloud Drive lifecycle behavior as plugin
failures.

After this change:

- reads perform the local coordinated read that Apple can provide;
- offline reads return local bytes when Apple has local bytes available;
- no read path creates `ICloudStorageTimeout` or a Dart timeout exception;
- writes/replaces do not block on plugin-owned `.current` waits;
- actual local file-operation failures still cross the Flutter boundary when
  the operation itself fails.

## Non-Goals

Do not add:

- a sync service;
- readiness/status/result models;
- companion APIs or compatibility shims;
- channel payload contract documents;
- native payload-emission tests;
- plugin-side conflict resolution;
- stale-write prevention protocols;
- compare-before-write tokens;
- private app telemetry validation;
- top-level `swift build` gates for this Dart plugin.

## Files To Touch

Dart API and tests:

- `lib/icloud_storage.dart`
- `lib/icloud_storage_platform_interface.dart`
- `lib/icloud_storage_method_channel.dart`
- `test/icloud_storage_test.dart`
- `test/icloud_storage_method_channel_test.dart`

iOS native implementation:

- `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DownloadWaiter.swift`
- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DownloadWaiterTests.swift`
- `ios/icloud_storage_plus/Package.swift`
- `ios/icloud_storage_plus.podspec`

macOS native implementation:

- `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DownloadWaiter.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DownloadWaiterTests.swift`
- `macos/icloud_storage_plus/Package.swift`
- `macos/icloud_storage_plus.podspec`

Docs/package metadata:

- `AGENTS.md`
- `README.md`
- `CHANGELOG.md`
- `doc/notes/download_flow.md`
- `pubspec.yaml`
- superseded tracked planning docs under `docs/superpowers/`

Only touch package metadata if the public API change or source-list cleanup
requires it.

## Implementation Plan

### 1. Remove read timeout arguments from Dart

- [x] Completed.

- Remove `idleTimeouts` and `retryBackoff` from `readInPlace`.
- Remove `idleTimeouts` and `retryBackoff` from `readInPlaceBytes`.
- Remove method-channel serialization of `idleTimeoutSeconds` and
  `retryBackoffSeconds` for those reads.
- Update Dart tests that currently assert those arguments are sent.

Validation:

```shell
flutter test test/icloud_storage_test.dart test/icloud_storage_method_channel_test.dart
```

### 2. Remove native read wait-for-current behavior

- [x] Completed.

- In iOS and macOS `readInPlace` / `readInPlaceBytes`, stop parsing timeout and
  backoff arguments.
- Keep resolving the ubiquity container and target file URL.
- Keep the existing local document/coordinated read helper.
- Do not call `waitForDownloadCompletion(...)`.
- Do not map `ICloudStorageTimeout` for reads.
- Do not add a replacement readiness exception.

`startDownloadingUbiquitousItem(at:)` may remain only as an Apple materialization
request. It must not be followed by a plugin-owned `.current` wait or watchdog.

Validation:

```shell
rg "waitForDownloadCompletion|ICloudStorageTimeout|idleTimeout|retryBackoff" \
  ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift \
  macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift
```

Expected result: no matches in read code. If `mapTimeoutError` still has matches
elsewhere, verify those matches are not read readiness paths.

### 3. Remove write wait-for-current timeout behavior

- [x] Completed.

- In `CoordinatedReplaceWriter.liveEnsureDownloaded`, remove the call to
  `waitForDownloadCompletion(...)`.
- Do not introduce write result models, readiness states, stale-write checks, or
  conflict policy.
- Keep the operation as a local coordinated write/replace.
- Preserve only errors returned by the immediate local operation being
  performed.
- Update `CoordinatedReplaceWriterTests.swift` on both platforms so tests no
  longer expect `ICloudStorageTimeout`.

Validation:

```shell
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation
```

These Swift tests are scoped to the changed foundation helper package. They are
not a new top-level Swift build gate.

### 4. Delete the timeout helper when unused

- [x] Completed.

- Delete `DownloadWaiter.swift` and `DownloadWaiterTests.swift` if no production
  code still needs them.
- Remove deleted files from Swift package and podspec source lists.
- If `iCloudMetadataQuerySearchScopes` is still needed elsewhere, move only
  that constant to a small shared file. Do not keep timeout machinery as a
  compatibility surface.

Validation:

```shell
! rg "waitForDownloadCompletion|DownloadSchedule|ICloudStorageTimeout" lib ios macos test
```

### 5. Update public docs and release notes

- [x] Completed.

- Remove README guidance about read idle watchdogs, retry backoff, timeout
  exceptions, not-downloaded readiness failures, or download-in-progress
  readiness failures.
- Document the corrected model: this plugin performs local iCloud Drive file
  operations; Apple owns sync lifecycle.
- Note the breaking API cleanup in `CHANGELOG.md`.
- Bump `pubspec.yaml` only if the release process requires the breaking change
  to be versioned now.

Validation:

```shell
rg "idleTimeout|retryBackoff|ICloudTimeoutException|E_TIMEOUT|E_NOT_DOWNLOADED|E_DOWNLOAD_IN_PROGRESS" README.md CHANGELOG.md lib test
```

Expected result: no public read-readiness guidance or tests remain. Existing
exception model tests may remain only when they cover actual API-boundary
failures, not iCloud lifecycle readiness. Delete tests whose only purpose is to
prove removed timeout/readiness functionality is absent.

## Final Validation

Run:

```shell
dart format .
flutter analyze
flutter test
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation
dart pub publish --dry-run
```

Run only if podspec source lists changed:

```shell
pod lib lint ios/icloud_storage_plus.podspec
pod lib lint macos/icloud_storage_plus.podspec
```

Final negative check:

```shell
! rg "idleTimeout|retryBackoff|waitForDownloadCompletion|DownloadSchedule|ICloudStorageTimeout" lib ios macos test README.md CHANGELOG.md
```

## Acceptance Criteria

- [x] `readInPlace` and `readInPlaceBytes` no longer accept timeout/backoff
      arguments.
- [x] Native read paths no longer wait for `.current`.
- [x] Native write/replace paths no longer wait for `.current`.
- [x] `ICloudStorageTimeout` and `DownloadSchedule` are gone from production
      code.
- [x] No replacement readiness/result/status API is introduced.
- [x] Public docs describe iCloud Drive as local folder access with
      Apple-owned sync lifecycle.
- [x] No private downstream app names, private telemetry, or private production
      events appear in public docs.
- [x] Flutter analysis, Flutter tests, changed Swift package tests, and publish
      dry-run pass or have explicit documented blockers.

## Build Notes

- Removed superseded tracked `docs/superpowers/` planning artifacts that still
  described the retired timeout/readiness contract.
- Removed tests whose only purpose was asserting deleted timeout/readiness
  functionality stayed deleted.
- Pre-commit `dart pub publish --dry-run` reached package validation and
  reported only repository-state warnings: the branch was intentionally dirty,
  and deleted tracked files remained gitignored until commit recorded their
  removal.
- `pod lib lint ios/icloud_storage_plus.podspec` is blocked by the current
  Flutter headers used by CocoaPods lint: `FlutterBinaryMessenger` does not
  expose `makeBackgroundTaskQueue` / the `taskQueue` channel initializer in
  that environment. This is unrelated to the removed readiness layer.
- `pod lib lint macos/icloud_storage_plus.podspec --allow-warnings` passes.
  Plain macOS lint reports existing Swift actor-isolation warnings.
