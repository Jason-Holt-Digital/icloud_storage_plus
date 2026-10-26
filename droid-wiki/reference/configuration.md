# Configuration

The plugin's manifests select platform implementations and deployment floors. A consuming app supplies its own iCloud capabilities, container identifiers, and signing; installing the package alone does not enable container access (`pubspec.yaml`, `README.md`).

## Platform and SDK settings

| Setting | Declared value | Source |
| --- | --- | --- |
| Package version | `4.1.0` | `pubspec.yaml` |
| Dart | `>=3.0.0 <4.0.0` | `pubspec.yaml` |
| Flutter | `>=3.10.0` | `pubspec.yaml` |
| iOS | `13.0` | `ios/icloud_storage_plus.podspec`, `ios/icloud_storage_plus/Package.swift` |
| macOS | `10.15` | `macos/icloud_storage_plus.podspec`, `macos/icloud_storage_plus/Package.swift` |
| CocoaPods Swift setting | `5.0` | Both platform podspecs |
| Swift package tools version | `5.9` | Both platform package manifests |
| Example Dart | `>=3.1.0 <4.0.0` | `example/pubspec.yaml` |

These are manifest declarations, not a claim that every modern development dependency resolves with the lowest declared SDK. No root lockfile is checked in.

## App capabilities

The setup in `README.md` requires an iCloud container assigned to the app's App ID and enabled under Xcode Signing & Capabilities with iCloud Documents.

The example entitlement files contain `CloudDocuments` but empty container-identifier arrays:

- `example/ios/Runner/Runner.entitlements`
- `example/ios/Runner/RunnerDebug.entitlements`
- `example/macos/Runner/DebugProfile.entitlements`
- `example/macos/Runner/Release.entitlements`

Configure the target's selected entitlement file and signing to match your app. The macOS debug/profile and release files also enable App Sandbox; the debug/profile file includes development JIT and server permissions. Those are example-host settings, not permissions granted by the plugin.

## Files app visibility

Use a literal `Documents/` prefix for visible documents. `README.md` describes adding `NSUbiquitousContainers` to the consuming app's Info.plist and notes that the app folder appears after at least one file exists there. Other container-relative paths remain app-managed content.

Neither `example/ios/Runner/Info.plist` nor `example/macos/Runner/Info.plist` currently declares `NSUbiquitousContainers`. Treat the example as a host template, not a fully provisioned public-container configuration.

## Native distribution

CocoaPods integration is described by `ios/icloud_storage_plus.podspec` and `macos/icloud_storage_plus.podspec`. Both enumerate production Foundation helper sources and privacy resources, while excluding the nested test package from the production source list.

SwiftPM integration is described by `ios/icloud_storage_plus/Package.swift` and `macos/icloud_storage_plus/Package.swift`. Each exports a library named `icloud-storage-plus` and explicitly lists production sources. The nested Foundation package manifests define independent helper test targets.

When adding a native helper, update both production manifest styles for both platforms where required. The existence of an on-disk Swift file alone does not prove that both distribution paths compile it.

## Runtime arguments

Container identifiers and paths are method arguments rather than global configuration. `getContainerPath` can expose a local absolute path; `relativePath` arguments are relative to that root. `listContents` uses null to mean the container root, not an empty path string (`lib/icloud_storage.dart`).

Check `icloudAvailable()` before operations, then handle actual container or operation failures. Availability is not a readiness guarantee. See [Trust boundaries](../security.md) and [Getting started](../overview/getting-started.md).
