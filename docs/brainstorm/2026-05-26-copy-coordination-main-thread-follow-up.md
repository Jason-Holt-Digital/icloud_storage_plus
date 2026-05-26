---
title: "copy coordination main-thread follow-up"
date: 2026-05-26
status: brainstorm
source: "PR #40 review"
---

# copy coordination main-thread follow-up

## Summary

PR #40 removed plugin-owned iCloud readiness and timeout behavior. During review,
Devin flagged a separate follow-up: `copy()` still performs synchronous
`NSFileCoordinator.coordinate(...)` work from the container-resolution callback.
That callback currently resumes on the main actor, so copy coordination and some
local copy I/O can block the main thread.

This is real technical debt, but it is not the same issue as the iCloud
readiness cleanup. It should be handled as a focused copy-coordination
performance/responsiveness change.

## Current shape

The affected code is in both Darwin entrypoints:

- `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
- `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`

`resolveContainerURL(...)` wraps container lookup in `Task { @MainActor ... }`
and invokes `onResolved(containerURL)` from that main-actor context.

Inside `copy()`:

- source existence is checked synchronously;
- `NSFileCoordinator.coordinate(readingItemAt:)` runs synchronously;
- if the destination exists, the coordination accessor calls
  `copyOverwritingExistingItem(...)`;
- `copyOverwritingExistingItem(...)` creates a replacement directory, copies the
  source into that directory, runs a second synchronous
  `NSFileCoordinator.coordinate(writingItemAt:)`, then calls
  `FileManager.replaceItemAt(...)`;
- if the destination does not exist, `copy()` runs a coordinated read/write
  copy and creates parent directories from inside the accessor.

The code captures coordinator `NSError` values, so this is not the same
"discarded coordinator error can hang the Dart future" bug that motivated the
delete/move consolidation. The main issue is where the blocking work runs.

## Why this matters

`NSFileCoordinator.coordinate(...)` is synchronous and may block while the
system coordinates with file presenters, other processes, Finder/Files app,
iCloud Drive/File Provider state, or filesystem contention. Large local copies
can also take noticeable time.

Running that work from the main actor can cause UI stalls or app
responsiveness problems. It also leaves `copy()` inconsistent with `delete()`
and `move()`, which now dispatch coordinated work onto the serial
`fileCoordinatorQueue` and hop back to the main queue only to deliver
`FlutterResult`.

There is also a smaller defensive-cleanup opportunity: the non-existing
destination branch currently calls `result(...)` inside the coordinator
accessor and then separately checks `copyCoordinationError` after coordination
returns. Apple's API should not normally call both paths, but `delete()` and
`move()` now use `CompletionGate` to make single delivery explicit.

## What this is not

Do not use this follow-up to restore plugin-owned iCloud readiness behavior.
Specifically, do not add:

- waits for `.current`;
- download/readiness timeouts;
- polling loops;
- not-downloaded/download-in-progress errors;
- conflict preflight policy;
- sync-service behavior;
- status/result companion APIs.

iCloud Drive lifecycle state remains Apple-owned. The copy follow-up should only
move local file coordination and local file I/O off the main actor while
preserving Foundation's operation result.

## Likely fix shape

A focused implementation should:

- dispatch all `copy()` coordination and local copy/replace work onto
  `fileCoordinatorQueue` on iOS and macOS;
- use a `CompletionGate`/`completeOnce` pattern like `delete()` and `move()`;
- deliver `FlutterResult` on the main queue;
- preserve current source-not-found and native error mappings;
- preserve PR #40's local-file boundary for existing destinations:
  - existing destination directories are rejected;
  - placeholder, freshness, and conflict metadata are not plugin preconditions;
  - actual `FileManager`/`NSFileCoordinator` failures are surfaced.

If extraction is useful, keep it small and copy-specific. Avoid creating a new
generic readiness or sync abstraction.

## Validation ideas

- Run `flutter analyze`.
- Run `flutter test`.
- Run the iOS and macOS Foundation package tests if helper code is extracted
  there.
- Add focused coverage only for behavior the plugin owns, such as single result
  delivery and coordinator-error mapping. Do not add tests whose only purpose is
  proving removed readiness behavior stayed removed.

