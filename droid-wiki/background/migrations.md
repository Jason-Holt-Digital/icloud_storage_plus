# Migrations

Recent breaking changes narrowed the plugin to local file operations and made the Dart boundary more explicit. Update callers and custom platform implementations directly instead of adding compatibility shims (`README.md`, `AGENTS.md`).

## Readiness removal, May 2026

The change dated 2026-05-26 removed the plugin's readiness/timeout layer, followed by the 2.2.0 release. Reads and writes no longer wait for a metadata state to become current within a plugin-defined deadline (`346b08a`, `ecb9295`, `CHANGELOG.md`).

Callers must remove `idleTimeouts` and `retryBackoff` from in-place reads. Former timeout, item-not-downloaded, and download-in-progress exception APIs were removed rather than replaced by a new status/result API (`README.md`).

Do not implement a readiness loop in a replacement helper. Materialization requests can still ask Apple for content; available local bytes and actual Foundation outcomes determine local read behavior. The detailed removal rationale is in `docs/plan/2026-05-26-fix-remove-icloud-readiness-timeout-layer-plan.md`.

## Explicit versions, June 2026

On 2026-06-19, commit `938e5a5` removed automatic conflict resolution, exposed `NSFileVersion` primitives, and added per-path mutation lanes. The API now lets the app enumerate versions, preserve selected bytes at an explicit destination, and mark versions resolved only when requested (`lib/icloud_storage.dart`, `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/VersionExposure.swift`).

This was an ownership change, not a new conflict manager. Ordinary local writes no longer pick a winner or remove losing versions. See [Conflict versions](../features/conflict-versions.md).

Document-change observation arrived on 2026-06-22 (`f9515d7`), followed by preparation of 3.0.0 on 2026-06-24 (`084ea51`). Events are refresh hints, not a real-time collaboration protocol or evidence of remote authorship. See [Document observation](../features/document-observation.md).

## Typed boundary, July 2026

The 4.0.0 release on 2026-07-19 (`150174f`) changed caller and implementer contracts:

| Before | Current requirement |
| --- | --- |
| Nullable content-read expectations | Successful `readInPlace` and `readInPlaceBytes` return non-nullable values; catch a missing-item exception for an optional domain outcome |
| Raw metadata maps in platform implementations | Return `Future<ICloudItemMetadata?>` |
| Public transport-coupled exception construction | Construct operation exceptions from normalized fields; transport decoding is internal |
| Non-null native success values for void methods | Return `null`; the Dart adapter rejects non-null void success |

The current signatures are in `lib/icloud_storage_platform_interface.dart`; enforcement is in `lib/icloud_storage_method_channel.dart`. The error model lives in `lib/models/exceptions.dart`, with internal decoding in `lib/src/platform_exception_decoder.dart`.

Strict decoding fails complete malformed snapshots instead of silently dropping entries. A failure at that boundary is a plugin-contract problem, not a reason to reinterpret ordinary iCloud lifecycle metadata as an exception.

## Porting checklist

Update public calls, custom platform implementations, fakes, and method-channel mocks together. Keep native production source lists aligned in both SwiftPM manifests and podspecs when adding or removing a helper. Recheck path rules and synchronous stream listeners in [Dart boundary](../systems/dart-boundary.md), then use [Testing](../how-to-contribute/testing.md) for proportionate verification.
