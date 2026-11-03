import Foundation
import TasksCore

/// One line of a list pane: a group label, a heading, a task, a Completed disclosure, a deleted list.
@MainActor
enum Line: @MainActor Identifiable {
    case group(key: String, title: String, sub: String?, quiet: Bool)
    case heading(TaskModel, openCount: Int)
    /// `groupDay`: in Upcoming, the day of the group it's in (its rows don't repeat that date).
    case task(TaskModel, indent: Bool, groupDay: CalendarDate? = nil)
    case completedToggle(key: String, count: Int, open: Bool)
    case deletedList(ListModel, count: Int, open: Bool)
    case draft
    case empty(title: String, message: String, symbol: String)

    var id: String {
        switch self {
        case let .group(key, _, _, _): "g:" + key
        case let .heading(h, _): "h:" + h.id
        case let .task(t, _, _): "t:" + t.id
        case let .completedToggle(key, _, _): "c:" + key
        case let .deletedList(l, _, _): "dl:" + l.id
        case .draft: "draft"
        case .empty: "empty"
        }
    }

    var isDraft: Bool {
        if case .draft = self { true } else { false }
    }
}

/// The lines of each view, composed from the projection's buckets and models and grouped by TasksCore's `ViewGroups`
/// (the Mac's rules), plus the rows checked a moment ago, which stay where they were.
extension AppModel {
    func lines(_ source: Source) -> [Line] {
        var out: [Line] = []
        let draftHere = draft?.source == source
        if draftHere { out.append(.draft) }
        switch source {
        case let .list(id): listLines(id, into: &out, draftHere: draftHere)
        case .today: todayLines(into: &out, draftHere: draftHere)
        case .upcoming: upcomingLines(into: &out, draftHere: draftHere)
        case .undated: undatedLines(into: &out, draftHere: draftHere)
        case .completed: completedLines(into: &out)
        case .trash: trashLines(into: &out)
        }
        return out
    }

    // MARK: A list

    private func listLines(_ id: EntityID, into out: inout [Line], draftHere: Bool) {
        // Its open tasks and headings in its order, with the ones checked a moment ago still in place.
        let models = withCompleting(projection.openTasks(in: id).ids) { $0.list == id }.compactMap(task)
        for (i, m) in models.enumerated() {
            guard m.isHeading else { out.append(.task(m, indent: false)); continue }
            // A heading's count: the open tasks under it, down to the next heading.
            let section = models[(i + 1)...].prefix { !$0.isHeading }
            out.append(.heading(m, openCount: section.filter { !$0.isDone }.count))
        }
        let done = projection.completedTasks(in: id).ids.filter { !completing.contains($0) }
        if !done.isEmpty {
            let open = showCompleted.contains(id)
            out.append(.completedToggle(key: id, count: done.count, open: open))
            if open { out += done.compactMap(task).map { .task($0, indent: false) } }
        }
        if models.isEmpty && done.isEmpty && !draftHere {
            out.append(.empty(title: "No tasks", message: "Tap + to add one. Tasks you add here stay in this list.", symbol: "checklist"))
        }
    }

    // MARK: Today

    /// Each live list's Today tasks in sidebar order (the projection's Today buckets), then what was done today.
    private func todayLines(into out: inout [Line], draftHere: Bool) {
        let day = today
        var any = false
        for l in activeLists {
            let ids = withCompleting(projection.todayTasks(in: l.id).ids) { t in
                t.list == l.id && projection.task(t.id).map { Today.datesArrived($0, today: day) } == true
            }
            guard !ids.isEmpty else { continue }
            any = true
            out.append(.group(key: l.id, title: l.name, sub: nil, quiet: false))
            out += ids.compactMap(task).map { .task($0, indent: false) }
        }
        let done = projection.todayDone.ids.filter { !completing.contains($0) }
        if !done.isEmpty {
            let open = showCompleted.contains(Self.todayDone)
            out.append(.completedToggle(key: Self.todayDone, count: done.count, open: open))
            if open { out += done.compactMap(task).map { .task($0, indent: false) } }
        }
        guard !any, !draftHere else { return }
        if done.isEmpty {
            out.append(.empty(title: "Nothing for today", message: "Tasks you plan for today, or that are due, show up here.", symbol: "sun.max"))
        } else {
            out.append(.empty(title: "All done for today", message: "", symbol: "sun.max.fill"))
        }
    }

    // MARK: Upcoming

    /// Each open task on the day it reaches Today, after today: the next seven days always, then a group per month that
    /// has tasks; in a day, by list in sidebar order, then the list's order (`ViewGroups`).
    private func upcomingLines(into out: inout [Line], draftHere: Bool) {
        let day = today
        var items: [(task: TaskModel, key: ViewGroups.UpcomingKey)] = []
        for (rank, l) in projection.activeLists.ids.enumerated() {
            for id in withCompleting(projection.openTasks(in: l).ids, belongs: { $0.list == l }) {
                guard let m = task(id), !m.isHeading,
                      let up = ViewGroups.upDay(when: m.when, deadline: m.deadline), up > day else { continue }
                items.append((m, ViewGroups.UpcomingKey(id: id, day: up, rank: rank, order: m.order)))
            }
        }
        items.sort { ViewGroups.upcomingPrecedes($0.key, $1.key) }
        var groups = ViewGroups.upcomingDays(today: day).map { ViewGroups.upcoming($0, today: day) }
        var rows: [String: [TaskModel]] = [:]
        for item in items {
            let g = ViewGroups.upcoming(item.key.day, today: day)
            if rows[g.id] == nil, !groups.contains(where: { $0.id == g.id }) { groups.append(g) }
            rows[g.id, default: []].append(item.task)
        }
        for g in groups {
            let mine = rows[g.id] ?? []
            out.append(.group(key: g.id, title: g.name, sub: g.sub, quiet: mine.isEmpty))
            out += mine.map { .task($0, indent: false, groupDay: g.day) }
        }
        if items.isEmpty && !draftHere {
            out.append(.empty(title: "Nothing upcoming", message: "Tasks with a date after today show up here, on the day they reach Today.", symbol: "calendar"))
        }
    }

    // MARK: Undated

    /// Open tasks with no When and no Deadline, by live list in sidebar order, each in its list's order.
    private func undatedLines(into out: inout [Line], draftHere: Bool) {
        var any = false
        for l in activeLists {
            let ids = withCompleting(projection.openTasks(in: l.id).ids) { $0.list == l.id }
            let mine = ids.compactMap(task).filter { !$0.isHeading && $0.when == nil && $0.deadline == nil }
            guard !mine.isEmpty else { continue }
            any = true
            out.append(.group(key: l.id, title: l.name, sub: nil, quiet: false))
            out += mine.map { .task($0, indent: false) }
        }
        if !any && !draftHere {
            out.append(.empty(title: "Every task has a date", message: "Open tasks with no When and no Deadline show up here, by list.", symbol: "square.stack"))
        }
    }

    // MARK: Completed and Trash

    /// Every live list's completed tasks, newest first, by the local day they were done (`ViewGroups.past`).
    private func completedLines(into out: inout [Line]) {
        var items: [(task: TaskModel, at: Int)] = []
        for l in projection.activeLists.ids {
            for id in projection.completedTasks(in: l).ids where !completing.contains(id) {
                if let m = task(id), let at = m.completedAt { items.append((m, at)) }
            }
        }
        // Each list's are newest first already; merged the same way, ties by id (the Mac's ViewItems).
        items.sort { $0.at != $1.at ? $0.at > $1.at : $0.task.id < $1.task.id }
        var seen: Set<String> = []
        for item in items {
            let g = ViewGroups.past(localDay(item.at), today: today)
            if seen.insert(g.id).inserted { out.append(.group(key: g.id, title: g.name, sub: g.sub, quiet: false)) }
            out.append(.task(item.task, indent: false))
        }
        if items.isEmpty {
            out.append(.empty(title: "Nothing completed yet", message: "Tasks you check off show up here, newest first.", symbol: "checkmark.circle"))
        }
    }

    /// Deleted lists and the tasks deleted on their own, newest first (`Projection.trash`), by the local day they were
    /// deleted.
    private func trashLines(into out: inout [Line]) {
        let entries = projection.trash()
        var seen: Set<String> = []
        for e in entries {
            let g = ViewGroups.past(localDay(e.deletedAt), today: today)
            if seen.insert(g.id).inserted { out.append(.group(key: g.id, title: g.name, sub: g.sub, quiet: false)) }
            out += trashEntry(e)
        }
        if entries.isEmpty {
            out.append(.empty(title: "Trash is empty", message: "Deleted tasks wait here until you put them back.", symbol: "trash"))
        }
    }

    /// A deleted list is one row, and opened, the tasks it took with it follow; a task deleted on its own is one row.
    private func trashEntry(_ e: Projection.TrashEntry) -> [Line] {
        switch e.item {
        case let .list(id):
            guard let l = list(id) else { return [] }
            let held = projection.tasksInDeletedList(id)
            let open = expandedTrash.contains(id)
            var out: [Line] = [.deletedList(l, count: held.count, open: open)]
            if open { out += held.compactMap(task).map { .task($0, indent: true) } }
            return out
        case let .task(id):
            return task(id).map { [.task($0, indent: false)] } ?? []
        }
    }

    /// The local calendar day of an instant (epoch ms), as the Mac reads completions and deletions.
    func localDay(_ ms: Int) -> CalendarDate {
        CalendarDate(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    // MARK: Checked a moment ago

    /// `ids` (a bucket, in its order) with the tasks checked a moment ago that `belongs` to it put back where their
    /// key places them, as the Mac's `applyPins` does: completing doesn't change a task's key.
    private func withCompleting(_ ids: [EntityID], belongs: (TaskModel) -> Bool) -> [EntityID] {
        guard !completing.isEmpty else { return ids }
        var out = ids
        for id in completing.sorted() {
            guard let t = task(id), t.isDone, !t.deleted, !out.contains(id), belongs(t) else { continue }
            let i = out.firstIndex { other in
                guard let o = task(other) else { return false }
                return orderPrecedes(t.order, t.id, o.order, o.id)
            } ?? out.count
            out.insert(id, at: i)
        }
        return out
    }
}
