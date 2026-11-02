import SwiftUI
import Observation
import TasksCore

/// What a list pane shows: one of the views, or a list.
enum Source: Hashable, Identifiable {
    case today, upcoming, undated, completed, trash
    case list(EntityID)

    var id: String {
        switch self {
        case .today: "today"
        case .upcoming: "upcoming"
        case .undated: "undated"
        case .completed: "completed"
        case .trash: "trash"
        case let .list(id): "list:" + id
        }
    }

    init?(id: String) {
        switch id {
        case "today": self = .today
        case "upcoming": self = .upcoming
        case "undated": self = .undated
        case "completed": self = .completed
        case "trash": self = .trash
        default:
            if id.hasPrefix("list:") { self = .list(String(id.dropFirst(5))) } else { return nil }
        }
    }

    /// Completed and Trash have no +.
    var canAdd: Bool { self != .completed && self != .trash }
}

enum DateKind: String, Identifiable { case when, deadline; var id: String { rawValue } }

struct DateTarget: Identifiable, Equatable {
    let taskID: EntityID
    let kind: DateKind
    var id: String { taskID + kind.rawValue }
}

/// "Completed “Email TA…”" with Undo.
struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
}

/// The row a new task is being typed into.
struct Draft: Equatable {
    var source: Source
    var title = ""
    var token = UUID()   // a new draft row after each commit
}

/// The app's UI state, next to TasksCore's `Store`, which holds every task and list and makes every change (ops,
/// undo, sync). This holds only what the screen needs: navigation, sheets, open disclosures, the notice, the draft, the
/// appearance, and the rows checked a moment ago that stay in place.
@Observable @MainActor
final class AppModel {
    let store: Store
    var projection: Projection { store.projection }
    /// The notice's Undo: every change made here registers on it (the Store's actions take it).
    @ObservationIgnored let undo = UndoManager()

    // Transient UI state
    /// Checked a moment ago: still shown in place, as the Mac's pins (§8).
    var completing: Set<EntityID> = []
    /// Open Completed disclosures: list ids, and `Self.todayDone` for Today's.
    var showCompleted: Set<String> = []
    /// Deleted lists opened in Trash.
    var expandedTrash: Set<EntityID> = []
    var notice: Notice?
    var draft: Draft?
    var path: [Source] = []
    var selection: Source? = .today           // the split view's sidebar
    var selectedTask: EntityID?               // the split view's detail
    var detailTask: EntityID?                 // the phone's detail sheet
    var dateTarget: DateTarget?
    var showSettings = false
    var listEditor: ListEditor?
    var isSplit = false                       // iPad: detail inline, not a sheet
    /// Screenshots: keep a notice and a just-checked row on screen instead of letting them go.
    var holdTransient = false

    /// The Mac's one theme, in System (the default, as on the Mac), Light or Dark; saved per device.
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var style: InterfaceStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Keys.style) }
    }

    static let todayDone = "today"

    struct ListEditor: Identifiable { let id = UUID(); var listID: EntityID?; var name: String }

    enum Keys {
        static let appearance = "appearance"
        static let style = "style"
    }

    init(store: Store) {
        self.store = store
        let d = UserDefaults.standard
        appearance = d.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        style = d.string(forKey: Keys.style).flatMap(InterfaceStyle.init(rawValue:)) ?? .classic
    }

    // MARK: Lookups

    var today: CalendarDate { projection.day.date }
    func task(_ id: EntityID) -> TaskModel? { projection.taskModel(id) }
    func list(_ id: EntityID) -> ListModel? { projection.listModel(id) }
    /// The live lists in sidebar order.
    var activeLists: [ListModel] { projection.activeLists.ids.compactMap(projection.listModel) }

    /// A task that can't be edited: deleted, or in a deleted list (§28).
    func isTrashed(_ t: TaskModel) -> Bool { t.deleted || (list(t.list)?.isDeleted ?? true) }

    func todayCount() -> Int { projection.activeLists.ids.reduce(0) { $0 + projection.todayTasks(in: $1).count } }
    func openCount(_ listID: EntityID) -> Int { projection.openTaskCount(in: listID) }

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

    // MARK: Ring cues

    /// The checkbox ring's cue (TasksCore's `ViewGroups.RingCue`, the Mac's rule): open tasks only.
    func cue(_ t: TaskModel, in source: Source) -> ViewGroups.RingCue {
        guard !t.isDone, !isTrashed(t) else { return ViewGroups.RingCue() }
        return ViewGroups.RingCue(when: t.when, deadline: t.deadline, today: today, inToday: source == .today)
    }

    // MARK: Tasks

    func toggle(_ id: EntityID) {
        guard let t = task(id), !isTrashed(t) else { return }
        if t.isDone {
            completing.remove(id)
            animate(Motion.layout) { _ = store.toggleComplete([id], undoManager: undo) }
            return
        }
        guard store.toggleComplete([id], undoManager: undo) else { return }
        completing.insert(id)
        show(Notice(text: "Completed “\(short(t.title))”") { [weak self] in
            guard let self else { return }
            self.completing.remove(id)
            animate(Motion.layout) { self.undo.undo() }
        })
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard completing.contains(id), !holdTransient else { return }
            animate(Motion.layout) { _ = completing.remove(id) }
        }
    }

    func delete(_ id: EntityID) {
        guard let t = task(id) else { return }
        let title = t.title
        if selectedTask == id { selectedTask = nil }
        if detailTask == id { detailTask = nil }
        var done = false
        animate(Motion.layout) { done = store.delete([id], undoManager: undo) }
        guard done else { return }
        show(Notice(text: "Deleted “\(short(title))”") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    /// Put Back (§22): a task deleted on its own goes back to its list, at its old place.
    func restore(_ id: EntityID) {
        guard let t = task(id) else { return }
        let title = t.title
        var done = false
        animate(Motion.layout) { done = store.putBack([id], undoManager: undo) }
        guard done else { return }
        show(Notice(text: "Restored “\(short(title))”") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    /// Whether Put Back can take the task out of Trash: deleted on its own, from a live list.
    func canRestore(_ t: TaskModel) -> Bool { t.deleted && !t.isHeading && projection.isActive(list: t.list) }

    func setDate(_ id: EntityID, _ kind: DateKind, _ date: CalendarDate?) {
        animate(Motion.layout) {
            switch kind {
            case .when: _ = store.setWhen([id], date, undoManager: undo)
            case .deadline: _ = store.setDeadline([id], date, undoManager: undo)
            }
        }
    }

    func move(_ id: EntityID, to listID: EntityID) {
        animate(Motion.layout) { _ = store.move([id], to: listID, undoManager: undo) }
    }

    func setTitle(_ id: EntityID, _ title: String) { store.setTitle(id, title, undoManager: undo) }
    func setNotes(_ id: EntityID, _ notes: String, name: String? = nil) { store.setNotes(id, notes, name: name, undoManager: undo) }

    // MARK: Lists

    func deleteList(_ id: EntityID) {
        guard let l = list(id) else { return }
        let name = l.name
        let next = activeLists.first { $0.id != id }
        var done = false
        animate(Motion.layout) {
            done = store.deleteList(id, undoManager: undo)
            guard done else { return }
            if selection == .list(id) { selection = next.map { .list($0.id) } ?? .today }
            path.removeAll { $0 == .list(id) }
        }
        guard done else { return }
        show(Notice(text: "Deleted \(name)") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    func restoreList(_ id: EntityID) {
        guard let l = list(id) else { return }
        let name = l.name
        var done = false
        animate(Motion.layout) {
            done = store.restoreList(id, undoManager: undo)
            if done { expandedTrash.remove(id) }
        }
        guard done else { return }
        show(Notice(text: "Restored \(name)") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    func saveList(_ editor: ListEditor) {
        let name = editor.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let id = editor.listID {
            store.rename(list: id, to: name, undoManager: undo)
            return
        }
        var id: EntityID?
        animate(Motion.layout) { id = store.createList(name: name, undoManager: undo) }
        if let id { open(.list(id)) }
    }

    // MARK: The draft

    func startDraft(_ source: Source) {
        animate(Motion.layout) { draft = Draft(source: source) }
    }

    /// Commits the draft row. A title makes the task, at the top of its list, and starts another row; an empty one
    /// cancels. Today's has a When of today, Upcoming's tomorrow; outside a list it goes to the default list.
    func commitDraft() {
        guard let d = draft else { return }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { animate(Motion.layout) { draft = nil }; return }
        var listID: EntityID?
        var when: CalendarDate?
        switch d.source {
        case let .list(id): listID = id
        case .today: when = today
        case .upcoming: when = today.adding(days: 1)
        default: break
        }
        animate(Motion.layout) {
            store.createTask(title: title, in: listID, at: .top, when: when, undoManager: undo)
            draft = Draft(source: d.source)
        }
    }

    func cancelDraft() { animate(Motion.layout) { draft = nil } }

    // MARK: Navigation

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

    func undoNotice() {
        guard let n = notice else { return }
        n.undo?()
        animate(Motion.natural) { notice = nil }
    }

    private func short(_ s: String) -> String { s.count > 26 ? String(s.prefix(24)) + "…" : s }
}
