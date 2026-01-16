// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NobleNotes",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .library(name: "StorageKit", targets: ["StorageKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .library(name: "AICore", targets: ["AICore"]),
        .library(name: "QuotaKit", targets: ["QuotaKit"]),
        .library(name: "TelemetryKit", targets: ["TelemetryKit"])
    ],
    targets: [
        .target(name: "CoreKit"),
        .target(name: "StorageKit", dependencies: ["CoreKit", "TelemetryKit"]),
        .target(name: "TelemetryKit", dependencies: ["CoreKit"]),
        .target(name: "QuotaKit", dependencies: ["CoreKit", "TelemetryKit"]),
        .target(name: "AICore", dependencies: ["CoreKit", "QuotaKit", "TelemetryKit"]),
        .target(name: "SyncKit", dependencies: ["CoreKit", "TelemetryKit", "StorageKit"]),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
        .testTarget(name: "QuotaKitTests", dependencies: ["QuotaKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"]),
        .testTarget(name: "AICoreTests", dependencies: ["AICore"]),
        .testTarget(name: "StorageKitTests", dependencies: ["StorageKit"]),
        .testTarget(name: "TelemetryKitTests", dependencies: ["TelemetryKit"])
    ]
)
