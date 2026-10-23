# Debugging

Find the failing layer before changing policy: app configuration, public validation, channel setup, native local I/O, or observation lifetime. Metadata lag and materialization state are not plugin-created errors (`AGENTS.md`).

## 1. Confirm the Apple target and container

Reproduce on a supported iOS/macOS target. Check `ICloudStorage.icloudAvailable()` before file operations. Both native implementations answer by checking whether `FileManager.default.ubiquityIdentityToken` is non-nil; that is not proof that a particular container identifier or path is accessible (`ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`).

Verify the consuming app's App ID, signing, iCloud Documents capability, selected container, and the exact `containerId` passed to the plugin. For Files app visibility, also check the app's `NSUbiquitousContainers` declaration and the literal `Documents/` path prefix (`README.md`). Use [Configuration](../reference/configuration.md), not another app's signing identifiers.

Container lookup is single-shot and dispatched off the main thread. A nil result is a container-access problem to investigate, not a reason to install a polling/readiness engine (`ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift`, `AGENTS.md`).

## 2. Classify the actual failure

| Symptom | Inspect |
| --- | --- |
| `InvalidArgumentException` before native work | The path/name or synchronous-listener rules in `lib/icloud_storage.dart` and `lib/src/synchronous_stream_bridge.dart`. Distinguish file-centric trailing-slash rejection from directory-oriented calls. |
| `ICloudOperationException` with category `pluginContract` | Plugin registration, missing native implementation, reply types/nullability, malformed list entries, or invalid event data in `lib/icloud_storage_method_channel.dart`. |
| Typed container, item-not-found, coordination, or native I/O exception | Preserve the failing operation and original native context; follow the native handler, not download-status heuristics. |
| Empty/stale metadata or no progress event, without an operation error | Identify which query produced the observation before concluding that local I/O failed. See step 4. |

`lib/models/exceptions.dart` exposes `operation`, `category`, `message`, `retryable`, `relativePath`, `pathKind`, `nativeDomain`, `nativeCode`, `nativeDescription`, and `underlying` when available. `lib/src/platform_exception_decoder.dart` decodes those fields; a details-less failure can have operation `unknown` and an unknown-native subtype. The exception's `toString()` only prints category/message, so inspect the fields when native context matters.

Both native routers include native domain/code/description and underlying-error context when constructing enriched Flutter failures. Preserve that evidence in a reproduction; do not replace it with “iCloud not ready.” The `retryable` field is a hint, not an installed retry scheduler. See [Data models](../reference/data-models.md).

For reads, use available local bytes, including offline. If bytes are absent, let the actual Foundation/document operation fail; do not synthesize errors from `.notDownloaded`, `.downloading`, or not-`.current` metadata. Writes likewise perform the local operation without a plugin-owned freshness wait (`AGENTS.md`, `lib/icloud_storage_platform_interface.dart`).

## 3. Check listener attachment and transfer failure delivery

Attach listeners inside `onUpdate`, `onChange`, or `onProgress` before the callback returns. Saving the stream for later or ignoring it fails before native allocation. Retain the subscription and cancel it when its owner is disposed (`lib/src/synchronous_stream_bridge.dart`).

For upload/download, inspect both stream `onError` and the returned Future:

- A native transfer failure delivered to an active progress listener is not thrown again by the method Future.
- If the listener is paused or canceled before that failure is delivered, the Future carries the native transfer failure instead.
- Setup and plugin-contract failures remain Future failures; do not assume that attaching progress makes the Future infallible.
- Canceling progress observation does not cancel the underlying local transfer. A synchronous progress cancellation can leave the transfer running without progress.

These decisions are implemented in `lib/icloud_storage_method_channel.dart` and `lib/src/synchronous_stream_bridge.dart` and exercised by `test/icloud_storage_method_channel_test.dart`. The detailed flow is in [Dart boundary](../systems/dart-boundary.md).

For a missing document-change event, check registration/subscription lifetime and platform-specific filtering rather than assuming every callback represents a remote edit. See [Document observation](../features/document-observation.md) and [Queries and presenter lifecycle](../systems/native-files/observation-lifecycle.md).

## 4. Separate metadata discovery from local files

After an awaited local rename/delete/copy, compare the relevant directory's `listContents` result with the `gather` snapshot. `gather` observes Apple's metadata index and can lag or include promises without a local representation; `listContents` enumerates direct local children and resolves placeholder names. Neither is a cloud-wide freshness oracle (`README.md`, both native plugin routers).

For a known path, use `documentExists`, whose native implementation uses `FileManager.fileExists(atPath:)`, rather than waiting for a metadata-query match. Existence does not prove readable bytes or current content. Use [Listing and metadata](../features/listing-and-metadata.md) to interpret these differences.

Do not add a sync deadline because a gather/progress stream is quiet. Apple's request to start downloading is not a promise that an item becomes `.current` within a plugin-defined interval (`AGENTS.md`).

## 5. Trace native work and collect evidence

Follow the operation from the platform router to its document/helper call site using [Native files](../systems/native-files/index.md) and [Local I/O](../systems/native-files/local-io.md). For mutations, distinguish waiting for an in-process path lane, entering coordination, staging/replacement, and the actual accessor error; do not treat all of them as synchronization.

In a debug session, capture the Flutter terminal output and platform console/debug logs from the same supported Apple run. Both native routers' `DebugHelper.log` prints only under `#if DEBUG`; absence of those lines in a release build is not evidence that a branch did not execute.

One current implementation detail matters when reading logs: upload and in-place write handlers catch proactive materialization-request failures, debug-log them, and continue to the local operation (both native plugin routers). The materializer helper itself throws a real request error (`macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift`). Do not mistake the logged request failure for the final operation result, or describe all helper errors as necessarily propagated. This existing catch/log behavior is in tension with `AGENTS.md`'s narrow failure-handling guidance; it is not a convention to extend.

Record the target/OS, build mode, container configuration, exact API and sanitized paths, subscription state, local operation result, typed error fields, and reproduction sequence. Keep private paths/content out of public reports. Capture logs for diagnosis without adding Sentry, breadcrumbs, or a plugin telemetry pipeline (`AGENTS.md`).

Use [Testing](testing.md) to turn a verified plugin-owned bug into the appropriate regression check. Local tests and logs still do not prove Apple's sync scheduling or cross-device completion.
