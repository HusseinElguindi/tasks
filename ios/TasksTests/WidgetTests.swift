import XCTest
import WidgetKit
import TasksCore
@testable import Tasks

/// The widgets' feed as the app writes it, the links the widgets open the app with, and Today as the widget computes
/// it from a feed (widgets/Shared's files are compiled into this bundle).
@MainActor
final class WidgetTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func openStore() async -> Store {
        await Store.open(directory: dir.appendingPathComponent("data", isDirectory: true))
    }

    private var feedURL: URL { dir.appendingPathComponent("feed/widget-feed.json") }

    private func waitForFeed(_ check: (WidgetFeed) -> Bool, timeout: TimeInterval = 4) async -> WidgetFeed? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let f = WidgetFeed.read(at: feedURL), check(f) { return f }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    // MARK: The feed

    func testTheFeedIsWrittenAtStartAndAfterAChange() async throws {
        let store = await openStore()
        let writer = WidgetFeedWriter(store: store, url: feedURL)
        writer.start()
        let first = try XCTUnwrap(WidgetFeed.read(at: feedURL), "written at start")
        XCTAssertFalse(first.lists.isEmpty, "the Inbox the store seeds")

        let today = store.projection.day.date
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        let feed = await waitForFeed { $0.tasks.contains { $0.id == id } }
        XCTAssertNotNil(feed, "a new task for today reaches the feed about a second later")
    }

    func testAChangeIsWrittenOnceAfterASecond() async throws {
        let store = await openStore()
        let writer = WidgetFeedWriter(store: store, url: feedURL)
        writer.start()
        let today = store.projection.day.date
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == id } ?? true, "not before the second")
        let feed = await waitForFeed { $0.tasks.contains { $0.id == id } }
        XCTAssertNotNil(feed)
    }

    func testGoingToTheBackgroundWritesAWaitingChangeAtOnce() async throws {
        let store = await openStore()
        let writer = WidgetFeedWriter(store: store, url: feedURL)
        writer.start()
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", when: store.projection.day.date))
        try await Task.sleep(for: .milliseconds(50))   // the change reaches the writer
        writer.flush()
        XCTAssertTrue(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == id } ?? false)
    }

    func testAFeedThatSaysTheSameIsntWrittenAgain() async throws {
        let store = await openStore()
        let writer = WidgetFeedWriter(store: store, url: feedURL)
        writer.start()
        let written = try XCTUnwrap(WidgetFeed.read(at: feedURL)).written
        // An undated task outside the list's first 12 isn't in the feed: fill the Inbox first.
        let inbox = try XCTUnwrap(store.projection.activeLists.ids.first)
        for i in 0..<WidgetFeed.listTopCount { _ = store.createTask(title: "Task \(i)", in: inbox) }
        let filled = await waitForFeed { $0.listTops[inbox]?.count == WidgetFeed.listTopCount }
        let stamp = try XCTUnwrap(filled).written
        XCTAssertNotEqual(stamp, written)
        _ = store.createTask(title: "Thirteenth", in: inbox)
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertEqual(WidgetFeed.read(at: feedURL)?.written, stamp, "nothing the widgets show changed")
    }

    /// After the first change, a second within 20 s of the last write waits for the gap (the widgets aren't on screen
    /// while the app is in front); going to the background writes it at once (coord title-design T10).
    func testWritesAreTwentySecondsApartUntilTheBackground() async throws {
        let store = await openStore()
        var now: TimeInterval = 1000
        let writer = WidgetFeedWriter(store: store, url: feedURL, reload: { _ in }, clock: { now })
        writer.start()
        let today = store.projection.day.date
        let a = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        let first = await waitForFeed { $0.tasks.contains { $0.id == a } }
        XCTAssertNotNil(first, "the first change goes out after its second: the launch write starts no gap")
        XCTAssertEqual(writer.writes, 2)
        now += 5
        let b = try XCTUnwrap(store.createTask(title: "Water the plants", when: today))
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertFalse(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? true, "held for the 20 s gap")
        XCTAssertEqual(writer.writes, 2)
        writer.flush()   // going to the background
        XCTAssertTrue(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? false)
        XCTAssertEqual(writer.writes, 3)
        // 20 s on, the next change waits only its second.
        now += WidgetFeedWriter.gap
        let c = try XCTUnwrap(store.createTask(title: "Later", when: today))
        let feed = await waitForFeed { $0.tasks.contains { $0.id == c } }
        XCTAssertNotNil(feed)
        XCTAssertEqual(writer.writes, 4)
    }

    /// An edit to a task's notes changes nothing a widget draws: no write, no reload. A change to a dated task in a
    /// list's tops reloads Today, the lock screen's Today and the List widget; the circular lock-screen widgets and
    /// the controls never reload.
    func testOnlyWhatAWidgetDrawsReloadsIt() async throws {
        let store = await openStore()
        var now: TimeInterval = 1000
        var reloaded: [[String]] = []
        let writer = WidgetFeedWriter(store: store, url: feedURL, reload: { reloaded.append($0) }, clock: { now })
        writer.start()
        XCTAssertEqual(reloaded.last.map(Set.init), [WidgetGroup.Kind.today, WidgetGroup.Kind.todayLock,
                                                     WidgetGroup.Kind.list], "no feed before: every kind that draws it")
        let inbox = try XCTUnwrap(store.projection.activeLists.ids.first)
        let undated = try XCTUnwrap(store.createTask(title: "Call the bank", in: inbox))
        _ = await waitForFeed { $0.tasks.contains { $0.id == undated } }
        XCTAssertEqual(reloaded.last, [WidgetGroup.Kind.list], "an undated task in the Inbox's tops: the List widget")

        now += WidgetFeedWriter.gap
        let writes = writer.writes
        reloaded = []
        _ = store.setNotes(undated, "- [ ] the account number")
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(writer.writes, writes, "notes aren't in the feed")
        XCTAssertEqual(reloaded, [])
        XCTAssertEqual(WidgetFeed.read(at: feedURL)?.tasks.first { $0.id == undated }?.notes, "")

        _ = store.setWhen([undated], store.projection.day.date)
        _ = await waitForFeed { $0.tasks.first { $0.id == undated }?.when != nil }
        XCTAssertEqual(reloaded.last.map(Set.init), [WidgetGroup.Kind.today, WidgetGroup.Kind.todayLock,
                                                     WidgetGroup.Kind.list], "dated, and in the Inbox's tops: all three")

        // A dated task outside the Inbox's first 12: Today's kinds alone.
        for i in 1..<WidgetFeed.listTopCount { _ = store.createTask(title: "Task \(i)", in: inbox) }
        now += WidgetFeedWriter.gap
        _ = await waitForFeed { $0.listTops[inbox]?.count == WidgetFeed.listTopCount }
        now += WidgetFeedWriter.gap
        let dated = try XCTUnwrap(store.createTask(title: "Thirteenth, for today", in: inbox,
                                                   when: store.projection.day.date))
        _ = await waitForFeed { $0.tasks.contains { $0.id == dated } }
        XCTAssertEqual(reloaded.last, [WidgetGroup.Kind.today, WidgetGroup.Kind.todayLock])
        XCTAssertFalse(reloaded.joined().contains(WidgetGroup.Kind.newTask))
        XCTAssertFalse(reloaded.joined().contains(WidgetGroup.Kind.todayCircle))
    }

    func testTheSampleDataNeverWritesAFeed() async {
        let store = await openStore()
        XCTAssertNil(WidgetFeedWriter(store: store, isSample: true))
    }

    func testTheFeedFolderIsTheBuildsOwn() {
        #if DEBUG
        XCTAssertEqual(WidgetGroup.folder?.lastPathComponent, "Tasks Dev")
        #else
        XCTAssertEqual(WidgetGroup.folder?.lastPathComponent, "Tasks")
        #endif
        XCTAssertNotNil(WidgetGroup.folder, "the app has the App Group")
    }

    // MARK: Links

    func testLinksRoundTrip() {
        let links: [DeepLink] = [.today, .upcoming, .list("school-9"), .task("a1b2"), .new(list: nil), .new(list: "home")]
        for l in links { XCTAssertEqual(DeepLink(l.url), l, l.url.absoluteString) }
        XCTAssertEqual(DeepLink.task("s4").url.absoluteString, "tasks://task/s4")
        XCTAssertEqual(DeepLink.new(list: "home").url.absoluteString, "tasks://new?list=home")
    }

    func testUnknownLinksAreIgnored() {
        for s in ["https://today", "tasks://", "tasks://list", "tasks://task/", "tasks://settings", "other://today"] {
            XCTAssertNil(DeepLink(URL(string: s)!), s)
        }
        XCTAssertEqual(DeepLink(URL(string: "tasks://new?list=")!), .new(list: nil))
        XCTAssertEqual(DeepLink(URL(string: "TASKS://Today")!), .today)
    }

    /// The app's own `DeepLink` (this bundle compiles the widgets' copy too, for their views).
    typealias AppLink = Tasks.DeepLink

    func testFollowingALinkOpensThere() async throws {
        let store = await openStore()
        let app = AppModel(store: store)
        let inbox = try XCTUnwrap(store.projection.activeLists.ids.first)
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", in: inbox))

        await app.follow(AppLink.upcoming)
        XCTAssertEqual(app.path, [.upcoming])
        await app.follow(AppLink.list(inbox))
        XCTAssertEqual(app.path, [.list(inbox)])
        await app.follow(AppLink.list("gone"))
        XCTAssertEqual(app.path, [.today], "a list that isn't there opens Today")
        app.detailTask = id
        await app.follow(AppLink.task(id))
        XCTAssertEqual(app.path, [.list(inbox)])
        XCTAssertNil(app.detailTask, "the task in its list, not its details")
        XCTAssertEqual(app.flashed, [id], "highlighted with the selected fill")
        try await Task.sleep(for: Tasks.AppModel.widgetTaskHold + .milliseconds(300))
        XCTAssertEqual(app.flashed, [], "which fades")
        await app.follow(AppLink.today)
        XCTAssertEqual(app.path, [.today])
        await app.follow(AppLink.new(list: inbox))
        XCTAssertEqual(app.path, [.list(inbox)])
        XCTAssertEqual(app.draft?.source, .list(inbox))
        await app.follow(AppLink.new(list: nil))
        XCTAssertEqual(app.draft?.source, .today)
    }

    // MARK: Today in the widget

    private static let day = Day(containing: CalendarDate(year: 2026, month: 11, day: 5)!.startDate().addingTimeInterval(9 * 3600))

    private func feed(_ tasks: [TaskItem], lists: [WidgetFeed.List]) -> WidgetFeed {
        WidgetFeed(written: 0, lists: lists, tasks: tasks, listTops: [:])
    }

    func testTodayIsTheAppsTodayInItsOrder() throws {
        let d = Self.day.date
        let school = WidgetFeed.List(id: "school", name: "School", order: "a0", slot: 0)
        let home = WidgetFeed.List(id: "home", name: "Home", order: "a1", slot: 2)
        let doneAt = Self.day.start + 3_600_000
        let tasks = [
            TaskItem(id: "h1", list: "home", order: "a0", title: "Buy milk", when: d),
            TaskItem(id: "s2", list: "school", order: "a1", title: "Problem set 6", deadline: d),
            TaskItem(id: "s1", list: "school", order: "a0", title: "Email Prof. Lin", deadline: d.adding(days: -2)),
            TaskItem(id: "s3", list: "school", order: "a2", title: "Book the dentist", when: d, deadline: d.adding(days: 4)),
            TaskItem(id: "s4", list: "school", order: "a3", title: "Later", when: d.adding(days: 1)),
            TaskItem(id: "h2", list: "home", order: "a1", title: "Pay the phone bill", when: d, completedAt: doneAt),
        ]
        let s = TodaySnapshot(WidgetOverlay(feed: feed(tasks, lists: [school, home])), day: Self.day)
        XCTAssertEqual(s.groups.map(\.list.name), ["School", "Home"])
        XCTAssertEqual(s.open.map(\.id), ["s1", "s2", "s3", "h1"], "lists in sidebar order, each in its order")
        XCTAssertEqual(s.done.map(\.id), ["h2"])
        XCTAssertEqual(s.openCount, 4)
        XCTAssertEqual(s.overdueCount, 1)
        XCTAssertEqual(s.dueCount, 1)
        XCTAssertEqual(s.open.map(\.cue), [.late, .due, .planned, .planned])
        XCTAssertEqual(s.open.map { $0.chip?.text }, ["2d ago", "Due today", "4d left", nil])
        XCTAssertEqual(s.groups[0].list.monogram, "S")
        XCTAssertTrue(s.done[0].done)
    }

    func testAtMidnightTheNextDayShowsWithoutTheApp() throws {
        let d = Self.day.date
        let inbox = WidgetFeed.List(id: "inbox", name: "Inbox", order: "a0", slot: 6)
        let tasks = [
            TaskItem(id: "t1", list: "inbox", order: "a0", title: "Tomorrow's", when: d.adding(days: 1)),
            TaskItem(id: "t2", list: "inbox", order: "a1", title: "Done today", when: d, completedAt: Self.day.start + 1000),
        ]
        let overlay = WidgetOverlay(feed: feed(tasks, lists: [inbox]))
        let now = Date(timeIntervalSince1970: Double(Self.day.start) / 1000 + 9 * 3600)
        let timeline = TodayProvider.timeline(overlay: overlay, now: now)
        XCTAssertEqual(timeline.entries.count, 1 + TodayProvider.midnights)
        XCTAssertEqual(timeline.policy, .atEnd)
        XCTAssertEqual(timeline.entries[1].date, Date(timeIntervalSince1970: Double(Self.day.end) / 1000))
        guard case let .today(first) = timeline.entries[0].content, case let .today(next) = timeline.entries[1].content else {
            return XCTFail("both entries show Today")
        }
        XCTAssertEqual(first.open.map(\.id), [])
        XCTAssertEqual(first.done.map(\.id), ["t2"])
        XCTAssertEqual(next.open.map(\.id), ["t1"], "tomorrow's task arrives at midnight")
        XCTAssertEqual(next.done.map(\.id), [], "yesterday's completed task has gone")
    }

    func testNoFeedAsksToOpenTheApp() {
        XCTAssertEqual(TodayProvider.content(nil, at: Date()), .setUp)
    }
}
