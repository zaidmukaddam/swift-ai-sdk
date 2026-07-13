// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ai-sdk",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "AI", targets: ["AI"]),
        .library(name: "AITesting", targets: ["AITesting"]),
        .executable(name: "demo", targets: ["Demo"])
    ],
    targets: [
        .target(
            name: "AI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "AITesting",
            dependencies: ["AI"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AITests",
            dependencies: ["AI", "AITesting"]
        ),
        .target(
            name: "Examples",
            dependencies: ["AI"],
            path: "Examples",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "Demo",
            dependencies: ["AI"]
        )
    ]
)
