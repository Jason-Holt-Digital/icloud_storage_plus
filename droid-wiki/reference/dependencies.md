# Dependencies

The root package declares three external Dart runtime packages plus the Flutter SDK. It has two development dependencies; the example has its own small dependency set (`pubspec.yaml`, `example/pubspec.yaml`).

## Root package

| Dependency | Declared constraint | Role |
| --- | --- | --- |
| Flutter | SDK dependency | Platform channels and plugin integration |
| `equatable` | `^2.0.8` | Equality for metadata, document changes, and versions |
| `logging` | `^1.3.0` | Internal diagnostic logger in the channel adapter |
| `plugin_platform_interface` | `^2.0.2` | Platform-interface token verification |
| `flutter_test` | SDK development dependency | Tests and Flutter binary-messenger mocking |
| `very_good_analysis` | `^10.0.0` | Root analyzer rules |

Usage entry points are `lib/models/icloud_file.dart`, `lib/models/icloud_document_change.dart`, `lib/models/icloud_version.dart`, `lib/icloud_storage_method_channel.dart`, `lib/icloud_storage_platform_interface.dart`, and `analysis_options.yaml`.

No dependency lockfile is checked in at the root or under the example. These are constraints, not resolved versions; this wiki does not claim that dependencies are current or stale. Resolve the project before consulting version-specific package API documentation.

## Example

`example/pubspec.yaml` declares Flutter, the root plugin via `path: ../`, and `cupertino_icons: ^1.0.2`. Its development dependencies are `flutter_test` and `flutter_lints: ^6.0.0`. The path dependency means the example demonstrates the checked-out plugin, not a separately downloaded release.

## Native frameworks and packaging

The iOS implementation imports Flutter and UIKit; the macOS implementation imports FlutterMacOS and Cocoa. Foundation helpers provide file coordination, metadata queries, version access, and container resolution (`ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`).

Both top-level native package manifests have empty external Swift package dependency arrays. Flutter host integration supplies the platform environment; the manifests do not make the full plugin a portable standalone Swift library (`ios/icloud_storage_plus/Package.swift`, `macos/icloud_storage_plus/Package.swift`).

The podspecs declare the `Flutter` or `FlutterMacOS` dependency. Nested Foundation package manifests use XCTest test targets rather than third-party test libraries.

## Automation dependencies

GitHub Actions workflows use checkout/artifact actions, GitHub Script, Factory Droid actions, `googleapis/release-please-action`, the Dart reusable publishing workflow, and a rolling-wiki pull-request action. These are CI dependencies, not plugin runtime packages. The Factory actions and the Release Please action pin to specific commits (identified as v10 and v5.0.0 respectively); see [Distribution and automation](../deployment.md).

The plugin has no database, hosted backend, or telemetry service dependency in `pubspec.yaml`. Apple's iCloud service behavior remains outside its ownership boundary (`AGENTS.md`).
