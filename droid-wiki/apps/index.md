# Apps

Active contributors: Jason

The repository bundles one non-publishable Flutter example app alongside the plugin. It exercises the plugin locally on Apple platforms; it is not a separately deployed service (`example/pubspec.yaml`).

## Example app

[Example](example.md) documents its screens, shared container input, and manual verification flow. The entry point is `example/lib/main.dart`.

## Key source files

| File | Purpose |
| --- | --- |
| `example/pubspec.yaml` | Demo dependencies and path dependency on the root plugin |
| `example/lib/main.dart` | Material app and named routes |
| `example/lib/gather.dart` | Default screen and container entry |

For app setup, see [Getting started](../overview/getting-started.md). For plugin internals, use [Systems](../systems/index.md).
