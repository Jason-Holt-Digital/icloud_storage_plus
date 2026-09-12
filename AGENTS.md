# iCloud Storage Plus

## Project Overview

iCloud Storage Plus is a Flutter plugin for accessing files in an iCloud Drive
ubiquity container on iOS and macOS. The container is a local filesystem
location managed by Apple. This project is not a sync service, cloud storage
client, conflict resolver, or iCloud daemon replacement.

This fork focuses on correct local file access using Foundation APIs such as
`FileManager`, `NSFileCoordinator`, `UIDocument`, and `NSDocument`.

## Scope

This repository is a Flutter plugin, not a Flutter app. UI/widget, theming,
routing, telemetry policy, and app state guidance are out of scope unless you
are editing the example app.

## Completion

Complete the requested plugin change and affected checks. Fix failures caused
by the change and rerun affected checks without asking at each step. Report
unrelated failures separately. Ask when a missing decision changes the public
contract or supported platforms; continue independent work while it is pending.

## Plugin Structure

- **lib/**: Dart API layer
  - `icloud_storage.dart`: Main public API
  - `icloud_storage_platform_interface.dart`: Platform interface definition
  - `icloud_storage_method_channel.dart`: Method channel implementation
  - `models/`: Data models and exceptions
- **ios/icloud_storage_plus/Sources/icloud_storage_plus/**: iOS implementation
- **macos/icloud_storage_plus/Sources/icloud_storage_plus/**: macOS implementation

## Flutter/Dart Plugin Rules

1. Prefer federated plugin architecture: app-facing API + platform interface + platform implementations.
2. Platform implementations must `extend` the platform interface (do not `implement`) and verify tokens via `PlatformInterface.verifyToken`. Use `MockPlatformInterfaceMixin` in tests that mock the interface.
3. Keep `flutter.plugin.platforms` in `pubspec.yaml` accurate (per-platform `pluginClass`, Android `package`, web `fileName`). For federated packages, use `implements` and endorse with `default_package` where applicable.
4. For native bindings, prefer `flutter create --template=package_ffi` (recommended since Flutter 3.38). Treat `plugin_ffi` as legacy.
5. If iOS + macOS implementations are shared, consider `sharedDarwinSource: true` and move sources to `darwin/`, updating podspec dependencies/targets accordingly.
6. iOS/macOS code must use background queues (avoid blocking main thread).
7. Translate actual API-boundary failures only when the Flutter method-channel
   contract requires it. Do not catch low-level filesystem behavior merely to
   log, report, wrap, demote, or reclassify it.
8. When adding native functionality, update both iOS and macOS implementations.
9. Check iCloud availability with `icloudAvailable()` before operations.

## iCloud Drive Boundary

iCloud Drive is a local ubiquity folder whose sync lifecycle is owned by Apple.
Treat it like a
local folder with Apple-managed materialization, metadata, freshness, upload,
download, and conflict behavior.

The plugin owns:

- resolving the ubiquity container URL off the main thread;
- validating caller arguments and preventing paths outside the container;
- performing local reads, writes, replaces, deletes, and existence checks;
- using `NSFileCoordinator`, `UIDocument`, or `NSDocument` where appropriate;
- exposing a small Dart API that maps to those local file operations.

Apple owns:

- iCloud Drive sync scheduling and retries;
- whether a file is downloaded, downloading, uploaded, current, evicted, or a
  placeholder;
- network, account, quota, server, and File Provider daemon behavior;
- conflict detection and resolution for iCloud documents;
- metadata freshness and propagation timing.

Do not write plugin code that pretends to own Apple's responsibilities. In
particular, do not create a sync engine, readiness engine, retry scheduler,
freshness policy, conflict manager, compare-before-write protocol, or telemetry
pipeline.

`startDownloadingUbiquitousItem(at:)` is an Apple request to materialize an
iCloud item locally. It is not a plugin-owned contract that the item must become
`.current` within an artificial deadline. Do not wrap it in custom timeout
machinery.

## iCloud Readiness Is Not A Plugin Error

Normal iCloud Drive lifecycle behavior must not become plugin error reporting.
Do not add artificial timeouts, watchdogs, polling loops, exception wrappers, or
Sentry-style reporting for cases like:

- an item is not downloaded yet;
- an item is downloaded locally but not `.current`;
- an item is downloading, uploading, evicted, pending, or a placeholder;
- metadata lags behind filesystem changes;
- the app is offline but local bytes are available;
- Apple has not finished materializing or refreshing the file yet.

Do not solve these by "capturing but ignoring" an error. Do not "demote" them
to warnings. Remove the useless error path entirely.

For reads, prefer the boring filesystem meaning: read the local file Apple makes
available. If local bytes exist, offline mode is not a plugin failure. If local
bytes do not exist, let the underlying Foundation/file operation outcome drive
the result; do not invent `ICloudStorageTimeout`, "not current", or
"readiness failed" exceptions.

For writes and replaces, perform the local coordinated operation. Do not block on
plugin-owned `.current` waits or invent stale-write guards. iCloud document sync
and conflict handling are Apple's layer.

## Error Handling Policy

The plugin should report only errors it can honestly own:

- invalid public API arguments;
- unsupported platform or method-channel contract violations;
- inability to resolve the ubiquity container;
- path validation failures;
- actual Foundation/file operation failures returned by the operation being
  performed.

Everything else is either normal iCloud Drive lifecycle or an Apple/system
failure. Do not add app telemetry, Sentry reporting, diagnostic breadcrumbs, or
custom exception types for those cases inside this public plugin.

When native failure translation is unavoidable at the Flutter boundary, catch
narrowly and preserve the original native domain/code/details. Do not wrap just
to satisfy a typed-exception style. The rule is not "try/catch everything"; the
rule is "avoid manufacturing errors."

Do not introduce broad state/error taxonomies, result models, companion status
APIs, channel payload contracts, compatibility shims, or duplicate APIs unless
the user explicitly asks for that design. If the public contract is wrong,
change it directly and require callers to update.

When unsure about iCloud behavior, consult Apple's Foundation/iCloud Drive docs
(https://developer.apple.com/documentation/foundation/icloud) before designing
policy. Do not infer cloud-service semantics from other storage SDKs.

## Before Planning iCloud Work

When planning an iCloud change, classify the affected code as local file
operations or Apple-owned sync lifecycle. Keep local file operations. Remove
plugin-owned sync lifecycle work within the requested change.

Reject plans that add any of the following unless the user explicitly asks for
them by name:

- artificial timeouts for waiting on iCloud current/download/upload state;
- plugin-created readiness errors;
- post-release Sentry validation or app telemetry policy;
- private app references in public docs;
- new status/result APIs alongside old APIs;
- compatibility shims for contracts the project wants to break;
- channel payload contract documents;
- native payload-emission tests;
- top-level `swift build` gates for a Dart plugin;
- plugin-side conflict resolution or stale-write prevention.

## Dart API and tooling

- Use the existing `pubspec.yaml`, lockfile, and `analysis_options.yaml` for
  dependencies, resolved versions, and lint rules. Do not replace the lint
  configuration with a starter template or run broad automatic fixes.
- Follow Effective Dart and the repository's formatting and naming conventions.
  Keep public API documentation current. Keep lines within 80 characters and
  avoid trailing comments.
- Keep Dart API and platform responsibilities separate. Use `Future` for one
  asynchronous result and `Stream` for sequences. Preserve sound null safety.
- Catch narrowly where translation changes the result at a real API boundary;
  prefer specific `on` clauses and do not catch `Error` types.
- Use `FileManager.fileExists(atPath:)` on the container URL for existence
  checks. Do not use `NSMetadataQuery` for existence.
- Use the existing logging approach rather than `print`. The iCloud error
  policy above controls what may be logged or reported.
- Run code generation only when its inputs change and the package uses it.
- For dependency changes, use available package tooling or standard
  Flutter/Dart package commands. Explain why a new dependency is needed.

## Verification

Choose checks for the changed responsibility. Use the existing test libraries
and conventions; prefer fakes or stubs where a test needs a controlled boundary.
Widget and app integration checks apply only to example-app changes.
Documentation-only changes need document checks, not an app launch or full suite.

### iCloud Testing Guidance

This is a Flutter plugin. Use `flutter test`, `flutter analyze`, focused Dart
tests, and targeted native tests for native code that is actually changed. Do
not require top-level `swift build` checks for this Dart plugin unless the
changed code is in a Swift package that supports them.

Do not invent native payload-emission tests, method-channel payload contracts,
or sync simulations just to test Apple-owned lifecycle behavior. Tests should
verify the plugin's responsibility boundary: argument validation, path handling,
method-channel behavior, and local file-operation decisions.

Public documentation and plans in this repository must not reference private app
names, private Sentry events, or private production telemetry. Use those only as
private research inputs, not as public project context.
