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

        /// The task pane's mode: Today or a list; nil for the Archive.
        var taskMode: TaskListView.Mode? {
            switch self {
            case .today: .today
            case .list(let id): .list(id)
            case .archive: nil
            }
        }

        var sidebarItem: SidebarItem {
            switch self {
            case .today: .today
            case .list(let id): .list(id)
            case .archive: .archive
            }
        }
    }

    enum Focus { case list, detail }

    var route: Route = .today {
        didSet {
            guard route != oldValue else { return }
            sidebarCurrent.select(route.sidebarItem)
            // Only real changes: Observation notifies on every write, and every row reads the selection.
            if !selection.isEmpty { selection = [] }
            if detailTaskID != nil { detailTaskID = nil }
            if quickAdd != nil { quickAdd = nil }
            if focus != .list { focus = .list }
            if rowDrop != nil { rowDrop = nil }
            rowHover.clear()
            selectionAnchor = nil
            selectionCursor = nil
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
    /// The sidebar's current row, one flag per row, so a route change redraws two rows rather than the sidebar.
    let sidebarCurrent: PaneFlags<SidebarItem> = {
        let flags = PaneFlags<SidebarItem>()
        flags.select(.today)
        return flags
    }()
    /// What the drag in progress carries, recorded when it starts; drops read it directly. Dragged task rows stay in
    /// place at 35% until the drag ends.
    var dragged: Dragged?
    /// Where a dragged task would land among the rows: above or below this one.
    var rowDrop: RowDrop?
    /// Bumped by a click on a row: the task list takes keyboard focus.
    var listFocusRequest = 0
    /// Today's quick-add row height, for placing drops below it.
    @ObservationIgnored var quickAddHeight: CGFloat = 0
    /// Shift-click and ⇧↑↓ extend from the anchor; ↑↓ move from the cursor.
    @ObservationIgnored var selectionAnchor: EntityID?
    @ObservationIgnored var selectionCursor: EntityID?
    @ObservationIgnored private var dragWatch: Task<Void, Never>?

    enum Dragged: Equatable {
        case tasks([EntityID])
        case list(EntityID)

        func contains(_ id: EntityID) -> Bool {
            if case .tasks(let ids) = self { ids.contains(id) } else { false }
        }
    }

    /// Where dragged tasks would land: above or below `target` (a task of `list`), drawn at `y` in the task stack.
    struct RowDrop: Equatable {
        var target: EntityID
        var list: EntityID
        var above: Bool
        var y: CGFloat
    }

    /// SwiftUI says when a drag starts but not when it ends: the drag is over once the mouse button is up. The drop
    /// itself (on the release) has run by then; a short grace covers the release racing the drop.
    func beginDrag(_ payload: Dragged) {
        dragged = payload
        dragWatch?.cancel()
        dragWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.dragged = nil
            self.rowDrop = nil
        }
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

    func toggleComplete() {
        withAnimation(PaneMotion.snappy) { store.toggleComplete(targetIDs, undoManager: undo) }
    }

    /// The task pane's rows, top to bottom: Today's groups in sidebar order then done today, or a list's open tasks
    /// then its completed ones when expanded. Built on demand (clicks and keys), never in a body.
    var rowOrder: [EntityID] {
        let p = store.projection
        func listRows(_ id: EntityID) -> [EntityID] {
            p.openTasks(in: id).ids + (window.expandedCompleted.contains(id) ? p.completedTasks(in: id).ids : [])
        }
        switch window.route {
        case .today: return p.activeLists.ids.flatMap { p.todayTasks(in: $0).ids } + p.todayDone.ids
        case .list(let id): return listRows(id)
        case .archive: return window.archiveSelection.map(listRows) ?? []
        }
    }

    /// A click on a task row: select it (⌘ toggles, ⇧ extends from the anchor), open it on a double-click, and give
    /// the list keyboard focus.
    func click(_ id: EntityID) {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        window.listFocusRequest += 1
        if event?.clickCount == 2, !flags.contains(.command), !flags.contains(.shift) {
            window.open(id)
            return
        }
        if flags.contains(.command) {
            if window.selection.contains(id) { window.selection.remove(id) } else { window.selection.insert(id) }
            window.selectionAnchor = id
        } else if flags.contains(.shift), let anchor = window.selectionAnchor {
            let order = rowOrder
            if let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
                window.selection = Set(order[min(a, b)...max(a, b)])
            }
        } else {
            window.selection = [id]
            window.selectionAnchor = id
        }
        window.selectionCursor = id
    }

    /// ↑ ↓ (⇧ extends). Returns the row moved to, to scroll it into view.
    func moveSelection(down: Bool, extend: Bool) -> EntityID? {
        let order = rowOrder
        guard !order.isEmpty else { return nil }
        let cursor = window.selectionCursor.flatMap { order.firstIndex(of: $0) }
            ?? (down ? order.lastIndex(where: window.selection.contains) : order.firstIndex(where: window.selection.contains))
        let next = cursor.map { min(max($0 + (down ? 1 : -1), 0), order.count - 1) } ?? (down ? 0 : order.count - 1)
        let id = order[next]
        if extend, let anchor = window.selectionAnchor.flatMap({ order.firstIndex(of: $0) }) {
            window.selection = Set(order[min(anchor, next)...max(anchor, next)])
        } else {
            window.selection = [id]
            window.selectionAnchor = id
        }
        window.selectionCursor = id
        return id
    }

    /// A right-click acts on the selection when the row is in it, else on that row alone.
    func menuTargets(for id: EntityID) -> [EntityID] {
        window.selection.contains(id) ? targetIDs : [id]
    }

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
