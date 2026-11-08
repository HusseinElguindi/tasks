import CoreGraphics
import Foundation
import TasksCore

/// What a view's layout depends on beyond the window state (§22): its rows in the view's order before grouping, each
/// with the day that places it. Read on every `TaskLayout.make` but cached, so a render that changes nothing here
/// (a selection, a hover) costs nothing: what it depends on is the cache key, read and so observed each time.
struct ViewItems: Equatable {
    var ids: [EntityID] = []
    /// Upcoming: the day each task reaches Today. Completed and Trash: the local day it was completed or deleted. In
    /// Trash an id is a task deleted on its own or a deleted list (§28).
    var days: [CalendarDate] = []
    /// Upcoming and Undated: each task's list, by its place in the sidebar, and its key in that list.
    var ranks: [Int] = []
    var orders: [String] = []
    /// Completed and Trash: when each was completed or deleted (ms), newest first.
    var stamps: [Int] = []

    /// What the rows were read from. Upcoming and Undated depend on each open task's dates, which no bucket changes
    /// with: `ViewDates` watches them and bumps `revision`. Completed and Trash depend on the buckets a completion,
    /// a delete or a put back changes (arrays compare by identity first, so an unchanged one costs nothing).
    struct CacheKey: Equatable {
        var route: WindowState.Route
        var active: [EntityID]
        var buckets: [[EntityID]]
        var pins: [EntityID: WindowState.Pin]
        var day: CalendarDate
        var revision: Int
    }

    /// The `at` of the op that last touched a task, which for a task in the Trash is its deletion: nothing edits a
    /// trashed task, so the last op is the one that set `deleted` (the prototype's `deletedAt`, dc:952).
    static func deletedAt(_ t: TaskItem) -> Int { Projection.deletedAt(t) }

    @MainActor
    static func read(store: Store, window: WindowState) -> ViewItems? {
        let p = store.projection
        let route = window.route
        guard route.isView else { return nil }
        let active = p.activeLists.ids
        var key = CacheKey(route: route, active: active, buckets: [], pins: window.pins, day: p.day.date, revision: 0)
        switch route {
        case .upcoming, .undated:
            // A fresh pass may have seen changes made while it was disarmed (in Today, say): read again.
            if window.viewDates.arm(store: store, window: window) { window.viewItemsCache = nil }
            key.revision = window.viewDatesRevision
        case .completed:
            key.buckets = active.map { p.completedTasks(in: $0).ids }
        default:
            // Trash changes with a delete or a put back in any list, live or deleted, and with a list deleted or
            // restored (§28).
            let deleted = p.deletedLists.ids
            key.buckets = (active + deleted).flatMap { [p.openTasks(in: $0).ids, p.completedTasks(in: $0).ids] } + [deleted]
        }
        if let c = window.viewItemsCache, c.key == key { return c.items }
        let v = build(store: store, key: key, dates: window.viewDates.entries)
        window.viewItemsCache = (key, v)
        return v
    }

    @MainActor
    private static func build(store: Store, key: CacheKey, dates: [ViewDates.Entry]) -> ViewItems {
        let p = store.projection
        let today = key.day
        let pins = key.pins
        let active = key.active
        var v = ViewItems()
        switch key.route {
        case .upcoming, .undated:
            let upcoming = key.route == .upcoming
            var items: [(id: EntityID, day: CalendarDate, rank: Int, order: String)] = []
            func consider(_ e: ViewDates.Entry) {
                if upcoming {
                    guard let day = ViewGroups.upDay(when: e.when, deadline: e.deadline), day > today else { return }
                    items.append((e.id, day, e.rank, e.order))
                } else if e.when == nil && e.deadline == nil {
                    items.append((e.id, today, e.rank, e.order))
                }
            }
            // The open tasks as `ViewDates` read them when it was last armed (that pass is what this depends on).
            for e in dates {
                if case .done = pins[e.id] { continue }
                consider(e)
            }
            // Checked here a moment ago: still in place until the rows settle (§8).
            for (id, pin) in pins where pin == .open {
                guard let t = p.task(id), !t.deleted, t.completedAt != nil, let rank = active.firstIndex(of: t.list) else { continue }
                consider(.init(id: id, rank: rank, order: t.order, when: t.when, deadline: t.deadline))
            }
            // By day, then by list in sidebar order, then by the key in the list (TasksCore's `ViewGroups`).
            items.sort { ViewGroups.upcomingPrecedes(.init(id: $0.id, day: $0.day, rank: $0.rank, order: $0.order),
                                                     .init(id: $1.id, day: $1.day, rank: $1.rank, order: $1.order)) }
            v.ids = items.map(\.id)
            v.days = items.map(\.day)
            v.ranks = items.map(\.rank)
            v.orders = items.map(\.order)
        case .completed:
            var items: [(id: EntityID, stamp: Int)] = []
            for l in active {
                for id in p.completedTasks(in: l).ids where pins[id] != .open {
                    if let at = p.task(id)?.completedAt { items.append((id, at)) }
                }
            }
            // Unchecked here a moment ago: still in place, at its old time, until the rows settle (§8).
            for (id, pin) in pins {
                guard case .done(let at) = pin, let t = p.task(id), !t.deleted, t.completedAt == nil, active.contains(t.list) else { continue }
                items.append((id, at))
            }
            items.sort { $0.stamp != $1.stamp ? $0.stamp > $1.stamp : $0.id < $1.id }
            v.ids = items.map(\.id)
            v.stamps = items.map(\.stamp)
            v.days = items.map { CalendarDate(Date(timeIntervalSince1970: TimeInterval($0.stamp) / 1000)) }
        default:
            // Deleted lists and the tasks deleted on their own, wherever their list is, newest first (§28). No bucket
            // holds deleted tasks: this scan runs only when a list's open or completed tasks change.
            let items = p.trash()
            v.ids = items.map(\.id)
            v.stamps = items.map(\.deletedAt)
            v.days = items.map { CalendarDate(Date(timeIntervalSince1970: TimeInterval($0.deletedAt) / 1000)) }
        }
        return v
    }
}

/// Watches every open task's dates in the active lists, and the lists' open tasks, for Upcoming and Undated: one pass
/// to arm it, then nothing until something it read changes, when it bumps `viewDatesRevision` (once) and waits to be
/// armed again by the next read. A render in those views reads the revision, not every task (SPEC §9).
@MainActor
final class ViewDates {
    /// An open task as last read: its list's place in the sidebar, its key in the list, and its dates.
    struct Entry {
        var id: EntityID
        var rank: Int
        var order: String
        var when: CalendarDate?
        var deadline: CalendarDate?
    }

    private var armed = false
    /// Every open task in the active lists, in sidebar then list order, from the pass that armed it.
    private(set) var entries: [Entry] = []

    /// Arms it unless it's armed; returns whether it read the tasks just now.
    @discardableResult
    func arm(store: Store, window: WindowState) -> Bool {
        guard !armed else { return false }
        armed = true
        let p = store.projection
        var out: [Entry] = []
        withObservationTracking {
            for (rank, l) in p.activeLists.ids.enumerated() {
                for id in p.openTasks(in: l).ids {
                    // Headings stay in their list (§23): Upcoming and Undated never show one.
                    if let m = p.taskModel(id), !m.isHeading { out.append(Entry(id: id, rank: rank, order: m.order, when: m.when, deadline: m.deadline)) }
                }
            }
        } onChange: { [weak self, weak window] in
            // Called as the change is about to be made: bump after it has been.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.armed = false
                    window?.viewDatesRevision &+= 1
                }
            }
        }
        entries = out
        return true
    }

    /// The next read reads the tasks again, now: for a render in the same turn as a change it must show (a drop's
    /// landing), which the revision, bumped a turn later, would leave on the old dates.
    func invalidate() { armed = false }
}

extension TaskLayout {
    /// Upcoming, Undated, Completed and Trash on Today's grid: a 32pt label slot, then 32pt rows (dc:2247–2316).
    static func buildView(store: Store, inputs: Inputs) -> TaskLayout {
        let p = store.projection
        let today = inputs.day
        let route = inputs.route
        let key: String = switch route {
        case .upcoming: "upcoming"
        case .undated: "undated"
        case .completed: "completed"
        default: "trash"
        }
        // The title line, without notes (§23).
        var L = TaskLayout(key: key, top: TaskLayout.titleBlockHeight(notes: nil, line: inputs.titleLine))
        L.titleHeight = L.top
        let v = inputs.view ?? ViewItems()
        L.reserve(v.ids.count + 1)
        var y = L.top
        func group(_ id: EntityID, _ info: LabelInfo, _ ids: [EntityID], kind: GroupKind, day: CalendarDate? = nil) {
            L.labels[id] = y
            L.labelOrder.append(id)
            L.labelInfo[id] = info
            y += L.labelHeight(id)
            L.groups.append(Group(listID: id, top: y, ids: ids, kind: kind, day: day))
            for rid in ids { L.place(rid, y, group: L.groups.count - 1); y += pitch }
        }
        let draft = inputs.draft
        let active = p.activeLists.ids

        switch route {
        case .undated:
            // By list in sidebar order, each in its list's order: exactly Today's grouping (dc:2262–2268).
            var byRank: [Int: [EntityID]] = [:]
            for (i, id) in v.ids.enumerated() { byRank[v.ranks[i], default: []].append(id) }
            for (rank, l) in active.enumerated() {
                var ids = byRank[rank] ?? []
                if let draft, draft.list == l, draft.when == nil {
                    ids.append(draft.id)
                    L.draftID = draft.id
                }
                guard !ids.isEmpty else { continue }
                group(l, LabelInfo(name: "", plus: true, list: l), ids, kind: .list)
            }
            if L.order.isEmpty { L.empty = .undated }

        case .upcoming:
            // Each open task on the day it reaches Today; a drag lays its rows out on the day under the copy (dc:2269–2296).
            var ids = v.ids, days = v.days, ranks = v.ranks
            var homeDays: Set<CalendarDate> = []
            if let d = inputs.drag, d.mode == .days, d.phase != .done, case .tasks(let dragged, _) = d.kind {
                let set = Set(dragged)
                for i in ids.indices where set.contains(ids[i]) { homeDays.insert(days[i]) }
            }
            if let d = inputs.drag, d.mode == .days, d.phase != .done, let to = d.toDay, case .tasks(let dragged, _) = d.kind {
                let set = Set(dragged)
                var items = ids.indices.map { (id: ids[$0], day: set.contains(ids[$0]) ? to : days[$0], rank: ranks[$0], order: v.orders[$0]) }
                // Moved rows sort into their new day by list, then by their key in it: where the drop will put them.
                items.sort { ViewGroups.upcomingPrecedes(.init(id: $0.id, day: $0.day, rank: $0.rank, order: $0.order),
                                                         .init(id: $1.id, day: $1.day, rank: $1.rank, order: $1.order)) }
                ids = items.map(\.id); days = items.map(\.day); ranks = items.map(\.rank)
            }
            if let draft, let when = draft.when, when > today, let rank = active.firstIndex(of: draft.list) {
                // The new task sits at the end of its list's rows on its day.
                let at = ids.indices.first { days[$0] > when || (days[$0] == when && ranks[$0] > rank) } ?? ids.count
                ids.insert(draft.id, at: at); days.insert(when, at: at); ranks.insert(rank, at: at)
                L.draftID = draft.id
            }
            // The groups are TasksCore's (`ViewGroups.upcoming`); a day's label has its + for that day. A month lists
            // its days, each under its own smaller label that works as a day's (`ViewGroups.upcomingDayInMonth`, the
            // user, 2026-11-08): a month's label is then a group with no rows, so it's still no drop target.
            struct Bucket { var id: EntityID; var kind: GroupKind; var day: CalendarDate?; var info: LabelInfo; var ids: [EntityID] = [] }
            func dayBucket(_ g: ViewGroups.Group, inMonth: Bool) -> Bucket {
                var info = LabelInfo(name: g.name, sub: g.sub, plus: true, day: g.day)
                info.inMonth = inMonth
                return Bucket(id: g.id, kind: .day, day: g.day, info: info)
            }
            // The next seven days always, then a month per month that has tasks, with a group per day in it that has
            // tasks. While rows are dragged, the days they left keep their labels (empty, as an empty day's), so the
            // labels under the pointer don't jump up as it leaves (§22 "Rescheduling by drag").
            var buckets: [Bucket] = ViewGroups.upcomingDays(today: today).map { dayBucket(ViewGroups.upcoming($0, today: today), inMonth: false) }
            var index: [EntityID: Int] = [:]
            for (i, b) in buckets.enumerated() { index[b.id] = i }
            func bucketIndex(_ day: CalendarDate) -> Int {
                let g = ViewGroups.upcoming(day, today: today)
                if g.kind == .day, let i = index[g.id] { return i }
                // A day in a month: its month's label first, then its own.
                if index[g.id] == nil {
                    index[g.id] = buckets.count
                    var info = LabelInfo(name: g.name)
                    info.month = true
                    buckets.append(Bucket(id: g.id, kind: .month, day: nil, info: info))
                }
                let d = ViewGroups.upcomingDayInMonth(day)
                if let i = index[d.id] { return i }
                index[d.id] = buckets.count
                buckets.append(dayBucket(d, inMonth: true))
                return buckets.count - 1
            }
            // Months and their days come in date order: rows are by day, and a kept day is merged in by its date.
            var kept = homeDays.filter { $0 > today.adding(days: 7) }.sorted()
            for (i, id) in ids.enumerated() {
                while let k = kept.first, k < days[i] { _ = bucketIndex(k); kept.removeFirst() }
                buckets[bucketIndex(days[i])].ids.append(id)
            }
            for k in kept { _ = bucketIndex(k) }
            // The columns: every list with a row here, and the widest Deadline as a date ("Due" is never wider).
            var seen = Set<Int>()
            for r in ranks where seen.insert(r).inserted { if r < active.count { L.markLists.append(active[r]) } }
            for id in ids {
                guard let dl = p.task(id)?.deadline else { continue }
                let text = DateLabel.upcomingDeadline(dl, today: today, groupDay: nil).text
                L.deadlineColumn = max(L.deadlineColumn, ChipLayer.width(.init(text: text, glyph: .flag)))
            }
            for var b in buckets {
                // An empty day's label is quiet; a month's has its rows under its days.
                b.info.quiet = b.kind == .day && b.ids.isEmpty
                group(b.id, b.info, b.ids, kind: b.kind, day: b.day)
            }
            if v.ids.isEmpty && L.draftID == nil {
                L.empty = .upcoming
                L.emptyTop = y + 24
            }

        default:
            // Completed and Trash: newest first, a group per day for the last week, then per month (dc:2297–2313); the
            // groups are TasksCore's (`ViewGroups.past`), which puts a stamp ahead of today in today's group.
            var buckets: [(id: EntityID, kind: GroupKind, info: LabelInfo, ids: [EntityID])] = []
            var index: [EntityID: Int] = [:]
            for (i, id) in v.ids.enumerated() {
                let g = ViewGroups.past(v.days[i], today: today)
                if index[g.id] == nil {
                    index[g.id] = buckets.count
                    buckets.append((g.id, g.kind == .day ? .day : .month, LabelInfo(name: g.name, sub: g.sub), []))
                }
                buckets[index[g.id]!].ids.append(id)
            }
            if route == .trash {
                // A deleted list is one row; expanded, its tasks follow it in the group, open then completed, and
                // collapsed they're folded under it, so they unfold from it and fold back into it (§28, §23).
                let expanded = Set(inputs.expanded)
                for i in buckets.indices {
                    var ids: [EntityID] = []
                    for id in buckets[i].ids {
                        ids.append(id)
                        guard p.list(id) != nil else { continue }
                        L.listRows.insert(id)
                        let kids = p.tasksInDeletedList(id)
                        if expanded.contains(id) {
                            ids += kids
                            for k in kids { L.childOf[k] = id }
                        } else {
                            for k in kids { L.folded[k] = id }
                        }
                    }
                    buckets[i].ids = ids
                }
            }
            for b in buckets { group(b.id, b.info, b.ids, kind: b.kind) }
            if v.ids.isEmpty { L.empty = route == .completed ? .completed : .trash }
        }
        L.height = y + 24
        L.applyDrag(inputs.drag)
        return L
    }

    /// A day's label inside one of Upcoming's months: 24pt, under the month's 32pt one (ROW-DENSITY.md direction C).
    static let dayInMonthLabel: CGFloat = 24

    /// An Upcoming month's label: a list heading's look, 13/16 semibold `ink` on a 1pt `line-separator` rule, in a 44pt
    /// slot, so the months stand apart from the days (the user, 2026-11-08: "the months need to be more clear").
    static let monthLabel: CGFloat = 44

    /// A group label's slot: 32, 24 for a day inside a month, 44 for an Upcoming month.
    func labelHeight(_ key: EntityID) -> CGFloat {
        guard let info = labelInfo[key] else { return Self.pitch }
        return info.inMonth ? Self.dayInMonthLabel : info.month ? Self.monthLabel : Self.pitch
    }

    /// In Upcoming, the day of the group `id` sits in: its rows don't repeat that date as a chip (dc:2319). Inside a
    /// month, the day's own group (direction C): the rule now holds for every row.
    func groupDay(_ id: EntityID) -> CalendarDate? {
        guard let i = index[id] else { return nil }
        let g = groupIndex[i]
        guard g >= 0, groups[g].kind == .day else { return nil }
        return groups[g].day
    }

    /// The kind of the group a row sits in.
    func groupKind(_ id: EntityID) -> GroupKind? {
        guard let i = index[id] else { return nil }
        let g = groupIndex[i]
        return g >= 0 ? groups[g].kind : nil
    }
}
