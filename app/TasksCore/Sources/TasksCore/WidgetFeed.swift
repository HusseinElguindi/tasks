import Foundation

/// Where the widget files live in the App Group container (design/WIDGETS.md §3.2): `<group>/Tasks/` for Release
/// builds, `<group>/Tasks Dev/` for Debug ones, so Debug and Release stay apart as their data folders do. The caller
/// passes the group's base URL (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`), so TasksCore
/// never names a group.
public enum WidgetFolder {
    public static let release = "Tasks"
    public static let debug = "Tasks Dev"

    /// The folder for this build: `Tasks Dev` when TasksCore is built with `DEBUG`.
    public static func url(in group: URL) -> URL {
        #if DEBUG
        url(in: group, debug: true)
        #else
        url(in: group, debug: false)
        #endif
    }

    public static func url(in group: URL, debug: Bool) -> URL {
        group.appendingPathComponent(debug ? Self.debug : release, isDirectory: true)
    }
}

/// What the app hands its widgets (design/WIDGETS.md §3.2): a small, self-contained copy of the tasks the widgets can
/// show. The app is its only writer; the widgets only read it and compute their views from it with TasksCore's pure
/// code (`Today`, `DeadlineStatus`), so the day can roll over without the app.
public struct WidgetFeed: Hashable, Sendable, Codable {
    /// A live list, as the widgets need it.
    public struct List: Hashable, Sendable, Codable {
        public var id: EntityID
        public var name: String
        /// The sidebar's fractional key.
        public var order: String
        /// `ListModel.slot(for: id)`, the tile's color.
        public var slot: Int

        public init(id: EntityID, name: String, order: String, slot: Int) {
            self.id = id
            self.name = name
            self.order = order
            self.slot = slot
        }
    }

    /// The format version this build writes and reads. A feed with a newer one isn't read.
    public static let currentSchema = 1
    public static let fileName = "widget-feed.json"
    /// Open tasks dated up to this many days ahead are in the feed: Today for the next two weeks of timeline entries.
    public static let horizonDays = 14
    /// Open tasks per list in `listTops` (headings among them come along and don't count).
    public static let listTopCount = 12

    public var schema: Int
    /// Epoch ms, when the app wrote it.
    public var written: Int
    /// The live lists, in sidebar order.
    public var lists: [List]
    /// The tasks, sorted by id: the union of the three selections in `make`.
    public var tasks: [TaskItem]
    /// For each live list, its first `listTopCount` open tasks in list order, with the headings among them.
    public var listTops: [EntityID: [EntityID]]

    public init(schema: Int = WidgetFeed.currentSchema, written: Int, lists: [List], tasks: [TaskItem],
                listTops: [EntityID: [EntityID]]) {
        self.schema = schema
        self.written = written
        self.lists = lists
        self.tasks = tasks
        self.listTops = listTops
    }

    /// `<folder>/widget-feed.json`, with `folder` from `WidgetFolder`.
    public static func url(in folder: URL) -> URL { folder.appendingPathComponent(fileName) }

    // MARK: - Making it (the app)

    /// The feed for the visible state on `day` (§3.2). It holds every live task that's
    /// - open, not a heading, with a When or a deadline on or before `day + horizonDays`;
    /// - completed during `day`;
    /// - or among its list's first `listTopCount` open tasks, or a heading among them.
    /// "Live" is `Projection.isLive`: not deleted, in a list that isn't in Trash.
    @MainActor
    public static func make(from projection: Projection, day: Day, now: Date = Date()) -> WidgetFeed {
        let horizon = day.date.adding(days: horizonDays)
        var lists: [List] = []
        var tops: [EntityID: [EntityID]] = [:]
        var ids: Set<EntityID> = []
        for listID in projection.activeLists.ids {
            guard let l = projection.list(listID) else { continue }
            lists.append(List(id: l.id, name: l.name, order: l.order, slot: ListModel.slot(for: l.id)))
            var top: [EntityID] = []
            var count = 0
            for id in projection.openTasks(in: listID).ids {
                guard count < listTopCount, let t = projection.task(id) else { break }
                top.append(id)
                if !t.isHeading { count += 1 }
            }
            // A heading right after the last task heads nothing in the feed.
            while let last = top.last, projection.task(last)?.isHeading == true { top.removeLast() }
            tops[listID] = top
            ids.formUnion(top)
            for id in projection.openTasks(in: listID).ids {
                guard let t = projection.task(id), !t.isHeading else { continue }
                if Self.dated(t, onOrBefore: horizon) { ids.insert(id) }
            }
            for id in projection.completedTasks(in: listID).ids {
                guard let t = projection.task(id), let c = t.completedAt else { continue }
                if c < day.start { break } // newest first
                if day.contains(ms: c) { ids.insert(id) }
            }
        }
        let tasks = ids.sorted().compactMap { projection.task($0) }
        let written = Int((now.timeIntervalSince1970 * 1000).rounded())
        return WidgetFeed(written: written, lists: lists, tasks: tasks, listTops: tops)
    }

    static func dated(_ t: TaskItem, onOrBefore date: CalendarDate) -> Bool {
        if let w = t.when, w <= date { return true }
        if let d = t.deadline, d <= date { return true }
        return false
    }

    // MARK: - Files

    /// The feed at `url`, or nil if it's missing, unreadable or from a newer schema ("Open Tasks to set up").
    public static func read(at url: URL) -> WidgetFeed? {
        guard let data = try? Data(contentsOf: url),
              let feed = try? JSONDecoder().decode(WidgetFeed.self, from: data),
              feed.schema <= currentSchema else { return nil }
        return feed
    }

    /// Writes the feed atomically (temp file, then rename), creating the folder if needed. A reader sees the old feed
    /// or the new one, never part of one.
    public func write(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - As state

    /// The feed as an `AppState` the reducer can apply ops to. Lists carry only what the feed has (no notes, live).
    public var state: AppState {
        var s = AppState()
        for l in lists { s.lists[l.id] = TaskList(id: l.id, name: l.name, order: l.order) }
        for t in tasks { s.tasks[t.id] = t }
        return s
    }
}

/// The feed with the widget's own taps on top (§3.3): the inbox ops the app hasn't drained yet, applied with the
/// reducer, as `pending` is for the app. What the widget's provider draws from.
public struct WidgetOverlay: Hashable, Sendable {
    public let feed: WidgetFeed
    /// `feed.state` with the ops applied.
    public private(set) var state: AppState

    public init(feed: WidgetFeed, ops: [Op] = []) {
        self.feed = feed
        state = feed.state
        for op in ops { state.apply(op) }
    }

    /// Applies one more op (a tap the provider hasn't re-read from the inbox yet).
    public mutating func apply(_ op: Op) { state.apply(op) }

    public var lists: [WidgetFeed.List] { feed.lists }

    public func task(_ id: EntityID) -> TaskItem? { state.tasks[id] }

    /// Today on `day` in Today's own order (§4 Q5): `open` grouped by list in sidebar order, each list's in its
    /// order; `done` is what was completed during `day`, oldest first, as the app's Completed group. Both follow
    /// `Today.contains`, so a task the widget just checked moves from `open` to `done`.
    public func today(_ day: Day) -> (open: [TaskItem], done: [TaskItem]) {
        var open: [TaskItem] = []
        var done: [TaskItem] = []
        var byList: [EntityID: [TaskItem]] = [:]
        for t in state.tasks.values where Today.contains(t, list: state.lists[t.list], day: day) {
            if t.completedAt == nil { byList[t.list, default: []].append(t) } else { done.append(t) }
        }
        for l in feed.lists {
            guard var ts = byList[l.id] else { continue }
            ts.sort { orderPrecedes($0.order, $0.id, $1.order, $1.id) }
            open.append(contentsOf: ts)
        }
        done.sort { $0.completedAt! != $1.completedAt! ? $0.completedAt! < $1.completedAt! : $0.id < $1.id }
        return (open, done)
    }

    /// A list's rows for the List widget: `listTops` through the overlay, in the feed's order. A task checked in the
    /// widget stays in its place, completed (§4 Q4); one deleted meanwhile is dropped. Empty for a list not in the
    /// feed (deleted, or in Trash).
    public func top(of list: EntityID) -> [TaskItem] {
        (feed.listTops[list] ?? []).compactMap { id in
            guard let t = state.tasks[id], !t.deleted, t.list == list else { return nil }
            return t
        }
    }
}
