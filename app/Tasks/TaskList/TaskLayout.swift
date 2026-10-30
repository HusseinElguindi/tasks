import CoreGraphics
import TasksCore

/// Where every row of the open view sits, in points from the top of the list's content (the prototype's `layout()`,
/// dc:609–653, and `applyDragToLayout`, dc:655–676). Reads index buckets only, plus the few tasks that are pinned
/// while checked rows wait (§8) and the new-task draft (§6).
///
/// O(rows in the view): a 2,000-task list is ~2,000 additions, microseconds.
@MainActor
struct TaskLayout {
    /// A group of rows that a drag can reorder: a list's open tasks, or one Today group. `listID` is the list.
    struct Group {
        var listID: EntityID
        var top: CGFloat
        var ids: [EntityID]
    }

    enum Empty: Equatable { case list, today, allDone }

    /// "today" or the list id: motion is tracked only between layouts with the same key.
    var key: String
    var top: CGFloat
    var ys: [EntityID: CGFloat] = [:]
    /// Rows top to bottom.
    var order: [EntityID] = []
    /// The group of each row: a list id, or `TaskLayout.doneGroup`.
    var groupOf: [EntityID: EntityID] = [:]
    var groups: [Group] = []
    /// Today's group labels by list id (and `doneGroup` for "Completed").
    var labels: [EntityID: CGFloat] = [:]
    var labelOrder: [EntityID] = []
    /// A list's "› Completed 23" row.
    var completedY: CGFloat?
    /// The landing slot under a list's open tasks (the ghost row and the add zone start here).
    var ghostY: CGFloat?
    var doneCount = 0
    var height: CGFloat = 0
    var empty: Empty?
    var draftID: EntityID?

    static let doneGroup = "\u{1}done"
    static let pitch = TK.M.pitch

    func y(of id: EntityID) -> CGFloat? { ys[id] }
    func isDone(_ id: EntityID) -> Bool { groupOf[id] == Self.doneGroup }

    /// The row whose 32pt band (its 30pt shape plus 1pt above and below, §5) contains `y`.
    func row(at y: CGFloat) -> EntityID? {
        // Rows are sorted by y; a binary search keeps this O(log n) for the hover tracker.
        var lo = 0, hi = order.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if (ys[order[mid]] ?? 0) - 1 <= y { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return nil }
        let id = order[lo - 1]
        guard let top = ys[id], y >= top - 1, y < top + TK.M.row + 1 else { return nil }
        return id
    }

    static func make(store: Store, window: WindowState) -> TaskLayout {
        let p = store.projection
        let pins = window.pins
        let draft = window.draft
        switch window.route {
        case .list(let listID):
            let archived = p.list(listID)?.archivedAt != nil
            var L = TaskLayout(key: listID, top: archived ? TK.M.rowTopArchived : TK.M.rowTop)
            var open = p.openTasks(in: listID).ids
            var done = p.completedTasks(in: listID).ids
            if !pins.isEmpty {
                (open, done) = applyPins(pins, open: open, done: done, store: store) { $0.list == listID }
            }
            if let draft, draft.list == listID {
                open.append(draft.id)
                L.draftID = draft.id
            }
            var y = L.top
            L.groups.append(Group(listID: listID, top: y, ids: open))
            for id in open { L.place(id, y, group: listID); y += pitch }
            L.ghostY = y
            y += pitch
            L.doneCount = done.count
            if !done.isEmpty {
                L.completedY = y + 8
                y = L.completedY! + pitch
                if window.completedOpen.contains(listID) {
                    for id in done { L.place(id, y, group: doneGroup); y += pitch }
                }
            }
            if open.isEmpty && done.isEmpty { L.empty = .list }
            L.height = y + 24
            L.applyDrag(window.drag)
            return L

        case .today:
            var L = TaskLayout(key: "today", top: TK.M.rowTop)
            var y = L.top
            let today = p.day.date
            var done = p.todayDone.ids
            var pinnedOpenByList: [EntityID: [EntityID]] = [:]
            var pinnedDone: [(EntityID, Int)] = []
            for (id, pin) in pins {
                guard let t = p.task(id), !t.deleted, p.isActive(list: t.list), Today.datesArrived(t, today: today) else { continue }
                switch pin {
                case .open where t.completedAt != nil: pinnedOpenByList[t.list, default: []].append(id)
                case .done(let at) where t.completedAt == nil && p.day.contains(ms: at): pinnedDone.append((id, at))
                default: break
                }
            }
            for listID in p.activeLists.ids {
                var open = p.todayTasks(in: listID).ids
                if !pins.isEmpty {
                    open.removeAll { if case .done = pins[$0] { true } else { false } }
                    for id in pinnedOpenByList[listID] ?? [] { insertByOrder(id, into: &open, store: store) }
                }
                if let draft, draft.list == listID {
                    open.append(draft.id)
                    L.draftID = draft.id
                }
                guard !open.isEmpty else { continue }
                L.labels[listID] = y
                L.labelOrder.append(listID)
                y += pitch
                L.groups.append(Group(listID: listID, top: y, ids: open))
                for id in open { L.place(id, y, group: listID); y += pitch }
            }
            if !pins.isEmpty {
                done.removeAll { pins[$0] == .open }
                if !pinnedDone.isEmpty {
                    // Today's Completed group is oldest first; a held row keeps its old completion time's place.
                    var keyed = done.map { ($0, p.task($0)?.completedAt ?? 0) } + pinnedDone
                    keyed.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
                    done = keyed.map(\.0)
                }
            }
            let anyOpen = !L.order.isEmpty
            if !anyOpen {
                L.empty = done.isEmpty ? .today : .allDone
                if !done.isEmpty { y = 132 }
            }
            if !done.isEmpty {
                L.labels[doneGroup] = y + (anyOpen ? 8 : 0)
                L.labelOrder.append(doneGroup)
                y += pitch + (anyOpen ? 8 : 0)
                for id in done { L.place(id, y, group: doneGroup); y += pitch }
            }
            L.doneCount = done.count
            L.height = y + 24
            L.applyDrag(window.drag)
            return L
        }
    }

    private mutating func place(_ id: EntityID, _ y: CGFloat, group: EntityID) {
        ys[id] = y
        order.append(id)
        groupOf[id] = group
    }

    /// Checked rows stay put and unchecked ones stay in the done area until the rows settle (§8).
    private static func applyPins(_ pins: [EntityID: WindowState.Pin], open: [EntityID], done: [EntityID], store: Store,
                                  belongs: (TaskItem) -> Bool) -> ([EntityID], [EntityID]) {
        let p = store.projection
        var open = open
        var done = done
        var heldDone: [(EntityID, Int)] = []
        for (id, pin) in pins {
            guard let t = p.task(id), !t.deleted, belongs(t) else { continue }
            switch pin {
            case .open where t.completedAt != nil:
                done.removeAll { $0 == id }
                insertByOrder(id, into: &open, store: store)
            case .done(let at) where t.completedAt == nil:
                open.removeAll { $0 == id }
                heldDone.append((id, at))
            default: break
            }
        }
        if !heldDone.isEmpty {
            // A list's done tasks are newest first.
            var keyed = done.map { ($0, p.task($0)?.completedAt ?? 0) } + heldDone
            keyed.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            done = keyed.map(\.0)
        }
        return (open, done)
    }

    private static func insertByOrder(_ id: EntityID, into ids: inout [EntityID], store: Store) {
        guard let t = store.projection.task(id), !ids.contains(id) else { return }
        let i = ids.firstIndex { other in
            guard let o = store.projection.task(other) else { return false }
            return orderPrecedes(t.order, t.id, o.order, o.id)
        } ?? ids.count
        ids.insert(id, at: i)
    }

    /// The rows of the dragged group part to open a gap at the target; over a sidebar list the group closes up and
    /// everything below it moves up, because the rows are leaving (dc:655–676).
    private mutating func applyDrag(_ drag: WindowState.Drag?) {
        guard let drag, drag.phase != .done, case .tasks(let dragged, let groupID) = drag.kind,
              let g = groups.first(where: { $0.listID == groupID }) else { return }
        let others = g.ids.filter { !dragged.contains($0) }
        let k = CGFloat(dragged.count)
        let gap = drag.over == nil
        let target = drag.over != nil ? others.count : min(max(drag.target, 0), others.count)
        for (i, id) in others.enumerated() {
            ys[id] = g.top + (CGFloat(i) + (gap && i >= target ? k : 0)) * Self.pitch
        }
        if drag.over != nil {
            let shift = k * Self.pitch
            let end = g.top + CGFloat(g.ids.count) * Self.pitch
            for (id, y) in ys where y >= end && groupOf[id] != groupID { ys[id] = y - shift }
            for (lid, y) in labels where y >= end { labels[lid] = y - shift }
            if let gy = ghostY { ghostY = gy - shift }
            if let cy = completedY { completedY = cy - shift }
        }
        for (i, id) in dragged.enumerated() where ys[id] != nil && gap {
            ys[id] = g.top + (CGFloat(target) + CGFloat(i)) * Self.pitch
        }
        // Keep `order` sorted by y for hit-testing.
        order.sort { (ys[$0] ?? 0) < (ys[$1] ?? 0) }
    }
}
