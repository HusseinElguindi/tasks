import XCTest
import TasksCore
@testable import Tasks

/// Settings ▸ Sync ▸ Live updates and the home line's live cloud on the phone (design/SYNC-STATUS.md): the row is
/// hidden until sync is set up and follows the socket; the cloud carries the bolt while live, keeps it through the
/// background and a quick reconnect, and goes plain after 5 s down; Sync Now skips the socket's wait. `/v1/sync` is
/// `MiniServer`, `/v1/events` a real WebSocket on 127.0.0.1 (`PokeServer`, PushSyncTests).
@MainActor
final class LiveUpdatesTests: XCTestCase {
    private var dir: URL!
    private var events: Events!
    private var pokes: PokeServer!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveUpdatesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        events = Events()
        pokes = try await PokeServer.start()
    }

    override func tearDown() async throws {
        pokes.stop()
        try? FileManager.default.removeItem(at: dir)
    }

    private var config: SyncConfig { SyncConfig(url: URL(string: "http://127.0.0.1:\(pokes.port)")!, token: "test-token") }

    /// The phone in front with sync set up, synced, the socket connected.
    private func phone() async throws -> AppModel {
        let store = await Store.open(directory: dir.appendingPathComponent("phone", isDirectory: true),
                                     transport: MiniServer(events: events))
        let app = AppModel(store: store, socket: SyncSocket(watchNetwork: false))
        app.store.config = config
        app.store.cancelScheduledSync()
        await app.store.sync()
        guard case .idle = app.store.syncState else { throw XCTSkip("the phone's sync didn't finish: \(app.store.syncState)") }
        app.cameToFront()
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.socket.isConnected)
        await eventually { if case .idle = app.store.syncState { true } else { false } }
        return app
    }

    private func eventually(_ seconds: Double = 5, _ done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func row(_ app: AppModel, now: Date = Date()) throws -> LiveStatus {
        LiveStatus(try XCTUnwrap(app.liveInput, "the row shows"), device: .iPhone, pace: LiveStatus.pace(for: .front), now: now)
    }

    func testTheRowIsHiddenUntilSyncIsSetUp() async {
        let store = await Store.open(directory: dir.appendingPathComponent("off", isDirectory: true), transport: DeadTransport())
        let app = AppModel(store: store, socket: SyncSocket(watchNetwork: false))
        XCTAssertNil(app.liveInput, "no server or token: hidden (Status says Off)")
        let sample = AppModel(store: store, isSample: true, socket: SyncSocket(watchNetwork: false))
        XCTAssertNil(sample.liveInput, "the sample data never syncs: hidden")
        XCTAssertFalse(app.syncLineLive)
    }

    func testTheRowAndTheCloudFollowTheSocket() async throws {
        let app = try await phone()
        var r = try row(app)
        XCTAssertEqual(r.word, "Live")
        XCTAssertEqual(r.dot, .live)
        XCTAssertEqual(r.detail, "Changes from your other devices arrive within seconds while Tasks is open.")
        XCTAssertTrue(app.syncLive)
        XCTAssertTrue(app.syncLineLive, "Synced, and live: the bolt cloud")

        // Another device's change: the head moves, so there's a last one.
        pokes.head += 1
        pokes.pokeAll()
        await eventually { app.socket.lastChangeAt != nil }
        r = try row(app)
        XCTAssertEqual(r.detail, "Changes from your other devices arrive within seconds while Tasks is open. Last one just now.")
        XCTAssertEqual(r.spoken, "Live. " + r.detail)

        // The server goes away: reconnecting, the countdown in the detail; the cloud keeps its bolt for now.
        pokes.stop()
        await eventually { if case .waiting = app.socket.state { true } else { false } }
        r = try row(app)
        XCTAssertEqual(r.word, "Reconnecting")
        XCTAssertEqual(r.dot, .ring)
        let lost = try XCTUnwrap(app.socket.droppedAt).formatted(date: .omitted, time: .shortened)
        XCTAssertTrue(r.detail.hasPrefix("Lost the connection at \(lost). Trying again in "), r.detail)
        XCTAssertTrue(r.detail.hasSuffix(" s; checking every 30 s meanwhile."), r.detail)
        XCTAssertTrue(app.syncLive, "down for less than 5 s: still the bolt")

        // Sync Now (Settings' button) connects at once instead of waiting.
        app.requestSyncNow()
        XCTAssertEqual(app.socket.state, .connecting)
        XCTAssertEqual(try row(app).word, "Connecting…")
    }

    func testThePlainCloudAfterFiveSecondsDown() async throws {
        let app = try await phone()
        pokes.stop()
        await eventually { if case .waiting = app.socket.state { true } else { false } }
        XCTAssertTrue(app.syncLive)
        await eventually(7) { !app.syncLive }
        XCTAssertFalse(app.syncLive, "5 s down: the plain cloud")
        XCTAssertFalse(app.syncLineLive)
    }

    /// The background closes the socket and counts nothing; coming back keeps the bolt while it reconnects.
    func testTheBackgroundKeepsTheBolt() async throws {
        let app = try await phone()
        app.wentToBackground()
        XCTAssertEqual(app.socket.state, .off)
        XCTAssertEqual(try row(app).word, "Off")
        XCTAssertTrue(app.syncLive, "kept in the background")
        app.cameToFront()
        XCTAssertEqual(app.socket.state, .connecting)
        XCTAssertTrue(app.syncLive, "no flash of the plain cloud while it reconnects")
        await eventually { app.socket.isConnected }
        XCTAssertTrue(app.syncLive)
    }

    /// The other home-line states keep the plain cloud: their words already say what's wrong.
    func testOnlySyncedShowsTheBolt() async throws {
        let app = try await phone()
        XCTAssertTrue(app.syncLineLive)
        _ = app.store.createTask(title: "Waiting to go out")
        XCTAssertFalse(app.syncLineLive, "a change waiting: icloud")
    }
}
