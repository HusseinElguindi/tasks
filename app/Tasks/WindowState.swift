import SwiftUI
import TasksCore

/// Per-window UI state: navigation, selection, the detail pane, quick add. Local view state, never synced.
@MainActor
@Observable
final class WindowState {
    enum Route: Hashable {
        case today
        case list(EntityID)
        case archive
    }

    enum Focus { case list, detail }

    var route: Route = .today {
        didSet {
            guard route != oldValue else { return }
            selection = []
            detailTaskID = nil
            quickAdd = nil
            focus = .list
            rowHover.clear()
        }
    }

    /// In the Archive, the archived list opened beside the archive pane.
    var archiveSelection: EntityID?
    var selection: Set<EntityID> = []
    /// The task the detail pane shows; nil = no detail pane.
    var detailTaskID: EntityID?
    /// The pane being typed in is focused (surface-base); the other fades to surface-dim.
    var focus: Focus = .list
    var quickAdd: QuickAddDraft?
    var sidebarVisible = true
    var expandedCompleted: Set<EntityID> = []
    var movePickerPresented = false
    var renamingList: EntityID?
    /// Hover, one item per region (design/INTERACTIONS.md): the task pane's rows (tasks, and Today's group labels by
    /// list id) and the sidebar's.
    let rowHover = PaneHoverRegion<EntityID>()
    let sidebarHover = PaneHoverRegion<SidebarItem>()
    /// What the drag in progress carries, recorded when it starts; drops read it directly.
    @ObservationIgnored var dragged: Dragged?

    enum Dragged: Equatable {
        case tasks([EntityID])
        case list(EntityID)
    }
    /// The window's undo manager, captured from the environment so commands can register with it.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// The list new tasks go to from here: the open list, or nil for the default list.
    var currentListID: EntityID? {
        switch route {
        case .list(let id): id
        case .archive: archiveSelection
        case .today: nil
        }
    }

    func open(_ taskID: EntityID) {
        selection = [taskID]
        detailTaskID = taskID
        focus = .detail
    }
}

/// The quick-add editor row's draft (design: title, notes, then list / When / Deadline chips).
struct QuickAddDraft: Equatable {
    var title = ""
    var notes = ""
    /// nil = the default list (Today) or the open list.
    var list: EntityID?
    var when: CalendarDate?
    var deadline: CalendarDate?
    /// A token that changes each time ⌘N is pressed, so the title field re-focuses.
    var focusToken = UUID()
}

struct WindowStateKey: FocusedValueKey { typealias Value = WindowState }
struct StoreKey: FocusedValueKey { typealias Value = Store }

extension FocusedValues {
    var windowState: WindowState? {
        get { self[WindowStateKey.self] }
        set { self[WindowStateKey.self] = newValue }
    }

    var store: Store? {
        get { self[StoreKey.self] }
        set { self[StoreKey.self] = newValue }
    }
}

/// Actions shared by menus, keyboard shortcuts and pane buttons.
@MainActor
struct WindowActions {
    let store: Store
    let window: WindowState

    var undo: UndoManager? { window.undoManager }

    /// The tasks an action applies to: the selection, or the task in the detail pane.
    var targetIDs: [EntityID] {
        let ids = window.selection.isEmpty ? (window.detailTaskID.map { [$0] } ?? []) : Array(window.selection)
        return ids.sorted { (store.projection.task($0)?.order ?? "") < (store.projection.task($1)?.order ?? "") }
    }

    /// Quick add; `list` presets its list (a Today group's ⊕), else the open list or the default.
    func newTask(in list: EntityID? = nil) {
        var draft = QuickAddDraft()
        if window.route == .today { draft.when = store.projection.day.date }
        draft.list = list ?? window.currentListID
        window.quickAdd = draft
        window.focus = .list
    }

    func toggleDetail() {
        if window.detailTaskID != nil {
            window.detailTaskID = nil
            window.focus = .list
        } else if let id = targetIDs.first {
            window.open(id)
        }
    }

    func toggleComplete() { store.toggleComplete(targetIDs, undoManager: undo) }

    func delete() {
        let ids = targetIDs
        guard !ids.isEmpty else { return }
        store.delete(ids, undoManager: undo)
        window.selection.subtract(ids)
        if let d = window.detailTaskID, ids.contains(d) { window.detailTaskID = nil }
    }

    func move(to list: EntityID) {
        store.move(targetIDs, to: list, undoManager: undo)
        window.movePickerPresented = false
    }

    func setWhen(_ date: CalendarDate?) { store.setWhen(targetIDs, date, undoManager: undo) }

    func newList() {
        let id = store.createList(name: "New List", undoManager: undo)
        window.route = .list(id)
        window.renamingList = id
    }

    func archive(list id: EntityID) {
        store.archive(list: id, undoManager: undo)
        if window.route == .list(id) { window.route = .today }
    }
}
