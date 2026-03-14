// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BuildNotifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BuildNotifier", targets: ["BuildNotifier"])
    ],
    targets: [
        .executableTarget(
            name: "BuildNotifier",
            path: "BuildNotifier",
            exclude: [
                "Assets"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
