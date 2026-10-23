# Trust boundaries

The important boundaries are caller-provided paths, app entitlements, Flutter transport values, and native file access. The repository requires operations to remain inside the requested container, but documentation must not equate lexical validation with a verified filesystem sandbox (`AGENTS.md`, `lib/icloud_storage.dart`).

## Public path validation

The facade in `lib/icloud_storage.dart` splits relative paths into segments and validates each name. It rejects empty segments, dot-prefixed names, names longer than 255 Dart string units, `:`, and embedded `/`. This blocks ordinary absolute paths, `.`/`..` segments, and hidden names through the public facade.

Directory-oriented operations allow one trailing slash; file-centric operations reject it. Local transfer paths are checked for non-empty text, not constrained to the ubiquity container, because copy-in and copy-out intentionally cross that boundary.

These checks are not a complete native defense against hostile channel callers or pre-existing symlinks. `WriteEntrypointPreflight.itemURL` and `prepare` append the path to the resolved container URL and can create parent directories. They do not establish a canonical, symlink-resolved containment proof (`ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/WriteEntrypointPreflight.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/WriteEntrypointPreflight.swift`).

`PerPathMutationLane.normalizationKey` uses standardized path strings for serialization. It is not an authorization check and should not be described as a symlink security boundary (`ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/PerPathMutationLane.swift`).

## App permissions and caller-owned destinations

Container resolution depends on the consuming app's Apple account, signing, and entitlements. The example's container arrays are empty until configured; macOS host entitlements enable App Sandbox (`example/ios/Runner/Runner.entitlements`, `example/macos/Runner/Release.entitlements`).

Transfer destinations and conflict-version copy destinations are app-chosen local paths. They intentionally do not use container-relative semantics. Callers must choose authorized paths and protect backups according to their own app requirements (`lib/icloud_storage.dart`).

The plugin exposes version primitives only on explicit calls. It does not select a winner, silently delete losing versions during writes, or treat normal materialization state as an authorization failure. See [Conflict versions](features/conflict-versions.md).

## Transport validation

The adapter rejects unexpected result types, malformed list entries, unsupported metadata/event enum values, and non-null void success. Missing native implementations become plugin-contract errors (`lib/icloud_storage_method_channel.dart`).

Public exception models can contain native error descriptions, relative paths, and underlying details. Do not automatically forward those values to a telemetry service or include document contents in logs. The plugin must not add an app telemetry pipeline (`lib/models/exceptions.dart`, `AGENTS.md`).

## Automation

The newer Factory review and mention workflows check actor permissions and same-repository PR state before running writable actions. Issue triage separates a read-only classification job from a bounded comment-publishing job. The wiki refresh similarly separates generation from the job that updates a rolling documentation branch (`.github/workflows/factory-review.yml`, `.github/workflows/factory-mentions.yml`, `.github/workflows/factory-triage.yml`, `.github/workflows/droid-wiki-refresh.yml`).

Older `droid` workflows remain separate definitions; do not assume newer gates cover them. No environment configuration or secret values were inspected for this wiki. See [Distribution and automation](deployment.md) for trigger and rollout details.
