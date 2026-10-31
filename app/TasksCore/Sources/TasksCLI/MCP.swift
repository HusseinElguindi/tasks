import Foundation

/// `tasks mcp`: a local stdio MCP server with two tools, `tasks_types` and `tasks_run`, around code mode
/// (docs/SDK-PLAN.md §6). Newline-delimited JSON-RPC on stdin/stdout; messages for people go to stderr.
@MainActor
enum MCP {
    static let instructions = """
    Tasks is the user's to-do app (lists, Today, When and Deadline dates). Read tasks_types once, then write one \
    tasks_run script per request: it can read and change everything the app can, and the whole script is one change \
    that the user can undo (the result names it). Use dryRun to preview a change you're unsure about.
    """

    static let tools: JSON = .array([
        JSON(["name": .string("tasks_types"),
              "description": .string("The TypeScript API (tasks.d.ts) that tasks_run scripts are written against: the `tasks` object, Task, List, Change, dates and refs. Read it before writing a script."),
              "inputSchema": JSON(["type": .string("object"), "properties": JSON([:])])]),
        JSON(["name": .string("tasks_run"),
              "description": .string("Run a TypeScript script against the user's Tasks. `tasks` is the API from tasks_types; every call is awaited; `return` a value to get it back, and console.log lines come back too. The whole script is one change: written and synced when it returns, nothing written if it throws. No files, network or env. Returns {ok, result, logs, change: {batch, summary, tasks, lists}, synced}, or {ok: false, error: {type, message, line}}."),
              "inputSchema": JSON(["type": .string("object"),
                                   "properties": JSON(["script": JSON(["type": .string("string"), "description": .string("TypeScript; top-level await and return work.")]),
                                                       "dryRun": JSON(["type": .string("boolean"), "description": .string("Run it without writing anything; the result includes the diff it would make.")])]),
                                   "required": .array([.string("script")])])]),
    ])

    static func serve(_ env: Environment, options: Options) async throws {
        env.err("tasks mcp: serving tasks_types and tasks_run on stdio.")
        for try await line in FileHandle.standardInput.bytes.lines {
            guard let message = try? JSON.parse(line) else {
                env.out(JSON(["jsonrpc": .string("2.0"), "id": .null, "error": JSON(["code": .int(-32700), "message": .string("Parse error")])]).text)
                continue
            }
            if let reply = await handle(message, env: env, options: options) { env.out(reply.text) }
        }
    }

    /// One JSON-RPC message → its reply, or nil for a notification.
    static func handle(_ m: JSON, env: Environment, options: Options) async -> JSON? {
        guard let id = m["id"] else { return nil }
        func result(_ r: JSON) -> JSON { JSON(["jsonrpc": .string("2.0"), "id": id, "result": r]) }
        func error(_ code: Int, _ message: String) -> JSON {
            JSON(["jsonrpc": .string("2.0"), "id": id, "error": JSON(["code": .int(code), "message": .string(message)])])
        }
        let params = m["params"]
        switch m["method"]?.stringValue ?? "" {
        case "initialize":
            return result(JSON(["protocolVersion": .string(params?["protocolVersion"]?.stringValue ?? "2025-06-18"),
                                "capabilities": JSON(["tools": JSON([:])]),
                                "serverInfo": JSON(["name": .string("tasks"), "version": .string("1.0")]),
                                "instructions": .string(instructions)]))
        case "ping":
            return result(JSON([:]))
        case "tools/list":
            return result(JSON(["tools": tools]))
        case "tools/call":
            let args = params?["arguments"]
            switch params?["name"]?.stringValue {
            case "tasks_types":
                return result(content(TypeScript.declarations(), isError: false))
            case "tasks_run":
                guard let script = args?["script"]?.stringValue else { return error(-32602, "tasks_run needs a script.") }
                let out = await run(script, dryRun: args?["dryRun"]?.boolValue ?? false, env: env, options: options)
                return result(content(out.text, isError: out["ok"] != .bool(true)))
            default:
                return error(-32602, "Unknown tool \(params?["name"]?.stringValue ?? "").")
            }
        default:
            return error(-32601, "Method not found")
        }
    }

    static func content(_ text: String, isError: Bool) -> JSON {
        JSON(["content": .array([JSON(["type": .string("text"), "text": .string(text)])]), "isError": .bool(isError)])
    }

    /// One script on a fresh session: lock, pull, run, commit, release, like one `tasks run`.
    static func run(_ script: String, dryRun: Bool, env: Environment, options: Options) async -> JSON {
        do {
            let server = try Server.resolve(env, override: options.server)
            let actor = try Session.actor(env, override: options.actor)
            let session = try await Session(env: env, server: server, actor: actor)
            defer {
                session.store.persistNow()
                session.nudgeIfPushed()
            }
            _ = try await session.sync()
            var o = options
            o.dryRun = dryRun
            let c = Context(env: env, session: session, options: o)
            defer { c.cleanup() }
            return try await CodeMode.execute(script, c, dryRun: dryRun).0
        } catch let e as CLIError {
            return JSON(["ok": .bool(false), "error": JSON(["type": .string(e.kind.rawValue), "message": .string(e.message)]),
                         "logs": .array([]), "change": .null])
        } catch {
            return JSON(["ok": .bool(false), "error": JSON(["type": .string("Error"), "message": .string("\(error)")]),
                         "logs": .array([]), "change": .null])
        }
    }
}
