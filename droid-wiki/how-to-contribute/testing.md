# Testing

Choose tests by the rule or local operation being changed, then collect Apple-runtime evidence where needed. Unit tests do not establish end-to-end native iCloud behavior (`AGENTS.md`).

## Dart test layers

The root `test/` directory contains five Dart test files:

| Test source | Mechanism and coverage |
| --- | --- |
| `test/icloud_storage_test.dart` | Replaces `ICloudStoragePlatform.instance` with a fake using `MockPlatformInterfaceMixin`. Exercises facade delegation, invalid paths, file-centric trailing-slash rejection, directory-path acceptance, rename-to-move path derivation, typed nullable metadata, and listing/status helpers. |
| `test/icloud_storage_method_channel_test.dart` | Initializes Flutter's test binding and installs handlers on `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger`. Uses `MockStreamHandler` for dynamic event channels. Exercises actual Dart channel adaptation against simulated replies/events, not Swift. |
| `test/models/exceptions_test.dart` | Constructs advertised native-error subtypes and checks category and normalized context fields. |
| `test/models/icloud_file_test.dart` | Checks equality/hash behavior across fields and nullable values, required-path rejection, and normalized download-status distinctions. |
| `test/models/icloud_item_metadata_test.dart` | Checks typed field/date decoding, derived `isLocal`, normalized statuses, and rejection of a present optional boolean with the wrong type. |

The fake-platform tests stop before method-channel serialization. Messenger tests execute `lib/icloud_storage_method_channel.dart`, including its decoder and stream bridge, but their responses are supplied by Dart test code. Neither layer invokes `UIDocument`, `NSDocument`, or a live ubiquity container. See [Dart boundary](../systems/dart-boundary.md) and [Data models](../reference/data-models.md).

### Channel edge cases worth preserving

`test/icloud_storage_method_channel_test.dart` covers:

- Synchronous listener attachment before native allocation; ignored/delayed listeners fail, and a throwing callback does not allocate native resources.
- Unique event-channel names for concurrent gathers and cancellation races during allocation.
- Required non-null reads, `null` success for void methods, wrong reply types, missing plugins, and whole-result failure for malformed list entries.
- Native error decoding with preserved context, details-less failures, and unknown future categories.
- Transfer progress/error/completion mapping, delivery-versus-Future failure arbitration, paused/canceled listener fallback, and setup failures.
- Typed document-change events, invalid payload/kind rejection, failed-start cleanup, and explicit conflict-version method arguments/defaults.

These are tests of existing boundary behavior, not a request to invent a new native payload API or simulate Apple's synchronization (`AGENTS.md`).

## Native Foundation harnesses

The nested manifests `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Package.swift` and `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Package.swift` each define a Foundation library and XCTest target. They compile helper sources from that directory without the Flutter plugin router/document target. Both declare Swift tools 5.9 and Apple platform floors.

Representative tests illustrate several different kinds of evidence:

| Test source | What it exercises |
| --- | --- |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquityContainerResolverTests.swift` | Closure-injected container lookup, one lookup on success/nil, and the live off-main-thread execution hop. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/WriteEntrypointPreflightTests.swift` | Injected resolver/directory creation, off-main work, nil-container errors, and skipping parent creation for a read-style lookup. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/PerPathMutationLaneTests.swift` | Same/equivalent-path exclusion, distinct-path overlap, two-endpoint locking, queued cancellation, lane reclamation, post-error reuse, and a dispatch-backed coordination stress case. |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift` | Injected verification/coordination/replacement/cleanup seams plus real temporary-file replacement and presenter checks. Separates coordinator failures from inner I/O failures and checks accessor-supplied destination URLs. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/MetadataQuerySessionTests.swift` | Observer cleanup, once-only completion, and initial-gather/update-cancellation ordering, including concurrent claims. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/DocumentChangeObservationTests.swift` | Observation start/cancel races, repeated teardown, date-baseline filtering, deferred cancellation, and bounded terminal-event delivery. |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/UbiquitousItemMaterializerTests.swift` | Injected materialization-request decisions and thrown request errors, without waiting for a real download. |

Corresponding suites exist under `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/` and `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/`; run both affected copies. Follow [Local I/O](../systems/native-files/local-io.md) and [Queries and presenter lifecycle](../systems/native-files/observation-lifecycle.md) for the production call paths.

Some replacement tests inspect source text, such as checking for prohibited helper entry points or version-removal calls. Those assertions check source structure, not runtime execution. Even real local Foundation replacement tests do not prove Flutter registration, live iCloud presenter delivery, cloud conflict behavior, or cross-device propagation.

## Commands

From the repository root, with Flutter available:

```bash
flutter pub get
flutter analyze
flutter test
```

For a narrower iteration, select an affected file:

```bash
flutter test test/icloud_storage_method_channel_test.dart
flutter test test/models/icloud_item_metadata_test.dart
```

On a Mac with a compatible Swift/Xcode toolchain, from the repository root:

```bash
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation
```

To focus one suite, append `--filter PerPathMutationLaneTests` to the relevant command. These are Darwin Foundation harnesses; Linux Swift is not a substitute. Do not require a top-level `swift build` of the Flutter plugin packages as a replacement for these checks (`AGENTS.md`).

For example changes, fetch dependencies and run `flutter analyze` from `example/` independently; root analysis excludes it (`analysis_options.yaml`, `example/analysis_options.yaml`). Docs-only edits need source/link/diff validation, not product tests.

## Supported-target verification

There are no checked-in example widget or integration tests. `example/pubspec.yaml` declares `flutter_test`, but not an installed Patrol or Marionette setup. `AGENTS.md` recommends [Patrol](https://patrol.leancode.co/documentation), [Marionette](https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md), or computer use: choose the method that proves the change, rather than requiring every tool.

Configure the example's signing, iCloud container, and entitlements, then run it on a supported physical Apple device or simulator and capture Flutter debug/platform logs. The demo does not expose every public API; a change to in-place content, document observation, or conflict versions may need a focused reproduction beyond its existing screens (`example/lib/main.dart`). See [Example](../apps/example.md) and [Debugging](debugging.md).

Report local operation outcomes separately from metadata hints. Do not introduce sync simulations, `.current` deadlines, or tests asserting that Apple must finish propagation within a plugin-defined interval.
