import CoreGraphics
import TasksCore

/// Where every row of the open view sits, in points from the top of the list's content (the prototype's `layout()`,
/// dc:609–653, and `applyDragToLayout`, dc:655–676). Reads index buckets only, plus the few tasks that are pinned
/// while checked rows wait (§8) and the new-task draft (§6).
///
/// Rows are parallel arrays with one id → index map, and the whole layout is reused while its inputs (the buckets'
/// arrays, the pins, the draft, the drag…) are unchanged, so a title edit or a selection change costs nothing here
/// (§9: a local edit redraws one row).
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
    /// Rows top to bottom, with their y and their group (an index into `groups`, or -1 for done rows).
    var order: [EntityID] = []
    var yList: [CGFloat] = []
    private var groupIndex: [Int] = []
    var index: [EntityID: Int] = [:]
    var groups: [Group] = []
    /// Today's group labels by list id (and `doneGroup` for "Completed").
    var labels: [EntityID: CGFloat] = [:]
    var labelOrder: [EntityID] = []
    /// A list's "› Completed 23" row.
    var completedY: CGFloat?
    /// The empty slot under a list's open tasks, where a new task lands (the Completed row sits one slot and 8pt below).
    var landingY: CGFloat?
    var doneCount = 0
    var height: CGFloat = 0
    var empty: Empty?
    var draftID: EntityID?

    static let doneGroup = "\u{1}done"
    static let pitch = TK.M.pitch

    func y(_ id: EntityID) -> CGFloat? { index[id].map { yList[$0] } }
    func contains(_ id: EntityID) -> Bool { index[id] != nil }

    /// A row's group: its list id, or `doneGroup`.
    func group(_ id: EntityID) -> EntityID? {
        guard let i = index[id] else { return nil }
        let g = groupIndex[i]
        return g < 0 ? Self.doneGroup : groups[g].listID
    }

    func isDone(_ id: EntityID) -> Bool { index[id].map { groupIndex[$0] < 0 } ?? false }

    /// The first row at or below `y`.
    func firstIndex(atOrBelow y: CGFloat) -> Int {
        var lo = 0, hi = yList.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if yList[mid] < y { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The row whose 32pt band (its 30pt shape plus 1pt above and below, §5) contains `y`.
    func row(at y: CGFloat) -> EntityID? {
        let i = firstIndex(atOrBelow: y + 1) - 1
        guard i >= 0, y >= yList[i] - 1, y < yList[i] + TK.M.row + 1 else { return nil }
        return order[i]
    }

    // MARK: - Building

    /// What a layout depends on. Arrays compare by identity first, so an unchanged bucket costs nothing.
    struct Inputs: Equatable {
        var route: WindowState.Route
        var lists: [[EntityID]]
        var archived: Bool
        var completedOpen: Bool
        var pins: [EntityID: WindowState.Pin]
        var draft: WindowState.Draft?
        var drag: WindowState.Drag?
        var day: CalendarDate
    }

    /// The layout for the window's view, reused from the last call while its inputs are unchanged.
    static func make(store: Store, window: WindowState) -> TaskLayout {
        let p = store.projection
        var lists: [[EntityID]] = []
        var archived = false
        var completedOpen = false
        switch window.route {
        case .list(let id):
            lists = [p.openTasks(in: id).ids, p.completedTasks(in: id).ids]
            archived = p.list(id)?.archivedAt != nil
            completedOpen = window.completedOpen.contains(id)
        case .today:
            let active = p.activeLists.ids
            lists = [active, p.todayDone.ids]
            for l in active { lists.append(p.todayTasks(in: l).ids) }
        }
        // The draft's title doesn't move rows.
        var draft = window.draft
        if let title = draft?.title { draft?.title = title.isEmpty ? "" : "x" }
        let inputs = Inputs(route: window.route, lists: lists, archived: archived, completedOpen: completedOpen,
                            pins: window.pins, draft: draft, drag: window.drag, day: p.day.date)
        if let cached = window.layoutCache, cached.inputs == inputs { return cached.layout }
        let layout = build(store: store, window: window, inputs: inputs)
        window.layoutCache = (inputs, layout)
        return layout
    }

    private static func build(store: Store, window: WindowState, inputs: Inputs) -> TaskLayout {
        let p = store.projection
        let pins = inputs.pins
        let draft = inputs.draft
        switch inputs.route {
        case .list(let listID):
            var L = TaskLayout(key: listID, top: inputs.archived ? TK.M.rowTopArchived : TK.M.rowTop)
            var open = inputs.lists[0]
            var done = inputs.lists[1]
            if !pins.isEmpty {
                (open, done) = applyPins(pins, open: open, done: done, store: store) { $0.list == listID }
            }
            if let draft, draft.list == listID {
                open.append(draft.id)
                L.draftID = draft.id
            }
            L.reserve(open.count + (inputs.completedOpen ? done.count : 0))
            var y = L.top
            L.groups.append(Group(listID: listID, top: y, ids: open))
            for id in open { L.place(id, y, group: 0); y += pitch }
            L.landingY = y
            y += pitch
            L.doneCount = done.count
            if !done.isEmpty {
                L.completedY = y + 8
                y = L.completedY! + pitch
                if inputs.completedOpen {
                    for id in done { L.place(id, y, group: -1); y += pitch }
                }
            }
            if open.isEmpty && done.isEmpty { L.empty = .list }
            L.height = y + 24
            L.applyDrag(inputs.drag)
            return L

        case .today:
            var L = TaskLayout(key: "today", top: TK.M.rowTop)
            var y = L.top
            let today = p.day.date
            let active = inputs.lists[0]
            var done = inputs.lists[1]
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
            for (i, listID) in active.enumerated() {
                var open = inputs.lists[2 + i]
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
                for id in open { L.place(id, y, group: L.groups.count - 1); y += pitch }
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
                for id in done { L.place(id, y, group: -1); y += pitch }
            }
            L.doneCount = done.count
            L.height = y + 24
            L.applyDrag(inputs.drag)
            return L
        }
    }

    private mutating func reserve(_ n: Int) {
        order.reserveCapacity(n)
        yList.reserveCapacity(n)
        groupIndex.reserveCapacity(n)
        index.reserveCapacity(n)
    }

    private mutating func place(_ id: EntityID, _ y: CGFloat, group: Int) {
        index[id] = order.count
        order.append(id)
        yList.append(y)
        groupIndex.append(group)
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
              let gi = groups.firstIndex(where: { $0.listID == groupID }) else { return }
        let g = groups[gi]
        let draggedSet = Set(dragged)
        let others = g.ids.filter { !draggedSet.contains($0) }
        let k = CGFloat(dragged.count)
        let gap = drag.over == nil
        let target = drag.over != nil ? others.count : min(max(drag.target, 0), others.count)
        for (i, id) in others.enumerated() {
            if let r = index[id] { yList[r] = g.top + (CGFloat(i) + (gap && i >= target ? k : 0)) * Self.pitch }
        }
        if drag.over != nil {
            let shift = k * Self.pitch
            let end = g.top + CGFloat(g.ids.count) * Self.pitch
            for r in yList.indices where yList[r] >= end && groupIndex[r] != gi { yList[r] -= shift }
            for (lid, y) in labels where y >= end { labels[lid] = y - shift }
            if let gy = landingY { landingY = gy - shift }
            if let cy = completedY { completedY = cy - shift }
        }
        if gap {
            for (i, id) in dragged.enumerated() {
                if let r = index[id] { yList[r] = g.top + (CGFloat(target) + CGFloat(i)) * Self.pitch }
            }
        }
        // Keep the rows sorted by y for hit-testing.
        let perm = yList.indices.sorted { yList[$0] < yList[$1] }
        order = perm.map { order[$0] }
        yList = perm.map { yList[$0] }
        groupIndex = perm.map { groupIndex[$0] }
        for (i, id) in order.enumerated() { index[id] = i }
    }
}
