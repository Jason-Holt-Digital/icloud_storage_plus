# AGENTS.md

This file provides guidance to AI coding assistants that read `AGENTS.md` (for example, Cursor).

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

## Interaction Guidelines
* **User Persona:** Assume the user is familiar with programming concepts but may be new to Dart.
* **Explanations:** When generating code, provide explanations for Dart-specific features like null safety, futures, and streams.
* **Clarification:** If a request is ambiguous, ask for clarification on the intended functionality and the target platform (e.g., iOS, macOS, web).
* **Dependencies:** When suggesting new dependencies from `pub.dev`, explain their benefits.
* **Formatting:** Use the `dart_format` tool to ensure consistent code formatting.
* **Fixes:** Use the `dart_fix` tool to automatically fix many common errors, and to help code conform to configured analysis options.
* **Linting:** Use the Dart linter with a recommended set of rules to catch common issues. Use the `analyze_files` tool to run the linter.

## Plugin Structure

- **lib/**: Dart API layer
  - `icloud_storage.dart`: Main public API
  - `icloud_storage_platform_interface.dart`: Platform interface definition
  - `icloud_storage_method_channel.dart`: Method channel implementation
  - `models/`: Data models and exceptions
- **ios/Classes/**: iOS native implementation
- **macos/Classes/**: macOS native implementation

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

Assume every future agent will be tempted to misunderstand this: iCloud Drive is
a local ubiquity folder whose sync lifecycle is owned by Apple. Treat it like a
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

Before proposing or implementing an iCloud change, ask this first: is the code
handling a local file operation, or is it trying to manage Apple's sync
lifecycle? Keep local file operations. Delete plugin-owned sync lifecycle work.

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

## Package Management
* **Pub Tool:** To manage packages, use the `pub` tool, if available.
* **External Packages:** If a new feature requires an external package, use the `pub_dev_search` tool, if it is available. Otherwise, identify the most suitable and stable package from pub.dev.
* **Adding Dependencies:** To add a regular dependency, use the `pub` tool, if it is available. Otherwise, run `flutter pub add <package_name>`.
* **Adding Dev Dependencies:** To add a development dependency, use the `pub` tool, if it is available, with `dev:<package name>`. Otherwise, run `flutter pub add dev:<package_name>`.
* **Dependency Overrides:** To add a dependency override, use the `pub` tool, if it is available, with `override:<package name>:1.0.0`. Otherwise, run `flutter pub add override:<package_name>:1.0.0`.
* **Removing Dependencies:** To remove a dependency, use the `pub` tool, if it is available. Otherwise, run `dart pub remove <package_name>`.

## Code Quality
* **Code structure:** Adhere to maintainable code structure and separation of concerns (Dart API vs. platform code).
* **Naming conventions:** Avoid abbreviations and use meaningful, consistent, descriptive names for variables, functions, and classes.
* **Conciseness:** Write code that is as short as it can be while remaining clear.
* **Simplicity:** Write straightforward code. Code that is clever or obscure is difficult to maintain.
* **Error Handling:** Handle errors the plugin owns. Do not turn normal iCloud
  Drive lifecycle behavior into catch blocks, logs, warnings, retries, or custom
  exceptions.
* **Styling:**
  * Line length: Lines should be 80 characters or fewer.
  * Use `PascalCase` for classes, `camelCase` for members/variables/functions/enums, and `snake_case` for files.
* **Functions:** Keep functions short and single-purpose (strive for less than 20 lines).
* **Testing:** Write code with testing in mind. Use the `file`, `process`, and `platform` packages, if appropriate, so you can inject in-memory and fake versions of the objects.
* **Logging:** Use the `logging` package instead of `print`.
* **iCloud existence checks:** Use `FileManager.fileExists(atPath:)` on the
  container URL for existence checks. Do not use `NSMetadataQuery` for
  existence.

## Dart Best Practices
* **Effective Dart:** Follow the official Effective Dart guidelines (https://dart.dev/effective-dart)
* **Class Organization:** Define related classes within the same library file. For large libraries, export smaller, private libraries from a single top-level library.
* **Library Organization:** Group related libraries in the same folder.
* **API Documentation:** Add documentation comments to all public APIs, including classes, constructors, methods, and top-level functions.
* **Comments:** Write clear comments for complex or non-obvious code. Avoid over-commenting.
* **Trailing Comments:** Don't add trailing comments.
* **Async/Await:** Ensure proper use of `async`/`await` for asynchronous operations.
  * Use `Future`s, `async`, and `await` for asynchronous operations.
  * Use `Stream`s for sequences of asynchronous events.
* **Null Safety:** Write code that is soundly null-safe. Leverage Dart's null safety features. Avoid `!` unless the value is guaranteed to be non-null.
* **Pattern Matching:** Use pattern matching features where they simplify the code.
* **Records:** Use records to return multiple types in situations where defining an entire class is cumbersome.
* **Switch Statements:** Prefer using exhaustive `switch` statements or expressions, which don't require `break` statements.
* **Exception Handling:** Use `try-catch` only where it changes the outcome at a
  real API boundary. Prefer specific `on` clauses; avoid catching `Error` types.
  Do not add custom exceptions for Apple-owned lifecycle behavior.
* **Arrow Functions:** Use arrow syntax for simple one-line functions.

## Lint Rules

Include the package in the `analysis_options.yaml` file. Use the following
analysis_options.yaml file as a starting point:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    # Add additional lint rules here:
    # avoid_print: false
    # prefer_single_quotes: true
```

## Code Generation
* **Build Runner:** If the project uses code generation, ensure that `build_runner` is listed as a dev dependency in `pubspec.yaml`.
* **Code Generation Tasks:** Use `build_runner` for all code generation tasks, such as for `json_serializable`.
* **Running Build Runner:** After modifying files that require code generation, run the build command:

```shell
dart run build_runner build --delete-conflicting-outputs
```

## Testing
* **Running Tests:** To run tests, use the `run_tests` tool if it is available, otherwise use `flutter test`.
* **Unit Tests:** Use `package:test` for unit tests.
* **Widget Tests:** Use `package:flutter_test` for widget tests (only for example app changes).
* **Integration Tests:** Use `package:integration_test` for integration tests (only for example app changes).
* **Assertions:** Prefer using `package:checks` for more expressive and readable assertions over the default `matchers`.

### Testing Best Practices
* **Convention:** Follow the Arrange-Act-Assert (or Given-When-Then) pattern.
* **Mocks:** Prefer fakes or stubs over mocks. If mocks are absolutely necessary, use `mockito` or `mocktail` to create mocks for dependencies.
* **Coverage:** Aim for high test coverage on the Dart API layer.

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
