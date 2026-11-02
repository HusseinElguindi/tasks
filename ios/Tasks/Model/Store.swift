import SwiftUI
import Observation

struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
}

struct Draft: Equatable {
    var source: Source
    var title = ""
    var token = UUID()   // a new draft row after each commit
}

struct DateTarget: Identifiable, Equatable {
    let taskID: String
    let kind: DateKind
    var id: String { taskID + kind.rawValue }
}

/// One line of a list pane: a group label, a heading, a task, the Completed disclosure, a deleted list.
enum Line: Identifiable {
    case group(key: String, title: String, sub: String?, quiet: Bool)
    case heading(Heading, openCount: Int)
    case task(TaskItem, indent: Bool)
    case completedToggle(count: Int, open: Bool)
    case deletedList(TaskList, count: Int, open: Bool)
    case draft
    case empty(title: String, message: String, symbol: String)

    var id: String {
        switch self {
        case let .group(key, _, _, _): "g:" + key
        case let .heading(h, _): "h:" + h.id
        case let .task(t, _): "t:" + t.id
        case .completedToggle: "completed"
        case let .deletedList(l, _, _): "dl:" + l.id
        case .draft: "draft"
        case .empty: "empty"
        }
    }
}

@Observable @MainActor
final class Store {
    var lists: [TaskList]
    var headings: [Heading]
    var tasks: [TaskItem]

    // Transient UI state
    var completing: Set<String> = []          // checked a moment ago; still in place
    var showCompleted: Set<String> = []       // list ids whose Completed disclosure is open
    var expandedTrash: Set<String> = []       // deleted lists opened in Trash
    var notice: Notice?
    var draft: Draft?
    var path: [Source] = []
    var selection: Source? = .today           // the split view's sidebar
    var selectedTask: String?                 // the split view's detail
    var detailTask: String?                   // the phone's detail sheet
    var dateTarget: DateTarget?
    var showSettings = false
    var listEditor: ListEditor?
    var isSplit = false
    /// Screenshots: keep a notice and a just-checked row on screen instead of letting them go.
    var holdTransient = false                        // iPad and Mac: detail inline, not a sheet

    // Appearance
    var themeID = "default"
    var appearance: Appearance = .dark
    var style: InterfaceStyle = .classic

    struct ListEditor: Identifiable { let id = UUID(); var listID: String?; var name: String }

    init() {
        let s = SampleData.make()
        lists = s.lists; headings = s.headings; tasks = s.tasks
    }

    // MARK: Lookups

    var liveLists: [TaskList] { lists.filter { $0.deletedAt == nil }.sorted { $0.order < $1.order } }
    func list(_ id: String) -> TaskList? { lists.first { $0.id == id } }
    func task(_ id: String) -> TaskItem? { tasks.first { $0.id == id } }
    func index(_ id: String) -> Int? { tasks.firstIndex { $0.id == id } }
    var inbox: TaskList { lists.first { $0.id == "inbox" }! }

    /// Shown as open: not completed, or completed a moment ago.
    func isOpen(_ t: TaskItem) -> Bool { !t.isTrashed && (!t.isDone || completing.contains(t.id)) }
    private func live(_ t: TaskItem) -> Bool { !t.isTrashed && (list(t.listID)?.deletedAt == nil) }

    func isToday(_ t: TaskItem) -> Bool {
        let today = Day.today
        if let w = t.when, w <= today { return true }
        if let d = t.deadline, Day.start(d) <= today { return true }
        return false
    }

    func todayCount() -> Int { tasks.filter { live($0) && !$0.isDone && isToday($0) }.count }
    func openCount(_ listID: String) -> Int { tasks.filter { $0.listID == listID && live($0) && !$0.isDone }.count }

    func title(_ s: Source) -> String {
        switch s {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .undated: "Undated"
        case .completed: "Completed"
        case .trash: "Trash"
        case let .list(id): list(id)?.name ?? "List"
        }
    }

    // MARK: Lines

    private func ordered(_ ts: [TaskItem]) -> [TaskItem] {
        ts.sorted { a, b in
            if a.listID != b.listID {
                return (list(a.listID)?.order ?? 0) < (list(b.listID)?.order ?? 0)
            }
            let ha = a.headingID.flatMap { h in headings.first { $0.id == h }?.order } ?? -1
            let hb = b.headingID.flatMap { h in headings.first { $0.id == h }?.order } ?? -1
            if ha != hb { return ha < hb }
            return a.order < b.order
        }
    }

    func lines(_ source: Source) -> [Line] {
        var out: [Line] = []
        let draftHere = draft?.source == source
        switch source {
        case let .list(id):
            if draftHere { out.append(.draft) }
            let mine = tasks.filter { $0.listID == id && !$0.isTrashed }
            let open = ordered(mine.filter(isOpen))
            for t in open where t.headingID == nil { out.append(.task(t, indent: false)) }
            for h in headings.filter({ $0.listID == id }).sorted(by: { $0.order < $1.order }) {
                let ts = open.filter { $0.headingID == h.id }
                out.append(.heading(h, openCount: ts.count))
                for t in ts { out.append(.task(t, indent: false)) }
            }
            let done = mine.filter { $0.isDone && !completing.contains($0.id) }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            if !done.isEmpty {
                let isOpenToggle = showCompleted.contains(id)
                out.append(.completedToggle(count: done.count, open: isOpenToggle))
                if isOpenToggle { for t in done { out.append(.task(t, indent: false)) } }
            }
            if open.isEmpty && done.isEmpty && !draftHere {
                out.append(.empty(title: "No tasks", message: "Tap + to add one. Tasks you add here stay in this list.", symbol: "checklist"))
            }

        case .today:
            if draftHere { out.append(.draft) }
            let ts = ordered(tasks.filter { live($0) && isOpen($0) && isToday($0) })
            for l in liveLists {
                let mine = ts.filter { $0.listID == l.id }
                if mine.isEmpty { continue }
                out.append(.group(key: l.id, title: l.name, sub: nil, quiet: false))
                for t in mine { out.append(.task(t, indent: false)) }
            }
            if ts.isEmpty && !draftHere {
                out.append(.empty(title: "Nothing for today", message: "Give a task a When of today, or a deadline, and it shows here.", symbol: "sun.max"))
            }

        case .upcoming:
            if draftHere { out.append(.draft) }
            let today = Day.today
            let ts = ordered(tasks.filter { t in
                guard live(t), isOpen(t) else { return false }
                if let w = t.when { return w > today }
                if let d = t.deadline { return Day.start(d) > today }
                return false
            })
            func day(_ t: TaskItem) -> Date { Day.start(t.when ?? t.deadline!) }
            // The next seven days always show, quiet when empty; then each later date, then months.
            for n in 1...7 {
                let d = Day.offset(n)
                let mine = ts.filter { day($0) == d }
                let title = n == 1 ? "Tomorrow" : Day.weekday(d)
                out.append(.group(key: "u\(n)", title: title, sub: Day.monthDay(d), quiet: mine.isEmpty))
                for t in mine { out.append(.task(t, indent: false)) }
            }
            let later = ts.filter { day($0) > Day.offset(7) }.sorted { day($0) < day($1) }
            var seen: [String] = []
            for t in later {
                let d = day(t)
                let inMonth = Day.diff(d) <= 31
                let key = inMonth ? "d" + Day.monthDay(d) : "m" + Day.fmt("MMMM yyyy", d)
                if !seen.contains(key) {
                    seen.append(key)
                    out.append(.group(key: key, title: inMonth ? Day.weekday(d) : Day.month(d), sub: inMonth ? Day.monthDay(d) : nil, quiet: false))
                }
                out.append(.task(t, indent: false))
            }

        case .undated:
            if draftHere { out.append(.draft) }
            let ts = ordered(tasks.filter { live($0) && isOpen($0) && $0.when == nil && $0.deadline == nil })
            for l in liveLists {
                let mine = ts.filter { $0.listID == l.id }
                if mine.isEmpty { continue }
                out.append(.group(key: l.id, title: l.name, sub: nil, quiet: false))
                for t in mine { out.append(.task(t, indent: false)) }
            }
            if ts.isEmpty { out.append(.empty(title: "Everything has a date", message: "Tasks without a When collect here.", symbol: "square.stack")) }

        case .completed:
            let ts = tasks.filter { live($0) && $0.isDone && !completing.contains($0.id) }
                .sorted { $0.completedAt! > $1.completedAt! }
            var seen: [String] = []
            for t in ts {
                let g = Day.pastGroup(t.completedAt!)
                if !seen.contains(g.key) { seen.append(g.key); out.append(.group(key: g.key, title: g.title, sub: g.sub, quiet: false)) }
                out.append(.task(t, indent: false))
            }
            if ts.isEmpty { out.append(.empty(title: "Nothing completed yet", message: "Tasks you check off land here, by the day you did them.", symbol: "checkmark.circle")) }

        case .trash:
            struct Entry { let date: Date; let line: [Line] }
            var entries: [Entry] = []
            for t in tasks where t.isTrashed && !t.deletedWithList {
                entries.append(Entry(date: t.deletedAt!, line: [.task(t, indent: false)]))
            }
            for l in lists where l.deletedAt != nil {
                let held = tasks.filter { $0.listID == l.id && ($0.deletedWithList || !$0.isTrashed) }
                let open = expandedTrash.contains(l.id)
                var ls: [Line] = [.deletedList(l, count: held.count, open: open)]
                if open {
                    let o = ordered(held.filter { !$0.isDone }) + held.filter(\.isDone)
                    ls += o.map { .task($0, indent: true) }
                }
                entries.append(Entry(date: l.deletedAt!, line: ls))
            }
            entries.sort { $0.date > $1.date }
            var seen: [String] = []
            for e in entries {
                let g = Day.pastGroup(e.date)
                if !seen.contains(g.key) { seen.append(g.key); out.append(.group(key: g.key, title: g.title, sub: g.sub, quiet: false)) }
                out += e.line
            }
            if entries.isEmpty { out.append(.empty(title: "Trash is empty", message: "Deleted tasks and lists wait here until you restore them.", symbol: "trash")) }
        }
        return out
    }

    // MARK: Ring cues

    struct Cue { var tone: Tone?; var planned: Bool }
    /// The checkbox ring's cue, open tasks only: the deadline's tone (late or due), and planned-for-today outside Today.
    func cue(_ t: TaskItem, in source: Source) -> Cue {
        guard !t.isDone, !t.isTrashed else { return Cue(tone: nil, planned: false) }
        var tone: Tone? = nil
        if let d = t.deadline { let x = Day.tone(d); if x == .late || x == .due { tone = x } }
        let planned = source != .today && (t.when.map { $0 <= Day.today } ?? false)
        return Cue(tone: tone, planned: planned)
    }

    // MARK: Actions

    func toggle(_ id: String) {
        guard let i = index(id), !tasks[i].isTrashed else { return }
        if tasks[i].isDone {
            completing.remove(id)
            animate(Motion.layout) { tasks[i].completedAt = nil }
            return
        }
        tasks[i].completedAt = Date()
        completing.insert(id)
        let title = tasks[i].title
        show(Notice(text: "Completed “\(short(title))”") { [weak self] in
            guard let self, let j = self.index(id) else { return }
            self.completing.remove(id)
            animate(Motion.layout) { self.tasks[j].completedAt = nil }
        })
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard completing.contains(id), !holdTransient else { return }
            animate(Motion.layout) { _ = completing.remove(id) }
        }
    }

    func delete(_ id: String) {
        guard let i = index(id) else { return }
        let title = tasks[i].title
        if selectedTask == id { selectedTask = nil }
        if detailTask == id { detailTask = nil }
        animate(Motion.layout) { tasks[i].deletedAt = Date() }
        show(Notice(text: "Deleted “\(short(title))”") { [weak self] in
            guard let self, let j = self.index(id) else { return }
            animate(Motion.layout) { self.tasks[j].deletedAt = nil }
        })
    }

    func restore(_ id: String) {
        guard let i = index(id) else { return }
        let title = tasks[i].title
        animate(Motion.layout) { tasks[i].deletedAt = nil; tasks[i].deletedWithList = false }
        show(Notice(text: "Restored “\(short(title))”") { [weak self] in
            guard let self, let j = self.index(id) else { return }
            animate(Motion.layout) { self.tasks[j].deletedAt = Date() }
        })
    }

    func deleteList(_ id: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        let name = lists[i].name
        let next = liveLists.first { $0.id != id && $0.id != "inbox" }
        animate(Motion.layout) {
            lists[i].deletedAt = Date()
            if selection == .list(id) { selection = next.map { .list($0.id) } ?? .today }
            path.removeAll { $0 == .list(id) }
        }
        show(Notice(text: "Deleted \(name)") { [weak self] in
            guard let self, let j = self.lists.firstIndex(where: { $0.id == id }) else { return }
            animate(Motion.layout) { self.lists[j].deletedAt = nil }
        })
    }

    func restoreList(_ id: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        let name = lists[i].name
        animate(Motion.layout) {
            lists[i].deletedAt = nil
            for j in tasks.indices where tasks[j].listID == id && tasks[j].deletedWithList {
                tasks[j].deletedAt = nil; tasks[j].deletedWithList = false
            }
            expandedTrash.remove(id)
        }
        show(Notice(text: "Restored \(name)") { [weak self] in
            guard let self, let j = self.lists.firstIndex(where: { $0.id == id }) else { return }
            animate(Motion.layout) { self.lists[j].deletedAt = Date() }
        })
    }

    func setDate(_ id: String, _ kind: DateKind, _ date: Date?) {
        guard let i = index(id) else { return }
        animate(Motion.layout) {
            switch kind {
            case .when: tasks[i].when = date.map(Day.start)
            case .deadline: tasks[i].deadline = date.map(Day.start)
            }
        }
    }

    func move(_ id: String, to listID: String) {
        guard let i = index(id) else { return }
        animate(Motion.layout) {
            tasks[i].listID = listID
            tasks[i].headingID = nil
            tasks[i].order = (tasks.filter { $0.listID == listID }.map(\.order).min() ?? 0) - 1
        }
    }

    func startDraft(_ source: Source) {
        animate(Motion.layout) { draft = Draft(source: source) }
    }

    /// Commits the draft row. A title makes the task and starts another row; an empty one cancels.
    func commitDraft() {
        guard let d = draft else { return }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { animate(Motion.layout) { draft = nil }; return }
        var listID = inbox.id
        var when: Date? = nil
        switch d.source {
        case let .list(id): listID = id
        case .today: when = Day.today
        case .upcoming: when = Day.offset(1)
        default: break
        }
        let order = (tasks.filter { $0.listID == listID }.map(\.order).min() ?? 0) - 1
        let t = TaskItem(id: UUID().uuidString, title: title, listID: listID, when: when, created: Date(), order: order)
        animate(Motion.layout) {
            tasks.append(t)
            draft = Draft(source: d.source)
        }
    }

    func cancelDraft() { animate(Motion.layout) { draft = nil } }

    func saveList(_ editor: ListEditor) {
        let name = editor.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let id = editor.listID, let i = lists.firstIndex(where: { $0.id == id }) {
            lists[i].name = name
            lists[i].mono = String(name.prefix(1)).uppercased()
            return
        }
        let used = Set(liveLists.map(\.hue))
        let hue = ListHue.slots.first { !used.contains($0) } ?? ListHue.slots[lists.count % ListHue.slots.count]
        let l = TaskList(id: UUID().uuidString, name: name, mono: String(name.prefix(1)).uppercased(), hue: hue,
                         created: Date(), order: (lists.map(\.order).max() ?? 0) + 1)
        animate(Motion.layout) { lists.append(l) }
        open(.list(l.id))
    }

    func open(_ s: Source) {
        selection = s
        selectedTask = nil
        if path.last != s { path = [s] }
    }

    // MARK: Notice

    func show(_ n: Notice) {
        animate(Motion.natural) { notice = n }
        let id = n.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if notice?.id == id && !holdTransient { animate(Motion.natural) { notice = nil } }
        }
    }

    func undo() {
        guard let n = notice else { return }
        n.undo?()
        animate(Motion.natural) { notice = nil }
    }

    private func short(_ s: String) -> String { s.count > 26 ? String(s.prefix(24)) + "…" : s }
}
