import Foundation
import TasksCore

/// Code mode (`tasks run`): built in phase 3 of docs/SDK-PLAN.md.
@MainActor
enum CodeMode {
    static func run(_ c: Context, file: String?) async throws -> Reply {
        throw CLIError(kind: .config, message: "tasks run isn't built yet.")
    }
}
