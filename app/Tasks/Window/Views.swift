import AppKit
import TasksCore

// The four views beside Today (design/INTERACTIONS-v2.md §22; the prototype's dc:2219–2530): Upcoming and Undated
// under Today, Completed and Trash after the lists. Each is a list pane like Today's; only what differs lives here.

extension WindowState.Route {
    /// The views' and Today's name, for headers, sidebar rows and notices.
    var viewName: String? {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .undated: "Undated"
        case .completed: "Completed"
        case .trash: "Trash"
        case .list: nil
        }
    }

    var isList: Bool { listID != nil }

    /// A sidebar row's key is its route (`SidebarModel.Key`).
    var route: WindowState.Route { self }

    /// Upcoming, Undated, Completed or Trash.
    var isView: Bool {
        switch self {
        case .upcoming, .undated, .completed, .trash: true
        default: false
        }
    }

    /// Completed and Trash: no +, and ⌘N adds in the default list instead (§22).
    var noAdd: Bool { self == .completed || self == .trash }

    /// The glyph in the sidebar's tile and the header (dc:25, dc:47).
    var glyph: Glyph? {
        switch self {
        case .today: .sun
        case .upcoming: .calendar
        case .undated: .layers
        case .completed: .doneCircle
        case .trash: .trash
        case .list: nil
        }
    }

    /// Its tile's hue (B, COLOR.md §2): Today the accent's, then the magenta, cyan and green slots'; the Trash the ink
    /// slot's graphite.
    func tileHue(_ p: TK.Palette) -> NSColor {
        switch self {
        case .today: p.tileToday
        case .upcoming: p.tile(.magenta)
        case .undated: p.tile(.cyan)
        case .completed: p.tile(.green)
        default: p.tile(.ink)
        }
    }

    /// The sidebar, top to bottom (dc:2236–2240): no deleted list, it's in Trash (§28). ⌘1–⌘9 open its first nine rows.
    @MainActor
    static func sidebarOrder(_ p: Projection) -> [WindowState.Route] {
        [.today, .upcoming, .undated] + p.activeLists.ids.map { .list($0) } + [.completed, .trash]
    }
}

extension WindowActions {
    var route: WindowState.Route { window.route }

    /// The name of a sidebar row: a view's, or a list's.
    func routeName(_ r: WindowState.Route) -> String {
        if case .list(let id) = r { return listName(id) }
        return r.viewName ?? ""
    }

    // MARK: Adding (dc:871–915, dc:2362–2375)

    /// Upcoming: for the day whose + was pressed, else the selected task's day, else tomorrow. Undated: no dates.
    func newTaskWhen(day: CalendarDate?) -> CalendarDate? {
        switch window.route {
        case .today: return today
        case .upcoming: return day ?? selectedDay() ?? today.adding(days: 1)
        default: return nil
        }
    }

    /// The day the selected task sits on in Upcoming (its group's day, else the day it reaches Today).
    func selectedDay() -> CalendarDate? {
        guard let id = targetIDs.first else { return nil }
        if let d = layout.groupDay(id) { return d }
        guard let t = p.task(id), let d = ViewItems.upDay(when: t.when, deadline: t.deadline), d > today else { return nil }
        return d
    }

    /// Completed and Trash add in the default list: open it, then add there.
    func addInDefault() {
        guard let id = store.defaultListID else {
            overlays.showNotice("Create a list first: ⇧⌘N", undo: false)
            return
        }
        go(.list(id))
        DispatchQueue.main.async { self.newTask(in: id) }
    }

    // MARK: Leaving the open view with a notice (dc:968–979, dc:2379–2386)

    /// Whether these tasks, changed as `change` says, leave the open view.
    func leavesView(_ ids: [EntityID], _ change: (TaskItem) -> (when: CalendarDate?, deadline: CalendarDate?)) -> Bool {
        ids.contains { id in
            guard let t = p.task(id) else { return false }
            let (when, deadline) = change(t)
            switch window.route {
            case .today: return !((when.map { $0 <= today } ?? false) || (deadline.map { $0 <= today } ?? false))
            case .upcoming:
                guard let d = ViewItems.upDay(when: when, deadline: deadline) else { return true }
                return d <= today
            case .undated: return when != nil || deadline != nil
            default: return false
            }
        }
    }

    // MARK: ⌥⌘↑ ⌥⌘↓ in Upcoming (dc:2388–2408)

    /// A day earlier or later (sets When); never past a deadline, and a day before tomorrow is Today. Returns false
    /// where the views don't take it (Today, a list, Undated: they move within the group).
    func viewMoveBy(_ delta: Int) -> Bool {
        switch window.route {
        case .completed, .trash: return true
        case .upcoming: break
        default: return false
        }
        var moves: [(EntityID, CalendarDate)] = []
        for id in targetIDs {
            guard let t = p.task(id), let base = ViewItems.upDay(when: t.when, deadline: t.deadline) else { continue }
            let nd = base.adding(days: delta)
            if nd < today || t.deadline.map({ nd > $0 }) == true { continue }
            moves.append((id, nd))
        }
        guard !moves.isEmpty else { return true }
        let gone = moves.filter { $0.1 <= today }.map(\.0)
        let next = gone.isEmpty ? [] : nextSelection(afterRemoving: gone)
        let byDay = Dictionary(grouping: moves, by: \.1)
        let did = undoable("Set When") {
            var any = false
            for (day, items) in byDay.sorted(by: { $0.key < $1.key }) {
                if store.setWhen(items.map(\.0), day, name: "Set When", undoManager: undo) { any = true }
            }
            return any
        }
        guard did else { return true }
        if !gone.isEmpty {
            select(next)
            overlays.showNotice("Scheduled for " + DateLabel.long(today, today: today), undo: true)
        } else if let first = moves.first?.0 {
            window.taskList?.scrollToVisible(first)
        }
        return true
    }

    // MARK: Completing from the sidebar (dc:2409)

    /// A drop on Completed: completes the open ones among them.
    func completeTasks(_ ids: [EntityID]) {
        let open = ids.filter { p.task($0)?.completedAt == nil }
        if !open.isEmpty { toggleComplete(open) }
    }
}
