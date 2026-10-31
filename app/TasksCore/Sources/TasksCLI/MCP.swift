import Foundation

/// `tasks mcp`: built in phase 3 of docs/SDK-PLAN.md.
@MainActor
enum MCP {
    static func serve(_ env: Environment, options: Options) async throws {
        throw CLIError(kind: .config, message: "tasks mcp isn't built yet.")
    }
}
