# iCloud Storage Plus

iCloud Storage Plus is a Flutter plugin for local file operations inside an Apple-managed iCloud Drive ubiquity container. It supports iOS 13 and macOS 10.15 or later, with a Dart API and Swift implementations on both platforms (`pubspec.yaml`, `ios/icloud_storage_plus.podspec`, `macos/icloud_storage_plus.podspec`).

## What it does

The public facade in `lib/icloud_storage.dart` provides:

- Path-only copy-in and copy-out for large files.
- In-place text and binary reads and writes for small files.
- Delete, move, rename, copy, and filesystem existence checks.
- Metadata discovery, immediate directory listing, and document-change observation.
- Explicit access to unresolved conflict versions.

Apple owns synchronization, materialization, metadata freshness, eviction, and document conflicts. Successful local operations do not promise that another device has received the change. The plugin does not run a sync scheduler or impose a deadline for an item to become current (`AGENTS.md`).

## Where to start

| Goal | Page |
| --- | --- |
| Configure a consuming app | [Getting started](getting-started.md) |
| Understand the platform boundary | [Architecture](architecture.md) |
| Choose a file API | [File access](../features/file-access.md) |
| Choose a listing API | [Listing and metadata](../features/listing-and-metadata.md) |
| Observe existing documents | [Document observation](../features/document-observation.md) |
| Inspect conflict versions | [Conflict versions](../features/conflict-versions.md) |
| Change or test the plugin | [Contributing](../how-to-contribute/index.md) |

## Repository map

`lib/` contains the public API, typed models, and method/event-channel adapter. `ios/` and `macos/` contain native document implementations and Foundation helpers. `example/lib/` is the interactive demonstration app. `test/` and the native Foundation package test directories check plugin-owned rules. See [Systems](../systems/index.md) for implementation entry points.

This wiki describes the checked-out source, not a guarantee about iCloud network behavior. Historical design notes in `ai_specs/` and `docs/` may describe removed behavior; current code and `AGENTS.md` take precedence.
