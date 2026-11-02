import Foundation

/// Visible state = confirmed state + a per-entity overlay of pending ops, plus the indexes and models views read
/// (spec §9). Every regular operation costs time proportional to what changed: one op touches one entity, which
/// is re-placed in its buckets and pushed into its cached model.
@MainActor
public final class Projection {
    /// The state reduced from the log `[0, cursor)`.
    public private(set) var confirmed: AppState
    /// Local ops not yet seen in the log, oldest first, each with its verbatim JSON.
    public private(set) var pending: [PendingOp]

    private var pendingTaskCount: [EntityID: Int] = [:]
    private var pendingListCount: [EntityID: Int] = [:]
    /// For each id with pending ops that took effect: confirmed + those ops. Visible = overlay ?? confirmed.
    private var taskOverlay: [EntityID: TaskItem] = [:]
    private var listOverlay: [EntityID: TaskList] = [:]

    public let dayModel: DayModel
    public var day: Day { dayModel.day }

    // MARK: Indexes (spec §9 table). Task buckets ignore whether their list is deleted; everything that shows what's
    // live (Today, the views, counts, Move to) iterates activeLists, so a deleted list's tasks count as deleted (§28).

    /// Open, non-deleted tasks of each list, by (order, id), headings included: the list's rows in order.
    private(set) var open: [EntityID: Bucket] = [:]
    /// The headings among them (design/INTERACTIONS-v2.md §23), by (order, id). Counts subtract these.
    private(set) var headings: [EntityID: Bucket] = [:]
    /// Completed, non-deleted tasks of each list, newest first.
    private(set) var completed: [EntityID: Bucket] = [:]
    /// Open tasks of each list that match the Today predicate, by (order, id).
    private(set) var today: [EntityID: Bucket] = [:]
    /// Tasks completed today that match the Today predicate, by completedAt.
    public let todayDone = Bucket()
    /// Lists with `archivedAt == nil`, by (order, id).
    public let activeLists = Bucket()
    /// Deleted lists, in Trash (`archivedAt` set, design/INTERACTIONS-v2.md §28), most recently deleted first.
    public let deletedLists = Bucket()

    struct TaskPlacement: Equatable {
        var list: EntityID
        var open: SortKey?
        var heading: SortKey?
        var inToday: Bool
        var completed: SortKey?
        var todayDone: SortKey?
    }

    struct ListPlacement: Equatable {
        var active: SortKey?
        var deleted: SortKey?
    }

    private(set) var taskPlacement: [EntityID: TaskPlacement] = [:]
    private(set) var listPlacement: [EntityID: ListPlacement] = [:]
    private var edits: [ObjectIdentifier: (bucket: Bucket, removes: [SortKey], inserts: [SortKey])] = [:]
    private var dirtyTasks: Set<EntityID> = []
    private var dirtyLists: Set<EntityID> = []

    // MARK: Model registry

    private(set) var taskModels: [EntityID: TaskModel] = [:]
    private(set) var listModels: [EntityID: ListModel] = [:]

    public init(confirmed: AppState = AppState(), pending: [PendingOp] = [], day: Day) {
        self.confirmed = confirmed
        self.pending = pending
        self.dayModel = DayModel(day)
        rebuildAll()
    }

    public convenience init(confirmed: AppState = AppState(), pendingOps: [Op], day: Day) {
        self.init(confirmed: confirmed, pending: pendingOps.map(PendingOp.init), day: day)
    }

    // MARK: - Reading

    public func task(_ id: EntityID) -> TaskItem? { taskOverlay[id] ?? confirmed.tasks[id] }
    public func list(_ id: EntityID) -> TaskList? { listOverlay[id] ?? confirmed.lists[id] }

    /// The cached model for a task, created from the visible entity the first time a row asks for it.
    public func taskModel(_ id: EntityID) -> TaskModel? {
        if let m = taskModels[id] { return m }
        guard let t = task(id) else { return nil }
        let m = TaskModel(t)
        taskModels[id] = m
        return m
    }

    public func listModel(_ id: EntityID) -> ListModel? {
        if let m = listModels[id] { return m }
        guard let l = list(id) else { return nil }
        let m = ListModel(l)
        listModels[id] = m
        return m
    }

    /// The list's rows in order: its open tasks and its headings.
    public func openTasks(in list: EntityID) -> Bucket { bucket(in: &open, list) }
    public func headings(in list: EntityID) -> Bucket { bucket(in: &headings, list) }
    /// Open tasks, headings not counted (§23: counts don't include them).
    public func openTaskCount(in list: EntityID) -> Int { openTasks(in: list).count - headings(in: list).count }
    public func completedTasks(in list: EntityID) -> Bucket { bucket(in: &completed, list) }
    public func todayTasks(in list: EntityID) -> Bucket { bucket(in: &today, list) }

    /// A live list: it exists and isn't in Trash.
    public func isActive(list id: EntityID) -> Bool {
        guard let l = list(id) else { return false }
        return l.archivedAt == nil
    }

    /// A list in Trash (§28): `archivedAt` is the moment it was deleted.
    public func isDeleted(list id: EntityID) -> Bool { list(id)?.archivedAt != nil }

    /// A task is live only if it isn't deleted and its list is live (SPEC §5 rule 5, §28). A task in a deleted list
    /// counts as deleted everywhere that decides what's live; restoring the list brings it back as it was.
    public func isLive(task id: EntityID) -> Bool {
        guard let t = task(id) else { return false }
        return !t.deleted && isActive(list: t.list)
    }

    /// One thing in Trash (§22, §28): a deleted list, or a task deleted on its own (wherever its list is), with when
    /// it was deleted.
    public struct TrashEntry: Hashable, Sendable {
        public enum Item: Hashable, Sendable { case list(EntityID), task(EntityID) }
        public var item: Item
        public var deletedAt: Int

        public var id: EntityID {
            switch item {
            case .list(let id), .task(let id): id
            }
        }
    }

    /// The `at` of the op that last touched a task, which for a deleted task is its deletion: nothing edits a trashed
    /// task, so the last op is the one that set `deleted` (§22's `deletedAt`).
    nonisolated public static func deletedAt(_ t: TaskItem) -> Int { t.updatedAt }

    /// What Trash holds, newest deleted first (§28): each deleted list once, at its `archivedAt`, and each task
    /// deleted on its own at its deletion. A deleted list's other tasks aren't listed: they're under it. A task deleted
    /// before its list stays a row of its own, and stays deleted when the list is restored. Headings aren't listed:
    /// they're only a name, and ⌘Z brings them back (§23). One pass over the tasks: no bucket holds deleted ones.
    public func trash() -> [TrashEntry] {
        var out: [TrashEntry] = []
        for id in deletedLists.ids {
            if let at = list(id)?.archivedAt { out.append(TrashEntry(item: .list(id), deletedAt: at)) }
        }
        for id in allTaskIDs {
            guard let t = task(id), t.deleted, !t.isHeading, list(t.list) != nil else { continue }
            out.append(TrashEntry(item: .task(id), deletedAt: Self.deletedAt(t)))
        }
        out.sort { $0.deletedAt != $1.deletedAt ? $0.deletedAt > $1.deletedAt : $0.id < $1.id }
        return out
    }

    /// The tasks a deleted list took with it, as Trash shows them under its row (§28): its open tasks in its order,
    /// then its completed ones, newest first. Headings stay out (they're in the opened list), and so do tasks deleted
    /// on their own: they're rows of their own.
    public func tasksInDeletedList(_ list: EntityID) -> [EntityID] {
        let open = openTasks(in: list).ids.filter { task($0)?.isHeading == false }
        return open + completedTasks(in: list).ids
    }

    /// The open tasks of a list with their keys, for computing new keys (spec §3).
    public func orderedOpenTasks(in list: EntityID) -> [OrderedItem] {
        (open[list]?.keys ?? []).map { OrderedItem(id: $0.id, order: $0.order) }
    }

    /// Every task of a list that isn't deleted, open and completed, with its key, sorted by (order, id): a completed
    /// task keeps its key, so it keeps its place under its heading (§23).
    public func orderedTasksIncludingCompleted(in list: EntityID) -> [OrderedItem] {
        var keys = open[list]?.keys ?? []
        for k in completed[list]?.keys ?? [] {
            if let t = task(k.id) { keys.append(.manual(t.order, t.id)) }
        }
        keys.sort()
        return keys.map { OrderedItem(id: $0.id, order: $0.order) }
    }

    /// A heading and the tasks under it, down to the next heading (§23 "section"), completed ones included, in order.
    public func section(of heading: EntityID) -> [EntityID] {
        guard let h = task(heading), h.isHeading, !h.deleted else { return [] }
        let all = orderedTasksIncludingCompleted(in: h.list)
        guard let i = all.firstIndex(where: { $0.id == heading }) else { return [heading] }
        var out = [heading]
        for item in all[(i + 1)...] {
            if task(item.id)?.isHeading == true { break }
            out.append(item.id)
        }
        return out
    }

    /// The heading a task sits under in its list, nil before the first one.
    public func heading(of id: EntityID) -> EntityID? {
        guard let t = task(id), !t.isHeading else { return nil }
        let key = SortKey.manual(t.order, t.id)
        return headings[t.list]?.keys.last { $0 < key }?.id
    }

    public func orderedActiveLists() -> [OrderedItem] {
        activeLists.keys.map { OrderedItem(id: $0.id, order: $0.order) }
    }

    public var allTaskIDs: Set<EntityID> { Set(confirmed.tasks.keys).union(taskOverlay.keys) }
    public var allListIDs: Set<EntityID> { Set(confirmed.lists.keys).union(listOverlay.keys) }

    private func bucket(in map: inout [EntityID: Bucket], _ id: EntityID) -> Bucket {
        if let b = map[id] { return b }
        let b = Bucket()
        map[id] = b
        return b
    }

    // MARK: - Local ops

    /// Applies local ops to the overlay (optimistic UI). The changed set is the ops' targets.
    public func perform(_ ops: [Op]) {
        perform(ops.map(PendingOp.init))
    }

    public func perform(_ ops: [PendingOp]) {
        for p in ops {
            pending.append(p)
            applyToOverlay(p.op, counting: true)
        }
        commit()
    }

    private func applyToOverlay(_ op: Op, counting: Bool) {
        if op.type.isTask {
            if counting { pendingTaskCount[op.target, default: 0] += 1 }
            var t = task(op.target)
            if Reducer.apply(op, to: &t) { taskOverlay[op.target] = t }
            dirtyTasks.insert(op.target)
        } else if op.type.isList {
            if counting { pendingListCount[op.target, default: 0] += 1 }
            var l = list(op.target)
            if Reducer.apply(op, to: &l) { listOverlay[op.target] = l }
            dirtyLists.insert(op.target)
        }
    }

    // MARK: - Sync (rebase)

    public enum Path: Equatable, Sendable { case none, fast, general }

    /// Applies a page of log entries: to confirmed, then drops our confirmed ops from pending, then updates visible
    /// state for touched ids only (spec §9 "After a sync").
    ///
    /// While recovering from a 409 (`touchingAll`), every id in the page counts as touched, ours included, because
    /// our own ops can come back in a different order than the overlay applied them (spec §5).
    @discardableResult
    public func confirm(_ entries: [LogEntry], touchingAll: Bool = false) -> Path {
        confirm(entries.map(\.op), touchingAll: touchingAll)
    }

    @discardableResult
    public func confirm(_ ops: [Op], touchingAll: Bool = false) -> Path {
        guard !ops.isEmpty else { return .none }

        // Fast path: the new entries are exactly the head of the pending queue. Visible state already reflects
        // them, so nothing redraws; ids left with no pending ops just lose their overlay entry.
        if !touchingAll, ops.count <= pending.count, zip(ops, pending).allSatisfy({ $0 == $1.op }) {
            for op in ops { confirmed.apply(op) }
            pending.removeFirst(ops.count)
            for op in ops { dropPending(op) }
            return .fast
        }

        // General path: remote ops are interleaved with ours.
        var pendingByID: [String: Op] = [:]
        pendingByID.reserveCapacity(pending.count)
        for p in pending where pendingByID[p.op.id] == nil { pendingByID[p.op.id] = p.op }
        var ours: [Op] = []
        var oursIDs: Set<String> = []
        var touchedTasks: Set<EntityID> = []
        var touchedLists: Set<EntityID> = []
        func touch(_ op: Op) {
            if op.type.isTask { touchedTasks.insert(op.target) } else if op.type.isList { touchedLists.insert(op.target) }
        }
        for op in ops {
            confirmed.apply(op)
            if touchingAll { touch(op) }
            if let mine = pendingByID[op.id], !oursIDs.contains(op.id) {
                ours.append(mine)
                oursIDs.insert(op.id)
                // Same id, different content (two Macs seeding the Inbox): the log's version wins, so rebuild.
                if mine != op { touch(op); touch(mine) }
            } else {
                touch(op)
            }
        }
        // Our confirmed ops are normally the head of pending, in order. If not, their overlays can't be trusted.
        if !ours.elementsEqual(pending.prefix(ours.count), by: { $0.id == $1.op.id }) {
            for op in ours { touch(op) }
        }
        if !oursIDs.isEmpty {
            pending.removeAll { oursIDs.contains($0.op.id) }
            for op in ours { dropPending(op) }
        }
        rebuild(tasks: touchedTasks, lists: touchedLists)
        commit()
        return .general
    }

    /// `invalid_op`: drops the op from pending and rebuilds its entity from confirmed + remaining pending.
    @discardableResult
    public func reject(opID: String) -> PendingOp? {
        guard let i = pending.firstIndex(where: { $0.op.id == opID }) else { return nil }
        let p = pending.remove(at: i)
        dropPending(p.op)
        rebuild(tasks: p.op.type.isTask ? [p.op.target] : [], lists: p.op.type.isList ? [p.op.target] : [])
        commit()
        return p
    }

    /// `409` recovery (spec §5): confirmed state restarts empty and every known op becomes pending. The overlay is
    /// then a replay of the old log + pending, which is what was already on screen.
    public func recover(pending queue: [PendingOp]) {
        confirmed = AppState()
        pending = queue
        rebuildAll()
    }

    private func dropPending(_ op: Op) {
        if op.type.isTask {
            let n = (pendingTaskCount[op.target] ?? 1) - 1
            if n <= 0 {
                pendingTaskCount[op.target] = nil
                taskOverlay[op.target] = nil
            } else {
                pendingTaskCount[op.target] = n
            }
        } else if op.type.isList {
            let n = (pendingListCount[op.target] ?? 1) - 1
            if n <= 0 {
                pendingListCount[op.target] = nil
                listOverlay[op.target] = nil
            } else {
                pendingListCount[op.target] = n
            }
        }
    }

    /// visible[id] = confirmed[id], then that id's remaining pending ops re-applied in order.
    private func rebuild(tasks: Set<EntityID>, lists: Set<EntityID>) {
        guard !tasks.isEmpty || !lists.isEmpty else { return }
        for id in tasks { taskOverlay[id] = nil }
        for id in lists { listOverlay[id] = nil }
        for p in pending {
            if p.op.type.isTask, tasks.contains(p.op.target) {
                applyToOverlay(p.op, counting: false)
            } else if p.op.type.isList, lists.contains(p.op.target) {
                applyToOverlay(p.op, counting: false)
            }
        }
        dirtyTasks.formUnion(tasks)
        dirtyLists.formUnion(lists)
    }

    // MARK: - Midnight

    /// Rebuilds Today when the day (or the time zone) changes: one pass over open tasks and today's completions.
    public func setDay(_ newDay: Day) {
        guard newDay != day else { return }
        dayModel.day = newDay
        for (listID, bucket) in open {
            var keys: [SortKey] = []
            for key in bucket.keys {
                guard let t = task(key.id) else { continue }
                // A heading's dates never arrive (`datesArrived`).
                let inToday = Today.datesArrived(t, today: newDay.date)
                if inToday { keys.append(key) }
                taskPlacement[key.id]?.inToday = inToday
            }
            todayTasks(in: listID).replace(with: keys)
        }
        for id in todayDone.ids { taskPlacement[id]?.todayDone = nil }
        var done: [SortKey] = []
        for (listID, bucket) in completed where isActive(list: listID) {
            for key in bucket.keys {
                let c = -key.time
                if c < newDay.start { break }
                guard c < newDay.end, let t = task(key.id), Today.datesArrived(t, today: newDay.date) else { continue }
                let k = SortKey.ascending(c, key.id)
                done.append(k)
                taskPlacement[key.id]?.todayDone = k
            }
        }
        done.sort()
        todayDone.replace(with: done)
    }

    // MARK: - Placement

    private func placement(for t: TaskItem) -> TaskPlacement? {
        guard !t.deleted else { return nil }
        // A heading is always a row in its list's order, whatever another client wrote on it (§23).
        if t.isHeading {
            let key = SortKey.manual(t.order, t.id)
            return TaskPlacement(list: t.list, open: key, heading: key, inToday: false, completed: nil, todayDone: nil)
        }
        if let c = t.completedAt {
            let isTodayDone = day.contains(ms: c) && Today.datesArrived(t, today: day.date) && isActive(list: t.list)
            return TaskPlacement(list: t.list, open: nil, heading: nil, inToday: false, completed: .descending(c, t.id),
                                 todayDone: isTodayDone ? .ascending(c, t.id) : nil)
        }
        return TaskPlacement(list: t.list, open: .manual(t.order, t.id), heading: nil, inToday: Today.datesArrived(t, today: day.date),
                             completed: nil, todayDone: nil)
    }

    private func placement(for l: TaskList) -> ListPlacement {
        if let a = l.archivedAt { return ListPlacement(active: nil, deleted: .descending(a, l.id)) }
        return ListPlacement(active: .manual(l.order, l.id), deleted: nil)
    }

    /// Re-places every dirty entity and pushes changed fields into cached models, then flushes bucket edits.
    private func commit() {
        for id in dirtyLists { refreshList(id) }
        dirtyLists.removeAll(keepingCapacity: true)
        for id in dirtyTasks { refreshTask(id) }
        dirtyTasks.removeAll(keepingCapacity: true)
        for (_, e) in edits { e.bucket.apply(removing: e.removes, inserting: e.inserts) }
        edits.removeAll(keepingCapacity: true)
    }

    private func refreshTask(_ id: EntityID) {
        let visible = task(id)
        let new = visible.flatMap(placement(for:))
        let old = taskPlacement[id]
        if new != old {
            move(old?.open.map { ($0, old!.list) }, new?.open.map { ($0, new!.list) }, in: \.open)
            move(old?.heading.map { ($0, old!.list) }, new?.heading.map { ($0, new!.list) }, in: \.headings)
            move(old?.inToday == true ? old?.open.map { ($0, old!.list) } : nil,
                 new?.inToday == true ? new?.open.map { ($0, new!.list) } : nil, in: \.today)
            move(old?.completed.map { ($0, old!.list) }, new?.completed.map { ($0, new!.list) }, in: \.completed)
            if old?.todayDone != new?.todayDone {
                edit(todayDone, remove: old?.todayDone, insert: new?.todayDone)
            }
            taskPlacement[id] = new
        }
        if let visible, let m = taskModels[id] { m.update(from: visible) }
    }

    private func move(_ old: (SortKey, EntityID)?, _ new: (SortKey, EntityID)?,
                      in index: ReferenceWritableKeyPath<Projection, [EntityID: Bucket]>) {
        if old?.0 == new?.0, old?.1 == new?.1 { return }
        if let (key, list) = old { edit(bucket(in: &self[keyPath: index], list), remove: key, insert: nil) }
        if let (key, list) = new { edit(bucket(in: &self[keyPath: index], list), remove: nil, insert: key) }
    }

    private func refreshList(_ id: EntityID) {
        let visible = list(id)
        let new = visible.map(placement(for:))
        let old = listPlacement[id]
        if new != old {
            if old?.active != new?.active { edit(activeLists, remove: old?.active, insert: new?.active) }
            if old?.deleted != new?.deleted { edit(deletedLists, remove: old?.deleted, insert: new?.deleted) }
            listPlacement[id] = new
            // Deleting, restoring or (re)creating a list changes which of its tasks count as done today.
            if (old?.active != nil) != (new?.active != nil), let bucket = completed[id] {
                for key in bucket.keys {
                    if -key.time < day.start { break }
                    dirtyTasks.insert(key.id)
                }
            }
        }
        if let visible, let m = listModels[id] { m.update(from: visible) }
    }

    private func edit(_ bucket: Bucket, remove: SortKey?, insert: SortKey?) {
        let k = ObjectIdentifier(bucket)
        if edits[k] == nil { edits[k] = (bucket, [], []) }
        if let remove { edits[k]!.removes.append(remove) }
        if let insert { edits[k]!.inserts.append(insert) }
    }

    // MARK: - From scratch (launch, 409)

    private func rebuildAll() {
        taskOverlay = [:]
        listOverlay = [:]
        pendingTaskCount = [:]
        pendingListCount = [:]
        dirtyTasks = []
        dirtyLists = []
        for p in pending { applyToOverlay(p.op, counting: true) }
        dirtyTasks = []
        dirtyLists = []

        listPlacement = [:]
        var active: [SortKey] = []
        var deleted: [SortKey] = []
        for id in allListIDs {
            guard let l = list(id) else { continue }
            let p = placement(for: l)
            listPlacement[id] = p
            if let k = p.active { active.append(k) }
            if let k = p.deleted { deleted.append(k) }
            listModels[id]?.update(from: l)
        }
        activeLists.replace(with: active.sorted())
        deletedLists.replace(with: deleted.sorted())

        taskPlacement = [:]
        var openKeys: [EntityID: [SortKey]] = [:]
        var headingKeys: [EntityID: [SortKey]] = [:]
        var todayKeys: [EntityID: [SortKey]] = [:]
        var completedKeys: [EntityID: [SortKey]] = [:]
        var done: [SortKey] = []
        for id in allTaskIDs {
            guard let t = task(id) else { continue }
            taskModels[id]?.update(from: t)
            guard let p = placement(for: t) else { continue }
            taskPlacement[id] = p
            if let k = p.open {
                openKeys[p.list, default: []].append(k)
                if p.inToday { todayKeys[p.list, default: []].append(k) }
            }
            if let k = p.heading { headingKeys[p.list, default: []].append(k) }
            if let k = p.completed { completedKeys[p.list, default: []].append(k) }
            if let k = p.todayDone { done.append(k) }
        }
        for (list, keys) in openKeys { openTasks(in: list).replace(with: keys.sorted()) }
        for (list, keys) in headingKeys { headings(in: list).replace(with: keys.sorted()) }
        for (list, keys) in todayKeys { todayTasks(in: list).replace(with: keys.sorted()) }
        for (list, keys) in completedKeys { completedTasks(in: list).replace(with: keys.sorted()) }
        for (list, b) in open where openKeys[list] == nil { b.replace(with: []) }
        for (list, b) in headings where headingKeys[list] == nil { b.replace(with: []) }
        for (list, b) in today where todayKeys[list] == nil { b.replace(with: []) }
        for (list, b) in completed where completedKeys[list] == nil { b.replace(with: []) }
        todayDone.replace(with: done.sorted())
    }
}
