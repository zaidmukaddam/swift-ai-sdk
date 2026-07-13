// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ai-sdk-apps",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "swift-ai-sdk", path: "..")
    ],
    targets: [
        .executableTarget(
            name: "StreamTextDemo",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        ),
        .executableTarget(
            name: "RealtimeDemo",
            dependencies: [.product(name: "AI", package: "swift-ai-sdk")]
        )
    ]
)
