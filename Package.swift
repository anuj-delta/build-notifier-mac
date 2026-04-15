// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BuildNotifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BuildNotifierCore", targets: ["BuildNotifierCore"]),
        .executable(name: "BuildNotifier", targets: ["BuildNotifier"]),
        .executable(name: "BuildNotifierMCP", targets: ["BuildNotifierMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .target(
            name: "BuildNotifierCore",
            path: "BuildNotifierCore",
            sources: [
                "Models/Build.swift",
                "Models/Pipeline.swift",
                "Models/Project.swift",
                "Models/WorkflowJob.swift",
                "Services/BuildNotifierSharedDefaults.swift",
                "Services/CircleCIAPI.swift",
                "Services/CircleCIMCPService.swift",
                "Services/KeychainService.swift"
            ]
        ),
        .executableTarget(
            name: "BuildNotifier",
            dependencies: ["BuildNotifierCore"],
            path: "BuildNotifier",
            exclude: [
                "Assets"
            ],
            sources: [
                "BuildNotifierApp.swift",
                "Models/VercelDeployment.swift",
                "Models/VercelProject.swift",
                "Models/VercelTeam.swift",
                "Models/WatchedProject.swift",
                "Models/WatchedVercelProject.swift",
                "Services/AppWindowManager.swift",
                "Services/AutoApprovalPoller.swift",
                "Services/BuildPoller.swift",
                "Services/LaunchAtLoginService.swift",
                "Services/MCPServerIntegration.swift",
                "Services/NotificationManager.swift",
                "Services/VercelAPI.swift",
                "Services/VercelPoller.swift",
                "State/AppState.swift",
                "Views"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .executableTarget(
            name: "BuildNotifierMCP",
            dependencies: [
                "BuildNotifierCore",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "BuildNotifierMCP"
        ),
        .testTarget(
            name: "BuildNotifierTests",
            dependencies: ["BuildNotifier", "BuildNotifierCore"],
            path: "Tests/BuildNotifierTests"
        )
    ]
)
