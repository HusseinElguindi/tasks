import XCTest
import TasksCore

/// The Mac app's widget feed (Tasks/Widgets/WidgetFeedWriter.swift, design/WIDGETS.md §3.2–3.4): written at launch,
/// a second after the last change, at once when quitting, never again when it would say the same, and each write
/// reloads the widgets. A store on a temp folder and a feed beside it; the real group container is never touched.
@MainActor
final class WidgetFeedWriterTests: XCTestCase {
    private var dir: URL!
    private var reloads = 0
    /// The kinds each reload named.
    private var reloaded: [[String]] = []
    /// The writer's clock (`writer(_:)`), moved past the 20 s gap where a test needs a second write.
    private var clockNow: TimeInterval = 1000

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacWidgetFeed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reloads = 0
        reloaded = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func openStore() async -> Store {
        await Store.open(directory: dir.appendingPathComponent("data", isDirectory: true))
    }

    private var feedURL: URL { dir.appendingPathComponent("group/Tasks/widget-feed.json") }

    private func writer(_ store: Store) -> WidgetFeedWriter {
        WidgetFeedWriter(store: store, url: feedURL, reload: { [weak self] kinds in
            self?.reloads += 1
            self?.reloaded.append(kinds)
        }, clock: { [unowned self] in self.clockNow })
    }

    private func waitForFeed(_ check: (WidgetFeed) -> Bool, timeout: TimeInterval = 4) async -> WidgetFeed? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let f = WidgetFeed.read(at: feedURL), check(f) { return f }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func testTheFeedIsWrittenAtLaunchAndReloadsTheWidgets() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        let feed = try XCTUnwrap(WidgetFeed.read(at: feedURL), "written at launch, its folder made")
        XCTAssertEqual(feed.lists.map(\.name), ["Inbox"], "the Inbox the store seeds")
        XCTAssertEqual(reloads, 1)
    }

    func testAChangeIsWrittenOnceASecondAfterTheLast() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        let today = store.projection.day.date
        let a = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        try await Task.sleep(for: .milliseconds(400))
        let b = try XCTUnwrap(store.createTask(title: "Water the plants", when: today))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == a } ?? true, "not before the second")
        let feed = await waitForFeed { f in [a, b].allSatisfy { id in f.tasks.contains { $0.id == id } } }
        XCTAssertNotNil(feed)
        XCTAssertEqual(w.writes, 2, "launch, then one write for both changes")
        XCTAssertEqual(reloads, 2)
    }

    func testQuittingWritesAWaitingChangeAtOnce() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", when: store.projection.day.date))
        try await Task.sleep(for: .milliseconds(50)) // the change reaches the writer
        w.flush()
        XCTAssertTrue(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == id } ?? false)
    }

    func testCompletingATaskTakesItOffTheWidgets() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        let today = store.projection.day.date
        let id = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        _ = await waitForFeed { $0.tasks.contains { $0.id == id } }
        clockNow += SyncSchedule.feedGap
        _ = store.toggleComplete([id])
        let feed = await waitForFeed { $0.tasks.first { $0.id == id }?.completedAt != nil }
        let overlay = WidgetOverlay(feed: try XCTUnwrap(feed), ops: [])
        let snap = TodaySnapshot(overlay, day: store.projection.day)
        XCTAssertFalse(snap.open.contains { $0.id == id }, "the widgets show open tasks only (the user)")
    }

    func testWithNoWindowABurstOfChangesIsOneWriteThenWaits() async throws {
        let store = await openStore()
        var visible = false
        var now: TimeInterval = 1000
        let w = WidgetFeedWriter(store: store, url: feedURL, reload: { [weak self] _ in self?.reloads += 1 },
                                 windowVisible: { visible }, clock: { now })
        w.start() // the launch write, which doesn't count toward the 2 minutes
        let today = store.projection.day.date
        let a = try XCTUnwrap(store.createTask(title: "From the phone", when: today))
        let first = await waitForFeed { $0.tasks.contains { $0.id == a } }
        XCTAssertNotNil(first, "the first change after launch goes out after its second, window or not")
        XCTAssertEqual(w.writes, 2)
        now += 10
        let b = try XCTUnwrap(store.createTask(title: "An agent's edit", when: today))
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertFalse(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? true,
                       "with no window, not within two minutes of the last write")
        XCTAssertEqual(w.writes, 2)
        // A window comes back (the app is activated): what was held back goes out at once.
        visible = true
        w.flush()
        XCTAssertTrue(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? false)
        XCTAssertEqual(w.writes, 3)
        // Two minutes on, with no window again: the next change waits only its second.
        visible = false
        now += SyncSchedule.windowlessFeedGap
        let c = try XCTUnwrap(store.createTask(title: "Later", when: today))
        let feed = await waitForFeed { $0.tasks.contains { $0.id == c } }
        XCTAssertNotNil(feed)
        XCTAssertEqual(reloads, 4)
    }

    /// With a window open, a second change within 20 s of the last write waits for the gap; leaving the window (hide,
    /// close, minimize, another app) writes it at once (coord title-design T8).
    func testWithAWindowOpenWritesAreTwentySecondsApartUntilTheWindowGoes() async throws {
        let store = await openStore()
        var now: TimeInterval = 1000
        let w = WidgetFeedWriter(store: store, url: feedURL, reload: { [weak self] kinds in
            self?.reloads += 1
            self?.reloaded.append(kinds)
        }, windowVisible: { true }, clock: { now })
        w.start()
        let today = store.projection.day.date
        let a = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        let first = await waitForFeed { $0.tasks.contains { $0.id == a } }
        XCTAssertNotNil(first, "the first change goes out after its second")
        XCTAssertEqual(w.writes, 2)
        now += 5
        let b = try XCTUnwrap(store.createTask(title: "Water the plants", when: today))
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertFalse(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? true, "held for the 20 s gap")
        XCTAssertEqual(w.writes, 2)
        w.flush() // the window hidden or closed
        XCTAssertTrue(WidgetFeed.read(at: feedURL)?.tasks.contains { $0.id == b } ?? false)
        XCTAssertEqual(w.writes, 3)
    }

    /// An edit to a task's notes changes nothing a widget draws: no write, no reload. A dated task's change reloads
    /// Today alone; an undated task in a list's tops reloads the List widget alone.
    func testOnlyWhatAWidgetDrawsReloadsIt() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        let today = store.projection.day.date
        let dated = try XCTUnwrap(store.createTask(title: "Buy milk", when: today))
        _ = await waitForFeed { $0.tasks.contains { $0.id == dated } }
        let writes = w.writes
        reloaded = []
        clockNow += SyncSchedule.feedGap
        _ = store.setNotes(dated, "- [ ] oat, not almond")
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(w.writes, writes, "notes aren't in the feed")
        XCTAssertEqual(reloaded, [])
        XCTAssertEqual(WidgetFeed.read(at: feedURL)?.tasks.first { $0.id == dated }?.notes, "")

        _ = store.setTitle(dated, "Buy oat milk")
        _ = await waitForFeed { $0.tasks.contains { $0.title == "Buy oat milk" } }
        XCTAssertEqual(reloaded.last.map(Set.init), [WidgetGroup.Kind.today, WidgetGroup.Kind.list],
                       "dated and in the Inbox's tops: both")
    }

    func testAFeedThatSaysTheSameIsntWrittenAgain() async throws {
        let store = await openStore()
        let w = writer(store)
        w.start()
        // A sync state change with nothing new, as the 30 s syncs make: compared, not written.
        w.write()
        w.write()
        XCTAssertEqual(w.writes, 1)
        XCTAssertEqual(reloads, 1)
        // A new writer (the next launch) reads the last feed and doesn't rewrite it either.
        let next = writer(store)
        next.start()
        XCTAssertEqual(next.writes, 0)
    }
}
