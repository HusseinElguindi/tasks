import BackgroundTasks
import Network
import XCTest
import TasksCore
@testable import Tasks

/// The poke socket on the phone (Sync.swift, design/PUSH-SYNC.md): coming to the front connects and catches up, a poke
/// while in front syncs, going to the background closes it (`.goingAway`), the background refresh never opens it,
/// and the periodic sync slows to 5 min while it's up. `/v1/sync` is `MiniServer` (in process); `/v1/events` is a real
/// WebSocket on 127.0.0.1 (`PokeServer`), so the phone's `SyncSocket` runs as it does against the Worker.
@MainActor
final class PushSyncTests: XCTestCase {
    private var dir: URL!
    private var events: Events!
    private var pokes: PokeServer!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PushSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        events = Events()
        pokes = try await PokeServer.start()
    }

    override func tearDown() async throws {
        pokes.stop()
        try? FileManager.default.removeItem(at: dir)
    }

    private var config: SyncConfig { SyncConfig(url: URL(string: "http://127.0.0.1:\(pokes.port)")!, token: "test-token") }

    private func store(_ name: String, _ transport: SyncTransport) async -> Store {
        await Store.open(directory: dir.appendingPathComponent(name, isDirectory: true), transport: transport)
    }

    /// "The Mac": writes and syncs at once, and tells the poke server its new head, as the Worker does after a push.
    private func mac(_ server: MiniServer) async -> Store {
        let mac = await store("mac", server)
        mac.config = config
        mac.cancelScheduledSync()
        return mac
    }

    @discardableResult
    private func macAdds(_ mac: Store, _ title: String, poke: Bool) async throws -> EntityID {
        let id = try XCTUnwrap(mac.createTask(title: title))
        mac.cancelScheduledSync()
        await mac.sync()
        guard case .idle = mac.syncState else { throw XCTSkip("the Mac's sync didn't finish: \(mac.syncState)") }
        pokes.head = mac.cursor
        if poke { pokes.pokeAll() }
        return id
    }

    /// The phone's AppModel in the background (as after a background launch), synced up to now, the socket off.
    private func phone(_ server: MiniServer) async throws -> AppModel {
        let app = AppModel(store: await store("phone", server), socket: SyncSocket(watchNetwork: false))
        app.inFront = false
        app.store.config = config
        app.store.cancelScheduledSync()
        await app.store.sync()
        guard case .idle = app.store.syncState else { throw XCTSkip("the phone's sync didn't finish: \(app.store.syncState)") }
        return app
    }

    private func eventually(_ seconds: Double = 5, _ done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testComingToTheFrontConnectsAndCatchesUp() async throws {
        let server = MiniServer(events: events)
        let mac = await mac(server)
        try await macAdds(mac, "Before the phone", poke: false)
        let app = try await phone(server)
        // Written while the phone is in the background: nobody pokes it.
        let id = try await macAdds(mac, "While the phone was away", poke: true)
        XCTAssertNil(app.task(id))
        XCTAssertEqual(pokes.connections, 0, "no socket in the background")

        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertEqual(app.socket.state, .connected)
        XCTAssertEqual(pokes.connections, 1)
        XCTAssertEqual(pokes.tokens, ["Bearer test-token"], "the token on the upgrade")
        await eventually { app.task(id) != nil }
        XCTAssertNotNil(app.task(id), "caught up")
        XCTAssertEqual(app.store.cursor, mac.cursor)
    }

    func testAPokeWhileInFrontSyncsWithinTwoSeconds() async throws {
        let server = MiniServer(events: events)
        let mac = await mac(server)
        let app = try await phone(server)
        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.socket.isConnected)
        // Let the front's own sync and the first head's check settle.
        await eventually(3) { app.store.cursor == mac.cursor && app.store.syncState != .syncing }
        try? await Task.sleep(for: .seconds(1))

        var latencies: [Double] = []
        for i in 0..<3 {
            let t0 = Date()
            let id = try await macAdds(mac, "Poked \(i)", poke: true)
            await eventually(4) { app.task(id) != nil }
            XCTAssertNotNil(app.task(id), "the poke synced")
            latencies.append(Date().timeIntervalSince(t0))
        }
        print("push latency (Mac sync → phone has it), s: \(latencies.map { String(format: "%.3f", $0) })")
        XCTAssertLessThan(latencies.max()!, 2, "\(latencies)")

        // The phone's own head: no sync.
        try? await Task.sleep(for: .seconds(1))
        events.clear()
        pokes.pokeAll()
        try? await Task.sleep(for: .seconds(1.5))
        XCTAssertFalse(events.all.contains("sync"), "a head the phone has asks for nothing: \(events.all)")
    }

    func testGoingToTheBackgroundClosesTheSocket() async throws {
        let server = MiniServer(events: events)
        let app = try await phone(server)
        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.socket.isConnected)

        app.wentToBackground()
        XCTAssertEqual(app.socket.state, .off)
        await eventually { !pokes.closes.isEmpty }
        XCTAssertEqual(pokes.closes, [1001], "closed with .goingAway")

        // Back to the front: a new connection at once.
        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.socket.isConnected)
        XCTAssertEqual(pokes.connections, 2)
    }

    func testTheBackgroundRefreshLeavesTheSocketAlone() async throws {
        let server = MiniServer(events: events)
        let mac = await mac(server)
        let app = try await phone(server)
        let id = try await macAdds(mac, "For the refresh", poke: true)
        let config = config
        let r = BackgroundRefresh(scheduler: FakeScheduler(events: events),
                                  history: RefreshHistory(directory: dir.appendingPathComponent("docs")),
                                  open: { app }, config: { _ in config })
        await r.handle(FakeTask())
        XCTAssertNotNil(app.task(id), "the refresh synced")
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(app.socket.state, .off, "in the background the refresh opens no socket")
        XCTAssertEqual(pokes.connections, 0)

        // In front with the socket up, a refresh (a launch-argument one, say) doesn't close or reopen it.
        app.cameToFront()
        await eventually { app.socket.isConnected }
        await r.handle(FakeTask())
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(app.socket.isConnected)
        XCTAssertEqual(pokes.connections, 1)
        XCTAssertEqual(pokes.closes, [])
    }

    /// `SocketPolicy.pollDue`: every 30 s tick syncs while the socket is down, every 5 min while it's up, none away.
    func testThePeriodicSyncSlowsWhileTheSocketIsUp() async throws {
        let server = MiniServer(events: events)
        let app = try await phone(server)
        app.inFront = true
        app.pollTick(now: 1000)
        XCTAssertEqual(app.lastPoll, 1000, "the first tick syncs")
        app.pollTick(now: 1030)
        XCTAssertEqual(app.lastPoll, 1030, "socket down: every 30 s")

        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.socket.isConnected)
        for t in stride(from: 1060.0, through: 1300, by: 30) { app.pollTick(now: t) }
        XCTAssertEqual(app.lastPoll, 1030, "socket up: nothing for 5 min")
        app.pollTick(now: 1330)
        XCTAssertEqual(app.lastPoll, 1330, "then the safety net")

        app.wentToBackground()
        app.pollTick(now: 2000)
        XCTAssertEqual(app.lastPoll, 1330, "nothing in the background")
    }
}

/// A WebSocket server on 127.0.0.1 standing in for the Worker's `/v1/events`: says `{"head":N}` when a socket
/// connects and on `pokeAll`, and records each upgrade's Authorization header and each close code.
final class PokeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var open: [NWConnection] = []
    private var _head = 0
    private var _connections = 0
    private var _closes: [Int] = []
    private(set) var port: UInt16 = 0

    var head: Int {
        get { lock.withLock { _head } }
        set { lock.withLock { _head = newValue } }
    }
    var connections: Int { lock.withLock { _connections } }
    var tokens: [String] { upgrades.lock.withLock { upgrades.tokens } }
    var closes: [Int] { lock.withLock { _closes } }

    /// The upgrade's Authorization headers, filled by the handshake handler (set up before the listener exists).
    private let upgrades: Upgrades

    private final class Upgrades: @unchecked Sendable {
        let lock = NSLock()
        var tokens: [String] = []
    }

    private init() throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        let upgrades = Upgrades()
        let queue = DispatchQueue(label: "PokeServer")
        self.upgrades = upgrades
        self.queue = queue
        ws.setClientRequestHandler(queue) { _, headers in
            let auth = headers.first { $0.name.lowercased() == "authorization" }?.value ?? ""
            upgrades.lock.withLock { upgrades.tokens.append(auth) }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    static func start() async throws -> PokeServer {
        let server = try PokeServer()
        try await server.listen()
        return server
    }

    private func listen() async throws {
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            let once = OnceThrowing(k)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = self?.listener.port?.rawValue ?? 0
                    once.resume(nil)
                case .failed(let e): once.resume(e)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            if case .ready = state {
                self.lock.withLock {
                    self._connections += 1
                    self.open.append(c)
                }
                self.send(c)
                self.receive(c)
            }
        }
        c.start(queue: queue)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] _, context, _, error in
            guard let self else { return }
            let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if let meta, meta.opcode == .close {
                let code: Int = switch meta.closeCode {
                case .protocolCode(let p): Int(p.rawValue)
                case .applicationCode(let a): Int(a)
                case .privateCode(let p): Int(p)
                @unknown default: -1
                }
                self.ended(c, code: code)
                return
            }
            if error != nil {
                self.ended(c, code: nil)
                return
            }
            self.receive(c)
        }
    }

    private func ended(_ c: NWConnection, code: Int?) {
        lock.withLock {
            if let code { _closes.append(code) }
            open.removeAll { $0 === c }
        }
        c.cancel()
    }

    private func send(_ c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "poke", metadata: [meta])
        c.send(content: Data(#"{"head":\#(head)}"#.utf8), contentContext: context, isComplete: true,
               completion: .contentProcessed { _ in })
    }

    /// The Worker after a push: the new head to every open socket.
    func pokeAll() {
        let all = lock.withLock { open }
        queue.async { all.forEach(self.send) }
    }

    func stop() {
        let all = lock.withLock { open }
        all.forEach { $0.cancel() }
        listener.cancel()
    }
}

private final class OnceThrowing: @unchecked Sendable {
    private let lock = NSLock()
    private var k: CheckedContinuation<Void, Error>?
    init(_ k: CheckedContinuation<Void, Error>) { self.k = k }
    func resume(_ error: Error?) {
        let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in defer { k = nil }; return k }
        if let error { c?.resume(throwing: error) } else { c?.resume() }
    }
}
