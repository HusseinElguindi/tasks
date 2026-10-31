import Foundation
import TasksCore

/// The log grouped into changes (docs/SDK-PLAN.md §4 "Review"): ops with a `batch` by batch; ops without one
/// (the app's) by request, i.e. contiguous entries received together. Pending ops come last, unconfirmed.
@MainActor
struct History {
    struct Group {
        var key: String
        var batch: String?
        var actor: String
        /// Server time for confirmed ops, the client's `at` for pending ones.
        var time: Int
        var confirmed: Bool
        var ops: [Op] = []
        var order: [String] = []
        var beforeTasks: [EntityID: TaskItem?] = [:]
        var beforeLists: [EntityID: TaskList?] = [:]
        var afterTasks: [EntityID: TaskItem] = [:]
        var afterLists: [EntityID: TaskList] = [:]

        var changes: [EntityChange] {
            order.compactMap { id in
                if let a = afterTasks[id] { return .task(before: beforeTasks[id] ?? nil, after: a) }
                if let a = afterLists[id] { return .list(before: beforeLists[id] ?? nil, after: a) }
                return nil
            }
        }

        var touches: Set<EntityID> { Set(order) }
    }

    var groups: [Group] = []
    private var byKey: [String: Int] = [:]
    /// Undo batch id → the batch it undoes.
    private var originals: [String: String] = [:]

    init(entries: [LogEntry], pending: [Op]) {
        var state = AppState()
        var lastKey: String?
        let items = entries.map { ($0.op, $0.received, true) } + pending.map { ($0, $0.at, false) }
        for (op, time, confirmed) in items {
            let key: String
            if let b = op.batch {
                key = "batch:" + b
            } else if confirmed {
                // Contiguous entries received together are one request: one change in the app.
                key = lastKey.flatMap { $0.hasPrefix("req:\(time):") ? $0 : nil } ?? "req:\(time):\(groups.count)"
            } else {
                key = lastKey?.hasPrefix("local:") == true ? lastKey! : "local:\(groups.count)"
            }
            lastKey = key
            let gi: Int
            if let i = byKey[key] { gi = i } else {
                gi = groups.count
                byKey[key] = gi
                groups.append(Group(key: key, batch: op.batch, actor: op.actor ?? "app", time: time, confirmed: confirmed))
            }
            if !confirmed { groups[gi].confirmed = false }
            let id = op.target
            if op.type.isTask {
                if groups[gi].beforeTasks.index(forKey: id) == nil {
                    groups[gi].beforeTasks[id] = .some(state.tasks[id])
                    groups[gi].order.append(id)
                }
            } else if op.type.isList {
                if groups[gi].beforeLists.index(forKey: id) == nil {
                    groups[gi].beforeLists[id] = .some(state.lists[id])
                    groups[gi].order.append(id)
                }
            }
            _ = state.apply(op)
            if op.type.isTask, let t = state.tasks[id] { groups[gi].afterTasks[id] = t }
            if op.type.isList, let l = state.lists[id] { groups[gi].afterLists[id] = l }
            groups[gi].ops.append(op)
        }
        for g in groups { if let b = g.batch { originals[Self.undoID(b)] = b } }
    }

    // MARK: Undo bookkeeping

    /// The id of the batch that undoes `batch`: derived, so "is it undone?" needs no stored state (§4).
    static func undoID(_ batch: String) -> String { Context.derivedID("undo:" + batch) }

    var batches: [Group] { groups.filter { $0.batch != nil } }

    func group(batch: String) -> Group? { byKey["batch:" + batch].map { groups[$0] } }

    func isUndone(_ batch: String) -> Bool { byKey["batch:" + Self.undoID(batch)] != nil }

    /// 0 for an ordinary change, 1 for an undo of one, 2 for a redo (an undo of an undo), and so on, with the
    /// ordinary change at the root.
    func lineage(_ batch: String) -> (depth: Int, root: String) {
        var d = 0
        var b = batch
        while let o = originals[b], d < 64 {
            d += 1
            b = o
        }
        return (d, b)
    }

    func depth(_ batch: String) -> Int { lineage(batch).depth }

    /// "Undo: Move 3 Tasks to School" for an undo, "Redo: …" for a redo, else the change's own summary.
    func summary(_ g: Group, _ d: Describe) -> String {
        guard let b = g.batch else { return d.summary(g.changes) }
        let (depth, root) = lineage(b)
        guard depth > 0, let original = group(batch: root) else { return d.summary(g.changes) }
        return (depth % 2 == 1 ? "Undo: " : "Redo: ") + d.summary(original.changes)
    }

    /// A batch by id or unique prefix (4+ characters).
    func resolve(_ ref: String) throws -> Group {
        let r = ref.lowercased()
        if let g = group(batch: r) { return g }
        guard r.count >= 4 else { throw CLIError(kind: .notFound, message: "No change \(ref). Use a batch id from tasks log.", field: "batch") }
        let matches = batches.filter { $0.batch!.hasPrefix(r) }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw CLIError(kind: .notFound, message: "No change \(ref) in the log.", field: "batch") }
        throw CLIError(kind: .ambiguous, message: "\(ref) matches \(matches.count) changes.", field: "batch",
                       candidates: matches.map { $0.batch! })
    }
}

extension Context {
    func history() throws -> History {
        let s = try replica
        return History(entries: s.persistence.readEntries(), pending: s.store.projection.pending.map(\.op))
    }

    /// Undo one batch from the log (§4): touched keys go back to their values just before it, except keys
    /// someone changed since (skipped and reported unless `force`). `redo` undoes this actor's newest undo.
    func undo(_ ref: String?, force: Bool, redo: Bool = false) throws {
        let h = try history()
        let actor = try replica.actor
        let target: History.Group
        if let ref {
            target = try h.resolve(ref)
        } else {
            let wantOdd = redo
            let candidates = h.batches.filter { g in
                g.actor == actor && h.depth(g.batch!) % 2 == (wantOdd ? 1 : 0) && !h.isUndone(g.batch!)
            }
            guard let newest = candidates.last else {
                throw CLIError(kind: .notFound, message: redo ? "Nothing of \(actor)'s to redo." : "Nothing of \(actor)'s to undo.", field: "batch")
            }
            target = newest
        }
        let batch = target.batch!
        if h.isUndone(batch) {
            let by = History.undoID(batch)
            throw CLIError.invalid("That change is already undone (by \(by.prefix(6))).", field: "batch")
        }
        if fork != nil || !ops.isEmpty { throw CLIError.invalid("An undo must be the only change in a command or run.") }
        try fixBatch(History.undoID(batch))
        let (depth, root) = h.lineage(batch)
        let rootSummary = h.group(batch: root).map { describe(try! self.p).summary($0.changes) } ?? "a change"
        summaryOverride = (depth % 2 == 0 ? "Undo: " : "Redo: ") + rootSummary

        let p = try self.p
        let r = Render(p)
        var out: [Op] = []
        let s = try writable()
        func op(_ type: OpType, _ id: EntityID, _ set: Patch) -> Op { Op(id: s.newID(), at: env.nowMs, type: type, target: id, set: set) }
        func skip(_ what: String, _ ref: String, _ title: String) {
            skipped.append("kept the later edit to the \(what) of \(ref) \"\(title)\"")
        }
        for id in target.order {
            if let after = target.afterTasks[id], let current = p.task(id) {
                let ref = r.taskRefs.ref(id)
                guard let before = target.beforeTasks[id] ?? nil else {
                    if !current.deleted { out.append(op(.taskUpdate, id, Patch(deleted: true))) }
                    continue
                }
                var set = Patch()
                func field<V: Equatable>(_ name: String, _ k: KeyPath<TaskItem, V>, _ apply: (V) -> Void) {
                    guard before[keyPath: k] != after[keyPath: k] else { return }
                    if current[keyPath: k] == after[keyPath: k] || force { apply(before[keyPath: k]) } else { skip(name, ref, current.title) }
                }
                if before.list != after.list || before.order != after.order {
                    if (current.list == after.list && current.order == after.order) || force {
                        set.list = before.list
                        set.order = before.order
                    } else { skip("position", ref, current.title) }
                }
                field("title", \.title) { set.title = $0 }
                field("notes", \.notes) { set.notes = $0 }
                field("when", \.when) { set.when = .some($0) }
                field("deadline", \.deadline) { set.deadline = .some($0) }
                field("completion", \.completedAt) { set.completedAt = .some($0) }
                field("deleted state", \.deleted) { set.deleted = $0 }
                if set != Patch() { out.append(op(.taskUpdate, id, set)) }
            } else if let after = target.afterLists[id], let current = p.list(id) {
                let ref = r.listRefs.ref(id)
                guard let before = target.beforeLists[id] ?? nil else {
                    if current.archivedAt == nil { out.append(op(.listUpdate, id, Patch(archivedAt: .some(env.nowMs)))) }
                    continue
                }
                var set = Patch()
                func field<V: Equatable>(_ name: String, _ k: KeyPath<TaskList, V>, _ apply: (V) -> Void) {
                    guard before[keyPath: k] != after[keyPath: k] else { return }
                    if current[keyPath: k] == after[keyPath: k] || force { apply(before[keyPath: k]) } else { skip(name, ref, current.name) }
                }
                field("name", \.name) { set.name = $0 }
                field("notes", \.notes) { set.notes = $0 }
                field("position", \.order) { set.order = $0 }
                field("archive state", \.archivedAt) { set.archivedAt = .some($0) }
                if set != Patch() { out.append(op(.listUpdate, id, set)) }
            }
        }
        if !out.isEmpty { s.perform(out) }
    }

    /// `tasks log`: changes newest first, filtered.
    func logJSON(actor glob: String?, since: String?, batch: String?, task: String?, limit: Int) throws -> (JSON, [String]) {
        let h = try history()
        let p = try self.p
        let r = Render(p)
        let d = describe(p)
        let sinceMs = try since.map(parseSince)
        let taskID = try task.map { try resolve.task($0, includeDeleted: true).id }
        let pattern = glob.map { NSPredicate(format: "SELF LIKE %@", $0) }
        var picked = h.groups.filter { g in
            (pattern?.evaluate(with: g.actor) ?? true) && (sinceMs.map { g.time >= $0 } ?? true)
                && (batch.map { b in g.batch?.hasPrefix(b.lowercased()) == true } ?? true)
                && (taskID.map { g.touches.contains($0) } ?? true)
        }
        picked = Array(picked.suffix(limit).reversed())
        var text: [String] = []
        var json: [JSON] = []
        for g in picked {
            let changes = g.changes
            let summary = h.summary(g, d)
            let undone = g.batch.map(h.isUndone) ?? false
            let id = g.batch.map { String($0.prefix(6)) } ?? "—"
            var line = "\(id.padding(toLength: 7, withPad: " ", startingAt: 0)) \(g.actor.padding(toLength: 18, withPad: " ", startingAt: 0)) \(clock(g.time))  \(summary)"
            if !g.confirmed { line += "  (not yet synced)" }
            if undone { line += "  (undone)" } else if let b = g.batch, h.depth(b) % 2 == 0 { line += "  · tasks undo \(b.prefix(6))" }
            text.append(line)
            json.append(JSON([
                "batch": .str(g.batch), "actor": .string(g.actor), "time": .int(g.time), "summary": .string(summary),
                "confirmed": .bool(g.confirmed), "undone": .bool(undone),
                "changes": .array(changes.map { c in
                    switch c {
                    case .task(let b, let a): JSON(["task": .string(a.id), "before": b.map(r.task) ?? .null, "after": r.task(a)])
                    case .list(let b, let a): JSON(["list": .string(a.id), "before": b.map(r.list) ?? .null, "after": r.list(a)])
                    }
                }),
                "ops": .array(g.ops.map { (try? JSON.parse($0.jsonData)) ?? .null }),
            ]))
        }
        if text.isEmpty { text = ["  No changes."] }
        return (.array(json), text)
    }

    /// The changes that touched one task, oldest first, for `tasks show --history`.
    func historyLines(_ id: EntityID) throws -> [String] {
        let h = try history()
        let d = describe(try p)
        return h.groups.filter { $0.touches.contains(id) }.map { g in
            let own = g.changes.filter { if case .task(_, let a) = $0 { a.id == id } else { false } }
            let summary = (g.batch.map { h.depth($0) > 0 } ?? false) ? h.summary(g, d) : d.summary(own)
            return "\(Render.time(g.time))  \(g.actor)  \(summary)"
        }
    }

    /// "2h", "30m", "3d", or a date.
    func parseSince(_ s: String) throws -> Int {
        let now = env.nowMs
        if let n = Int(s.dropLast()), let unit = s.last {
            let ms = ["m": 60_000, "h": 3_600_000, "d": 86_400_000, "w": 604_800_000][String(unit)]
            if let ms { return now - n * ms }
        }
        if let day = try resolveDate(s) { return Int(day.startDate(in: env.clock.calendar).timeIntervalSince1970 * 1000) }
        throw CLIError.invalid("--since takes 30m, 2h, 3d, 1w or a date.", field: "since")
    }

    private func clock(_ ms: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        f.dateFormat = env.clock.calendar.isDate(date, inSameDayAs: env.clock.now()) ? "HH:mm" : "MMM d HH:mm"
        return f.string(from: date)
    }
}
