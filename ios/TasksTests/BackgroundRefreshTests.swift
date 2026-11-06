import BackgroundTasks
import XCTest
import TasksCore
@testable import Tasks

/// The background refresh's handler (BackgroundRefresh.swift) with the system's task and scheduler faked: one sync,
/// then the feed, then the reload, then the next request; nothing for the sample data or without a token; expiry ends
/// it at once. And its log and Settings' line. (The simulator can't run background tasks, so this is the check here.)
@MainActor
final class BackgroundRefreshTests: XCTestCase {
    private var dir: URL!
    private var events: Events!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("BackgroundRefreshTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        events = Events()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let config = SyncConfig(url: URL(string: "http://127.0.0.1:9")!, token: "test-token")
    private var feedURL: URL { dir.appendingPathComponent("feed/widget-feed.json") }

    private func store(_ name: String, _ transport: SyncTransport) async -> Store {
        await Store.open(directory: dir.appendingPathComponent(name, isDirectory: true), transport: transport)
    }

    /// "The Mac": a task for today, synced to the server.
    private func macAddsATask(_ server: MiniServer) async throws -> EntityID {
        let mac = await store("mac", server)
        let id = try XCTUnwrap(mac.createTask(title: "Written on the Mac", when: mac.projection.day.date))
        mac.cancelScheduledSync()
        mac.config = config
        mac.cancelScheduledSync()
        await mac.sync()
        guard case .idle = mac.syncState else { throw XCTSkip("the Mac's sync didn't finish: \(mac.syncState)") }
        return id
    }

    /// The phone's AppModel with its feed at `feedURL`; the reload says whether the feed had `id` by then.
    private func phone(_ server: SyncTransport, isSample: Bool = false, watching id: EntityID? = nil) async -> AppModel {
        let app = AppModel(store: await store("phone", server), isSample: isSample)
        let url = feedURL
        let events = events!
        app.widgetFeed = WidgetFeedWriter(store: app.store, url: url) {
            let has = id.map { id in WidgetFeed.read(at: url)?.tasks.contains { $0.id == id } ?? false } ?? false
            events.add(has ? "reload (feed has the Mac's task)" : "reload")
        }
        return app
    }

    private func refresh(_ app: AppModel, scheduler: FakeScheduler, config: SyncConfig?, now: Date = Date()) -> BackgroundRefresh {
        BackgroundRefresh(scheduler: scheduler, history: RefreshHistory(directory: dir.appendingPathComponent("docs")),
                          open: { app }, config: { _ in config }, now: { now })
    }

    // MARK: The handler

    func testARunSyncsThenWritesTheFeedThenReloadsThenPersistsThenAsksForTheNext() async throws {
        let server = MiniServer(events: events)
        let id = try await macAddsATask(server)
        events.clear()
        let app = await phone(server, watching: id)
        let scheduler = FakeScheduler(events: events)
        let now = Date()
        let r = refresh(app, scheduler: scheduler, config: config, now: now)
        let task = FakeTask()

        await r.handle(task)

        let e = events.all
        let lastSync = try XCTUnwrap(e.lastIndex(of: "sync"), "it synced: \(e)")
        let reload = try XCTUnwrap(e.firstIndex(of: "reload (feed has the Mac's task)"), "the feed had the Mac's task by the reload: \(e)")
        let submit = try XCTUnwrap(e.firstIndex(of: "submit"), "it asked for the next run: \(e)")
        XCTAssertLessThan(lastSync, reload, "the sync, then the feed and its reload: \(e)")
        XCTAssertLessThan(reload, submit, "then the next request: \(e)")
        XCTAssertEqual(e.filter { $0.hasPrefix("reload") }.count, 1, "one reload: \(e)")
        XCTAssertEqual(task.completed, [true], "completed once, successfully")
        XCTAssertNil(task.expirationHandler, "the expiry handler is let go")
        XCTAssertNotNil(app.task(id), "the Mac's task is in the phone's store")
        XCTAssertEqual(app.store.config, config, "the config a foreground sync uses")

        let request = try XCTUnwrap(scheduler.submitted.last)
        XCTAssertEqual(request.identifier, BackgroundRefresh.identifier)
        XCTAssertEqual(try XCTUnwrap(request.earliestBeginDate).timeIntervalSince(now), 15 * 60, accuracy: 0.001)

        // Persisted: a fresh open of the folder has it (the snapshot, written by persistNow).
        let reopened = await store("phone", DeadTransport())
        XCTAssertNotNil(reopened.projection.taskModel(id), "saved before the task ended")

        let s = r.history.summary
        XCTAssertEqual(s.runs, 1)
        let last = try XCTUnwrap(s.last)
        XCTAssertEqual(last.outcome, .ok)
        XCTAssertGreaterThan(last.entries, 0, "the entries the pull applied")
        XCTAssertEqual(last.feed, true)
        let log = try String(contentsOf: r.history.logURL, encoding: .utf8)
        XCTAssertEqual(log.split(separator: "\n").count, 1)
        XCTAssertTrue(log.contains("  ok  entries \(last.entries)  feed changed"), log)
    }

    func testANothingNewRunDoesntReloadTheWidgets() async throws {
        let server = MiniServer(events: events)
        _ = try await macAddsATask(server)
        let app = await phone(server)
        let r = refresh(app, scheduler: FakeScheduler(events: events), config: config)
        await r.handle(FakeTask())
        events.clear()
        let task = FakeTask()
        await r.handle(task)
        XCTAssertFalse(events.all.contains { $0.hasPrefix("reload") }, "the same feed: no reload, \(events.all)")
        XCTAssertEqual(events.all.last, "submit")
        XCTAssertEqual(task.completed, [true])
        XCTAssertEqual(r.history.summary.runs, 2)
        XCTAssertEqual(r.history.summary.last?.entries, 0)
        XCTAssertEqual(r.history.summary.last?.feed, false)
    }

    func testTheSampleDataNeverSyncsOrSchedules() async throws {
        let server = MiniServer(events: events)
        let app = await phone(server, isSample: true)
        let scheduler = FakeScheduler(events: events)
        let r = refresh(app, scheduler: scheduler, config: config)

        r.schedule(for: app)
        XCTAssertEqual(events.all, ["cancel"], "going to the background with the sample data asks for nothing")

        let task = FakeTask()
        await r.handle(task)
        XCTAssertFalse(events.all.contains("sync"), "nothing synced: \(events.all)")
        XCTAssertFalse(events.all.contains("submit"), "nothing scheduled: \(events.all)")
        XCTAssertFalse(events.all.contains { $0.hasPrefix("reload") })
        XCTAssertNil(WidgetFeed.read(at: feedURL), "no feed written for the sample data")
        XCTAssertNil(app.store.config)
        XCTAssertEqual(task.completed, [true])
        XCTAssertEqual(r.history.summary.last?.outcome, .skipped("sample data"))
    }

    func testNoTokenNoSync() async throws {
        let server = MiniServer(events: events)
        let app = await phone(server)
        let scheduler = FakeScheduler(events: events)
        let r = refresh(app, scheduler: scheduler, config: nil)

        r.schedule(for: app)
        XCTAssertEqual(events.all, ["cancel"], "no server and token: no request")

        let task = FakeTask()
        await r.handle(task)
        XCTAssertFalse(events.all.contains("sync"), "nothing synced: \(events.all)")
        XCTAssertFalse(events.all.contains("submit"), "nothing scheduled: \(events.all)")
        XCTAssertNil(WidgetFeed.read(at: feedURL))
        XCTAssertNil(app.store.config, "the store gets no config")
        XCTAssertEqual(task.completed, [true])
        XCTAssertEqual(r.history.summary.last?.outcome, .skipped("sync is off"))
    }

    func testTheRealConfigIsTheForegroundOne() async throws {
        // Debug builds sync only with a local server: the default server gives no config, so no request.
        let app = await phone(MiniServer(events: events))
        let r = BackgroundRefresh(scheduler: FakeScheduler(events: events),
                                  history: RefreshHistory(directory: dir.appendingPathComponent("docs")), open: { app })
        r.schedule(for: app)
        XCTAssertEqual(events.all.contains("submit"), app.syncConfig != nil)
    }

    func testARejectedTokenIsAFailedRunThatStillAsksForTheNext() async throws {
        let server = MiniServer(events: events)
        let app = await phone(server)
        let r = refresh(app, scheduler: FakeScheduler(events: events), config: SyncConfig(url: config.url, token: "wrong"))
        let task = FakeTask()
        await r.handle(task)
        XCTAssertEqual(task.completed, [false])
        XCTAssertEqual(r.history.summary.last?.outcome, .error("the server rejected the token"))
        XCTAssertEqual(events.all.last, "submit")
    }

    func testExpiryEndsTheRunAtOnceAndAsksForTheNext() async throws {
        let server = MiniServer(events: events)
        let gate = Gate()
        server.gate = gate
        let app = await phone(server)
        let r = refresh(app, scheduler: FakeScheduler(events: events), config: config)
        let task = FakeTask()

        let run = Task { await r.handle(task) }
        try await waitFor { self.events.all.contains("sync") }
        task.expirationHandler?()   // the system, on its own queue in life
        try await waitFor { !task.completed.isEmpty }

        XCTAssertEqual(task.completed, [false], "ended at once, not successfully")
        XCTAssertEqual(events.all.last, "submit", "and the next one asked for")
        XCTAssertEqual(r.history.summary.last?.outcome, .expired)
        XCTAssertFalse(events.all.contains { $0.hasPrefix("reload") })

        // The request the sync was waiting on comes back later: the run doesn't end twice or write after.
        gate.open()
        await run.value
        XCTAssertEqual(task.completed, [false])
        XCTAssertEqual(r.history.summary.runs, 1)
        XCTAssertEqual(events.all.filter { $0 == "submit" }.count, 1)
    }

    // MARK: The log and Settings' line

    func testTheLogKeepsTheLast200Runs() throws {
        let h = RefreshHistory(directory: dir.appendingPathComponent("docs"))
        let t0 = Date(timeIntervalSince1970: 1_793_000_000)
        for i in 0..<205 {
            let start = t0.addingTimeInterval(Double(i) * 3600)
            h.record(.init(start: start, end: start.addingTimeInterval(0.25), outcome: i == 204 ? .error("can't reach the server: offline") : .ok,
                           entries: i, feed: i % 2 == 0))
        }
        let lines = try String(contentsOf: h.logURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 200)
        XCTAssertTrue(lines.first!.contains("entries 5  "), String(lines.first!))
        XCTAssertTrue(lines.last!.contains("0.250 s  error: can't reach the server: offline  entries 204  feed changed"), String(lines.last!))
        let s = h.summary
        XCTAssertEqual(s.runs, 205)
        XCTAssertEqual(s.since, t0)
        XCTAssertEqual(s.last?.entries, 204)
    }

    func testTheSettingsLine() throws {
        XCTAssertEqual(RefreshHistory.Summary().text(),
                       "Last background refresh: not yet. iOS runs it now and then while the app is closed.")

        let h = RefreshHistory(directory: dir.appendingPathComponent("docs"))
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 6; c.hour = 9; c.minute = 41
        let first = try XCTUnwrap(Calendar.current.date(from: c))
        for i in 0..<12 {
            let start = first.addingTimeInterval(Double(i) * 600)
            h.record(.init(start: start, end: start.addingTimeInterval(0.1), outcome: .ok, entries: 0, feed: false))
        }
        let last = first.addingTimeInterval(11 * 600)
        let text = h.summary.text(now: last.addingTimeInterval(12 * 60))
        let abs = last.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        XCTAssertTrue(text.hasPrefix("Last background refresh: 12 minutes ago ("), text)
        XCTAssertTrue(text.contains("(\(abs))."), text)
        XCTAssertTrue(text.hasSuffix("12 runs since \(first.formatted(.dateTime.month(.abbreviated).day()))."), text)

        h.noteSubmit(error: "Background App Refresh is off for Tasks (or Low Power Mode is on)")
        XCTAssertTrue(h.summary.text().hasSuffix("Background App Refresh is off for Tasks (or Low Power Mode is on)."))
        h.noteSubmit(error: nil)
        XCTAssertNil(h.summary.submitError)

        h.record(.init(start: last, end: last, outcome: .expired, entries: 0, feed: nil))
        XCTAssertTrue(h.summary.text().contains("It ended expired (iOS's time ran out)."), h.summary.text())
    }

    private func waitFor(_ check: @escaping () -> Bool, timeout: TimeInterval = 4) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if check() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("timed out")
    }
}

// MARK: Fakes

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ e: String) { lock.withLock { list.append(e) } }
    func clear() { lock.withLock { list = [] } }
    var all: [String] { lock.withLock { list } }
}

final class FakeTask: RefreshTask {
    var expirationHandler: (() -> Void)?
    private(set) var completed: [Bool] = []
    func setTaskCompleted(success: Bool) { completed.append(success) }
}

final class FakeScheduler: RefreshScheduler {
    let events: Events
    private(set) var submitted: [BGAppRefreshTaskRequest] = []
    init(events: Events) { self.events = events }
    func submit(_ taskRequest: BGTaskRequest) throws {
        events.add("submit")
        submitted.append(taskRequest as! BGAppRefreshTaskRequest)
    }
    func cancel(taskRequestWithIdentifier identifier: String) { events.add("cancel") }
}

/// Holds a request until opened.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { c in
            let go = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiting.append(c)
                return false
            }
            if go { c.resume() }
        }
    }
    func open() {
        let w = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        w.forEach { $0.resume() }
    }
}

/// A transport that never answers usefully (for reopening a folder).
struct DeadTransport: SyncTransport {
    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome { .transient("offline") }
}

/// An in-memory `/v1/sync`: a bearer token, `from`, op-id dedup, and the log from `from` in one page. Hashes are
/// stand-ins (the client only echoes them).
final class MiniServer: SyncTransport, @unchecked Sendable {
    private struct Entry { var seq: Int; var id: String; var text: Data; var hash: String }
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var ids: Set<String> = []
    let events: Events
    var gate: Gate?
    init(events: Events) { self.events = events }

    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        events.add("sync")
        if let gate { await gate.wait() }
        let (status, data) = lock.withLock { handle(body, token: config.token) }
        return HTTPSyncTransport.classify(status: status, body: data)
    }

    private func handle(_ body: Data, token: String) -> (Int, Data) {
        guard token == "test-token" else { return (401, Data(#"{"error":"bad_token","message":"stub"}"#.utf8)) }
        guard let request = try? JSONDecoder().decode(SyncRequest.self, from: body),
              let raw = try? JSONSlices.arrayElements(named: "ops", in: body),
              request.from <= entries.count else { return (400, Data(#"{"error":"bad_request","message":"stub"}"#.utf8)) }
        for (op, text) in zip(request.ops, raw) where ids.insert(op.id).inserted {
            entries.append(Entry(seq: entries.count, id: op.id, text: text, hash: "h\(entries.count)"))
        }
        var out = Data(#"{"entries":["#.utf8)
        for e in entries[request.from...] {
            if e.seq > request.from { out.append(UInt8(ascii: ",")) }
            out.append(Data(#"{"seq":\#(e.seq),"received":1761811261234,"hash":"\#(e.hash)","op":"#.utf8))
            out.append(e.text)
            out.append(UInt8(ascii: "}"))
        }
        out.append(Data(#"],"head":\#(entries.count),"more":false}"#.utf8))
        return (200, out)
    }
}
