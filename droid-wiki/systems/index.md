# Systems

Active contributors: Jason

The implementation is split between a Dart boundary and two native document backends. These pages explain internal components; [Features](../features/index.md) explains which public operation to choose.

## Component map

| System | Purpose | Source |
| --- | --- | --- |
| [Dart boundary](dart-boundary.md) | Validation, platform replacement, typed method results, stream lifetime | `lib/icloud_storage.dart`, `lib/icloud_storage_platform_interface.dart`, `lib/icloud_storage_method_channel.dart` |
| [Native files](native-files/index.md) | Container lookup, documents, coordination, metadata sessions, path lanes | `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`, `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift` |

## Key source files

| File | Purpose |
| --- | --- |
| `lib/icloud_storage.dart` | Public facade and API exports |
| `lib/icloud_storage_platform_interface.dart` | Token-verified implementation interface |
| `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift` | Foundation coordination bridge for iOS source tree |
| `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedIO.swift` | Corresponding macOS bridge |

`lib/models/` contains typed Dart values, documented in [Data models](../reference/data-models.md). Native Foundation test packages are verification harnesses within each platform tree, not extra user-facing Flutter packages.
