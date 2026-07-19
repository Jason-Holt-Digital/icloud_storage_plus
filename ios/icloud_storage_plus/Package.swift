// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

let package = Package(
    name: "icloud_storage_plus",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        // If the plugin name contains "_", replace with "-" for the library name.
        .library(name: "icloud-storage-plus", targets: ["icloud_storage_plus"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "icloud_storage_plus",
            dependencies: [],
            path: "Sources",
            exclude: [
                "icloud_storage_plus_foundation/Package.swift",
                "icloud_storage_plus_foundation/Tests",
                "icloud_storage_plus_foundation/Placeholder.swift",
            ],
            sources: [
                "icloud_storage_plus/FileWriteHelpers.swift",
                "icloud_storage_plus/ICloudDocument.swift",
                "icloud_storage_plus/iOSICloudStoragePlugin.swift",
                "icloud_storage_plus_foundation/CoordinatedIO.swift",
                "icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift",
                "icloud_storage_plus_foundation/DocumentChangeObservation.swift",
                "icloud_storage_plus_foundation/MetadataQuerySupport.swift",
                "icloud_storage_plus_foundation/MetadataQuerySession.swift",
                "icloud_storage_plus_foundation/WriteEntrypointPreflight.swift",
                "icloud_storage_plus_foundation/UbiquityContainerResolver.swift",
                "icloud_storage_plus_foundation/VersionExposure.swift",
                "icloud_storage_plus_foundation/PerPathMutationLane.swift",
                "icloud_storage_plus_foundation/UbiquitousItemMaterializer.swift",
            ],
            resources: [
                .process("icloud_storage_plus/PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("icloud_storage_plus/include/icloud_storage_plus"),
            ]
        ),
    ]
)
