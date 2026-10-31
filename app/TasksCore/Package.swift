// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TasksCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TasksCore", targets: ["TasksCore"]),
        // The agent CLI (docs/SDK-PLAN.md): another replica of the log, built on TasksCore.
        .executable(name: "tasks", targets: ["TasksCLI"]),
    ],
    targets: [
        .target(name: "TasksCore"),
        .executableTarget(name: "TasksCLI", dependencies: ["TasksCore"]),
        .testTarget(
            name: "TasksCoreTests",
            dependencies: ["TasksCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "TasksCLITests", dependencies: ["TasksCLI"]),
    ]
)
