# Getting started

Use Flutter to install the package, then configure iCloud capabilities in the consuming Apple app. Dart tests can run without iCloud; native runtime behavior needs a configured Apple environment (`README.md`, `AGENTS.md`).

## Prerequisites

`pubspec.yaml` declares Dart `>=3.0.0 <4.0.0` and Flutter `>=3.10.0`. Native deployment floors are iOS 13.0 and macOS 10.15. The example requires Dart `>=3.1.0 <4.0.0` (`example/pubspec.yaml`).

Use Xcode and signing appropriate for the app's iCloud container. No root dependency lockfile is checked in, so declared lower bounds do not describe one reproducible resolved development toolchain.

## Install and configure

From the consuming Flutter app:

```bash
flutter pub add icloud_storage_plus
```

Create an iCloud container for the App ID. In the app target's Xcode Signing & Capabilities settings, enable iCloud Documents and select that container. For Files app visibility, configure `NSUbiquitousContainers` in the app's Info.plist and store visible items below the literal `Documents/` prefix (`README.md`).

Swift Package Manager integration is optional and documented for Flutter 3.24 or later:

```bash
flutter config --enable-swift-package-manager
```

The plugin also ships CocoaPods specifications. See [Configuration](../reference/configuration.md) for the packaging and entitlement entry points.

## First local read and write

```dart
import 'package:icloud_storage_plus/icloud_storage.dart';

Future<String?> readExample() async {
  if (!await ICloudStorage.icloudAvailable()) return null;

  const containerId = 'iCloud.com.yourapp.container';
  const path = 'Documents/example.txt';
  await ICloudStorage.writeInPlace(
    containerId: containerId,
    relativePath: path,
    contents: 'Hello from the local container',
  );
  return ICloudStorage.readInPlace(
    containerId: containerId,
    relativePath: path,
  );
}
```

The API in `lib/icloud_storage.dart` returns non-nullable contents on successful reads. Missing items throw an operation exception; the example's nullable result only represents the availability check. Use path-only transfers for large files because in-place operations pass complete contents through Flutter channels.

## Work on the repository

From the repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

For native helper changes, run targeted tests from the supported Foundation package on a Mac:

```bash
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation
```

These packages use Apple Foundation APIs. A Linux Swift installation is not sufficient to verify Darwin document behavior. Do not substitute a top-level `swift build` for Flutter integration.

## Run the example

From `example/`, fetch packages and run on a supported target:

```bash
flutter pub get
flutter run -d macos
```

For iOS, select a configured device with `flutter devices` and run `flutter run -d <device-id>`. Configure signing, entitlements, and the container entered in the demo before expecting file access. `example/lib/main.dart` exposes gather, listing, upload/download, delete, move, and rename screens; it is not an automated integration suite.

Prefer a physical device for iCloud behavior. Capture Flutter debug and platform logs when verifying native changes (`AGENTS.md`). Continue with [Testing](../how-to-contribute/testing.md) or [Debugging](../how-to-contribute/debugging.md).
