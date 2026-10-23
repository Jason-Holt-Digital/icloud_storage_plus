# Observation lifecycle
Active contributors: Jason, Erik

## Purpose

The native plugin retains metadata queries, document presenters, and event-channel registrations for different lifetimes. This page explains their ownership and teardown; [Listing and metadata](../../features/listing-and-metadata.md) and [Document observation](../../features/document-observation.md) describe their caller-facing use.

## Key abstractions

| Abstraction | Owns or coordinates |
| --- | --- |
| `MetadataQuerySession` | A query, notification observer tokens, cancellation, and completion of cleanup |
| `GatherSessionLifecycle` | Initial-snapshot completion versus optional update cancellation |
| `DocumentChangeRegistration` | Strong document/observation lifetime and idempotent cancellation |
| `DocumentChangeObservation` | Presenter start/cancel state and macOS modification-date filtering; it is not a file presenter |
| `EventChannelRegistration` | The Flutter channel, stream handler, and deferred unregistration handshake |
| `StreamEventDelivery` / `DeferredCancellationHandler` | Delivery-versus-cancellation ordering and cancellation before handler installation |
| `CompletionGate` | At-most-once native completion for the download flow |

## Key source files

| Source | Responsibility |
| --- | --- |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` | Query/session maps, gather and progress wiring, document/event registrations |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySession.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySession.swift` | Query start, observer-token ownership, cancellation and release |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySupport.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/MetadataQuerySupport.swift` | Shared scopes, gather lifecycle, completion gate |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/DocumentChangeObservation.swift` | Observation, deferred cancellation, stream delivery |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` | iOS presenter state-notification mapping |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift` | Passive macOS presenter setup, content-change coordination, baseline recording |

## Query ownership and cleanup

Each plugin has a UUID-keyed `metadataQuerySessions` map protected by a serial state queue. `makeMetadataQuerySession` inserts a session before starting it; its cleanup callback removes it only after query shutdown. The plugin's deinitializer cancels retained query sessions and document-change registrations (both plugin entry files).

`MetadataQuerySession` registers observer tokens for its specific query on the query's operation queue. A serial state queue protects cancellation and token ownership. `start` asynchronously hops to the main queue and checks cancellation before calling `query.start()`; the returned start boolean is not handled by a separate failure path. `cancel` is idempotent: it marks cancelled, removes tokens, then stops a started query on the main queue and invokes cleanup once. Adding an observer after cancellation removes its newly created token immediately (both query-session files).

The session owns resources, not a metadata freshness policy. It has no query deadline or polling loop. The common scopes include both `NSMetadataQueryUbiquitousDataScope` and `NSMetadataQueryUbiquitousDocumentsScope` (both metadata-support files).

### Gather

Gather assigns a serial, user-initiated `OperationQueue` to its query and filters `NSMetadataItemPathKey` with a string `beginswith` predicate for the resolved container path. This is the query's filter, not a general path-security check. Finish/update callbacks disable updates while mapping a full snapshot and re-enable them only if the session remains active. Flutter results/events are dispatched to the main queue (both plugin entry files).

| Lifecycle case | Cleanup decision |
| --- | --- |
| No registered update handler | Return initial snapshot, then cancel the query session |
| Active update handler | Return initial snapshot and retain the session for full-snapshot updates |
| Dart cancels updates before initial completion | Remove the stream handler, but keep the query until the initial result can complete |
| Dart cancels after initial completion | Cancel the query session and remove the stream handler |

`GatherSessionLifecycle` makes the initial-completion/cancellation rendezvous claim cleanup once. It is why cancelling the optional stream does not strand the initial gather method result (both metadata-support files and plugin entry files). Query results are metadata-index observations; the implementation does not establish a stronger cloud-wide consistency guarantee.

### Progress queries

Progress queries use `.main` as their operation queue and an exact path predicate. Upload monitoring starts **after** successful local copy-in; metadata progress reaching at least 100 ends its stream and cancels the session. No matching query result simply produces no progress event. There is no plugin-defined deadline for a silent or incomplete metadata query (both plugin entry files).

Download requests `startDownloadingUbiquitousItem`, optionally starts a progress query, and invokes document copy-out without waiting for a query status to become `.current`. Copy-out completion, not a progress notification, settles the method and closes its monitoring session. Cancelling the progress stream stops monitoring only; it does not cancel a copy-out already writing the local destination. `CompletionGate` prevents a second method completion, and per-channel progress state emits `max(newProgress, previousProgress)` (both plugin entry files and metadata-support files).

## Presenter registration

Watching requires a registered nonempty event-channel name. The plugin constructs an `ICloudDocument` for the requested URL, connects a `DocumentChangeObservation`, and retains both through `DocumentChangeRegistration`. Cancelling a matching registration stops the observation and clears its document reference to that observation. The identity check prevents an old cancellation callback from removing a newer registration under the same name (both plugin entry files).

`DocumentChangeObservation` has pending, starting, active, and cancelled states protected by a lock. Repeated start/cancel calls are ignored when inappropriate. Cancellation during a start is remembered; when the start hook returns, teardown runs once. A failed start does not leave an active observation. Delivery checks the lifecycle before creating its event (both observation helper files).

### iOS

The start/cancel hooks add and remove the existing `UIDocument` as an `NSFilePresenter`. `ICloudDocument` installs a `UIDocument.stateChangedNotification` observer for itself. Its state callback can emit conflict, saving-error, and editing-disabled notifications in one pass; it emits invalidation when no specific flag was handled. The watcher setup does not call document `open` or read content as part of registration (`ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`).

### macOS

macOS marks its `NSDocument` as a passive presenter. Startup synchronously coordinates a read, reads the file modification date, records the baseline, and adds the presenter. Because startup performs blocking work, the plugin invokes the observation start hook on a global worker, then returns the Flutter result on main (`macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`).

For passive `presentedItemDidChange`, the document dispatches coordinated reading to a global worker rather than blocking the presenter callback queue. It uses itself as the coordinator's presenter. Unresolved versions produce a conflict notification; otherwise a modification-date change consumed by the observation produces invalidation. Equal dates produce no invalidation; missing/unreadable dates are skipped. A coordination failure DEBUG-logs and emits invalidation. This is date-based notification filtering, **not** a read freshness check or stale-write guard (macOS document file).

For plugin content replacement, `coordinatedReplaceWriter(for:)` captures matching watchers, supplies one presenter to the writer, and records successful-write dates for distinct initial/current matching registrations. This reduces callbacks matching a successful plugin overwrite. It does not cover every possible mutation path and does not promise exactly-once external-change detection (`macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`). See [Local I/O](local-io.md) for replacement dispatch and the separate copy-overwrite implementation.

## Event-channel retirement

Both plugin files define the Flutter channel/handler classes. Event names cannot be reused while present in either the active or retiring registration map:

1. `createEventChannel` creates a channel, retains its handler, installs it, and returns success.
2. `removeStreamHandler` removes active registration/progress state and moves the registration to the retiring map.
3. `EventChannelRegistration` remembers whether Dart never listened, is listening, or has cancelled. A listening channel stays attached until cancellation is acknowledged.
4. A non-listening channel with no pending terminal events can detach immediately. A retained terminal sequence keeps a never-listened channel available for the listen/cancel handshake.
5. Detachment calls `setStreamHandler(nil)` on main and removes the matching retiring registration.

`StreamEventDelivery` drops ordinary events before a listener exists. It retains only a bounded terminal sequence of at most two events for a late listener; finishing is one-shot. Its recursive lock serializes cancellation and delivery, and cancellation clears the listener/pending events. This is not an unbounded replay buffer (both observation helper files).

`DeferredCancellationHandler` handles cancellation arriving before the operation installs its cleanup callback: it remembers the cancellation and returns the first subsequently installed handler for execution. Handler invocation happens outside the separate `StreamHandler` state queue. This addresses the gap between Flutter subscription setup and asynchronous container/query/presenter allocation (both plugin entry files and observation helper files). Dart's corresponding handshake is covered in [Dart boundary](../dart-boundary.md).

## Modification and validation

When adding an observer, use session-owned tokens and preserve the main-queue start/stop boundary. When changing a watcher, inspect both document implementations and cancellation-during-start behavior. When changing stream teardown, consider never-listened, late-listened, already-cancelled, and pending-terminal cases together.

The relevant tests are:

| Tests | Focus |
| --- | --- |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/MetadataQuerySessionTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/MetadataQuerySessionTests.swift` | Token cleanup, once-only completion, gather cancellation rendezvous |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DocumentChangeObservationTests.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DocumentChangeObservationTests.swift` | Observation state, date filtering, deferred cancellation, stream delivery |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift` | Presenter-owned local replacement and same-path watcher baseline behavior |

These tests do not simulate Apple's sync lifecycle or prove live Flutter/native presenter delivery. See [Testing](../../how-to-contribute/testing.md) for runtime verification and the [native section snapshot](index.md#subsystem-snapshot) for measured file/test and author-label counts.
