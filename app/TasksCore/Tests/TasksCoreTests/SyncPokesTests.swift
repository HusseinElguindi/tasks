import XCTest
@testable import TasksCore

/// A `StubServer` whose replies wait `delay` first, so a test can poke while a sync is in flight.
final class SlowServer: SyncTransport, @unchecked Sendable {
    let server: StubServer
    let delay: Duration

    init(_ server: StubServer, delay: Duration) {
        self.server = server
        self.delay = delay
    }

    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        try? await Task.sleep(for: delay)
        return await server.send(body, config: config)
    }
}

/// Pokes and nudges into syncs (design/PUSH-SYNC.md §3, `SyncPokes`, `Store.syncIfBehind`): a head the store already
/// has asks for nothing, a poke during a sync is checked once it ends, a burst is one sync, a nudge always syncs.
@MainActor
final class SyncPokesTests: XCTestCase {
    var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func makeStore(_ transport: SyncTransport) -> Store {
        let d = tempDirectory("pokes-\(dirs.count)")
        dirs.append(d)
        let p = Persistence(directory: d)
        let t0 = SyncTests.t0
        let store = Store(loaded: p.loadSync(), persistence: p, transport: transport,
                          clock: StoreClock(now: { t0 }, calendar: TodayTests().cal))
        store.config = SyncConfig(url: URL(string: "http://stub.invalid")!, token: "test-token")
        store.cancelScheduledSync()
        return store
    }

    /// Waits until `done()` or about two seconds.
    func eventually(_ done: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Two stores on one server, both synced: `b` is the other device, `a` the one being poked.
    func twoDevices(_ server: StubServer) async -> (Store, Store) {
        let a = makeStore(server)
        let b = makeStore(server)
        await a.sync()
        await b.sync()
        await a.sync()
        return (a, b)
    }

    func testAHeadTheStoreHasAsksForNothing() async {
        let server = StubServer()
        let (a, _) = await twoDevices(server)
        let requests = server.rawRequests.count
        XCTAssertEqual(a.cursor, server.head)
        let asked = await a.syncIfBehind(head: server.head)
        XCTAssertFalse(asked)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(server.rawRequests.count, requests)
    }

    func testAHeadPastTheCursorSyncs() async {
        let server = StubServer()
        let (a, b) = await twoDevices(server)
        let id = b.createTask(title: "From B")!
        await b.sync()
        XCTAssertGreaterThan(server.head, a.cursor)
        let asked = await a.syncIfBehind(head: server.head)
        XCTAssertTrue(asked)
        await eventually { a.cursor == server.head }
        XCTAssertEqual(a.projection.task(id)?.title, "From B")
    }

    func testAHeadBelowTheCursorSyncsSoTheRecoveryRuns() async {
        let server = StubServer()
        let (a, _) = await twoDevices(server)
        let asked = await a.syncIfBehind(head: a.cursor - 1)
        XCTAssertTrue(asked, "the server lost entries (a restore): the 409 recovers it")
    }

    func testANudgeAlwaysSyncs() async {
        let server = StubServer()
        let (a, _) = await twoDevices(server)
        let requests = server.rawRequests.count
        let asked = await a.syncIfBehind(head: nil)
        XCTAssertTrue(asked)
        await eventually { server.rawRequests.count > requests }
        XCTAssertEqual(server.rawRequests.count, requests + 1)
    }

    /// The writer's own poke usually arrives before its sync's reply: it's checked once that sync ends, and by then
    /// the cursor is at the head, so it costs nothing.
    func testAPokeDuringASyncWaitsForItThenChecksOnce() async {
        let server = StubServer()
        let slow = SlowServer(server, delay: .milliseconds(200))
        let a = makeStore(slow)
        let b = makeStore(server)
        await a.sync()
        await b.sync()
        await a.sync()
        let requests = server.rawRequests.count
        a.createTask(title: "From A")
        a.cancelScheduledSync()
        let running = Task { await a.sync() }
        try? await Task.sleep(for: .milliseconds(50))
        // The push is in flight; the server already has the op in a moment, and pokes with the new head.
        let head = server.head + 1
        let asked = await a.syncIfBehind(head: head)
        XCTAssertFalse(asked, "the sync in flight brought the cursor to the head")
        XCTAssertEqual(a.cursor, head)
        await running.value
        XCTAssertEqual(server.rawRequests.count, requests + 1, "one request: the push")

        // From another device during a sync: checked after it, and one more sync fetches it.
        b.createTask(title: "From B")
        await b.sync()
        a.createTask(title: "Again from A")
        a.cancelScheduledSync()
        let again = Task { await a.sync() }
        try? await Task.sleep(for: .milliseconds(50))
        let behind = server.head + 5 // a head this sync won't reach: still behind once it ends
        let asked2 = await a.syncIfBehind(head: behind)
        XCTAssertTrue(asked2)
        await again.value
    }

    // MARK: SyncPokes

    func testABurstOfPokesAndNudgesIsOneSync() async {
        let server = StubServer()
        let (a, b) = await twoDevices(server)
        let pokes = SyncPokes(store: a, debounce: SyncNudge.Debounce(quiet: 0.05, cap: 1))
        var log: [String] = []
        pokes.log = { log.append($0) }
        b.createTask(title: "1")
        await b.sync()
        let requests = server.rawRequests.count
        for i in 0..<5 {
            pokes.poke(head: server.head - 1 + i % 2)
            pokes.nudge()
            try? await Task.sleep(for: .milliseconds(10))
        }
        await eventually { !log.isEmpty }
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(log, ["sync requested"])
        await eventually { a.cursor == server.head }
        XCTAssertEqual(server.rawRequests.count, requests + 1)
    }

    func testFiringKeepsTheHighestHead() async {
        let server = StubServer()
        let (a, b) = await twoDevices(server)
        let pokes = SyncPokes(store: a, debounce: SyncNudge.Debounce(quiet: 10, cap: 10))
        var log: [String] = []
        pokes.log = { log.append($0) }
        b.createTask(title: "1")
        await b.sync()
        pokes.poke(head: server.head)
        pokes.poke(head: a.cursor) // an older poke heard later doesn't hide the newer head
        await pokes.fire()
        XCTAssertEqual(log, ["sync requested"])
        // Nothing waiting now: a poke at the head the store reached asks for nothing.
        await eventually { a.cursor == server.head }
        pokes.poke(head: a.cursor)
        await pokes.fire()
        XCTAssertEqual(log, ["sync requested", "up to date"])
    }
}
