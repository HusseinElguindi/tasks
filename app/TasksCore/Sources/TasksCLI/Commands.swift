import Foundation
import TasksCore

/// A parameter's type: how the CLI reads it, how code mode decodes it, and its TypeScript type.
enum ParamType: Sendable {
    case text, ref, refs, listRef, date, place, bool, int

    var ts: String {
        switch self {
        case .text: "string"
        case .ref, .listRef: "Ref"
        case .refs: "Ref | Ref[]"
        case .date: "DateInput"
        case .place: "Place"
        case .bool: "boolean"
        case .int: "number"
        }
    }
}

struct Param: Sendable {
    let name: String
    let type: ParamType
    var optional = false
}

/// A CLI flag: one that takes a value (`--list L`), sets a fixed value (`--today` is `when: "today"`), or wraps
/// its value (`--after R` is `place: {after: R}`).
struct Flag: Sendable {
    enum Kind: Sendable {
        case value(String)
        case constant(JSON)
        case wrap(String, String)
    }

    let name: String
    let param: String
    let kind: Kind

    var takesValue: Bool { if case .constant = kind { false } else { true } }
}

/// A code-mode argument: one parameter, or an object whose fields are parameters.
enum MethodArg: Sendable {
    case param(String)
    case object(String, [String])
}

enum Needs { case nothing, replica, synced }

enum Section: String, CaseIterable { case views = "Views", tasks = "Tasks", lists = "Lists", history = "History and sync", code = "Code mode", help = "Help" }

/// What a command returns: a value (JSON and its text), or a change rendered once it's committed.
enum Reply {
    case value(JSON, [String])
    case change
    case createdTask(EntityID)
    case createdList(EntityID)
    case text(String)
}

typealias Args = [String: JSON]

/// One command of the table. Every surface comes from this: the parser, `tasks help`, code mode's methods and
/// their argument decoding, and `tasks.d.ts` (docs/SDK-PLAN.md §3).
struct Command: @unchecked Sendable {
    let name: String
    let usage: String
    let doc: String
    let example: String
    let section: Section
    var method: String? = nil
    var params: [Param] = []
    var positionals: [String] = []
    var flags: [Flag] = []
    var signature: [MethodArg] = []
    var returns: String = "Change"
    var needs: Needs = .synced
    var writes = false
    let run: @MainActor (Context, Args) async throws -> Reply

    func param(_ name: String) -> Param? { params.first { $0.name == name } }
}

private let placeFlags: [Flag] = [
    Flag(name: "top", param: "place", kind: .constant(.string("top"))),
    Flag(name: "bottom", param: "place", kind: .constant(.string("bottom"))),
    Flag(name: "up", param: "place", kind: .constant(.string("up"))),
    Flag(name: "down", param: "place", kind: .constant(.string("down"))),
    Flag(name: "after", param: "place", kind: .wrap("after", "REF")),
    Flag(name: "before", param: "place", kind: .wrap("before", "REF")),
]

extension Args {
    func text(_ k: String) -> String? { self[k]?.stringValue }
    func bool(_ k: String) -> Bool { self[k]?.boolValue ?? false }

    func refs(_ k: String) throws -> [String] {
        switch self[k] {
        case .string(let s)?: return [s]
        case .array(let a)?:
            return try a.map {
                guard let s = $0.stringValue else { throw CLIError.invalid("\(k) must be refs (strings).", field: k) }
                return s
            }
        default: throw CLIError.invalid("\(k) is required.", field: k)
        }
    }

    func required(_ k: String) throws -> String {
        guard let s = self[k]?.stringValue else { throw CLIError.invalid("\(k) is required.", field: k) }
        return s
    }
}

enum Commands {
    static let all: [Command] = [
        // MARK: Views
        Command(name: "today", usage: "", doc: "Today: open tasks with When today or earlier, or due today or overdue, grouped by list in sidebar order, then those completed today.",
                example: "tasks today", section: .views, method: "today",
                returns: "{ date: CalendarDate; groups: { list: List; tasks: Task[] }[]; done: Task[] }", needs: .synced) { c, _ in
            let (j, t) = try c.todayJSON(); return .value(j, t)
        },
        Command(name: "lists", usage: "", doc: "The sidebar: active lists in order, each with its open count.",
                example: "tasks lists", section: .views, method: "lists", returns: "List[]") { c, _ in
            let (j, t) = try c.listsJSON(); return .value(j, t)
        },
        Command(name: "ls", usage: "[<list>] [--done]", doc: "A list: open tasks in order, then completed ones newest first. No list means the first one.",
                example: "tasks ls School --done", section: .views, method: "list",
                params: [Param(name: "list", type: .listRef, optional: true), Param(name: "done", type: .bool, optional: true)],
                positionals: ["list"], flags: [Flag(name: "done", param: "done", kind: .constant(.bool(true)))],
                signature: [.param("list")], returns: "{ list: List; open: Task[]; completed: Task[] }") { c, a in
            let (j, t) = try c.listJSON(a.text("list"), done: a.bool("done")); return .value(j, t)
        },
        Command(name: "archive", usage: "", doc: "Archived lists, most recently archived first.",
                example: "tasks archive", section: .views, method: "archive", returns: "List[]") { c, _ in
            let (j, t) = try c.archiveJSON(); return .value(j, t)
        },
        Command(name: "show", usage: "<task> [--history]", doc: "One task: every field and its notes (the detail pane). Deleted tasks too.",
                example: "tasks show 3f9a2c --history", section: .views, method: "task",
                params: [Param(name: "task", type: .ref), Param(name: "history", type: .bool, optional: true)],
                positionals: ["task"], flags: [Flag(name: "history", param: "history", kind: .constant(.bool(true)))],
                signature: [.param("task")], returns: "Task") { c, a in
            let t = try c.resolve.task(try a.required("task"), includeDeleted: true)
            let r = Render(try c.p)
            return .value(r.task(t), r.detail(t, history: a.bool("history") ? try c.historyLines(t.id) : []))
        },
        Command(name: "find", usage: "<text> [--list L] [--done | --open] [--deleted]", doc: "Tasks whose title or notes contain the text (any list; read-only). Empty text matches everything.",
                example: "tasks find dentist --ids", section: .views, method: "find",
                params: [Param(name: "text", type: .text, optional: true), Param(name: "list", type: .listRef, optional: true),
                         Param(name: "done", type: .bool, optional: true), Param(name: "deleted", type: .bool, optional: true)],
                positionals: ["text"],
                flags: [Flag(name: "list", param: "list", kind: .value("L")), Flag(name: "done", param: "done", kind: .constant(.bool(true))),
                        Flag(name: "open", param: "done", kind: .constant(.bool(false))), Flag(name: "deleted", param: "deleted", kind: .constant(.bool(true)))],
                signature: [.object("q", ["text", "list", "done", "deleted"])], returns: "Task[]") { c, a in
            let (j, t) = try c.find(text: a.text("text"), list: a.text("list"), done: a["done"]?.boolValue, deleted: a.bool("deleted"))
            return .value(j, t)
        },
        Command(name: "date", usage: "<text>", doc: "What a date phrase means today, without writing anything: null if it reads as no date.",
                example: "tasks date \"next fri\"", section: .views, method: "date",
                params: [Param(name: "text", type: .text)], positionals: ["text"], signature: [.param("text")],
                returns: "CalendarDate | null", needs: .replica) { c, a in
            let text = try a.required("text")
            guard let d = try c.resolveDate(text) else {
                return .value(.null, ["\"\(text)\" doesn't read as a date."])
            }
            let today = try c.today
            return .value(.string(d.string), ["\(d.string)  \(DateLabel.long(d, today: today)), \(DateLabel.relative(d, today: today))"])
        },

        // MARK: Tasks
        Command(name: "add", usage: "<title> [--list L] [--today] [--when D] [--deadline D] [--notes TEXT|-] [--top | --after REF | --before REF] [--key K | --id ID]",
                doc: "New task, at the bottom of the list's open tasks (or the place given). No list means the first list. --key makes it safe to repeat: same key, same task.",
                example: "tasks add \"Pay rent\" --list Home --deadline \"nov 1\" --key rent-2026-11", section: .tasks, method: "add",
                params: [Param(name: "title", type: .text), Param(name: "list", type: .listRef, optional: true),
                         Param(name: "notes", type: .text, optional: true), Param(name: "when", type: .date, optional: true),
                         Param(name: "deadline", type: .date, optional: true), Param(name: "place", type: .place, optional: true),
                         Param(name: "key", type: .text, optional: true), Param(name: "id", type: .text, optional: true)],
                positionals: ["title"],
                flags: [Flag(name: "list", param: "list", kind: .value("L")), Flag(name: "today", param: "when", kind: .constant(.string("today"))),
                        Flag(name: "when", param: "when", kind: .value("D")), Flag(name: "deadline", param: "deadline", kind: .value("D")),
                        Flag(name: "notes", param: "notes", kind: .value("TEXT")), Flag(name: "key", param: "key", kind: .value("K")),
                        Flag(name: "id", param: "id", kind: .value("ID"))] + placeFlags.filter { !["up", "down"].contains($0.name) },
                signature: [.object("t", ["title", "list", "notes", "when", "deadline", "place", "key", "id"])],
                returns: "Task", writes: true) { c, a in
            let t = try c.add(title: try a.required("title"), list: a.text("list"), notes: a.text("notes"),
                              when: try c.date(a["when"], field: "when"), deadline: try c.date(a["deadline"], field: "deadline"),
                              place: try c.place(a["place"]), id: a.text("id"), key: a.text("key"))
            return .createdTask(t.id)
        },
        Command(name: "rename", usage: "<task> <title>", doc: "Rename a task.", example: "tasks rename 3f9a2c \"Buy oat milk\"",
                section: .tasks, method: "rename", params: [Param(name: "task", type: .ref), Param(name: "title", type: .text)],
                positionals: ["task", "title"], signature: [.param("task"), .param("title")], writes: true) { c, a in
            try c.rename(try a.required("task"), try a.required("title")); return .change
        },
        Command(name: "notes", usage: "<task> <TEXT|-> [--append]", doc: "Replace a task's notes (Markdown), or add a line with --append. - reads stdin.",
                example: "tasks notes 3f9a2c --append \"- [ ] call back\"", section: .tasks, method: "setNotes",
                params: [Param(name: "task", type: .ref), Param(name: "notes", type: .text), Param(name: "append", type: .bool, optional: true)],
                positionals: ["task", "notes"], flags: [Flag(name: "append", param: "append", kind: .constant(.bool(true)))],
                signature: [.param("task"), .param("notes")], writes: true) { c, a in
            try c.setNotes(try a.required("task"), try a.required("notes"), append: a.bool("append")); return .change
        },
        Command(name: "done", usage: "<task>…", doc: "Complete tasks. Already done ones are left alone.", example: "tasks done 3f9a2c 77b0e1",
                section: .tasks, method: "complete", params: [Param(name: "tasks", type: .refs)], positionals: ["tasks"],
                signature: [.param("tasks")], writes: true) { c, a in
            try c.complete(try a.refs("tasks")); return .change
        },
        Command(name: "undone", usage: "<task>…", doc: "Mark tasks as not done.", example: "tasks undone 3f9a2c",
                section: .tasks, method: "uncomplete", params: [Param(name: "tasks", type: .refs)], positionals: ["tasks"],
                signature: [.param("tasks")], writes: true) { c, a in
            try c.uncomplete(try a.refs("tasks")); return .change
        },
        Command(name: "toggle", usage: "<task>…", doc: "⌘K: complete them all, unless all are done, then mark them all not done.",
                example: "tasks toggle 3f9a2c 77b0e1", section: .tasks, method: "toggle", params: [Param(name: "tasks", type: .refs)],
                positionals: ["tasks"], signature: [.param("tasks")], writes: true) { c, a in
            try c.toggle(try a.refs("tasks")); return .change
        },
        Command(name: "when", usage: "<date|none> <task>…", doc: "Set When: the day a task shows in Today. A date, a phrase the date field reads (\"fri\", \"next week\", \"3d\"), or none.",
                example: "tasks when fri 3f9a2c 77b0e1", section: .tasks, method: "setWhen",
                params: [Param(name: "tasks", type: .refs), Param(name: "date", type: .date)], positionals: ["date", "tasks"],
                signature: [.param("tasks"), .param("date")], writes: true) { c, a in
            try c.setWhen(try a.refs("tasks"), try c.date(a["date"] ?? .null, field: "date")); return .change
        },
        Command(name: "deadline", usage: "<date|none> <task>…", doc: "Set or remove the Deadline.",
                example: "tasks deadline \"nov 9\" 3f9a2c", section: .tasks, method: "setDeadline",
                params: [Param(name: "tasks", type: .refs), Param(name: "date", type: .date)], positionals: ["date", "tasks"],
                signature: [.param("tasks"), .param("date")], writes: true) { c, a in
            try c.setDeadline(try a.refs("tasks"), try c.date(a["date"] ?? .null, field: "date")); return .change
        },
        Command(name: "move", usage: "<task>… [--to L] [--top | --bottom | --up | --down | --after REF | --before REF]",
                doc: "Move tasks to another list (they land at the bottom, in the order given), or to a place: next to an open task (in its list), the top or bottom, or one slot up or down.",
                example: "tasks move 3f9a2c 77b0e1 --to School", section: .tasks, method: "move",
                params: [Param(name: "tasks", type: .refs), Param(name: "list", type: .listRef, optional: true), Param(name: "place", type: .place, optional: true)],
                positionals: ["tasks"], flags: [Flag(name: "to", param: "list", kind: .value("L"))] + placeFlags,
                signature: [.param("tasks"), .object("to", ["list", "place"])], writes: true) { c, a in
            try c.move(try a.refs("tasks"), list: a.text("list"), place: try c.place(a["place"])); return .change
        },
        Command(name: "delete", usage: "<task>…", doc: "Delete tasks. tasks restore (or undo) brings them back.",
                example: "tasks delete 3f9a2c", section: .tasks, method: "delete", params: [Param(name: "tasks", type: .refs)],
                positionals: ["tasks"], signature: [.param("tasks")], writes: true) { c, a in
            try c.delete(try a.refs("tasks")); return .change
        },
        Command(name: "restore", usage: "<task>…", doc: "Bring back deleted tasks.", example: "tasks restore 3f9a2c",
                section: .tasks, method: "restore", params: [Param(name: "tasks", type: .refs)], positionals: ["tasks"],
                signature: [.param("tasks")], writes: true) { c, a in
            try c.restore(try a.refs("tasks")); return .change
        },

        // MARK: Lists
        Command(name: "list add", usage: "<name> [--top | --after L | --before L]", doc: "New list, at the bottom of the sidebar (or the place given).",
                example: "tasks list add School", section: .lists, method: "addList",
                params: [Param(name: "name", type: .text), Param(name: "place", type: .place, optional: true)],
                positionals: ["name"], flags: placeFlags.filter { ["top", "after", "before"].contains($0.name) },
                signature: [.param("name"), .param("place")], returns: "List", writes: true) { c, a in
            let l = try c.addList(try a.required("name"), place: try c.place(a["place"])); return .createdList(l.id)
        },
        Command(name: "list rename", usage: "<list> <name>", doc: "Rename a list.", example: "tasks list rename School \"School 2026\"",
                section: .lists, method: "renameList", params: [Param(name: "list", type: .listRef), Param(name: "name", type: .text)],
                positionals: ["list", "name"], signature: [.param("list"), .param("name")], writes: true) { c, a in
            try c.renameList(try a.required("list"), try a.required("name")); return .change
        },
        Command(name: "list move", usage: "<list> (--top | --bottom | --up | --down | --after L | --before L)", doc: "Move a list in the sidebar.",
                example: "tasks list move School --after Work", section: .lists, method: "moveList",
                params: [Param(name: "list", type: .listRef), Param(name: "place", type: .place)], positionals: ["list"],
                flags: placeFlags, signature: [.param("list"), .param("place")], writes: true) { c, a in
            try c.moveList(try a.required("list"), try c.place(a["place"])); return .change
        },
        Command(name: "list archive", usage: "<list>", doc: "Archive a list (the app's \"delete list\"). Its tasks are kept and come back with it.",
                example: "tasks list archive School", section: .lists, method: "archiveList", params: [Param(name: "list", type: .listRef)],
                positionals: ["list"], signature: [.param("list")], writes: true) { c, a in
            try c.archiveList(try a.required("list")); return .change
        },
        Command(name: "list unarchive", usage: "<list>", doc: "Unarchive a list, back to its old place in the sidebar.",
                example: "tasks list unarchive School", section: .lists, method: "unarchiveList", params: [Param(name: "list", type: .listRef)],
                positionals: ["list"], signature: [.param("list")], writes: true) { c, a in
            try c.unarchiveList(try a.required("list")); return .change
        },

        // MARK: History and sync
        Command(name: "log", usage: "[--actor GLOB] [--since 2h|DATE] [--batch B] [--task T] [--limit N]",
                doc: "What changed and who did it, newest first, one line per change, with how to undo it.",
                example: "tasks log --actor 'agent:*' --since 2h", section: .history,
                params: [Param(name: "actor", type: .text, optional: true), Param(name: "since", type: .text, optional: true),
                         Param(name: "batch", type: .text, optional: true), Param(name: "task", type: .ref, optional: true),
                         Param(name: "limit", type: .int, optional: true)],
                flags: [Flag(name: "actor", param: "actor", kind: .value("GLOB")), Flag(name: "since", param: "since", kind: .value("2h")),
                        Flag(name: "batch", param: "batch", kind: .value("B")), Flag(name: "task", param: "task", kind: .value("T")),
                        Flag(name: "limit", param: "limit", kind: .value("N"))], returns: "") { c, a in
            let limit = a["limit"].map { $0.intValue ?? Int($0.stringValue ?? "") ?? 20 } ?? 20
            let (j, t) = try c.logJSON(actor: a.text("actor"), since: a.text("since"), batch: a.text("batch"), task: a.text("task"), limit: limit)
            return .value(j, t)
        },
        Command(name: "undo", usage: "[<batch>] [--force]",
                doc: "Undo a change from the log: by batch id, or your newest one. Fields edited since are kept and reported, unless --force.",
                example: "tasks undo 2c1f9e", section: .history, method: "undo",
                params: [Param(name: "batch", type: .text, optional: true), Param(name: "force", type: .bool, optional: true)],
                positionals: ["batch"], flags: [Flag(name: "force", param: "force", kind: .constant(.bool(true)))],
                signature: [.param("batch")], writes: true) { c, a in
            try c.undo(a.text("batch"), force: a.bool("force")); return .change
        },
        Command(name: "redo", usage: "[--force]", doc: "Redo your newest undo.", example: "tasks redo", section: .history,
                params: [Param(name: "force", type: .bool, optional: true)],
                flags: [Flag(name: "force", param: "force", kind: .constant(.bool(true)))], writes: true) { c, a in
            try c.undo(nil, force: a.bool("force"), redo: true); return .change
        },
        Command(name: "sync", usage: "", doc: "Sync now (⌘R): push anything queued and pull.", example: "tasks sync", section: .history, returns: "") { c, _ in
            let s = try c.replica
            return .text("Synced: \(s.store.cursor) changes in the log, \(s.store.projection.pending.count) waiting to send.")
        },
        Command(name: "status", usage: "", doc: "The server, where the token comes from (never the token), the actor, and what's waiting to sync.",
                example: "tasks status", section: .history, returns: "", needs: .replica) { c, _ in
            let s = try c.replica
            let st = s.store
            let rejected = (try? String(contentsOf: s.directory.appendingPathComponent("rejected.jsonl"), encoding: .utf8))?
                .split(separator: "\n").count ?? 0
            let json = JSON(["server": .string(s.server.config.url.absoluteString), "token": .string("set, from \(s.server.tokenSource)"),
                             "actor": .string(s.actor), "replica": .string(s.directory.path), "cursor": .int(st.cursor),
                             "pending": .int(st.projection.pending.count), "rejected": .int(rejected)])
            return .value(json, ["server   \(s.server.config.url.absoluteString)", "token    set, from \(s.server.tokenSource)",
                                 "actor    \(s.actor)", "replica  \(c.env.pretty(s.directory))",
                                 "log      \(st.cursor) changes", "waiting  \(st.projection.pending.count) to send" + (rejected > 0 ? ", \(rejected) rejected" : "")])
        },

        // MARK: Code mode
        Command(name: "run", usage: "[<file>|-] [--dry-run]",
                doc: "Run a TypeScript script against the API in tasks.d.ts (tasks types), in a sandbox with no files or network. The whole script is one change.",
                example: "tasks run reschedule.ts --dry-run", section: .code, params: [Param(name: "file", type: .text, optional: true)],
                positionals: ["file"], returns: "", writes: true) { c, a in
            try await CodeMode.run(c, file: a.text("file"))
        },
        Command(name: "types", usage: "", doc: "Print tasks.d.ts: the API a tasks run script sees.", example: "tasks types",
                section: .code, returns: "", needs: .nothing) { _, _ in .text(TypeScript.declarations()) },
        Command(name: "mcp", usage: "", doc: "Serve MCP over stdio with two tools, tasks_types and tasks_run. For MCP clients without a shell.",
                example: "claude mcp add tasks -- tasks mcp", section: .code, returns: "", needs: .nothing) { c, _ in
            try await MCP.serve(c.env, options: c.options); return .text("")
        },
        Command(name: "help", usage: "[<command>]", doc: "This overview, or one command's flags and an example.", example: "tasks help move",
                section: .help, params: [Param(name: "command", type: .text, optional: true)], positionals: ["command"],
                returns: "", needs: .nothing) { _, a in
            .text(try Help.text(a.text("command")))
        },
    ]

    static func named(_ name: String) -> Command? { all.first { $0.name == name } }
    static var methods: [Command] { all.filter { $0.method != nil } }
    static func method(_ name: String) -> Command? { all.first { $0.method == name } }

    /// Every flag that takes a value, so argv can be split before the command is known.
    static let valueFlags: Set<String> = Set(all.flatMap(\.flags).filter(\.takesValue).map(\.name)).union(["actor", "server"])
}

/// Flags every command takes.
struct Options: Sendable {
    var json = false
    var ids = false
    var dryRun = false
    var cached = false
    var large = false
    var actor: String?
    var server: String?
}

/// argv → a command, its arguments and the global options.
enum Parser {
    struct Invocation {
        var command: Command
        var args: Args
        var options: Options
    }

    static func parse(_ argv: [String], stdin: () -> String) throws -> Invocation {
        var positionals: [String] = []
        var flags: [(String, String?)] = []
        var i = 0
        var onlyPositional = false
        while i < argv.count {
            let a = argv[i]
            i += 1
            if onlyPositional || a == "-" || !a.hasPrefix("-") {
                positionals.append(a)
                continue
            }
            if a == "--" { onlyPositional = true; continue }
            if a == "-h" { flags.append(("help", nil)); continue }
            guard a.hasPrefix("--") else { throw CLIError.usage("Unknown flag \(a).") }
            var name = String(a.dropFirst(2))
            var value: String?
            if let eq = name.firstIndex(of: "=") {
                value = String(name[name.index(after: eq)...])
                name = String(name[..<eq])
            } else if Commands.valueFlags.contains(name) {
                guard i < argv.count else { throw CLIError.usage("--\(name) needs a value.") }
                value = argv[i]
                i += 1
            }
            flags.append((name, value))
        }

        var command: Command
        if positionals.count >= 2, positionals[0] == "list", let c = Commands.named("list " + positionals[1]) {
            command = c
            positionals.removeFirst(2)
        } else if let first = positionals.first, let c = Commands.named(first) {
            command = c
            positionals.removeFirst()
        } else if positionals.isEmpty {
            command = Commands.named("help")!
        } else if positionals[0] == "list" {
            throw CLIError.usage("tasks list takes add, rename, move, archive or unarchive. (The sidebar is tasks lists.)")
        } else {
            throw CLIError.usage("Unknown command \"\(positionals[0])\". tasks help lists them.")
        }

        var options = Options()
        var args: Args = [:]
        for (name, value) in flags {
            if name == "help" {
                return Invocation(command: Commands.named("help")!, args: ["command": .string(command.name)], options: options)
            }
            if let f = command.flags.first(where: { $0.name == name }) {
                switch f.kind {
                case .constant(let v): args[f.param] = v
                case .value: args[f.param] = .string(value ?? "")
                case .wrap(let key, _): args[f.param] = JSON([key: .string(value ?? "")])
                }
                continue
            }
            switch name {
            case "json": options.json = true
            case "ids": options.ids = true
            case "dry-run": options.dryRun = true
            case "cached": options.cached = true
            case "large": options.large = true
            case "actor": options.actor = value
            case "server": options.server = value
            default: throw CLIError.usage("tasks \(command.name) has no --\(name). tasks help \(command.name) shows its flags.")
            }
        }

        // Positionals fill the command's positional params in order; a refs param takes the rest.
        var rest = positionals[...]
        for name in command.positionals {
            guard let p = command.param(name), !rest.isEmpty else { continue }
            if p.type == .refs {
                args[name] = .array(rest.map(JSON.string))
                rest = []
            } else {
                args[name] = .string(rest.removeFirst())
            }
        }
        if let extra = rest.first {
            throw CLIError.usage("Unexpected argument \"\(extra)\". Quote titles and names with spaces. Usage: tasks \(command.name) \(command.usage)")
        }
        for p in command.params where !p.optional && args[p.name] == nil {
            throw CLIError.usage("tasks \(command.name) needs <\(p.name)>. Usage: tasks \(command.name) \(command.usage)")
        }

        // `-` reads stdin: one ref per line, or a text argument whole.
        var usedStdin = false
        func stdinOnce() throws -> String {
            guard !usedStdin else { throw CLIError.usage("Only one argument can read stdin.") }
            usedStdin = true
            return stdin()
        }
        for (k, v) in args {
            if case .array(let items) = v, items.contains(.string("-")) {
                var out: [JSON] = []
                for item in items {
                    if item == .string("-") {
                        out += try stdinOnce().split(whereSeparator: \.isNewline)
                            .map { $0.split(separator: "\t").first.map(String.init) ?? "" }
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(JSON.string)
                    } else {
                        out.append(item)
                    }
                }
                guard !out.isEmpty else { throw CLIError.usage("No refs on stdin.") }
                args[k] = .array(out)
            } else if v == .string("-"), command.param(k)?.type == .text, k != "file" {
                args[k] = .string(try stdinOnce())
            }
        }
        return Invocation(command: command, args: args, options: options)
    }
}

/// `tasks help`, written for a model reading it cold: one line per command, then the conventions.
enum Help {
    static func text(_ name: String?) throws -> String {
        if let name {
            guard let c = Commands.named(name) ?? Commands.named("list " + name) else {
                throw CLIError.usage("No command \"\(name)\". tasks help lists them.")
            }
            var lines = ["tasks \(c.name)\(c.usage.isEmpty ? "" : " " + c.usage)", "", c.doc]
            if c.writes { lines.append("It's one change: --dry-run previews it, and the output names the undo.") }
            if let m = c.method { lines.append("Code mode: tasks.\(m)(…) (tasks types).") }
            lines += ["", "Example:", "  " + c.example]
            return lines.joined(separator: "\n")
        }
        var lines = [
            "tasks: your Tasks lists from the command line. It's a replica of the same log the Mac app syncs, so",
            "it sees exactly what the app shows. Every write is one change that syncs at once and can be undone.",
        ]
        for s in Section.allCases {
            lines += ["", s.rawValue]
            for c in Commands.all where c.section == s {
                let head = "  tasks \(c.name)\(c.usage.isEmpty ? "" : " " + c.usage)"
                lines.append(head)
                lines.append("      " + c.doc)
            }
        }
        lines += [
            "",
            "Refs: a task or list id, a unique id prefix of 4+ characters (output shows 6), or a list's name.",
            "      - in a ref position reads refs from stdin, one per line: tasks find milk --ids | tasks done -",
            "Dates: 2026-11-06, today, tomorrow, fri, next week, 3d, nov 9, the 9th; none clears. tasks date checks one.",
            "Global flags: --json (the objects code mode returns)  --ids (one id per line)  --dry-run  --cached (no sync)",
            "              --actor A (default: TASKS_ACTOR, agent:claude-code under Claude Code, else cli)  --server URL  --large",
            "Exit codes: 0 done and synced · 75 applied but not yet synced (offline) · 1 error, nothing written · 2 usage.",
            "tasks help <command> shows one command with an example.",
        ]
        return lines.joined(separator: "\n")
    }
}

/// `tasks.d.ts`, generated from the table and the shared shapes, so it can't drift from what the host accepts.
enum TypeScript {
    static func declarations() -> String {
        func iface(_ name: String, _ fields: [Field]) -> String {
            "interface \(name) {\n" + fields.map { "  \($0.name)\($0.optional ? "?" : ""): \($0.ts);" }.joined(separator: "\n") + "\n}"
        }
        var out = [
            "// tasks.d.ts: the API a `tasks run` script sees. Run one with `tasks run script.ts` (--dry-run to preview).",
            "// The whole script is one change: written when it returns, nothing written if it throws. `return` a value to",
            "// get it back; console.log lines come back too. No files, network or env: only `tasks`.",
            "",
            "/** A day, \"YYYY-MM-DD\", no time or zone. Compares correctly as a string. */",
            "type CalendarDate = string;",
            "/** \"YYYY-MM-DD\", or what the app's date field reads: \"today\", \"fri\", \"next week\", \"3d\", \"nov 9\". null clears. */",
            "type DateInput = string | null;",
            "/** A task or list id, a unique id prefix (4+ chars), or for lists a name. */",
            "type Ref = string;",
            "/** up/down: one slot among the list's open tasks. after/before: next to an open task, in its list. */",
            "type Place = \"top\" | \"bottom\" | \"up\" | \"down\" | { after: Ref } | { before: Ref };",
            "",
            iface("Task", Shapes.task),
            iface("List", Shapes.list),
            "/** What a write did. `batch` is this run's change id (tasks log, tasks undo). */",
            iface("Change", Shapes.change),
            "",
            "declare const tasks: {",
        ]
        for c in Commands.methods {
            let args = c.signature.map { arg -> String in
                switch arg {
                case .param(let n):
                    let p = c.param(n)!
                    return "\(n)\(p.optional ? "?" : ""): \(p.type.ts)"
                case .object(let n, let fields):
                    let inner = fields.map { f in
                        let p = c.param(f)!
                        return "\(f)\(p.optional ? "?" : ""): \(p.type.ts)"
                    }.joined(separator: "; ")
                    let allOptional = fields.allSatisfy { c.param($0)!.optional }
                    return "\(n)\(allOptional ? "?" : ""): { \(inner) }"
                }
            }.joined(separator: ", ")
            out.append("  /** \(c.doc) */")
            out.append("  \(c.method!)(\(args)): Promise<\(c.returns)>;")
        }
        out.append("};")
        return out.joined(separator: "\n") + "\n"
    }
}
