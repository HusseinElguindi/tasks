import XCTest
@testable import TasksCore

/// `SyncSocket` against a real server: the Worker under a local `wrangler dev` (never the deployed one).
///
///     TASKS_LIVE_URL=http://127.0.0.1:8797 TASKS_LIVE_TOKEN=… swift test --filter LiveSocketTests
///
/// Connects, hears another client's push, and checks what a bad token, an old server (no `/v1/events`) and a dead
/// port do. The log on that server grows by a few ops each run.
@MainActor
final class LiveSocketTests: XCTestCase {
    var dirs: [URL] = []
    var sockets: [SyncSocket] = []

    override func tearDown() async throws {
        for s in sockets { s.update(config: nil, hold: false) }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func config() throws -> SyncConfig {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["TASKS_LIVE_URL"].flatMap(URL.init(string:)), let token = e["TASKS_LIVE_TOKEN"] else {
            throw XCTSkip("Set TASKS_LIVE_URL and TASKS_LIVE_TOKEN to run against wrangler dev.")
        }
        guard ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            throw XCTSkip("Live tests only run against a local wrangler dev, never a deployed server.")
        }
        return SyncConfig(url: url, token: token)
    }

    func socket(pingInterval: Double = SocketPolicy.pingInterval) -> (SyncSocket, Recorder) {
        let s = SyncSocket(watchNetwork: false, pingInterval: pingInterval)
        let r = Recorder()
        s.onHead = { r.heads.append($0) }
        s.onState = { r.states.append($0) }
        sockets.append(s)
        return (s, r)
    }

    final class Recorder {
        var heads: [Int] = []
        var states: [SyncSocket.State] = []
    }

    func eventually(_ seconds: Double = 5, _ done: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func store(_ config: SyncConfig) -> Store {
        let d = tempDirectory("live-socket-\(dirs.count)")
        dirs.append(d)
        let p = Persistence(directory: d)
        let s = Store(loaded: p.loadSync(), persistence: p, transport: HTTPSyncTransport())
        s.config = config
        s.cancelScheduledSync()
        return s
    }

    func testConnectsAndHearsAnotherClientsPush() async throws {
        let config = try config()
        let writer = store(config)
        await writer.sync()
        let (s, r) = socket()
        s.update(config: config, hold: true)
        await eventually { s.isConnected }
        XCTAssertEqual(s.state, .connected)
        XCTAssertEqual(r.heads, [writer.cursor], "the head at once on connect")

        // Another client pushes: the poke arrives with the new head.
        var latencies: [Double] = []
        for i in 0..<5 {
            writer.createTask(title: "Live socket \(i)")
            writer.cancelScheduledSync()
            let before = r.heads.count
            let t0 = Date()
            await writer.sync()
            await eventually { r.heads.count > before }
            latencies.append(Date().timeIntervalSince(t0) * 1000)
            XCTAssertEqual(r.heads.last, writer.cursor)
        }
        print("push → poke (ms, from the start of the writer's sync):", latencies.map { Int($0.rounded()) })

        // Holding off closes it; holding again connects again and gets the head.
        s.update(config: config, hold: false)
        XCTAssertEqual(s.state, .off)
        s.update(config: config, hold: true)
        await eventually { s.isConnected }
        XCTAssertEqual(r.heads.last, writer.cursor)
        XCTAssertEqual(r.states.filter { $0 == .connected }.count, 2)
    }

    /// The server (workerd) answers protocol pings, so the socket stays up through them.
    func testPingsGetPongs() async throws {
        let config = try config()
        let (s, r) = socket(pingInterval: 0.1)
        s.update(config: config, hold: true)
        await eventually { s.pongs >= 5 }
        XCTAssertGreaterThanOrEqual(s.pongs, 5)
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(r.states.filter { $0 == .connected }.count, 1, "no reconnect")
    }

    func testABadTokenStopsUntilTheTokenChanges() async throws {
        let good = try config()
        let (s, r) = socket()
        s.update(config: SyncConfig(url: good.url, token: "not-the-token"), hold: true)
        await eventually { s.state == .stopped }
        XCTAssertEqual(s.state, .stopped)
        XCTAssertEqual(r.heads, [])
        s.reconnectNow()
        XCTAssertEqual(s.state, .stopped, "a wake doesn't retry a refused token")
        s.update(config: good, hold: true)
        await eventually { s.isConnected }
        XCTAssertTrue(s.isConnected, "a new token connects")
    }

    func testAnOldServerWaitsAnHour() async throws {
        let good = try config()
        // No /v1/events under this prefix: a 404, as from a server without the route.
        let (s, _) = socket()
        s.update(config: SyncConfig(url: good.url.appendingPathComponent("old"), token: good.token), hold: true)
        await eventually { if case .waiting = s.state { true } else { false } }
        guard case .waiting(let after) = s.state else { return XCTFail("\(s.state)") }
        XCTAssertGreaterThanOrEqual(after, 3600 * 0.8)
        XCTAssertLessThanOrEqual(after, 3600 * 1.2)
    }

    func testADeadPortBacksOffFromASecond() async throws {
        let good = try config()
        let (s, r) = socket()
        s.update(config: SyncConfig(url: URL(string: "http://127.0.0.1:9")!, token: good.token), hold: true)
        await eventually { if case .waiting = s.state { true } else { false } }
        guard case .waiting(let first) = s.state else { return XCTFail("\(s.state)") }
        XCTAssertEqual(first, 1, accuracy: 0.2 + 1e-9)
        // It tries again on its own, and backs off further.
        await eventually(4) { r.states.filter { if case .waiting = $0 { true } else { false } }.count >= 2 }
        let waits = r.states.compactMap { if case .waiting(let w) = $0 { w } else { nil } }
        XCTAssertGreaterThanOrEqual(waits.count, 2)
        if waits.count >= 2 { XCTAssertEqual(waits[1], 2, accuracy: 0.4 + 1e-9) }
        // A wake or a network change skips the wait.
        s.reconnectNow()
        XCTAssertEqual(s.state, .connecting)
    }
}
