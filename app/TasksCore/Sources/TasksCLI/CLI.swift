import Foundation
import TasksCore

/// One `tasks` invocation: parse, open the replica, pull, run the command on a fork, commit, print.
@MainActor
enum CLI {
    static func run(_ argv: [String], env: Environment) async -> Int32 {
        let wantsJSON = argv.contains("--json")
        do {
            let inv = try Parser.parse(argv, stdin: env.readStdin)
            return try await execute(inv, env: env)
        } catch let e as CLIError {
            report(e, env: env, json: wantsJSON)
            return e.exitCode
        } catch {
            report(CLIError(kind: .sync, message: "\(error)"), env: env, json: wantsJSON)
            return 1
        }
    }

    static func execute(_ inv: Parser.Invocation, env: Environment) async throws -> Int32 {
        let o = inv.options
        var session: Session?
        var synced = true
        if inv.command.needs != .nothing {
            let server = try Server.resolve(env, override: o.server)
            let actor = try Session.actor(env, override: o.actor)
            session = try await Session(env: env, server: server, actor: actor)
            if inv.command.needs == .synced && !o.cached { synced = try await session!.sync() }
        }
        let c = Context(env: env, session: session, options: o)
        // Persistence writes on a background queue; flush it (and the snapshot) before the process exits, or
        // a pull is lost.
        defer {
            c.cleanup()
            session?.store.persistNow()
            session?.nudgeIfPushed()
        }
        let reply = try await inv.command.run(c, inv.args)

        // A write: render it against the fork (the state it produces), then commit unless it's a dry run.
        var isChange = inv.command.writes && !c.committed
        if case .value = reply { isChange = false }
        if isChange {
            let view = c.fork?.projection
            let base: JSON
            switch reply {
            case .createdTask(let id): base = try Render(view ?? c.p).task((view ?? c.p).task(id)!)
            case .createdList(let id): base = try Render(view ?? c.p).list((view ?? c.p).list(id)!)
            default: base = try c.changeJSON(view: view)
            }
            let summary = try c.summary(c.changes(view: view), view ?? c.p)
            let diff = try c.describe(view ?? c.p).diff(c.changes(view: view), refs: Render(view ?? c.p))
            let ids = try c.changes(view: view).map { ch -> String in
                switch ch { case .task(_, let a): a.id; case .list(_, let a): a.id }
            }
            if o.dryRun {
                emit(env, o, json: object(base, adding: ["dryRun": .bool(true), "diff": .array(diff.map(JSON.string))]),
                     ids: ids, text: diff + ["Dry run: \(summary). Nothing was written."])
                return 0
            }
            let wrote = !c.ops.isEmpty
            if wrote { synced = try await c.commit() }
            var text: [String] = []
            text.append(wrote ? "\(summary) · undo: tasks undo \(c.batch.prefix(6))" : "No change.")
            text += c.skipped.map { "  " + $0 }
            if !synced, wrote { env.err("tasks: saved locally; it syncs with the next tasks command that reaches the server.") }
            emit(env, o, json: object(base, adding: ["synced": .bool(synced)]), ids: ids, text: text)
            return synced ? 0 : 75
        }

        switch reply {
        case .value(let json, let text):
            emit(env, o, json: json, ids: Self.ids(in: json), text: text)
            if let code = c.exitCode { return code }
        case .text(let s): if !s.isEmpty { env.out(s) }
        case .change, .createdTask, .createdList: break
        }
        return synced || o.cached ? 0 : 75
    }

    private static func object(_ j: JSON, adding extra: KeyValuePairs<String, JSON>) -> JSON {
        guard case .object(var m) = j else { return j }
        m += extra.map { JSON.Member(key: $0.key, value: $0.value) }
        return .object(m)
    }

    static func emit(_ env: Environment, _ o: Options, json: JSON, ids: [String], text: [String]) {
        if o.json {
            env.out(json.text)
        } else if o.ids {
            if !ids.isEmpty { env.out(ids.joined(separator: "\n")) }
        } else if !text.isEmpty {
            env.out(text.joined(separator: "\n"))
        }
    }

    /// The task (and list) ids in a reply, for --ids: a task, a list of tasks, Today, a list view.
    static func ids(in j: JSON) -> [String] {
        switch j {
        case .array(let items): return items.flatMap(ids)
        case .object:
            if j["id"] != nil, let id = j["id"]?.stringValue { return [id] }
            var out: [String] = []
            for k in ["groups", "tasks", "open", "completed", "done"] { if let v = j[k] { out += ids(in: v) } }
            return out
        default: return []
        }
    }

    static func report(_ e: CLIError, env: Environment, json: Bool) {
        if json {
            env.out(JSON(["error": JSON(["type": .string(e.kind.rawValue), "message": .string(e.message), "field": .str(e.field),
                                         "candidates": .array(e.candidates.map(JSON.string))])]).text)
        } else {
            env.err("tasks: " + e.message)
        }
    }
}
