// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpatialWorkspace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SpatialWorkspace", targets: ["SpatialWorkspaceApp"]),
        .executable(name: "spatial-agent", targets: ["SpatialAgentCLI"]),
        .executable(name: "spatial-runtime-worker", targets: ["SpatialRuntimeWorker"]),
    ],
    targets: [
        .target(
            name: "SpatialRuntimeKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SpatialAgentBridgeKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "SpatialAgentCLI",
            dependencies: ["SpatialAgentBridgeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SpatialRuntimeWorker",
            dependencies: ["SpatialRuntimeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SpatialWorkspaceApp",
            dependencies: ["SpatialAgentBridgeKit", "SpatialRuntimeKit"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "SpatialWorkspaceTests",
            dependencies: ["SpatialWorkspaceApp", "SpatialAgentBridgeKit", "SpatialRuntimeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
