# iCloud Storage Plus

This is a Flutter plugin for local file operations in an Apple-managed iCloud
Drive ubiquity container on iOS and macOS. App UI, theming, routing, and telemetry
policy are out of scope except when editing the example app.

## Ownership

The plugin owns container resolution, public argument and path validation,
local file operations, and the Dart/Flutter platform boundary. Resolve the
container off the main thread and prevent access outside it. Coordinate document
operations with Foundation APIs such as `NSFileCoordinator`, `UIDocument`, or
`NSDocument` where appropriate. Update both iOS and macOS for native features.

Apple owns sync scheduling, retries, materialization, upload/download state,
metadata freshness, eviction, and document conflicts. Do not introduce a sync
engine, readiness engine, retry scheduler, freshness policy, conflict manager,
stale-write guard, compare-before-write protocol, or telemetry pipeline.

`startDownloadingUbiquitousItem(at:)` requests local materialization. It does not
promise that an item becomes `.current` within a plugin-defined deadline.
Do not add timeouts, watchdogs, polling loops, or status APIs to enforce one.

For reads, use the local bytes Apple makes available. Offline operation is not
a failure when local bytes exist. If bytes are absent, let the actual Foundation
operation determine the outcome. For writes and replaces, perform the local
coordinated operation without plugin-owned `.current` waits.

Check iCloud availability with `icloudAvailable()` before operations. Use
`FileManager.fileExists(atPath:)` on the container URL for existence checks,
not `NSMetadataQuery`.

## Errors and public contracts

Report failures the plugin owns: invalid arguments, unsupported platforms,
method-channel contract violations, container resolution, path validation, and
actual Foundation/file operation failures.

Downloading, uploading, eviction, placeholders, metadata lag, and an item not
being `.current` are not plugin-created errors. Do not wrap them in exceptions,
demote them to warnings, or capture and ignore them. Remove those error paths.
Do not add Sentry reporting, breadcrumbs, or app telemetry to this public plugin.

When native failure translation is required at the Flutter boundary, catch
narrowly and preserve the original native domain, code, and details. Do not
catch merely to log or satisfy a typed-exception convention.

Do not introduce broad state/error taxonomies, result models, companion status
APIs, channel payload contracts, compatibility shims, or duplicate APIs without
an explicit request for that design. If the approved public contract changes,
update it directly and require callers to update.

Keep private app names, private Sentry events, and private production telemetry
out of public documentation and plans.

## Decisions and completion

Before designing iCloud policy, distinguish a local file operation from an
attempt to manage Apple's sync lifecycle. For uncertain Apple behavior, consult
[Apple's Foundation/iCloud documentation](https://developer.apple.com/documentation/foundation/icloud).
Verify unfamiliar APIs against official documentation for the resolved version.

Complete requested changes through affected local checks and fix failures caused
by the change without asking for approval at each step. Report unrelated failures
without expanding scope. Ask only when a missing decision changes the public
contract, project scope, or approved ownership boundary.


For Flutter widget, layout, or platform behavior, use the
[Flutter docs](https://docs.flutter.dev/) and [API reference](https://api.flutter.dev/).
For Dart language or core-library behavior, use the
[Dart language docs](https://dart.dev/language) and [API reference](https://api.dart.dev/).
For plugin platform boundaries, use the
[Flutter plugin docs](https://docs.flutter.dev/packages-and-plugins/developing-packages).
For package APIs, use `https://pub.dev/documentation/PACKAGE/VERSION/` with the
resolved version in `pubspec.lock`. Use live official docs, not downloaded copies.

## Verification

Unit tests should check real plugin rules and edge cases, not repeat their own
setup or implementation. They do not prove end-to-end native file behavior.
For runtime verification, exercise the example app on a supported physical
device or simulator while capturing debug and platform logs. Use
[Patrol](https://patrol.leancode.co/documentation) for repeatable Flutter/native
integration tests, [Marionette](https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md)
for widget-key-based interaction with a running debug app, or computer use.
Choose the method that proves the changed behavior; do not require every method.

Use `flutter analyze`, `flutter test`, and targeted native tests for native code
that changed. Example-app changes may need widget or integration tests.
Generate code only when changed generated inputs require it.

Tests should cover argument validation, path handling, method-channel behavior,
and local file-operation decisions. Do not invent native payload-emission tests,
channel payload contracts, or sync simulations for Apple-owned behavior. Do not
require top-level `swift build` unless the changed code belongs to a Swift package
that supports it. Do not require post-release Sentry validation for this plugin.

Preserve unrelated files and local changes. Keep Dart API and platform ownership
separate; platform implementations extend the platform interface and verify its
token. Follow the repository's existing analysis configuration.
