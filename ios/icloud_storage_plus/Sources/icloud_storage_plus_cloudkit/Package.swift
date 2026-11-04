// swift-tools-version: 5.9

import PackageDescription

// Builds the Flutter-free CloudKit sync bridge files on their own, without
// any document storage source, so the bridge's tests run with `swift test`.
let package = Package(
    name: "icloud_storage_plus_cloudkit",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0"),
    ],
    products: [
        .library(
            name: "icloud_storage_plus_cloudkit",
            targets: ["icloud_storage_plus_cloudkit"]
        ),
    ],
    targets: [
        .target(
            name: "icloud_storage_plus_cloudkit",
            path: ".",
            exclude: ["Package.swift", "Tests", "CloudKitSyncChannel.swift"]
        ),
        .testTarget(
            name: "icloud_storage_plus_cloudkitTests",
            dependencies: ["icloud_storage_plus_cloudkit"],
            path: "Tests/icloud_storage_plus_cloudkitTests"
        ),
    ]
)
