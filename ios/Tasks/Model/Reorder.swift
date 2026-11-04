import Foundation
import TasksCore

// Drag to reorder (§14, §23): the model side. The drag itself is the collection view's (TaskCollection+Drag.swift
// for a list and the views, HomeCollection.swift for Home's lists): our own gap at the slot the row will take, our own
// lifted copy, a heading's section folded into the copy with its count, and Upcoming's day label lit. It hands its drop
// here as an offset, as SwiftUI's `.onMove` did, and the writes are only the core's `reorder`, `moveSection` and
// `reorderLists`; the code here only picks the anchor.
//
// Runs (`dragRuns`): a drag stays within one. A list and Upcoming are one run each; Today and Undated have one per
// list's group, so a row never crosses into another list's group. The air above a group label is the last row of the
// run above (`Line.edge`), so a drop there is that group's end. Home's lists have an edge above and one below them
// (`HomeItem`). A heading's notes are in its row (`Line.heading(notes:)`), so no slot opens between them.
//
// Upcoming (IX §22, the Mac's `dayTarget` and `endViewDrag`): the whole view is one run, so a row crosses days. The
// group whose label is the last one above the drop takes it (above them all, the first). On a day, When is set to that
// day, one "Set When" step (`setDate`), and the deadline is never touched; the row then takes its slot in the day, by
// list order. A month, a day after the task's deadline, or its own day writes nothing, and the row goes back.

/// A run of lines that a drag stays within: a whole list, all of Upcoming, or one Today or Undated group (the last one
/// with Today's Completed under it). The drag's gap and lifted copy stay within it (CollectionDrag).
struct DragRun: Identifiable {
    let id: String
    var lines: [Line]
}

extension Line {
    /// The task or heading on this line, for a drop.
    var entityID: EntityID? {
        switch self {
        case let .task(t, _, _, _): t.id
        case let .heading(h, _, _): h.id
        default: nil
        }
    }

    /// An open task, or a heading. Done tasks, labels and the rest don't lift.
    var canDrag: Bool {
        switch self {
        case let .task(t, _, _, _): !t.isDone
        case .heading: true
        default: false
        }
    }
}

/// Where a drop lands, as an `Ordering.Anchor`, from the slot the drag ended in. One place, mirroring the Mac's
/// `WindowActions.reorder(group:ids:target:)` (app/Tasks/Window/WindowActions.swift:580–603), its heading drop
/// (TaskListView.swift, "A heading's section lands only before another heading or at the end") and `moveList`.
enum DropSlot {
    /// A task dropped at `target` among `others` (the run's lines without the dragged ones; nil for a line that's no
    /// task): right after the open row above it, else right before the open row below it, else the end of a view's
    /// group (Today, Undated) or the top of a list. `foldedEnd` gives, for a collapsed heading, its section's last
    /// open task that isn't moving (nil for any other row, or a section with none).
    static func task(target: Int, others: [EntityID?], open: Set<EntityID>, inView: Bool,
                     foldedEnd: (EntityID) -> EntityID? = { _ in nil }) -> Ordering.Anchor {
        let t = min(max(target, 0), others.count)
        let isOpen: (EntityID?) -> Bool = { $0.map(open.contains) ?? false }
        if let prev = others[..<t].last(where: isOpen) ?? nil {
            // Right under a collapsed heading: the end of its section, where it stays folded (§23).
            if let last = foldedEnd(prev) { return .after(last) }
            return .after(prev)
        }
        if let next = others[t...].first(where: isOpen) ?? nil { return .before(next) }
        return inView ? .bottom : .top
    }

    /// A heading dropped at `target`: its section lands only before another heading or at the end, never inside a
    /// section or above the tasks that have no heading. The nearest such slot takes it.
    static func section(target: Int, others: [EntityID?], isHeading: (EntityID) -> Bool) -> Ordering.Anchor {
        let allowed = (0...others.count).filter { $0 == others.count || others[$0].map(isHeading) == true }
        let t = allowed.min { abs($0 - target) < abs($1 - target) } ?? others.count
        if t < others.count, let next = others[t] { return .before(next) }
        return .bottom
    }

    /// A list dropped at `target` among the other active lists.
    static func list(target: Int, others: [EntityID]) -> Ordering.Anchor {
        let t = min(max(target, 0), others.count)
        return t > 0 ? .after(others[t - 1]) : (others.isEmpty ? .top : .before(others[0]))
    }

    /// A drop's destination is an offset in the run before the move (as `.onMove` gives it); this is the slot among
    /// the others.
    static func slot(_ from: IndexSet, _ to: Int) -> Int { to - from.count(in: 0..<to) }
}

extension AppModel {
    /// The runs a drag stays within (`DragRun`), in the views where rows move: a list, Today, Upcoming and Undated.
    func dragRuns(_ lines: [Line], _ source: Source) -> [DragRun]? {
        // A deleted list doesn't reorder (§28).
        guard deletedList(source) == nil else { return nil }
        switch source {
        case .list, .today, .upcoming, .undated: break
        default: return nil
        }
        var runs: [DragRun] = []
        for line in lines {
            // A label's air goes to the run above, as its last row: a drop there is that group's end, not a crossing.
            if case .group = line, !runs.isEmpty {
                runs[runs.count - 1].lines.append(.edge(key: line.id, height: GroupLabel.air))
            }
            // A new run at each Today or Undated group's label; Upcoming is one run, across its days. A list is one
            // run: a drop under Completed lands after its last open task (the done ones aren't open, so
            // `DropSlot.task` passes over them).
            let starts = if case .group = line { source != .upcoming } else { false }
            // Stable ids, so starting or ending adding (the draft line, at the top) doesn't remake the rows.
            if starts { runs.append(DragRun(id: line.id, lines: [])) } else if runs.isEmpty { runs.append(DragRun(id: "top", lines: [])) }
            runs[runs.count - 1].lines.append(line)
        }
        return runs
    }

    /// A drop in one run. Returns whether anything was written.
    @discardableResult
    func drop(_ from: IndexSet, _ to: Int, in lines: [Line], source: Source) -> Bool {
        if source == .upcoming { return dropOnDay(from, to, in: lines) }
        let ids = lines.map(\.entityID)
        let moving = from.compactMap { ids[$0] }
        guard let first = moving.first, let t = task(first) else { return false }
        let others = ids.indices.filter { !from.contains($0) }.map { ids[$0] }
        let target = DropSlot.slot(from, to)
        if t.isHeading {
            let anchor = DropSlot.section(target: target, others: others) { self.task($0)?.isHeading == true }
            return undoable("Move Heading", ids: [first]) { store.moveSection(first, at: anchor, name: "Move Heading", undoManager: undo) }
        }
        let inView = if case .list = source { false } else { true }
        let open = Set(projection.openTasks(in: t.list).ids)
        let anchor = DropSlot.task(target: target, others: others, open: open, inView: inView) { prev in
            guard self.collapsed.contains(prev), self.isHeading(prev) else { return nil }
            return self.projection.section(of: prev).dropFirst().last { open.contains($0) && !moving.contains($0) }
        }
        return undoable("Move", ids: moving) { store.reorder(moving, in: t.list, at: anchor, name: "Move", undoManager: undo) }
    }

    /// A drop in Upcoming (above, "Upcoming"): on a day, When is set to it, one "Set When" step; on a month, past
    /// the task's deadline or on its own day, nothing. Returns whether anything was written.
    private func dropOnDay(_ from: IndexSet, _ to: Int, in lines: [Line]) -> Bool {
        let moving = from.compactMap { lines[$0].entityID }.compactMap(task).filter { !$0.isHeading && !$0.isDone }
        guard !moving.isEmpty else { return false }
        let others = lines.indices.filter { !from.contains($0) }.map { lines[$0] }
        let slot = min(max(DropSlot.slot(from, to), 0), others.count)
        let labels = others.indices.filter { if case .group = others[$0] { true } else { false } }
        guard let label = labels.last(where: { $0 < slot }) ?? labels.first else { return false }
        // The seven days are the only day groups; the rest are months, which aren't targets.
        let days = ViewGroups.upcomingDays(today: today)
        guard let day = days.first(where: { "g:" + ViewGroups.upcoming($0, today: today).id == others[label].id }),
              moving.allSatisfy({ $0.deadline.map { day <= $0 } ?? true }),
              moving.contains(where: { ViewGroups.upDay(when: $0.when, deadline: $0.deadline) != day }) else { return false }
        return setDate(moving.map(\.id), .when, day)
    }

    /// A list dropped on Home (and iPad's sidebar). Today and the views aren't in the run, so they don't move. `ids`:
    /// the run's rows, nil for its edges.
    @discardableResult
    func dropList(_ from: IndexSet, _ to: Int, in ids: [EntityID?]) -> Bool {
        let moving = from.compactMap { ids[$0] }
        guard !moving.isEmpty else { return false }
        let rest = ids.indices.filter { !from.contains($0) }.map { ids[$0] }
        // The slot among the other rows, as a slot among the other lists.
        let slot = min(max(DropSlot.slot(from, to), 0), rest.count)
        let others = rest.compactMap { $0 }
        let anchor = DropSlot.list(target: rest[..<slot].compactMap { $0 }.count, others: others)
        return undoable("Move List") { store.reorderLists(moving, at: anchor, name: "Move List", undoManager: undo) }
    }
}

/// Home's lists run: an edge above them, the lists, an edge below (HomeCollection).
@MainActor
enum HomeItem: @MainActor Identifiable {
    case top, list(ListModel), end

    static func items(_ lists: [ListModel]) -> [HomeItem] { [.top] + lists.map { .list($0) } + [.end] }

    var id: String {
        switch self {
        case .top: "e:top"
        case .end: "e:end"
        case let .list(l): l.id
        }
    }

    var listID: EntityID? { if case let .list(l) = self { l.id } else { nil } }
}
