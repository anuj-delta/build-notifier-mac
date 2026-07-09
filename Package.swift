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
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.21.0")
    ],
    targets: [
        .executableTarget(
            name: "BuildNotifier",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "BuildNotifier",
            exclude: [
                "Assets"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BuildNotifierTests",
            dependencies: ["BuildNotifier"],
            path: "Tests/BuildNotifierTests"
        )
    ]
)
