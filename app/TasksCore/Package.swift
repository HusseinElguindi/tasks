// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TasksCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TasksCore", targets: ["TasksCore"]),
    ],
    targets: [
        .target(name: "TasksCore"),
        .testTarget(
            name: "TasksCoreTests",
            dependencies: ["TasksCore"],
            resources: [.copy("Resources")]
        ),
    ]
)
