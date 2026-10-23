# Contributing

Contribute focused improvements to public validation, local file operations, and the Flutter platform boundary. Start with `AGENTS.md`: this plugin does not own Apple's iCloud synchronization lifecycle.

## Choose work and find its owner

Describe the observable problem before choosing an implementation. Is it an invalid argument, a local file-operation failure, an incorrect channel result, an observation-lifetime problem, or example-app behavior? A delayed metadata update or a file not being `.current` is not, by itself, a plugin error (`AGENTS.md`).

| Change | Start here | Implementation entry points |
| --- | --- | --- |
| Public API, paths, or channel decoding | [Dart boundary](../systems/dart-boundary.md) | `lib/icloud_storage.dart`, `lib/icloud_storage_platform_interface.dart`, `lib/icloud_storage_method_channel.dart` |
| Local reads, writes, or mutations | [Native files](../systems/native-files/index.md) and [File access](../features/file-access.md) | `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` |
| Listing or observation | [Listing and metadata](../features/listing-and-metadata.md) and [Document observation](../features/document-observation.md) | Both native plugin routers and their Foundation helpers |
| Explicit version operations | [Conflict versions](../features/conflict-versions.md) | `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift` |
| Demo UI or reproduction | [Example](../apps/example.md) | `example/lib/main.dart` and the relevant screen |

Keep unrelated files and local changes intact. Historical plans do not override current source or `AGENTS.md`. Ask for a decision when a change would alter the public contract, project scope, or ownership boundary; do not silently add a parallel API or compatibility shim.

## Ownership rules

The plugin owns container resolution, argument/path validation, local coordinated I/O, and the platform boundary. Native features need both iOS and macOS implementations. Apple owns synchronization, materialization, freshness, eviction, and document conflicts. Do not add readiness waits, sync deadlines, polling, retry schedulers, conflict selection, or telemetry (`AGENTS.md`).

For uncertain platform behavior, consult the live official documentation linked by `AGENTS.md`. Use [Patterns and conventions](patterns-and-conventions.md) for implementation conventions rather than reinterpreting historical designs.

## Pull request expectations

A useful PR explains the problem, the changed local behavior, affected platforms, and verification. Include a minimal reproduction for a bug and identify any approved public-contract change with caller migration guidance. Preserve native error context rather than replacing actual failures with generic lifecycle errors (`AGENTS.md`, `lib/models/exceptions.dart`).

Report commands run, outcomes, and checks unavailable in your environment. For native runtime evidence, describe the Apple target and capture Flutter debug/platform logs. Do not present unit tests as proof of iCloud propagation. Docs-only edits need source/link/content checks, not unrelated product-test runs.

Review automation is defined in `.github/workflows/factory-review.yml`; release versioning is managed by `.github/workflows/release-please.yml` and publication is separate in `.github/workflows/publish.yml`. See [Distribution and automation](../deployment.md). Those files do not establish required reviewers or branch-protection settings.

## Definition of done

- The change stays within the approved ownership boundary and scope.
- Affected public contracts, examples, and documentation agree; both native platforms are addressed when relevant.
- Appropriate [tests and runtime checks](testing.md) are complete, with failures or unavailable checks clearly reported.
- The diff contains no unintended files, private production details, or telemetry additions.
- User-visible release notes are recorded in `CHANGELOG.md` when appropriate; publication is not implied by opening a PR.

Continue with [Development workflow](development-workflow.md), [Debugging](debugging.md), or [Tooling](tooling.md).
