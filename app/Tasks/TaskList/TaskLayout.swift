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
        /// The views' groups (§22): a list's (Undated), a day's or a month's (Upcoming, Completed, Trash).
        var kind: GroupKind = .list
        var day: CalendarDate?
    }

    enum GroupKind: Equatable { case list, day, month }

    /// A view's group label: its name, the day's date after it, whether it's an empty day, and its + (§22).
    struct LabelInfo: Equatable {
        var name: String
        var sub: String?
        var quiet = false
        var plus = false
        /// The + adds to this list (Undated) or for this day (Upcoming).
        var list: EntityID?
        var day: CalendarDate?
        /// A day inside one of Upcoming's months: a 24pt label (`dayInMonthLabel`).
        var inMonth = false
        /// One of Upcoming's months: a list heading's look in a 44pt slot (`monthLabel`, round 2: B).
        var month = false
    }

    enum Empty: Equatable { case list, today, allDone, upcoming, undated, completed, trash }

    /// "today" or the list id: motion is tracked only between layouts with the same key.
    var key: String
    var top: CGFloat
    /// Rows top to bottom, with their y and their group (an index into `groups`, or -1 for done rows).
    var order: [EntityID] = []
    var yList: [CGFloat] = []
    var groupIndex: [Int] = []
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
    /// Upcoming's empty state sits under its seven empty days, not 34% down.
    var emptyTop: CGFloat?
    var draftID: EntityID?
    /// The views' labels (Today's are list names, from `labels` alone).
    var labelInfo: [EntityID: LabelInfo] = [:]
    /// Upcoming's columns (direction C): the lists its rows are in, whose widest short name sets the mark's column, and
    /// the Deadline's column, as wide as its widest date (0: no row has one). Both stay put through a drag.
    var markLists: [EntityID] = []
    var deadlineColumn: CGFloat = 0

    // Headings and the title block (design/INTERACTIONS-v2.md §23).
    /// The title block's top (under a deleted list's banner, §28) and height: the large title, and a list's notes.
    var headY: CGFloat = 0
    var titleHeight: CGFloat = 0
    /// Heading rows (a new one being named included). A heading's slot is its air, its row and its notes; `yList`
    /// holds its row's top, like a task's.
    var headingIDs: Set<EntityID> = []
    var slotH: [EntityID: CGFloat] = [:]
    /// A heading's notes height under its row (0 when it shows none), at its row's top + 32.
    var noteH: [EntityID: CGFloat] = [:]
    /// Tasks folded under a collapsed heading: not laid out, kept so they can fold into it and unfold from it. In
    /// Trash, a collapsed deleted list's tasks, folded under its row (§28).
    var folded: [EntityID: EntityID] = [:]
    /// Trash (§28): the deleted lists' rows, and each expanded list's tasks under it, by their list.
    var listRows: Set<EntityID> = []
    var childOf: [EntityID: EntityID] = [:]

    static let doneGroup = "\u{1}done"
    /// A list's "› Completed" row, as what its closed tasks fold into.
    static let completedRowKey = "\u{1}crow"

    /// Where a folded row goes and comes from: its heading's row, Today's Completed label, or a list's Completed row.
    func foldY(_ key: EntityID) -> CGFloat? {
        if let y = y(key) { return y }
        if let y = labels[key] { return y }
        return key == Self.completedRowKey ? completedY : nil
    }
    static let pitch = TK.M.pitch
    /// A heading's air above its row (`HEAD_AIR`, dc:445).
    static let headAir: CGFloat = 8

    func isHeading(_ id: EntityID) -> Bool { headingIDs.contains(id) }
    /// A row's slot: 32, or a heading's air, row and notes.
    func slotHeight(_ id: EntityID) -> CGFloat { slotH[id] ?? Self.pitch }
    /// Where a row's shape sits in its slot: 0, or a heading's air.
    func rowOffset(_ id: EntityID) -> CGFloat { headingIDs.contains(id) ? Self.headAir : 0 }

    /// The title block: 4 above the title line (30, and 26 more for each line a long name wraps onto), then a list's
    /// notes 4 below it, then 12 to the rows (css:439–445).
    static func titleBlockHeight(notes: CGFloat?, line: CGFloat = 30) -> CGFloat {
        4 + max(30, line) + (notes.map { 4 + max(19, $0) } ?? 0) + 12
    }
    /// A deleted list's banner sits above the title block (§28: the large title starts at 60).
    static let bannerBlock: CGFloat = 60

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
        /// A list's headings (§23): which are collapsed, which show notes and how tall, the list's notes' height, and a
        /// new heading being named.
        var collapsed: Set<EntityID> = []
        var noteHeights: [EntityID: CGFloat] = [:]
        var titleNotes: CGFloat?
        /// The large title's line (`WindowState.titleLine`).
        var titleLine: CGFloat = 30
        var newHeading: EntityID?
        var newHeadingBefore: EntityID?
        /// The list is deleted: its banner sits above the title (§28).
        var deleted: Bool
        /// Trash: the deleted lists that show their tasks under their row (§28).
        var expanded: [EntityID] = []
        var completedOpen: Bool
        var pins: [EntityID: WindowState.Pin]
        var draft: WindowState.Draft?
        var drag: WindowState.Drag?
        var day: CalendarDate
        /// A view's rows as read this time (`ViewItems`): what its layout depends on beyond the buckets.
        var view: ViewItems?
    }

    /// The layout for the window's view, reused from the last call while its inputs are unchanged.
    static func make(store: Store, window: WindowState) -> TaskLayout {
        let p = store.projection
        var lists: [[EntityID]] = []
        var deleted = false
        var completedOpen = false
        var expanded: [EntityID] = []
        switch window.route {
        case .list(let id):
            lists = [p.openTasks(in: id).ids, p.completedTasks(in: id).ids, p.headings(in: id).ids]
            deleted = p.isDeleted(list: id)
            completedOpen = window.completedOpen.contains(id)
        case .today:
            let active = p.activeLists.ids
            lists = [active, p.todayDone.ids]
            for l in active { lists.append(p.todayTasks(in: l).ids) }
            // Today's Completed group folds like a heading (v2 feedback 15).
            completedOpen = !window.todayDoneCollapsed
        case .trash:
            // An expanded deleted list's rows follow its buckets (§28).
            expanded = p.deletedLists.ids.filter(window.trashExpanded.contains)
            for l in expanded { lists += [p.openTasks(in: l).ids, p.completedTasks(in: l).ids] }
        case .upcoming, .undated, .completed:
            break
        }
        let view = ViewItems.read(store: store, window: window)
        // The draft's title doesn't move rows.
        var draft = window.draft
        if let title = draft?.title { draft?.title = title.isEmpty ? "" : "x" }
        var inputs = Inputs(route: window.route, lists: lists, deleted: deleted, expanded: expanded, completedOpen: completedOpen,
                            pins: window.pins, draft: draft, drag: window.drag, day: p.day.date, view: view)
        inputs.titleLine = window.titleLine
        if case .list(let id) = window.route {
            let heads = lists[2]
            if !heads.isEmpty {
                inputs.collapsed = window.collapsed.intersection(heads)
                for h in heads {
                    // A heading shows its notes when it has some, or while they're being edited (§23).
                    let shown = window.paneNotes == .task(h) || !(p.taskModel(h)?.notes.isEmpty ?? true)
                    if shown, !inputs.collapsed.contains(h) { inputs.noteHeights[h] = window.noteHeights[h] ?? 19 }
                }
            }
            // A deleted list's empty notes take no room: they can't be written (§28).
            let emptyDeleted = deleted && (p.listModel(id)?.notes.isEmpty ?? true)
            inputs.titleNotes = emptyDeleted ? nil : window.noteHeights[TaskLayout.listNotesKey(id)] ?? 19
            if let r = window.rename, let n = r.newHeading, n.list == id {
                inputs.newHeading = r.id
                inputs.newHeadingBefore = n.before
            }
        }
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
        case .upcoming, .undated, .completed, .trash:
            return buildView(store: store, inputs: inputs)
        case .list(let listID):
            var L = TaskLayout(key: listID, top: 0)
            L.headY = inputs.deleted ? bannerBlock : 0
            L.titleHeight = titleBlockHeight(notes: inputs.titleNotes, line: inputs.titleLine)
            L.top = L.headY + L.titleHeight
            var open = inputs.lists[0]
            var done = inputs.lists[1]
            let heads = Set(inputs.lists[2])
            if !pins.isEmpty {
                (open, done) = applyPins(pins, open: open, done: done, store: store) { $0.list == listID }
            }
            if let h = inputs.newHeading {
                if let b = inputs.newHeadingBefore, let i = open.firstIndex(of: b) { open.insert(h, at: i) } else { open.append(h) }
            }
            if let draft, draft.list == listID {
                switch draft.anchor {
                case .after(let a)?: if let i = open.firstIndex(of: a) { open.insert(draft.id, at: i + 1) } else { open.append(draft.id) }
                case .before(let b)?: if let i = open.firstIndex(of: b) { open.insert(draft.id, at: i) } else { open.append(draft.id) }
                default: open.append(draft.id)
                }
                L.draftID = draft.id
            }
            L.reserve(open.count + (inputs.completedOpen ? done.count : 0))
            var y = L.top
            var ids: [EntityID] = []
            ids.reserveCapacity(open.count)
            // Rows in the list's order: a heading's slot is its air, its row and its notes; a collapsed heading's tasks
            // aren't laid out, down to the next heading (dc:3468–3488).
            var fold: EntityID?
            for id in open {
                if heads.contains(id) || id == inputs.newHeading {
                    fold = inputs.collapsed.contains(id) ? id : nil
                    let nh = inputs.noteHeights[id].map { $0 + 6 } ?? 0
                    L.headingIDs.insert(id)
                    L.noteH[id] = nh
                    L.slotH[id] = headAir + pitch + nh
                    L.place(id, y + headAir, group: 0)
                    ids.append(id)
                    y += headAir + pitch + nh
                    continue
                }
                if let f = fold, id != draft?.id {
                    L.folded[id] = f
                    continue
                }
                L.place(id, y, group: 0)
                ids.append(id)
                y += pitch
            }
            L.groups.append(Group(listID: listID, top: L.top, ids: ids))
            L.landingY = y
            y += pitch
            L.doneCount = done.count
            if !done.isEmpty {
                L.completedY = y + 8
                y = L.completedY! + pitch
                if inputs.completedOpen {
                    for id in done { L.place(id, y, group: -1); y += pitch }
                } else {
                    // Closed, they fold into the Completed row and unfold from it (v2 feedback 15).
                    for id in done { L.folded[id] = completedRowKey }
                }
            }
            if open.isEmpty && done.isEmpty { L.empty = .list }
            L.height = y + 24
            L.applyDrag(inputs.drag)
            return L

        case .today:
            // The title line, without notes (§23).
            var L = TaskLayout(key: "today", top: titleBlockHeight(notes: nil, line: inputs.titleLine))
            L.titleHeight = L.top
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
                if inputs.completedOpen {
                    for id in done { L.place(id, y, group: -1); y += pitch }
                } else {
                    // Collapsed: the rows fold into the label, as a heading's do (v2 feedback 15).
                    for id in done { L.folded[id] = doneGroup }
                }
            }
            L.doneCount = done.count
            L.height = y + 24
            L.applyDrag(inputs.drag)
            return L
        }
    }

    mutating func reserve(_ n: Int) {
        order.reserveCapacity(n)
        yList.reserveCapacity(n)
        groupIndex.reserveCapacity(n)
        index.reserveCapacity(n)
    }

    mutating func place(_ id: EntityID, _ y: CGFloat, group: Int) {
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

    static func listNotesKey(_ id: EntityID) -> String { "list:" + id }

    /// Where a gap at each target would start among `others` (the group's rows without the dragged ones): rows have
    /// different heights once there are headings (`slotTops`, dc:3457).
    func slotTops(_ g: Group, others: [EntityID]) -> [CGFloat] {
        var out = [g.top]
        var y = g.top
        for id in others { y += slotHeight(id); out.append(y) }
        return out
    }

    /// The dragged rows' gap: their slots, a heading's without its notes (they fold into the copy, dc:965).
    func gapHeight(_ dragged: [EntityID]) -> CGFloat {
        if let h = dragged.first, isHeading(h) { return Self.headAir + Self.pitch }
        return dragged.reduce(0) { $0 + slotHeight($1) }
    }

    /// The rows of the dragged group part to open a gap at the target; over the sidebar the group closes up and
    /// everything below it moves up, because the rows are leaving (dc:655–676).
    mutating func applyDrag(_ drag: WindowState.Drag?) {
        // Upcoming's drag is laid out by `buildView` (the rows at the day under the copy); in Completed and Trash nothing
        // parts (§22).
        guard let drag, drag.phase != .done, drag.mode == .group, case .tasks(let dragged, let groupID) = drag.kind,
              let gi = groups.firstIndex(where: { $0.listID == groupID }) else { return }
        let g = groups[gi]
        let draggedSet = Set(dragged)
        let others = g.ids.filter { !draggedSet.contains($0) }
        let gap = !drag.sidebar
        let target = drag.sidebar ? others.count : min(max(drag.target, 0), others.count)
        let gapH = gapHeight(dragged.filter { index[$0] != nil })
        var y = g.top
        for (i, id) in others.enumerated() {
            if gap && i == target { y += gapH }
            if let r = index[id] { yList[r] = y + rowOffset(id) }
            y += slotHeight(id)
        }
        if drag.sidebar {
            let shift = gapH
            let end = g.top + g.ids.reduce(0) { $0 + slotHeight($1) }
            for r in yList.indices where yList[r] >= end && groupIndex[r] != gi { yList[r] -= shift }
            for (lid, y) in labels where y >= end { labels[lid] = y - shift }
            if let gy = landingY { landingY = gy - shift }
            if let cy = completedY { completedY = cy - shift }
        }
        if gap {
            // The dragged rows wait in the gap (they're hidden: the copy stands for them). A heading's tasks sit at its
            // row, folded into the copy.
            let tops = slotTops(g, others: others)
            var dy = tops[target]
            for id in dragged {
                guard let r = index[id] else { continue }
                yList[r] = dy + rowOffset(id)
                if !isHeading(dragged[0]) { dy += slotHeight(id) }
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
