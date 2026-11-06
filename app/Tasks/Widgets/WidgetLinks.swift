import AppKit
import TasksCore

// Where a widget's link opens the app (design/WIDGETS.md §2.2; `DeepLink`, widgets/Shared). The user (2026-11-06): a
// task opens at that task, scrolled to and highlighted as before, without its details; the header opens Today or the
// list; the + opens a new task there.

extension WindowActions {
    /// Opens where `link` points in this window. Whatever was being typed is written first, as a press elsewhere
    /// would. A list or a task that's gone or in the Trash opens Today.
    func follow(_ link: DeepLink) {
        endEdits()
        if window.zoomed { setZoom(false) }
        switch link {
        case .today:
            go(.today, focus: .list)
        case .upcoming:
            go(.upcoming, focus: .list)
        case let .list(id):
            go(p.isActive(list: id) ? .list(id) : .today, focus: .list)
        case let .task(id):
            guard let t = p.task(id), !t.isHeading, !isTrashed(id), p.isActive(list: t.list) else {
                go(.today, focus: .list)
                return
            }
            // A task the widget showed open but that's done by now is under its list's Completed; one under a folded
            // heading needs the heading open.
            if t.completedAt != nil {
                window.completedOpen.insert(t.list)
            } else if let h = p.heading(of: id) {
                expand(h)
            }
            // Selected in its list and scrolled to, not opened: the detail pane closes rather than show it.
            closeDetail()
            go(.list(t.list), select: [id], focus: .list)
        case let .new(list):
            let route: WindowState.Route = list.flatMap { p.isActive(list: $0) ? .list($0) : nil } ?? .today
            go(route, focus: .list)
            newTask(in: route.listID)
        }
    }
}
