# Example

Active contributors: Jason

## Purpose

The example is a small Material app for manually exercising container listing and file operations. It uses the root plugin through a relative path dependency, so local plugin edits are used when the app is rebuilt (`example/pubspec.yaml`).

## Directory layout

```text
example/
  lib/           nine Dart source files
  ios/           iOS host app and signing configuration
  macos/         macOS host app and signing configuration
  pubspec.yaml   non-publishable Flutter app
```

There are nine Dart source files and no checked-in widget or integration test files in the example. Recent human changes on `origin/main` are by Jason. Historical author labels are not a reliable bus-factor measure because aliases and inherited upstream history overlap.

## Screens and abstractions

`MyApp` in `example/lib/main.dart` defaults to the `Gather` widget in `example/lib/gather.dart`. The container identifier entered there is passed as a route argument to operation screens.

| Route | Source | Capability |
| --- | --- | --- |
| Default | `example/lib/gather.dart` | Initial metadata snapshot and subscribed full updates |
| `/upload` | `example/lib/upload.dart` | Local path to container, optional progress |
| `/download` | `example/lib/download.dart` | Container path to local destination |
| `/delete` | `example/lib/delete.dart` | Delete a container entry |
| `/move` | `example/lib/move.dart` | Move within the container |
| `/rename` | `example/lib/rename.dart` | Rename an entry |
| `/listContents` | `example/lib/list_contents.dart` | One-shot listing and status display |

The app does not provide dedicated screens for every API, including in-place content, document observation, or conflict-version primitives. Do not mistake the route list for the complete plugin surface.

## How it works

The gather screen attaches its update listener synchronously, displays returned relative paths, and cancels the subscription on stop or disposal (`example/lib/gather.dart`). The listing screen turns an empty optional directory field into a null argument and renders each `ContainerItem`'s available status fields (`example/lib/list_contents.dart`).

Error presentation and progress formatting live in `example/lib/utils.dart`. The app displays operation errors and an optional retry hint; that text does not start a retry scheduler or guarantee an action will succeed later.

## Integration points

The iOS and macOS hosts supply the entitlements and app configuration that native iCloud access requires. Review them before running the demo, rather than copying signing identities or identifiers into a production app. [Configuration](../reference/configuration.md) lists the relevant files.

Use [File access](../features/file-access.md) and [Listing and metadata](../features/listing-and-metadata.md) to interpret results. A local operation finishing or a metadata update arriving is not proof of propagation to another device.

## Entry points for modification

Add navigation in `example/lib/main.dart` and the menu in `example/lib/gather.dart` when adding a demonstration screen. Keep example UI changes separate from plugin policies. Add suitable widget or native runtime verification for changed behavior, following [Testing](../how-to-contribute/testing.md).

## Key source files

| File | Purpose |
| --- | --- |
| `example/lib/main.dart` | App startup and route dispatch |
| `example/lib/gather.dart` | Container entry and metadata subscription |
| `example/lib/list_contents.dart` | Direct directory listing demonstration |
| `example/lib/upload.dart` | Copy-in controls |
| `example/lib/download.dart` | Copy-out controls |
| `example/lib/utils.dart` | Error messages and progress formatting |
| `example/pubspec.yaml` | Path dependency and package constraints |
