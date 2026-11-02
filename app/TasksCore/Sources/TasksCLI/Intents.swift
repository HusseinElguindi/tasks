import CryptoKit
import Foundation
import TasksCore

/// Where a task or list goes (`Ordering.Anchor`, plus ⌥⌘↑ / ⌥⌘↓).
enum Place: Equatable {
    case top, bottom, up, down
    case after(String)
    case before(String)
}

/// A date argument: absent, cleared, or a day.
enum DateArg: Equatable {
    case clear
    case day(CalendarDate)

    var value: CalendarDate? { if case .day(let d) = self { d } else { nil } }
}

/// One command or code-mode run: the replica, the fork its writes are built on, and its batch id.
@MainActor
final class Context {
    let env: Environment
    let session: Session?
    let options: Options
    /// Every op of this command or run carries it (§4). An undo uses the id derived from what it undoes.
    var batch: String
    private(set) var batchFixed = false
    private(set) var fork: Store?
    private var forkDir: URL?
    private var forkBase = 0
    /// Undo: later edits it kept rather than overwrite (§4 "Conflicts").
    var skipped: [String] = []
    /// Undo: "Undo: Move 3 Tasks to School" rather than a description of the inverse ops.
    var summaryOverride: String?
    /// `tasks run`: 1 when the script failed, 75 when its change isn't synced yet.
    var exitCode: Int32?

    init(env: Environment, session: Session?, options: Options) {
        self.env = env
        self.session = session
        self.options = options
        batch = UUID().uuidString.lowercased()
    }

    var replica: Session {
        get throws {
            guard let session else { throw CLIError(kind: .config, message: "This command needs the replica.") }
            return session
        }
    }

    /// What reads see: the fork once anything has been written (so a script reads its own writes), else the replica.
    var store: Store {
        get throws { try fork ?? replica.store }
    }

    var p: Projection { get throws { try store.projection } }
    var resolve: Resolver { get throws { Resolver(p: try p) } }
    var today: CalendarDate { get throws { try p.day.date } }

    func writable() throws -> Store {
        if let fork { return fork }
        let (f, dir) = try replica.fork()
        fork = f
        forkDir = dir
        forkBase = f.projection.pending.count
        return f
    }

    /// The ops this command has made, oldest first.
    var ops: [Op] { fork.map { Array($0.projection.pending.dropFirst(forkBase).map(\.op)) } ?? [] }

    /// Pins the batch id (an undo). Only before anything else is written, and only once.
    func fixBatch(_ id: String) throws {
        guard ops.isEmpty, !batchFixed else {
            throw CLIError.invalid("An undo must be the only change in a command or run.")
        }
        batch = id
        batchFixed = true
    }

    func requireUnfixed() throws {
        if batchFixed { throw CLIError.invalid("An undo must be the only change in a command or run.") }
    }

    private(set) var committed = false
    private(set) var synced = true

    /// Writes this command's ops to the replica as one batch and syncs (once). Returns whether they're in the log.
    func commit() async throws -> Bool {
        guard !committed else { return synced }
        committed = true
        let ops = self.ops
        guard !ops.isEmpty else { return synced }
        if ops.count > 500 && !options.large {
            throw CLIError(kind: .limit, message: "This change is \(ops.count) ops; one change is at most 500 unless you pass --large (then it isn't atomic on the wire).")
        }
        synced = try await replica.commit(ops, batch: batch, push: !options.cached)
        return synced
    }

    func cleanup() {
        fork?.persistNow()
        if let forkDir { try? FileManager.default.removeItem(at: forkDir) }
    }

    // MARK: The change

    /// Entities the ops from index `from` touched, in first-touch order, with their state before this command
    /// (from the replica) and after (`view`).
    func changes(from: Int = 0, view: Projection? = nil) throws -> [EntityChange] {
        let before = try replica.store.projection
        let after = try view ?? p
        var seenTasks = Set<String>(), seenLists = Set<String>()
        var out: [EntityChange] = []
        for op in ops.dropFirst(from) {
            if op.type.isTask, seenTasks.insert(op.target).inserted, let a = after.task(op.target) {
                out.append(.task(before: before.task(op.target), after: a))
            } else if op.type.isList, seenLists.insert(op.target).inserted, let a = after.list(op.target) {
                out.append(.list(before: before.list(op.target), after: a))
            }
        }
        return out
    }

    func summary(_ cs: [EntityChange], _ p: Projection) -> String {
        if let summaryOverride, !cs.isEmpty { return summaryOverride }
        return describe(p).summary(cs)
    }

    func describe(_ p: Projection) -> Describe {
        Describe(listName: { p.list($0)?.name ?? "(missing list)" }, today: p.day.date)
    }

    /// A `Change` (§3): the batch, a summary in the app's undo names, and the entities after it.
    func changeJSON(from: Int = 0, view: Projection? = nil, extra: KeyValuePairs<String, JSON> = [:]) throws -> JSON {
        let v = try view ?? p
        let cs = try changes(from: from, view: v)
        let r = Render(v)
        var members: [JSON.Member] = [
            .init(key: "batch", value: ops.count > from ? .string(batch) : .null),
            .init(key: "summary", value: .string(summary(cs, v))),
            .init(key: "tasks", value: .array(cs.compactMap { if case .task(_, let a) = $0 { r.task(a) } else { nil } })),
            .init(key: "lists", value: .array(cs.compactMap { if case .list(_, let a) = $0 { r.list(a) } else { nil } })),
        ]
        if !skipped.isEmpty { members.append(.init(key: "skipped", value: .array(skipped.map(JSON.string)))) }
        members += extra.map { JSON.Member(key: $0.key, value: $0.value) }
        return .object(members)
    }

    // MARK: Arguments

    func date(_ v: JSON?, field: String) throws -> DateArg? {
        guard let v else { return nil }
        if v.isNull { return .clear }
        guard let text = v.stringValue?.trimmingCharacters(in: .whitespaces) else {
            throw CLIError.invalid("\(field) must be a date, a phrase like \"fri\", or null.", field: field)
        }
        if ["none", "null", "clear"].contains(text.lowercased()) { return .clear }
        guard let d = try resolveDate(text) else {
            throw CLIError.invalid("\"\(text)\" isn't a date (try 2026-11-06, today, tomorrow, fri, next week, 3d, nov 9).", field: field)
        }
        return .day(d)
    }

    /// What the date field reads on Return (`DatePhrase.match`, INTERACTIONS-v2 §11), or an exact YYYY-MM-DD.
    func resolveDate(_ text: String) throws -> CalendarDate? {
        if let d = CalendarDate(text) { return d }
        return DatePhrase.match(text, today: try today, numericOrder: numericOrder)
    }

    var numericOrder: DatePhrase.NumericOrder {
        switch env["TASKS_DATE_ORDER"] {
        case "dm": .dayFirst
        case "md": .monthFirst
        default: DatePhrase.numericOrder(for: .current)
        }
    }

    func place(_ v: JSON?, field: String = "place") throws -> Place? {
        guard let v, !v.isNull else { return nil }
        if let s = v.stringValue {
            switch s {
            case "top": return .top
            case "bottom": return .bottom
            case "up": return .up
            case "down": return .down
            default: break
            }
        }
        if let a = v["after"]?.stringValue { return .after(a) }
        if let b = v["before"]?.stringValue { return .before(b) }
        throw CLIError.invalid("\(field) must be \"top\", \"bottom\", \"up\", \"down\", {after: ref} or {before: ref}.", field: field)
    }

    static func text(_ s: String, field: String, max: Int, nonEmpty: Bool) throws -> String {
        if nonEmpty, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError.invalid("\(field) can't be empty.", field: field)
        }
        guard s.utf16.count <= max else {
            throw CLIError(kind: .limit, message: "\(field) is \(s.utf16.count) characters; the limit is \(max) (UTF-16 units).", field: field)
        }
        return s
    }

    /// A stable id from a key: a lowercase UUIDv8 from SHA-256 (`add --key`, and undo batch ids).
    static func derivedID(_ seed: String) -> String {
        var b = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x80
        b[8] = (b[8] & 0x3F) | 0x80
        let hex = b.map { String(format: "%02x", $0) }.joined()
        let i = hex.startIndex
        func s(_ a: Int, _ z: Int) -> Substring { hex[hex.index(i, offsetBy: a)..<hex.index(i, offsetBy: z)] }
        return "\(s(0, 8))-\(s(8, 12))-\(s(12, 16))-\(s(16, 20))-\(s(20, 32))"
    }
}

// MARK: - Intents: every UI operation, on the fork (docs/SDK-PLAN.md §3)

extension Context {
    func add(title: String, list: String?, notes: String?, when: DateArg?, deadline: DateArg?, place: Place?,
             id: String?, key: String?) throws -> TaskItem {
        try requireUnfixed()
        let title = try Self.text(title, field: "title", max: 1000, nonEmpty: true)
        let notes = try Self.text(notes ?? "", field: "notes", max: 20000, nonEmpty: false)
        if id != nil && key != nil { throw CLIError.invalid("Pass id or key, not both.", field: "key") }
        if let id, !(1...64).contains(id.utf16.count) { throw CLIError.invalid("An id is 1 to 64 characters.", field: "id") }
        let taskID = id ?? key.map { Self.derivedID("key:" + $0) }
        // Same id, same task: repeating an add with a key writes nothing (§3 "Ids are stable").
        if let taskID, let existing = try p.task(taskID) { return existing }

        let r = try resolve
        var anchorTask: TaskItem?
        switch place {
        case .up, .down: throw CLIError.invalid("A new task can't move up or down.", field: "place")
        case .after(let a), .before(let a):
            anchorTask = try r.task(a)
            guard anchorTask?.completedAt == nil else { throw CLIError.invalid("Place it next to an open task.", field: "place") }
        default: break
        }
        let explicit = try list.map(r.list)
        if let explicit, let anchorTask, anchorTask.list != explicit.id {
            throw CLIError.invalid("The place is in \(try p.list(anchorTask.list)?.name ?? "another list"), not \(explicit.name).", field: "place")
        }
        let s = try writable()
        guard let listID = explicit?.id ?? anchorTask?.list ?? s.defaultListID else {
            throw CLIError(kind: .noActiveList, message: "There's no active list to add to. Add one with tasks list add NAME.")
        }
        guard let newID = s.createTask(id: taskID, title: title, notes: notes, in: listID, when: when?.value,
                                       deadline: deadline?.value) else {
            throw CLIError(kind: .noActiveList, message: "There's no active list to add to.")
        }
        if let place, place != .bottom {
            s.reorder([newID], in: listID, at: anchor(place, anchorTask))
        }
        return s.projection.task(newID)!
    }

    private func anchor(_ place: Place, _ task: TaskItem?) -> Ordering.Anchor {
        switch place {
        case .top: .top
        case .after: .after(task!.id)
        case .before: .before(task!.id)
        default: .bottom
        }
    }

    func rename(_ ref: String, _ title: String) throws {
        try requireUnfixed()
        let title = try Self.text(title, field: "title", max: 1000, nonEmpty: true)
        let t = try resolve.task(ref)
        try writable().setTitle(t.id, title)
    }

    func setNotes(_ ref: String, _ notes: String, append: Bool) throws {
        try requireUnfixed()
        let t = try resolve.task(ref)
        var text = notes
        if append, !t.notes.isEmpty { text = t.notes + (t.notes.hasSuffix("\n") ? "" : "\n") + notes }
        text = try Self.text(text, field: "notes", max: 20000, nonEmpty: false)
        try writable().setNotes(t.id, text)
    }

    /// Completing, dates and Move to don't apply to a heading (§23): name it and write nothing.
    func refuseHeadings(_ tasks: [TaskItem], field: String = "tasks") throws {
        if let h = tasks.first(where: \.isHeading) {
            throw CLIError.invalid("\(h.title.isEmpty ? "(untitled)" : h.title) is a heading; headings have no completion or dates and stay in their list.",
                                   field: field)
        }
    }

    func complete(_ refs: [String]) throws {
        try requireUnfixed()
        let tasks = try resolve.tasks(refs)
        try refuseHeadings(tasks)
        let open = tasks.filter { $0.completedAt == nil }.map(\.id)
        if !open.isEmpty { try writable().toggleComplete(open) }
    }

    func uncomplete(_ refs: [String]) throws {
        try requireUnfixed()
        let tasks = try resolve.tasks(refs)
        try refuseHeadings(tasks)
        let done = tasks.filter { $0.completedAt != nil }.map(\.id)
        if !done.isEmpty { try writable().toggleComplete(done) }
    }

    /// ⌘K: completes all unless all are done, then uncompletes all.
    func toggle(_ refs: [String]) throws {
        try requireUnfixed()
        let tasks = try resolve.tasks(refs)
        try refuseHeadings(tasks)
        let ids = tasks.map(\.id)
        try writable().toggleComplete(ids)
    }

    func setWhen(_ refs: [String], _ date: DateArg?) throws {
        try requireUnfixed()
        guard let date else { throw CLIError.invalid("Give a date, or none to remove When.", field: "date") }
        let tasks = try resolve.tasks(refs)
        try refuseHeadings(tasks)
        let ids = tasks.map(\.id)
        try writable().setWhen(ids, date.value)
    }

    func setDeadline(_ refs: [String], _ date: DateArg?) throws {
        try requireUnfixed()
        guard let date else { throw CLIError.invalid("Give a date, or none to remove the deadline.", field: "date") }
        let tasks = try resolve.tasks(refs)
        try refuseHeadings(tasks)
        let ids = tasks.map(\.id)
        try writable().setDeadline(ids, date.value)
    }

    func delete(_ refs: [String]) throws {
        try requireUnfixed()
        let ids = try resolve.tasks(refs).map(\.id)
        try writable().delete(ids)
    }

    /// `deleted: false`, for when there's no undo stack to bring a task back.
    func restore(_ refs: [String]) throws {
        try requireUnfixed()
        let gone = try resolve.tasks(refs, includeDeleted: true).filter(\.deleted)
        guard !gone.isEmpty else { return }
        let s = try writable()
        s.perform(gone.map { Op(id: s.newID(), at: env.nowMs, type: .taskUpdate, target: $0.id, set: Patch(deleted: false)) })
    }

    func move(_ refs: [String], list: String?, place: Place?) throws {
        try requireUnfixed()
        let r = try resolve
        let tasks = try r.tasks(refs)
        let ids = tasks.map(\.id)
        guard list != nil || place != nil else {
            throw CLIError.invalid("Say where: a list (--to) or a place (--top, --after REF, --up…).", field: "to")
        }
        let target = try list.map(r.list)
        if tasks.contains(where: \.isHeading) {
            try moveHeading(tasks, to: target, place: place)
            return
        }
        func refuseArchived(_ listID: EntityID) throws {
            if let l = try p.list(listID), l.archivedAt != nil, tasks.contains(where: { $0.list != listID }) {
                throw CLIError.invalid("\(l.name) is archived; unarchive it first.", field: "to")
            }
        }
        guard let place else {
            try refuseArchived(target!.id)
            try writable().move(ids, to: target!.id)
            return
        }
        if tasks.contains(where: { $0.completedAt != nil }) {
            throw CLIError.invalid("Completed tasks have no place among the open ones; mark them not done first.", field: "place")
        }
        switch place {
        case .up, .down:
            guard tasks.count == 1, let t = tasks.first else { throw CLIError.invalid("--up and --down move one task.", field: "place") }
            if let target, target.id != t.list { throw CLIError.invalid("--up and --down move a task within its own list.", field: "place") }
            let items = try p.orderedOpenTasks(in: t.list)
            guard let i = items.firstIndex(where: { $0.id == t.id }) else { return }
            if place == .up, i > 0 {
                try writable().reorder([t.id], in: t.list, at: .before(items[i - 1].id))
            } else if place == .down, i + 1 < items.count {
                try writable().reorder([t.id], in: t.list, at: .after(items[i + 1].id))
            }
        case .after(let a), .before(let a):
            let anchorTask = try r.task(a)
            if ids.contains(anchorTask.id) { throw CLIError.invalid("A task can't be placed next to itself.", field: "place") }
            guard anchorTask.completedAt == nil else { throw CLIError.invalid("Place them next to an open task.", field: "place") }
            if let target, target.id != anchorTask.list {
                throw CLIError.invalid("\(a) is in \(try p.list(anchorTask.list)?.name ?? "another list"), not \(target.name).", field: "place")
            }
            try refuseArchived(anchorTask.list)
            let at: Ordering.Anchor = if case .after = place { .after(anchorTask.id) } else { .before(anchorTask.id) }
            try writable().reorder(ids, in: anchorTask.list, at: at)
        case .top, .bottom:
            let lists = Set(tasks.map(\.list))
            guard let listID = target?.id ?? (lists.count == 1 ? lists.first : nil) else {
                throw CLIError.invalid("The tasks are in different lists; say which with --to.", field: "to")
            }
            try refuseArchived(listID)
            try writable().reorder(ids, in: listID, at: place == .top ? .top : .bottom)
        }
    }

    /// `move <heading>`: its section moves with it (§23). It lands only before another heading or at the end, never
    /// inside a section or above the tasks that have no heading:
    /// - `--before H`: before heading H (a task as the anchor is an error);
    /// - `--after R`: after the whole section R is in (R's own if it's a heading), so before the next heading or at
    ///   the end; after a task above the first heading, that's before the first heading;
    /// - `--top`: before the first heading; `--bottom`: the end; `--up` / `--down`: past the previous / next section.
    private func moveHeading(_ tasks: [TaskItem], to target: TaskList?, place: Place?) throws {
        guard tasks.count == 1, let h = tasks.first else {
            throw CLIError.invalid("Move a heading on its own: its tasks go with it.", field: "tasks")
        }
        if let target, target.id != h.list { try refuseHeadings([h], field: "to") }
        guard let place else { return }
        let p = try self.p
        let others = p.headings(in: h.list).ids.filter { $0 != h.id }
        let mine = p.headings(in: h.list).ids.firstIndex(of: h.id) ?? 0
        /// Before the first heading after `section` (nil: the tasks above the first heading), or the end.
        func after(section: EntityID?) -> Ordering.Anchor {
            guard let section else { return others.first.map { .before($0) } ?? .bottom }
            let all = p.headings(in: h.list).ids
            let i = all.firstIndex(of: section) ?? all.count
            return all[(i + 1)...].first { $0 != h.id }.map { .before($0) } ?? .bottom
        }
        let anchor: Ordering.Anchor?
        switch place {
        case .top: anchor = others.first.map { .before($0) }
        case .bottom: anchor = .bottom
        case .up: anchor = mine > 0 ? .before(others[mine - 1]) : nil
        case .down: anchor = mine < others.count ? (mine + 1 < others.count ? .before(others[mine + 1]) : .bottom) : nil
        case .after(let ref), .before(let ref):
            let r = try resolve.task(ref)
            guard r.list == h.list else {
                throw CLIError.invalid("\(ref) is in \(p.list(r.list)?.name ?? "another list"); a heading stays in its list.", field: "place")
            }
            if case .before = place {
                guard r.isHeading else {
                    throw CLIError.invalid("A heading goes before another heading, or --after a row (it lands after that row's section).",
                                           field: "place")
                }
                anchor = r.id == h.id ? nil : .before(r.id)
            } else {
                anchor = after(section: r.isHeading ? r.id : p.heading(of: r.id))
            }
        }
        guard let anchor, !isWhere(h.id, anchor, p) else { return }
        try writable().moveSection(h.id, at: anchor)
    }

    /// Whether a heading's section already ends right before `anchor`'s heading (or at the end, for `.bottom`).
    private func isWhere(_ heading: EntityID, _ anchor: Ordering.Anchor, _ p: Projection) -> Bool {
        guard let t = p.task(heading) else { return true }
        let all = p.orderedTasksIncludingCompleted(in: t.list).map(\.id)
        guard let last = p.section(of: heading).last, let i = all.firstIndex(of: last) else { return false }
        let next = i + 1 < all.count ? all[i + 1] : nil
        switch anchor {
        case .bottom: return next == nil
        case .before(let id): return next == id
        default: return false
        }
    }

    // MARK: Headings and a list's notes (§23)

    /// A heading: above `--before R`, after `--after R` (after R's section when R is a heading), at the top, or at
    /// the bottom (the default). No list means the place's list, else the first list.
    func addHeading(name: String, list: String?, notes: String?, place: Place?) throws -> TaskItem {
        try requireUnfixed()
        let name = try Self.text(name, field: "name", max: 1000, nonEmpty: true)
        let notes = try Self.text(notes ?? "", field: "notes", max: 20000, nonEmpty: false)
        let r = try resolve
        var anchorRow: TaskItem?
        switch place {
        case .up, .down: throw CLIError.invalid("A new heading can't move up or down.", field: "place")
        case .after(let a), .before(let a):
            anchorRow = try r.task(a)
            guard anchorRow?.completedAt == nil else { throw CLIError.invalid("Place it next to an open task or a heading.", field: "place") }
        default: break
        }
        let explicit = try list.map(r.list)
        if let explicit, let anchorRow, anchorRow.list != explicit.id {
            throw CLIError.invalid("The place is in \(try p.list(anchorRow.list)?.name ?? "another list"), not \(explicit.name).", field: "place")
        }
        let s = try writable()
        guard let listID = explicit?.id ?? anchorRow?.list ?? s.defaultListID else {
            throw CLIError(kind: .noActiveList, message: "There's no active list to add to. Add one with tasks list add NAME.")
        }
        if let l = s.projection.list(listID), l.archivedAt != nil {
            throw CLIError.invalid("\(l.name) is archived; unarchive it first.", field: "list")
        }
        let anchor: Ordering.Anchor
        switch place {
        case .top: anchor = .top
        case .before: anchor = .before(anchorRow!.id)
        case .after:
            // After a heading means after its section: before the next heading, or the end.
            if anchorRow!.isHeading {
                let all = s.projection.headings(in: listID).ids
                let i = all.firstIndex(of: anchorRow!.id) ?? all.count
                anchor = i + 1 < all.count ? .before(all[i + 1]) : .bottom
            } else {
                anchor = .after(anchorRow!.id)
            }
        default: anchor = .bottom
        }
        guard let id = s.createHeading(title: name, notes: notes, in: listID, at: anchor) else {
            throw CLIError(kind: .noActiveList, message: "There's no active list to add to.")
        }
        return s.projection.task(id)!
    }

    func setListNotes(_ ref: String, _ notes: String, append: Bool) throws {
        try requireUnfixed()
        let l = try resolve.list(ref)
        var text = notes
        if append, !l.notes.isEmpty { text = l.notes + (l.notes.hasSuffix("\n") ? "" : "\n") + notes }
        text = try Self.text(text, field: "notes", max: 20000, nonEmpty: false)
        try writable().setNotes(list: l.id, text)
    }

    // MARK: Lists

    func addList(_ name: String, place: Place?) throws -> TaskList {
        try requireUnfixed()
        let name = try Self.text(name, field: "name", max: 200, nonEmpty: true)
        let anchor = try listAnchor(place, moving: nil)
        let s = try writable()
        let id = s.createList(name: name)
        if let anchor { s.reorderLists([id], at: anchor) }
        return s.projection.list(id)!
    }

    func renameList(_ ref: String, _ name: String) throws {
        try requireUnfixed()
        let name = try Self.text(name, field: "name", max: 200, nonEmpty: true)
        let l = try resolve.list(ref)
        try writable().rename(list: l.id, to: name)
    }

    func moveList(_ ref: String, _ place: Place?) throws {
        try requireUnfixed()
        let l = try resolve.list(ref)
        guard l.archivedAt == nil else { throw CLIError.invalid("\(l.name) is archived, so it isn't in the sidebar.", field: "list") }
        guard let place else { throw CLIError.invalid("Give a place: top, bottom, up, down, or after/before a list.", field: "place") }
        if let anchor = try listAnchor(place, moving: l) { try writable().reorderLists([l.id], at: anchor) }
    }

    /// nil means "the bottom" for a new list, or "nowhere to go" for ⌥⌘↑ on the first list.
    private func listAnchor(_ place: Place?, moving: TaskList?) throws -> Ordering.Anchor? {
        guard let place else { return nil }
        let items = try p.orderedActiveLists()
        switch place {
        case .top: return .top
        case .bottom: return moving == nil ? nil : .bottom
        case .up, .down:
            guard let moving, let i = items.firstIndex(where: { $0.id == moving.id }) else {
                throw CLIError.invalid("A new list can't move up or down.", field: "place")
            }
            if place == .up { return i > 0 ? .before(items[i - 1].id) : nil }
            return i + 1 < items.count ? .after(items[i + 1].id) : nil
        case .after(let ref), .before(let ref):
            let other = try resolve.list(ref)
            guard other.archivedAt == nil else { throw CLIError.invalid("\(other.name) is archived.", field: "place") }
            if other.id == moving?.id { throw CLIError.invalid("A list can't be placed next to itself.", field: "place") }
            if case .after = place { return .after(other.id) }
            return .before(other.id)
        }
    }

    func archiveList(_ ref: String) throws {
        try requireUnfixed()
        let l = try resolve.list(ref)
        try writable().deleteList(l.id)
    }

    func unarchiveList(_ ref: String) throws {
        try requireUnfixed()
        let l = try resolve.list(ref)
        try writable().restoreList(l.id)
    }

    // MARK: Views

    func todayJSON() throws -> (JSON, [String]) {
        let p = try self.p
        let r = Render(p)
        var groups: [JSON] = []
        var text = ["Today · \(DateLabel.long(p.day.date, today: p.day.date))"]
        for id in p.activeLists.ids {
            let tasks = r.tasks(p.todayTasks(in: id).ids)
            guard !tasks.isEmpty, let l = p.list(id) else { continue }
            groups.append(JSON(["list": r.list(l), "tasks": .array(tasks.map(r.task))]))
            text.append(l.name)
            text += r.rows(tasks, inToday: true)
        }
        let done = r.tasks(p.todayDone.ids)
        if !done.isEmpty {
            text.append("Completed")
            text += r.rows(done, showList: true)
        }
        if groups.isEmpty && done.isEmpty { text.append("  Nothing for today.") }
        return (JSON(["date": .string(p.day.date.string), "groups": .array(groups), "done": .array(done.map(r.task))]), text)
    }

    func listsJSON() throws -> (JSON, [String]) {
        let p = try self.p
        let r = Render(p)
        let lists = p.activeLists.ids.compactMap(p.list)
        return (.array(lists.map(r.list)), lists.map(r.listRow))
    }

    func archiveJSON() throws -> (JSON, [String]) {
        let p = try self.p
        let r = Render(p)
        let lists = p.deletedLists.ids.compactMap(p.list)
        return (.array(lists.map(r.list)), lists.isEmpty ? ["  No archived lists."] : lists.map(r.listRow))
    }

    func listJSON(_ ref: String?, done: Bool) throws -> (JSON, [String]) {
        let p = try self.p
        let r = Render(p)
        let l: TaskList
        if let ref { l = try resolve.list(ref) } else {
            guard let id = p.activeLists.ids.first, let first = p.list(id) else {
                throw CLIError(kind: .noActiveList, message: "There are no lists. Add one with tasks list add NAME.")
            }
            l = first
        }
        let open = r.tasks(p.openTasks(in: l.id).ids)
        let completed = r.tasks(p.completedTasks(in: l.id).ids)
        var text = [l.name + (l.archivedAt.map { " · Archived \(r.archivedDate($0))" } ?? "")]
        if !l.notes.isEmpty { text += l.notes.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 } }
        text += open.isEmpty ? ["  No open tasks."] : r.sections(open)
        if done, !completed.isEmpty {
            text.append("Completed")
            text += r.rows(completed)
        } else if !completed.isEmpty {
            text.append("  + \(completed.count) completed (--done shows them)")
        }
        return (JSON(["list": r.list(l), "open": .array(open.map(r.task)), "completed": .array(completed.map(r.task))]), text)
    }

    func find(text: String?, list: String?, done: Bool?, deleted: Bool) throws -> (JSON, [String]) {
        let p = try self.p
        let r = Render(p)
        let listID = try list.map { try resolve.list($0).id }
        let rank = Dictionary(uniqueKeysWithValues: (p.activeLists.ids + p.deletedLists.ids).enumerated().map { ($1, $0) })
        let needle = text?.trimmingCharacters(in: .whitespaces) ?? ""
        let matches = p.allTaskIDs.compactMap(p.task).filter { t in
            !t.isHeading && (deleted || !t.deleted) && (listID == nil || t.list == listID) && (done == nil || (t.completedAt != nil) == done)
                && (needle.isEmpty || t.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || t.notes.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }.sorted { a, b in
            if (a.completedAt != nil) != (b.completedAt != nil) { return a.completedAt == nil }
            let ra = rank[a.list] ?? Int.max, rb = rank[b.list] ?? Int.max
            if ra != rb { return ra < rb }
            if a.completedAt != nil, a.completedAt != b.completedAt { return (a.completedAt ?? 0) > (b.completedAt ?? 0) }
            return orderPrecedes(a.order, a.id, b.order, b.id)
        }
        return (.array(matches.map(r.task)), matches.isEmpty ? ["  No matching tasks."] : r.rows(matches, showList: true))
    }
}
