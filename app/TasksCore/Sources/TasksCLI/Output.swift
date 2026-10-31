import Foundation
import TasksCore

/// A field of a JSON type every surface shares. `tasks.d.ts` declares these, and the encoders below write
/// exactly these keys in this order (a test checks).
struct Field: Sendable {
    let name: String
    let ts: String
    var optional = false
}

enum Shapes {
    static let task: [Field] = [
        Field(name: "id", ts: "string"), Field(name: "ref", ts: "string"),
        Field(name: "kind", ts: "\"heading\" /* only on a heading: a row that groups the tasks under it */", optional: true),
        Field(name: "list", ts: "string"), Field(name: "listName", ts: "string"), Field(name: "title", ts: "string"),
        Field(name: "notes", ts: "string /* Markdown */"), Field(name: "when", ts: "CalendarDate | null"),
        Field(name: "deadline", ts: "CalendarDate | null"), Field(name: "done", ts: "boolean"),
        Field(name: "completedAt", ts: "number | null"), Field(name: "deleted", ts: "boolean"),
        Field(name: "createdAt", ts: "number"), Field(name: "updatedAt", ts: "number"),
    ]
    static let list: [Field] = [
        Field(name: "id", ts: "string"), Field(name: "ref", ts: "string"), Field(name: "name", ts: "string"),
        Field(name: "notes", ts: "string /* Markdown, under the list's title */"),
        Field(name: "archivedAt", ts: "number | null"), Field(name: "open", ts: "number /* open tasks, headings not counted */"),
    ]
    static let change: [Field] = [
        Field(name: "batch", ts: "string | null /* null when nothing changed */"), Field(name: "summary", ts: "string"),
        Field(name: "tasks", ts: "Task[]"), Field(name: "lists", ts: "List[]"),
        Field(name: "skipped", ts: "string[] /* undo: later edits it kept */", optional: true),
    ]
}

/// Renders entities as JSON and as text, against one projection (the replica's, or a fork's).
@MainActor
struct Render {
    let p: Projection
    let taskRefs: RefIndex
    let listRefs: RefIndex

    init(_ p: Projection) {
        self.p = p
        taskRefs = RefIndex(p.allTaskIDs)
        listRefs = RefIndex(p.allListIDs)
    }

    var today: CalendarDate { p.day.date }

    func listName(_ id: EntityID) -> String { p.list(id)?.name ?? "(missing list)" }

    // MARK: JSON

    /// `kind` is there only on a heading (INTERACTIONS-v2 §23), so a task's JSON is what it was before headings.
    func task(_ t: TaskItem) -> JSON {
        var m: [JSON.Member] = [.init(key: "id", value: .string(t.id)), .init(key: "ref", value: .string(taskRefs.ref(t.id)))]
        if t.isHeading { m.append(.init(key: "kind", value: .string(Patch.heading))) }
        let rest = JSON(["list": .string(t.list),
                         "listName": .string(listName(t.list)), "title": .string(t.title), "notes": .string(t.notes),
                         "when": .str(t.when?.string), "deadline": .str(t.deadline?.string), "done": .bool(t.completedAt != nil),
                         "completedAt": .num(t.completedAt), "deleted": .bool(t.deleted), "createdAt": .int(t.createdAt),
                         "updatedAt": .int(t.updatedAt)])
        if case .object(let r) = rest { m += r }
        return .object(m)
    }

    func list(_ l: TaskList) -> JSON {
        JSON(["id": .string(l.id), "ref": .string(listRefs.ref(l.id)), "name": .string(l.name), "notes": .string(l.notes),
              "archivedAt": .num(l.archivedAt), "open": .int(p.openTaskCount(in: l.id))])
    }

    func tasks(_ ids: [EntityID]) -> [TaskItem] { ids.compactMap(p.task) }

    // MARK: Text

    /// "  ○ 3f9a2c  Buy milk      Overdue · 2d", titles padded to a common width within a block.
    func rows(_ tasks: [TaskItem], inToday: Bool = false, showList: Bool = false, indent: String = "  ") -> [String] {
        let width = min(36, tasks.map(\.title.count).max() ?? 0)
        return tasks.map { t in
            let mark = t.deleted ? "✕" : t.completedAt != nil ? "●" : "○"
            var chips: [String] = []
            if t.completedAt == nil, !t.deleted {
                if let w = t.when {
                    let chip = DateLabel.whenChip(w, today: today)
                    if !(inToday && chip == "Today") { chips.append(chip) }
                }
                if let d = t.deadline {
                    // The flag stands in for the app's capsule: "⚑ 3d left", "⚑ 2d ago" (§24).
                    chips.append("⚑ " + DateLabel.deadlineChip(d, today: today).text)
                }
            }
            if showList { chips.append(listName(t.list)) }
            let title = t.title.isEmpty ? "(untitled)" : t.title
            let pad = String(repeating: " ", count: max(0, width - title.count))
            let tail = chips.isEmpty ? "" : "  " + pad + chips.joined(separator: "  ")
            return "\(indent)\(mark) \(taskRefs.ref(t.id))  \(title)\(tail)"
        }
    }

    /// A list's open rows as `ls` prints them (§23): the tasks before the first heading, then each heading as a
    /// section line ("  # 4f2a1c  Labs") with its tasks indented under it.
    func sections(_ rows: [TaskItem]) -> [String] {
        var out: [String] = []
        var block: [TaskItem] = []
        var underHeading = false
        func flush() {
            out += self.rows(block, indent: underHeading ? "    " : "  ")
            block = []
        }
        for t in rows {
            if t.isHeading {
                flush()
                out.append("  # \(taskRefs.ref(t.id))  \(t.title.isEmpty ? "(untitled)" : t.title)")
                underHeading = true
            } else {
                block.append(t)
            }
        }
        flush()
        return out
    }

    func listRow(_ l: TaskList) -> String {
        let open = p.openTaskCount(in: l.id)
        var line = "  \(listRefs.ref(l.id))  \(l.name)  \(open)"
        if let a = l.archivedAt { line += "  archived \(archivedDate(a))" }
        return line
    }

    func archivedDate(_ ms: Int) -> String {
        DateLabel.monthDay(CalendarDate(Date(timeIntervalSince1970: Double(ms) / 1000)))
    }

    func detail(_ t: TaskItem, history: [String]) -> [String] {
        var out = ["\(taskRefs.ref(t.id))  \(t.title.isEmpty ? "(untitled)" : t.title)"]
        func line(_ k: String, _ v: String) { out.append("  " + k.padding(toLength: 10, withPad: " ", startingAt: 0) + v) }
        line("id", t.id)
        line("list", "\(listName(t.list))\(p.list(t.list)?.archivedAt != nil ? " (archived)" : "")")
        if t.isHeading {
            // A heading has no completion and no dates (§23).
            line("kind", "heading")
            line("status", t.deleted ? "deleted" : "open")
            line("open", "\(openTasks(under: t.id)) open tasks under it")
        } else {
            line("status", t.deleted ? "deleted" : t.completedAt != nil ? "done" : "open")
            line("when", t.when.map { "\($0.string) (\(DateLabel.long($0, today: today)), \(DateLabel.relative($0, today: today)))" } ?? "—")
            line("deadline", t.deadline.map { "\($0.string) (\(DateLabel.long($0, today: today)), \(DateLabel.deadlineWords($0, today: today)))" } ?? "—")
        }
        line("created", Self.time(t.createdAt))
        if let c = t.completedAt, !t.isHeading { line("completed", Self.time(c)) }
        if !t.notes.isEmpty {
            out.append("  notes")
            out += t.notes.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }
        }
        if !history.isEmpty {
            out.append("  history")
            out += history.map { "    " + $0 }
        }
        return out
    }

    /// The open tasks in a heading's section.
    func openTasks(under heading: EntityID) -> Int {
        p.section(of: heading).dropFirst().filter { p.task($0)?.completedAt == nil }.count
    }

    static func time(_ ms: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

/// What changed for one entity, between two states.
enum EntityChange {
    case task(before: TaskItem?, after: TaskItem)
    case list(before: TaskList?, after: TaskList)
}

/// Summaries in the app's undo vocabulary (INTERACTIONS-v2 §9), with the target: "Move 3 Tasks to School",
/// "Set When: Fri, Nov 6 on "Buy milk"". Used for a command's `Change` and for `tasks log`.
@MainActor
struct Describe {
    let listName: (EntityID) -> String
    let today: CalendarDate

    private enum Kind: Int, CaseIterable {
        case newTask, delete, restore, complete, uncomplete, move, when, removeWhen, deadline, removeDeadline,
             rename, notes, reorder, newList, renameList, listNotes, archive, unarchive, moveList
    }

    func summary(_ changes: [EntityChange]) -> String {
        var groups: [Kind: [EntityChange]] = [:]
        for c in changes {
            for k in kinds(c) { groups[k, default: []].append(c) }
        }
        // Re-keyed neighbours (ties, a rebalance) are noise next to any other change.
        if groups.count > 1 { groups[.reorder] = nil }
        let parts = Kind.allCases.compactMap { k in groups[k].map { phrase(k, $0) } }
        if parts.isEmpty { return "No change" }
        return parts.count > 2 ? parts.prefix(2).joined(separator: "; ") + "; …" : parts.joined(separator: "; ")
    }

    private func kinds(_ c: EntityChange) -> [Kind] {
        switch c {
        case .task(nil, _): return [.newTask]
        case .task(let b?, let a):
            var k: [Kind] = []
            if !b.deleted && a.deleted { k.append(.delete) }
            if b.deleted && !a.deleted { k.append(.restore) }
            if b.completedAt == nil && a.completedAt != nil { k.append(.complete) }
            if b.completedAt != nil && a.completedAt == nil { k.append(.uncomplete) }
            if b.list != a.list { k.append(.move) } else if b.order != a.order { k.append(.reorder) }
            if b.when != a.when { k.append(a.when == nil ? .removeWhen : .when) }
            if b.deadline != a.deadline { k.append(a.deadline == nil ? .removeDeadline : .deadline) }
            if b.title != a.title { k.append(.rename) }
            if b.notes != a.notes { k.append(.notes) }
            return k
        case .list(nil, _): return [.newList]
        case .list(let b?, let a):
            var k: [Kind] = []
            if b.name != a.name { k.append(.renameList) }
            if b.notes != a.notes { k.append(.listNotes) }
            if b.archivedAt == nil && a.archivedAt != nil { k.append(.archive) }
            if b.archivedAt != nil && a.archivedAt == nil { k.append(.unarchive) }
            if b.order != a.order { k.append(.moveList) }
            return k
        }
    }

    private func phrase(_ k: Kind, _ cs: [EntityChange]) -> String {
        let tasks = cs.compactMap { if case .task(_, let a) = $0 { a } else { nil } }
        let lists = cs.compactMap { if case .list(_, let a) = $0 { a } else { nil } }
        let n = tasks.count
        // A heading is named as one (§23); several rows with a heading among them are "items".
        let headings = tasks.filter(\.isHeading)
        func one(_ verb: String) -> String {
            if n == 1 { return "\(verb)\(headings.isEmpty ? "" : " Heading") \(quote(tasks[0].title))" }
            return headings.isEmpty ? "\(verb) \(n) Tasks" : "\(verb) \(n) Items"
        }
        func dated(_ name: String, _ d: (TaskItem) -> CalendarDate?) -> String {
            let dates = Set(tasks.compactMap(d))
            let label = dates.count == 1 ? ": " + DateLabel.long(dates.first!, today: today) : ""
            return n == 1 ? "\(name)\(label) on \(quote(tasks[0].title))" : "\(name)\(label) (\(n) tasks)"
        }
        let listQuote = lists.first.map { quote($0.name) } ?? ""
        switch k {
        case .newTask:
            if n == 1 { return "New \(headings.isEmpty ? "Task" : "Heading") \(quote(tasks[0].title)) in \(listName(tasks[0].list))" }
            return headings.isEmpty ? "New \(n) Tasks" : "New \(n) Items"
        case .delete: return one("Delete")
        case .restore: return one("Restore")
        case .complete: return one("Complete")
        case .uncomplete: return n == 1 ? "Mark Not Done \(quote(tasks[0].title))" : "Mark \(n) Tasks Not Done"
        case .move:
            let targets = Set(tasks.map(\.list))
            let to = targets.count == 1 ? " to \(listName(targets.first!))" : ""
            return one("Move") + to
        case .reorder:
            // A section moves as its heading and its tasks: one "Move Heading" (§23).
            if headings.count == 1 { return "Move Heading \(quote(headings[0].title))" }
            return one("Reorder")
        case .when: return dated("Set When", \.when)
        case .removeWhen: return n == 1 ? "Remove When from \(quote(tasks[0].title))" : "Remove When (\(n) tasks)"
        case .deadline: return dated("Set Deadline", \.deadline)
        case .removeDeadline: return n == 1 ? "Remove Deadline from \(quote(tasks[0].title))" : "Remove Deadline (\(n) tasks)"
        case .rename:
            return n == 1 ? "Rename \(headings.isEmpty ? "Task" : "Heading") to \(quote(tasks[0].title))" : "Rename \(n) Tasks"
        case .notes: return n == 1 ? "Edit Notes on \(quote(tasks[0].title))" : "Edit Notes (\(n) tasks)"
        case .newList: return lists.count == 1 ? "New List \(listQuote)" : "New \(lists.count) Lists"
        case .renameList: return lists.count == 1 ? "Rename List to \(listQuote)" : "Rename \(lists.count) Lists"
        case .listNotes: return lists.count == 1 ? "Edit List Notes on \(listQuote)" : "Edit List Notes (\(lists.count) lists)"
        case .archive: return lists.count == 1 ? "Archive List \(listQuote)" : "Archive \(lists.count) Lists"
        case .unarchive: return lists.count == 1 ? "Unarchive List \(listQuote)" : "Unarchive \(lists.count) Lists"
        case .moveList: return lists.count == 1 ? "Move List \(listQuote)" : "Move \(lists.count) Lists"
        }
    }

    /// Titles over 28 characters end in …, as the app's notices do.
    func quote(_ s: String) -> String {
        let t = s.isEmpty ? "(untitled)" : s
        return "\"" + (t.count > 28 ? t.prefix(27) + "…" : t) + "\""
    }

    /// Dry-run lines: `+ 3f9a2c "Buy milk"  in Groceries`, `~ 3f9a2c "Buy milk"  when: — → 2026-11-06 (Fri)`.
    func diff(_ changes: [EntityChange], refs: Render) -> [String] {
        changes.compactMap { c in
            switch c {
            case .task(let b, let a):
                let head = "\(b == nil ? "+" : "~") \(refs.taskRefs.ref(a.id)) \(quote(a.title))"
                let fields = taskFields(b, a)
                return fields.isEmpty ? nil : head + "  " + fields.joined(separator: "; ")
            case .list(let b, let a):
                let head = "\(b == nil ? "+" : "~") list \(refs.listRefs.ref(a.id)) \(quote(a.name))"
                var f: [String] = []
                if b == nil { f.append("new list") }
                if let b, b.name != a.name { f.append("name: \(quote(b.name)) → \(quote(a.name))") }
                if let b, b.notes != a.notes { f.append("notes edited") }
                if b == nil, !a.notes.isEmpty { f.append("notes") }
                if b?.archivedAt != a.archivedAt { f.append(a.archivedAt == nil ? "unarchived" : "archived") }
                if let b, b.order != a.order { f.append("sidebar position") }
                return f.isEmpty ? nil : head + "  " + f.joined(separator: "; ")
            }
        }
    }

    private func taskFields(_ b: TaskItem?, _ a: TaskItem) -> [String] {
        func d(_ x: CalendarDate?) -> String { x.map { "\($0.string) (\(DateLabel.whenChip($0, today: today)))" } ?? "—" }
        guard let b else {
            var f = [a.isHeading ? "heading in \(listName(a.list))" : "in \(listName(a.list))"]
            if let w = a.when { f.append("when \(d(w))") }
            if let dl = a.deadline { f.append("deadline \(d(dl))") }
            if !a.notes.isEmpty { f.append("notes") }
            return f
        }
        var f: [String] = []
        if b.list != a.list { f.append("list: \(listName(b.list)) → \(listName(a.list))") } else if b.order != a.order { f.append("position") }
        if b.title != a.title { f.append("title: \(quote(b.title)) → \(quote(a.title))") }
        if b.notes != a.notes { f.append("notes edited") }
        if b.when != a.when { f.append("when: \(d(b.when)) → \(d(a.when))") }
        if b.deadline != a.deadline { f.append("deadline: \(d(b.deadline)) → \(d(a.deadline))") }
        if (b.completedAt == nil) != (a.completedAt == nil) { f.append(a.completedAt == nil ? "not done" : "done") }
        if b.deleted != a.deleted { f.append(a.deleted ? "deleted" : "restored") }
        return f
    }
}
