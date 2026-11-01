// swift-tools-version: 6.0
// Golden JSON for the TypeScript port in ../src/core: TasksCore, by path, run as is. See README.md.
import PackageDescription

let package = Package(
    name: "parity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../app/TasksCore")],
    targets: [
        .executableTarget(name: "golden", dependencies: [.product(name: "TasksCore", package: "TasksCore")]),
    ]
)
