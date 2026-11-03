import Foundation
import TasksCore

// Drag to reorder (§14, §23), on the iPhone's own drag: List's `.onMove` (ListScreen, HomeView). Long-press then move
// lifts the row; holding still opens its menu. The other rows part to open a gap, and the list scrolls at its edges.
//
// Three deviations from the Mac, accepted by the user on 2026-11-03 (option A):
// - The lifted copy is the system's: its platter and shadow, not `fill-lift` and `shadow-lift`. It has the row's
//   radius (`contentShape(.dragPreview, …)`).
// - A heading lifts alone. Its section doesn't fold into the copy and there's no count badge; the drop still moves
//   the whole section (`Store.moveSection`).
// - In Today and Undated the copy can cross into another list's group. The drop there is refused by the system (each
//   group is its own ForEach): the copy flies back and nothing is written.
//
// The writes are only the core's `reorder`, `moveSection` and `reorderLists`; the code here only picks the anchor.

/// A run of lines that a drag stays within: a whole list, or one Today or Undated group (the last one with Today's
/// Completed under it). Each is its own ForEach, so a drop never lands in another.
struct DragRun: Identifiable {
    let id: String
    var lines: [Line]
}

extension Line {
    /// The task or heading on this line, for a drop.
    var entityID: EntityID? {
        switch self {
        case let .task(t, _, _, _): t.id
        case let .heading(h, _): h.id
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

    /// `.onMove`'s destination is an offset in the run before the move; this is the slot among the others.
    static func slot(_ from: IndexSet, _ to: Int) -> Int { to - from.count(in: 0..<to) }
}

extension AppModel {
    /// The runs a drag stays within (`DragRun`), in the views where rows move: a list, Today and Undated.
    func dragRuns(_ lines: [Line], _ source: Source) -> [DragRun]? {
        switch source {
        case .list, .today, .undated: break
        default: return nil
        }
        var runs: [DragRun] = []
        for line in lines {
            // A new run at each Today or Undated group's label. A list is one run: a drop under Completed lands
            // after its last open task (the done ones aren't open, so `DropSlot.task` passes over them).
            let starts = if case .group = line { true } else { false }
            // Stable ids, so starting or ending adding (the draft line, at the top) doesn't remake the rows.
            if starts { runs.append(DragRun(id: line.id, lines: [])) } else if runs.isEmpty { runs.append(DragRun(id: "top", lines: [])) }
            runs[runs.count - 1].lines.append(line)
        }
        return runs
    }

    /// A drop from `.onMove` in one run. Returns whether anything was written.
    @discardableResult
    func drop(_ from: IndexSet, _ to: Int, in lines: [Line], source: Source) -> Bool {
        let ids = lines.map(\.entityID)
        let moving = from.compactMap { ids[$0] }
        guard let first = moving.first, let t = task(first) else { return false }
        let others = ids.indices.filter { !from.contains($0) }.map { ids[$0] }
        let target = DropSlot.slot(from, to)
        if t.isHeading {
            let anchor = DropSlot.section(target: target, others: others) { self.task($0)?.isHeading == true }
            return store.moveSection(first, at: anchor, name: "Move Heading", undoManager: undo)
        }
        let inView = if case .list = source { false } else { true }
        let open = Set(projection.openTasks(in: t.list).ids)
        let anchor = DropSlot.task(target: target, others: others, open: open, inView: inView) { prev in
            guard self.collapsed.contains(prev), self.isHeading(prev) else { return nil }
            return self.projection.section(of: prev).dropFirst().last { open.contains($0) && !moving.contains($0) }
        }
        return store.reorder(moving, in: t.list, at: anchor, name: "Move", undoManager: undo)
    }

    /// A list dropped on Home (and iPad's sidebar). Today and the views aren't in the run, so they don't move.
    @discardableResult
    func dropList(_ from: IndexSet, _ to: Int) -> Bool {
        let ids = activeLists.map(\.id)
        let moving = from.map { ids[$0] }
        let others = ids.indices.filter { !from.contains($0) }.map { ids[$0] }
        let anchor = DropSlot.list(target: DropSlot.slot(from, to), others: others)
        return store.reorderLists(moving, at: anchor, name: "Move List", undoManager: undo)
    }
}
