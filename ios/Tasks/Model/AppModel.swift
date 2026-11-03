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

/// "Completed “Email TA…”" with Undo, for 5 s; one without Undo ("Create a list first") is information, for 1.8 s
/// (the Mac's `TK.Timer.notice`, `noticeInfo`).
struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?

    static let life: Duration = .seconds(5)
    static let infoLife: Duration = .milliseconds(1800)
}

/// The text being typed in a list, in place: a new task or heading, or a heading's name or notes (§23). Each ends the
/// same way (Return, a tap elsewhere, leaving, the app going to the background) and writes once, at the end.
struct Draft: Equatable {
    enum Kind: Equatable {
        /// A new task: at the top of its list, or in a view.
        case task
        /// "New Task in <heading>": at the end of its section.
        case taskIn(heading: EntityID)
        /// A new heading, above a task (which becomes its section's first) or, nil, at the bottom of the list.
        case heading(before: EntityID?)
        /// A heading's name, in place; `original` is the name when the edit began (`EditSession`).
        case rename(heading: EntityID, original: String)
        /// A heading's notes, under it.
        case notes(heading: EntityID, original: String)
    }
    var source: Source
    var kind: Kind = .task
    /// The text typed: the title, the name or the notes.
    var title = ""
    var token = UUID()   // a new draft row after each commit

    /// A new task's row: Return writes it and opens the next.
    var addsTask: Bool {
        switch kind {
        case .task, .taskIn: true
        default: false
        }
    }

    /// The heading whose name or notes are being typed, in place.
    var editedHeading: EntityID? {
        switch kind {
        case let .rename(h, _), let .notes(h, _): h
        default: nil
        }
    }
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
    /// Checked a moment ago: still shown in place, as the Mac's pins (§8), until the rows settle together.
    var completing: Set<EntityID> = []
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// Open Completed disclosures: list ids, and `Self.todayDone` for Today's.
    var showCompleted: Set<String> = []
    /// Deleted lists opened in Trash.
    var expandedTrash: Set<EntityID> = []
    /// Collapsed headings, by id (§23): saved per device, never synced, as the Mac's `WindowState.collapsed`. The
    /// sample store keeps them only while it runs.
    var collapsed: Set<EntityID> = [] {
        didSet {
            guard !isSample, collapsed != oldValue else { return }
            UserDefaults.standard.set(collapsed.sorted(), forKey: Keys.collapsed)
        }
    }
    var notice: Notice?
    /// The new-task row. It lives only while its list is on screen and nothing else is opened: leaving the list,
    /// opening a task, a date, Settings or a list's name ends it (`endDraft`), as on the Mac (INTERACTIONS-v2 §6, "The
    /// pointer while adding": anything else writes a title, then does that; an untitled one is dropped).
    var draft: Draft?
    var path: [Source] = [] {                 // the phone's stack
        didSet { if !isSplit { endDraft(unlessShowing: path.last) } }
    }
    var selection: Source? = .today {         // the split view's sidebar
        didSet { if isSplit { endDraft(unlessShowing: selection) } }
    }
    var selectedTask: EntityID? {             // the split view's detail
        didSet { if selectedTask != nil { endDraft() } }
    }
    var detailTask: EntityID? {               // the phone's detail sheet
        didSet { if detailTask != nil { endDraft() } }
    }
    var dateTarget: DateTarget? {
        didSet { if dateTarget != nil { endDraft() } }
    }
    var showSettings = false {
        didSet { if showSettings { endDraft() } }
    }
    var listEditor: ListEditor? {
        didSet { if listEditor != nil { endDraft() } }
    }
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

    // Sync (Sync.swift)
    /// The Worker's base URL. A `-serverURL` launch argument overrides it without saving (UserDefaults' argument
    /// domain), as on the Mac.
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: SyncKeys.serverURL)
            applyConfig()
        }
    }
    /// A token is saved in the Keychain (its value is never shown, logged or kept anywhere else).
    var hasToken: Bool
    /// The `-sampleData` store: never synced.
    let isSample: Bool
    /// In front (scenePhase active): the 30 s syncs run only then.
    @ObservationIgnored var inFront = true

    static let todayDone = "today"

    struct ListEditor: Identifiable {
        let id = UUID()
        var listID: EntityID?
        var name: String
        /// The name when the editor opened: a rename writes only if the user changed it (`EditSession`).
        let original: String
        init(listID: EntityID?, name: String) { self.listID = listID; self.name = name; original = name }
    }

    enum Keys {
        static let appearance = "appearance"
        static let style = "style"
        /// The Mac's key (`WindowState.collapsedKey`).
        static let collapsed = "collapsedHeadings"
    }

    init(store: Store, isSample: Bool = false) {
        self.store = store
        self.isSample = isSample
        let d = UserDefaults.standard
        appearance = d.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        style = d.string(forKey: Keys.style).flatMap(InterfaceStyle.init(rawValue:)) ?? .classic
        serverURL = d.string(forKey: SyncKeys.serverURL) ?? Self.defaultServer
        hasToken = Keychain.token() != nil
        collapsed = isSample ? [] : Set(d.stringArray(forKey: Keys.collapsed) ?? [])
    }

    // MARK: Lookups

    /// The list or view on screen: the phone's top of the stack, or iPad's sidebar selection.
    var shown: Source? { isSplit ? selection : path.last }

    var today: CalendarDate { projection.day.date }
    func task(_ id: EntityID) -> TaskModel? { projection.taskModel(id) }
    func list(_ id: EntityID) -> ListModel? { projection.listModel(id) }
    /// The live lists in sidebar order.
    var activeLists: [ListModel] { projection.activeLists.ids.compactMap(projection.listModel) }

    /// A task that can't be edited: deleted, or in a deleted list (§28).
    func isTrashed(_ t: TaskModel) -> Bool { t.deleted || (list(t.list)?.isDeleted ?? true) }

    func todayCount() -> Int { projection.activeLists.ids.reduce(0) { $0 + projection.todayTasks(in: $1).count } }
    func openCount(_ listID: EntityID) -> Int { projection.openTaskCount(in: listID) }

    /// A deleted list's row in Trash: "11 tasks", "1 task"; with none open "4 completed"; an empty list "Empty" (§28,
    /// the Mac's `deletedListCount`).
    func deletedListCount(_ id: EntityID) -> String {
        let open = projection.openTaskCount(in: id)
        if open > 0 { return open == 1 ? "1 task" : "\(open) tasks" }
        let done = projection.completedTasks(in: id).count
        return done > 0 ? "\(done) completed" : "Empty"
    }

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
            restartSettle()
            return
        }
        guard store.toggleComplete([id], undoManager: undo) else { return }
        completing.insert(id)
        restartSettle()
        show(Notice(text: "Completed \(quote(t.title))") { [weak self] in
            guard let self else { return }
            self.completing.remove(id)
            animate(Motion.layout) { self.undo.undo() }
        })
    }

    /// Checked rows stay in place until 1.5 s pass with no further check; each check restarts the wait, so a run of
    /// checks moves together (IX:665–669; the Mac's `TK.Timer.settle`).
    private func restartSettle() {
        settleTask?.cancel()
        guard !completing.isEmpty else { return }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, !self.holdTransient else { return }
            animate(Motion.layout) { self.completing.removeAll() }
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
        show(Notice(text: "Deleted \(quote(title))") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    /// Put Back (§22): a task deleted on its own goes back to its list, at its old place. "Put back “Milk” in Inbox",
    /// with Undo (the Mac's `putBack`: a task is put back, a list is restored, `TrashVerb`).
    func putBack(_ id: EntityID) {
        guard let t = task(id), canPutBack(t) else { return }
        var done = false
        animate(Motion.layout) { done = store.putBack([id], name: "Put Back", undoManager: undo) }
        guard done else { return }
        show(Notice(text: "Put back \(quote(t.title)) in \(listName(t.list))") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    /// Whether Put Back can take the task out of Trash: deleted on its own, from a live list.
    func canPutBack(_ t: TaskModel) -> Bool { t.deleted && !t.isHeading && projection.isActive(list: t.list) }

    /// A When or a deadline. A change that takes the task out of the view on screen (Today's rule, Upcoming's and
    /// Undated's) says where it went, with Undo: "Scheduled for Fri, Nov 6", "Due …", "Removed from Today" (the Mac's
    /// `setDate`, IX:701–704).
    func setDate(_ id: EntityID, _ kind: DateKind, _ date: CalendarDate?) {
        guard let t = task(id), !t.isHeading, !isTrashed(t) else { return }
        let name = kind == .when ? (date == nil ? "Remove When" : "Set When") : (date == nil ? "Remove Deadline" : "Set Deadline")
        let view = shown
        let leaves = leaves(view, when: kind == .when ? date : t.when, deadline: kind == .deadline ? date : t.deadline)
        var done = false
        animate(Motion.layout) {
            switch kind {
            case .when: done = store.setWhen([id], date, name: name, undoManager: undo)
            case .deadline: done = store.setDeadline([id], date, name: name, undoManager: undo)
            }
        }
        guard done, leaves else { return }
        let text = date.map { (kind == .when ? "Scheduled for " : "Due ") + DateLabel.long($0, today: today) }
            ?? "Removed from \(view.map(title) ?? "Today")"
        show(Notice(text: text) { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    /// Whether a task with these dates is no longer in `view` (the Mac's `leavesView`): Today holds a When or a deadline
    /// on or before today; Upcoming, a day after today; Undated, no dates. A list keeps it whatever its dates.
    func leaves(_ view: Source?, when: CalendarDate?, deadline: CalendarDate?) -> Bool {
        switch view {
        case .today: !((when.map { $0 <= today } ?? false) || (deadline.map { $0 <= today } ?? false))
        case .upcoming: ViewGroups.upDay(when: when, deadline: deadline).map { $0 <= today } ?? true
        case .undated: when != nil || deadline != nil
        default: false
        }
    }

    /// Move to: out of the list on screen, "Moved to School", with Undo. In a view the task stays, and nothing is
    /// said (the Mac's `move`).
    func move(_ id: EntityID, to listID: EntityID) {
        guard let t = task(id), t.list != listID, !t.isHeading, !isTrashed(t) else { return }
        var done = false
        animate(Motion.layout) { done = store.move([id], to: listID, name: "Move", undoManager: undo) }
        guard done, case .list? = shown else { return }
        show(Notice(text: "Moved to \(listName(listID))") { [weak self] in
            animate(Motion.layout) { self?.undo.undo() }
        })
    }

    func setTitle(_ id: EntityID, _ title: String, name: String? = nil) { store.setTitle(id, title, name: name, undoManager: undo) }
    func setNotes(_ id: EntityID, _ notes: String, name: String? = nil) { store.setNotes(id, notes, name: name, undoManager: undo) }

    // MARK: Lists

    func deleteList(_ id: EntityID) {
        guard list(id) != nil else { return }
        let name = listName(id)
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
        guard list(id) != nil else { return }
        let name = listName(id)
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
            // Only a name the user changed: an untouched Rename never writes the old name over one that synced in.
            let original = editor.original.trimmingCharacters(in: .whitespaces)
            if EditSession.write(name, original: original, current: list(id)?.name) != nil {
                store.rename(list: id, to: name, undoManager: undo)
            }
            return
        }
        var id: EntityID?
        animate(Motion.layout) { id = store.createList(name: name, undoManager: undo) }
        if let id { open(.list(id)) }
    }

    // MARK: The draft (INTERACTIONS-v2 §6): nothing is written until it has a title

    /// Starts typing in `source`. Text being typed elsewhere ends first, as a tap elsewhere would end it.
    func startDraft(_ source: Source, _ kind: Draft.Kind = .task, text: String = "") {
        if draft != nil { endDraft() }
        animate(Motion.layout) { draft = Draft(source: source, kind: kind, title: text) }
    }

    /// Return: a title makes the task and opens the next row (an empty row ends adding); a heading's name is written
    /// and the field ends.
    func submitDraft() {
        guard let d = draft else { return }
        animate(Motion.layout) { draft = write(d) && d.addsTask ? Draft(source: d.source, kind: d.kind) : nil }
    }

    /// Done with the row any other way: a tap outside it, a swipe, leaving the list, opening something else, the app
    /// going to the background. A title is written; an empty row goes without a trace (no op, no undo step).
    func endDraft() {
        guard let d = draft else { return }
        animate(Motion.layout) {
            _ = write(d)
            draft = nil
        }
    }

    /// Cancel: the row goes with whatever was typed, and nothing is written.
    func cancelDraft() {
        guard draft != nil else { return }
        animate(Motion.layout) { draft = nil }
    }

    /// Ends the draft if its list isn't the one now shown.
    private func endDraft(unlessShowing shown: Source?) {
        if let d = draft, d.source != shown { endDraft() }
    }

    /// One `task.create` for a titled draft (Today's has a When of today, Upcoming's tomorrow; outside a list it goes
    /// to the default list); false, and nothing written, for an empty one. A heading's name or notes: one write, only
    /// if the user changed them (`writeHeading`).
    private func write(_ d: Draft) -> Bool {
        if case .notes = d.kind { return writeHeading(d) }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        var listID: EntityID?
        var when: CalendarDate?
        var anchor = Ordering.Anchor.top
        switch d.source {
        case let .list(id): listID = id
        case .today: when = today
        case .upcoming: when = today.adding(days: 1)
        default: break
        }
        switch d.kind {
        case .task: break
        case let .taskIn(h):
            guard let listID else { return false }
            anchor = sectionEnd(h, in: listID)
        case .heading, .rename, .notes:
            return writeHeading(Draft(source: d.source, kind: d.kind, title: title, token: d.token))
        }
        store.createTask(title: title, in: listID, at: anchor, when: when, undoManager: undo)
        return true
    }

    // MARK: Navigation

    func open(_ s: Source) {
        selection = s
        selectedTask = nil
        if path.last != s { path = [s] }
    }

    // MARK: Notice

    func show(_ n: Notice) {
        animate(Motion.natural) { notice = n }
        // Said as it appears, as the Mac's status messages are (IX:1139).
        AccessibilityNotification.Announcement(n.text).post()
        let id = n.id
        Task { @MainActor in
            try? await Task.sleep(for: n.undo == nil ? Notice.infoLife : Notice.life)
            if notice?.id == id && !holdTransient { animate(Motion.natural) { notice = nil } }
        }
    }

    func undoNotice() {
        guard let n = notice else { return }
        n.undo?()
        animate(Motion.natural) { notice = nil }
    }

    /// “Buy milk”, cut at 28 characters; an empty title is “Untitled” (the Mac's `quote`).
    func quote(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = t.isEmpty ? "Untitled" : t
        return "“" + (s.count > 28 ? String(s.prefix(27)) + "…" : s) + "”"
    }

    /// A list's name in a notice; an empty one is "Untitled" (the Mac's `listName`).
    func listName(_ id: EntityID) -> String {
        let n = list(id)?.name ?? ""
        return n.isEmpty ? "Untitled" : n
    }
}
