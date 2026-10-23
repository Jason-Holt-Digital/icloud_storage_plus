# Document observation
Active contributors: Jason, Erik, vishalrao8

## Purpose

`watchDocumentChanges` observes an **existing file**, not future path creation or a directory tree. Create/load the document and check iCloud availability before starting. Events tell callers to reread coordinated local state; they are not a remote-origin signal, change history, or sync-completion service (`lib/icloud_storage.dart`, `lib/models/icloud_document_change.dart`).

## Subscription lifecycle

1. Pass `containerId`, a file `relativePath`, and `onChange`. Attach `.listen(...)` **inside** `onChange` before that callback returns; ignoring the stream or delaying subscription fails before native allocation.
2. The adapter creates a unique event channel for each call, attaches the source, then requests native observation. Each call exposes one single-subscription Dart stream. Two calls on the same path remain independent.
3. Native registration retains an `ICloudDocument` presenter and `DocumentChangeObservation`. The returned `Future<void>` represents setup, not the lifetime of observation.
4. Retain the Dart `StreamSubscription` and `await subscription.cancel()` when the caller is finished. Cancellation removes presenter observation and the native stream registration; it does not delete the document.

The bridge checks cancellation before starting native work and cancels a source attached after cancellation. Native lifecycle state handles cancellation before or during presenter startup: a pending start is skipped, or one teardown runs after an in-flight start completes. A deferred cancellation handler also preserves cancellation that arrives before its cleanup callback is installed. Repeated cancellation is harmless. Setup failures close the exposed stream and fail the setup Future (`lib/src/synchronous_stream_bridge.dart`, both native watch handlers).

## Event interpretation

`ICloudDocumentChange` carries `relativePath` and a typed `kind`; no event timestamp, revision, or origin is supplied.

| Kind | Meaning | Platforms |
| --- | --- | --- |
| `invalidation` | Refresh local document/metadata state through a coordinated API | iOS and macOS |
| `conflict` | Inspect versions and apply app-owned policy | iOS and macOS |
| `savingError` | `UIDocument` reported its saving-error state | iOS only |
| `editingDisabled` | `UIDocument` reported its editing-disabled state | iOS only |

On iOS, one state notification may emit **multiple** specific kinds when several flags are set. If none of those flags is active, it emits `invalidation`. `editingDisabled` may be a temporary artifact of `UIDocument`'s revert handling, rather than a lasting editing restriction. Debounce/coalesce in the caller only if its workflow requires it; the plugin does not promise one event per write.

On macOS, passive presenter startup coordinates an attribute read to establish a modification-date baseline. Non-conflict callbacks with an unchanged date are suppressed; a new date is consumed once. Conflict callbacks bypass that filter and can repeat. The plugin's successful upload/in-place **existing-file overwrite** records the final modification date for all registered same-path passive watchers, including registrations found after the write began. This suppresses matching queued callbacks from that overwrite; it is not a blanket guarantee that every own mutation is invisible.

Foundation can delay, coalesce, repeat, or omit notifications, and changed bytes with an unchanged date need not yield a macOS invalidation. Do not infer cross-device freshness or authorship from an event or its absence. See [File access](file-access.md) for rereads and [Conflict versions](conflict-versions.md) for explicit conflict actions.

## Key source files

| Path | Role / modification entry point |
| --- | --- |
| `lib/icloud_storage.dart` | Existing-file watch API and lexical validation |
| `lib/icloud_storage_method_channel.dart`, `lib/src/synchronous_stream_bridge.dart` | Independent channel allocation, synchronous listen, cancellation/setup failures |
| `lib/models/icloud_document_change.dart` | Event model and four supported kinds |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` | Watch registration/cleanup; macOS same-path writer baselines |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` | Platform callbacks, passive presentation, state/date interpretation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift` | Start/cancel races, modification-date consumption, deferred cleanup |
| `test/icloud_storage_test.dart`, `test/icloud_storage_method_channel_test.dart` | Watch path rules, stream setup/decoding/errors, allocation-time cancellation |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DocumentChangeObservationTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DocumentChangeObservationTests.swift` | Cancellation races, cleanup idempotency, date filtering |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift` | Replacement hooks and same-path watcher baselines |

Scoped footprint: 10 source files and 5 test files listed above, with both platform copies counted. History over those paths on `origin/main` has 6 distinct nonbot human author labels; aliases may overlap, so this is a knowledge-concentration proxy, not a people count. Helper/channel tests check local rules and races, not live iCloud notification delivery. Use [Testing](../how-to-contribute/testing.md) for supported-runtime verification and [Dart boundary](../systems/dart-boundary.md) for stream internals.
