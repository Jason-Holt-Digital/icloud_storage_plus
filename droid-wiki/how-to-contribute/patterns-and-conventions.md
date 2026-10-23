# Patterns and conventions

Changes should preserve a small ownership boundary: public validation, local coordinated file operations, and Flutter integration belong to the plugin. Apple's synchronization lifecycle does not (`AGENTS.md`).

## Ownership before implementation

Check iCloud availability before app operations. Use filesystem existence checks for local container paths. Read local bytes when available, including offline; let actual Foundation operations report missing bytes or I/O failures. Do not add readiness deadlines, polling loops, automatic retries, conflict selection, freshness rules, or telemetry.

Historical plans are context, not current requirements. `docs/plan/2026-05-26-fix-remove-icloud-readiness-timeout-layer-plan.md` records removal of a former readiness layer; current behavior is in source and `AGENTS.md`.

## Dart API and platform separation

Keep public path/name rules in `lib/icloud_storage.dart`, platform extension points in `lib/icloud_storage_platform_interface.dart`, and channel decoding in `lib/icloud_storage_method_channel.dart`. Implementations extend the platform interface and pass its token verification.

File-centric operations reject trailing slashes. Directory-oriented operations accept one trailing slash and validate the remaining path segments. Names cannot be empty, longer than 255 Dart string units, begin with `.`, or contain `:` or `/` (`lib/icloud_storage.dart`). Do not treat this lexical check as proof of filesystem-level symlink isolation.

## Native operation patterns

Update both `ios/` and `macos/` for native features. Container lookup is off the main thread and single-shot. Use the existing closure-injected seams for deterministic helper tests (`ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/UbiquityContainerResolver.swift`, `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/WriteEntrypointPreflight.swift`).

Acquire mutation lanes before coordination. Keep blocking Foundation coordination off Swift cooperative-pool threads. Existing-file replacement uses staging and coordinated replacement rather than remove-then-write, rejects directory destinations, and leaves version resolution to explicit callers (`ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/PerPathMutationLane.swift`, `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`).

## Errors and streams

Dart validation uses `InvalidArgumentException`; native and channel failures use `ICloudOperationException` and its subtypes (`lib/models/exceptions.dart`). Preserve native domain, code, description, and underlying context when translating a real error. Decode transport errors internally in `lib/src/platform_exception_decoder.dart`, rather than exposing Flutter transport decoding as public API.

Native success for void operations is `null`; a non-null value is a plugin-contract failure. List decoding is all-or-error, not partial success (`lib/icloud_storage_method_channel.dart`).

Attach stream listeners synchronously in callbacks. Cancel subscriptions when done. Cancellation stops observation; canceling transfer progress does not cancel the local transfer (`lib/src/synchronous_stream_bridge.dart`, `lib/icloud_storage_platform_interface.dart`).

## Coding principles

`AGENTS.md` records five approved working principles:

- Validate unknown values once at the boundary that owns them, then pass typed values inward. Do not defensively revalidate values already guaranteed by a schema, constructor, or internal type.
- Do not extract single-use helpers preemptively. Inline the logic at the call site unless the helper is reused, hides a genuinely complex boundary, or has a clear independent name that improves the caller.
- Before adding complexity for a speculative or vanishingly unlikely race or security edge case, explain the concrete failure mode, likelihood, and complexity cost and get buy-in. Do not silently expand scope for theoretical robustness.
- Test the actual implementation; do not duplicate logic into tests.
- Add comments for non-obvious constraints and surprising behavior, not for obvious assignments or control flow.

## Style and tests

The root analyzer includes `very_good_analysis` and excludes the nested example package (`analysis_options.yaml`). The example has its own configuration in `example/analysis_options.yaml`. Match surrounding code instead of adding new taxonomies or compatibility layers.

Tests should exercise real validation, channel behavior, path handling, and local operation decisions. Do not simulate Apple synchronization or add tests that only reproduce their own setup. Use [Testing](testing.md) to choose the smallest relevant check, then verify changed native behavior in an Apple runtime when needed.
