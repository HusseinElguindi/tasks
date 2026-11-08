import Network
import XCTest
@testable import TasksCore

/// What `SyncSocket` publishes for Settings ▸ Sync ▸ Live updates (design/SYNC-STATUS.md §1), against a WebSocket on
/// 127.0.0.1 (`PokeServer`) and a dead port: when it connected, dropped and last heard a change, why it waits, and
/// Sync Now skipping the wait.
@MainActor
final class SyncSocketTests: XCTestCase {
    var server: PokeServer!
    var sockets: [SyncSocket] = []

    override func setUp() async throws {
        server = try await PokeServer.start()
    }

    override func tearDown() async throws {
        for s in sockets { s.update(config: nil, hold: false) }
        server.stop()
    }

    var config: SyncConfig { SyncConfig(url: URL(string: "http://127.0.0.1:\(server.port)")!, token: "t") }

    func socket() -> SyncSocket {
        let s = SyncSocket(watchNetwork: false, random: { 0.5 })
        sockets.append(s)
        return s
    }

    func eventually(_ seconds: Double = 5, _ done: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testConnectedAndTheLastChangeHeard() async throws {
        server.head = 4
        let s = socket()
        let before = Date()
        s.update(config: config, hold: true)
        await eventually { s.isConnected }
        XCTAssertEqual(s.state, .connected)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(s.connectedAt), before)
        XCTAssertNil(s.lastChangeAt, "the first message only says where the head is")
        XCTAssertNil(s.droppedAt)
        XCTAssertEqual(LiveStatus.kind(s.liveInput), .live)

        server.pokeAll() // the same head again
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(s.lastChangeAt, "a head that didn't move isn't a change")

        server.head = 5
        let poked = Date()
        server.pokeAll()
        await eventually { s.lastChangeAt != nil }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(s.lastChangeAt), poked)

        s.update(config: config, hold: false)
        XCTAssertEqual(s.state, .off)
        XCTAssertNil(s.connectedAt)
        XCTAssertNotNil(s.lastChangeAt, "kept while the settings are the same")
        s.update(config: SyncConfig(url: config.url, token: "other"), hold: false)
        XCTAssertNil(s.lastChangeAt, "new settings start over")
    }

    func testADropWaitsOutTheBackoffAndSyncNowSkipsIt() async throws {
        let s = socket()
        s.update(config: config, hold: true)
        await eventually { s.isConnected }
        let dropped = Date()
        server.dropAll()
        await eventually { if case .waiting = s.state { true } else { false } }
        guard case .waiting(let until, let why) = s.state else { return XCTFail("\(s.state)") }
        XCTAssertEqual(why, .dropped)
        XCTAssertEqual(until.timeIntervalSince(dropped), 1, accuracy: 0.5, "the first delay, 1 s")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(s.droppedAt), dropped)
        XCTAssertNil(s.connectedAt)
        XCTAssertEqual(LiveStatus.kind(s.liveInput), .reconnecting(at: until))

        // Sync Now: connects at once instead of waiting.
        let connections = server.connections
        s.retryNow()
        XCTAssertEqual(s.state, .connecting)
        await eventually { s.isConnected }
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(server.connections, connections + 1)

        // While live it leaves the connection alone.
        s.retryNow()
        XCTAssertEqual(s.state, .connected)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.connections, connections + 1, "no new connection")
    }

    func testAFailedTryThatNeverConnectedHasNoDropTime() async throws {
        let s = socket()
        s.update(config: SyncConfig(url: URL(string: "http://127.0.0.1:9")!, token: "t"), hold: true)
        await eventually { if case .waiting = s.state { true } else { false } }
        guard case .waiting(_, .dropped) = s.state else { return XCTFail("\(s.state)") }
        XCTAssertNil(s.droppedAt)
        let row = LiveStatus(s.liveInput, device: .mac(syncWithoutWindow: true), pace: 30, now: Date())
        XCTAssertEqual(row.detail, "Couldn't connect. Checking every 30 s meanwhile.")
        // Not held: Sync Now does nothing.
        s.update(config: SyncConfig(url: URL(string: "http://127.0.0.1:9")!, token: "t"), hold: false)
        s.retryNow()
        XCTAssertEqual(s.state, .off)
    }
}

/// A WebSocket server on 127.0.0.1 standing in for the Worker's `/v1/events` (the iPhone's PushSyncTests has its
/// twin): says `{"head":N}` when a socket connects and on `pokeAll`; `dropAll` cuts every connection.
final class PokeServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "PokeServer")
    private let lock = NSLock()
    private var open: [NWConnection] = []
    private var _head = 0
    private var _connections = 0
    private(set) var port: UInt16 = 0

    var head: Int {
        get { lock.withLock { _head } }
        set { lock.withLock { _head = newValue } }
    }
    var connections: Int { lock.withLock { _connections } }

    private init() throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
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
            let once = ResumeOnce(k)
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
            guard let self, let c, case .ready = state else { return }
            self.lock.withLock {
                self._connections += 1
                self.open.append(c)
            }
            self.send(c)
            self.receive(c)
        }
        c.start(queue: queue)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] _, _, _, error in
            guard let self else { return }
            if error != nil {
                self.lock.withLock { self.open.removeAll { $0 === c } }
                c.cancel()
                return
            }
            self.receive(c)
        }
    }

    private func send(_ c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "poke", metadata: [meta])
        c.send(content: Data(#"{"head":\#(head)}"#.utf8), contentContext: context, isComplete: true,
               completion: .contentProcessed { _ in })
    }

    func pokeAll() {
        let all = lock.withLock { open }
        queue.async { all.forEach(self.send) }
    }

    /// A deploy, or the network going: every connection cut without a close frame.
    func dropAll() {
        let all = lock.withLock { () -> [NWConnection] in defer { open = [] }; return open }
        all.forEach { $0.forceCancel() }
    }

    func stop() {
        dropAll()
        listener.cancel()
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var k: CheckedContinuation<Void, Error>?
    init(_ k: CheckedContinuation<Void, Error>) { self.k = k }
    func resume(_ error: Error?) {
        let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in defer { k = nil }; return k }
        if let error { c?.resume(throwing: error) } else { c?.resume() }
    }
}
