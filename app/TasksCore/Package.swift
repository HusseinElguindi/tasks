// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TasksCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TasksCore", targets: ["TasksCore"]),
        // The agent CLI (docs/SDK-PLAN.md): another replica of the log, built on TasksCore.
        .executable(name: "tasks", targets: ["TasksCLI"]),
        // The theme (tokens, Rex, the lit tile's finish), for the Mac and iOS apps. Values and CoreGraphics only;
        // TasksCore and the CLI don't use it.
        .library(name: "TasksTheme", targets: ["TasksTheme"]),
    ],
    targets: [
        .target(name: "TasksCore"),
        .target(name: "TasksTheme"),
        .testTarget(name: "TasksThemeTests", dependencies: ["TasksTheme"]),
        .executableTarget(name: "TasksCLI", dependencies: ["TasksCore"]),
        .testTarget(
            name: "TasksCoreTests",
            dependencies: ["TasksCore"],
            resources: [.copy("Resources")]
        ),
        // tasks.d.ts is the golden copy CodeModeTests compares against, read by path.
        .testTarget(name: "TasksCLITests", dependencies: ["TasksCLI"], exclude: ["tasks.d.ts"]),
    ]
)
