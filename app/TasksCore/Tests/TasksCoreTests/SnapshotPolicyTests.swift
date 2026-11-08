import XCTest
@testable import TasksCore

/// When `snapshot.json` is written (spec §8 "When it's written", `SnapshotPolicy`): on `persistNow`, when the tail
/// reaches the limit, or by the timer; never just because a sync applied entries.
@MainActor
final class SnapshotPolicyTests: XCTestCase {
    var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func makeStore(_ server: StubServer, dir: URL? = nil, policy: SnapshotPolicy = .standard) -> Store {
        let d = dir ?? tempDirectory("snapshot-\(dirs.count)")
        if dir == nil { dirs.append(d) }
        let p = Persistence(directory: d)
        let t0 = SyncTests.t0
        let store = Store(loaded: p.loadSync(), persistence: p, transport: server,
                          clock: StoreClock(now: { t0 }, calendar: TodayTests().cal), snapshotPolicy: policy)
        store.config = SyncConfig(url: URL(string: "http://stub.invalid")!, token: "test-token")
        store.cancelScheduledSync()
        return store
    }

    /// An edit that comes back from the server as a log entry: one more entry in the tail.
    func edit(_ store: Store, _ title: String) async {
        store.createTask(title: title)
        store.cancelScheduledSync()
        await store.sync()
    }

    /// The snapshot's bytes and its cursor, or nil if there's none, after queued writes.
    func snapshot(_ store: Store) throws -> (data: Data, cursor: Int, modified: Date)? {
        store.persistence.flush()
        let url = store.persistence.snapshotURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        return (data, try XCTUnwrap(json["cursor"] as? Int), modified)
    }

    /// Waits up to `limit` for the main actor's timer to have written a snapshot at `cursor`.
    func waitForSnapshot(_ store: Store, at cursor: Int, within limit: Duration = .seconds(5)) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if try snapshot(store)?.cursor == cursor { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func testNoSnapshotWritePerSync() async throws {
        let server = StubServer()
        let store = makeStore(server)
        await edit(store, "first")
        store.persistNow()
        let before = try XCTUnwrap(snapshot(store))
        XCTAssertEqual(before.cursor, store.cursor)

        for i in 0..<10 { await edit(store, "edit \(i)") }
        XCTAssertEqual(store.cursor, before.cursor + 10)
        // Past the old 5 s debounce: nothing writes before 10 min or 500 entries.
        try await Task.sleep(for: .milliseconds(5500))
        let after = try XCTUnwrap(snapshot(store))
        XCTAssertEqual(after.data, before.data, "a sync that applied entries didn't rewrite the snapshot")
        XCTAssertEqual(after.modified, before.modified)
        XCTAssertEqual(store.snapshotCursor, before.cursor)

        // Resign active / quit still writes it.
        store.persistNow()
        XCTAssertEqual(try snapshot(store)?.cursor, store.cursor)
    }

    func testSnapshotOnceTheTailReachesTheLimit() async throws {
        let server = StubServer()
        let store = makeStore(server, policy: SnapshotPolicy(tailLimit: 5, interval: .seconds(3600)))
        await edit(store, "a") // the Inbox seed and this: 2 entries
        XCTAssertEqual(store.cursor, 2)
        await edit(store, "b")
        await edit(store, "c")
        XCTAssertEqual(store.cursor, 4)
        XCTAssertNil(try snapshot(store), "a tail of 4 is under the limit")
        await edit(store, "d")
        XCTAssertEqual(try snapshot(store)?.cursor, 5, "the tail reached 5")
        XCTAssertEqual(store.snapshotCursor, 5)
        // The count starts again from there.
        for t in ["e", "f", "g", "h"] { await edit(store, t) }
        XCTAssertEqual(try snapshot(store)?.cursor, 5)
        await edit(store, "i")
        XCTAssertEqual(try snapshot(store)?.cursor, 10)

        // One sync that brings more than the limit at once (another device's batch) writes once, at its end.
        let other = makeStore(server, policy: SnapshotPolicy(tailLimit: 5, interval: .seconds(3600)))
        other.cancelScheduledSync()
        await other.sync()
        XCTAssertEqual(try snapshot(other)?.cursor, server.head)
    }

    func testTimerWritesANonEmptyTail() async throws {
        let server = StubServer()
        let store = makeStore(server, policy: SnapshotPolicy(tailLimit: 500, interval: .milliseconds(200)))
        // Nothing to write: no tail, no timer, no snapshot.
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(try snapshot(store))

        await edit(store, "a")
        XCTAssertNil(try snapshot(store), "not at once")
        let firstTail = store.cursor
        let written = try await waitForSnapshot(store, at: firstTail)
        XCTAssertTrue(written, "the timer wrote the tail")
        XCTAssertEqual(store.snapshotCursor, firstTail)

        // Syncs that keep landing don't postpone it: it fires one interval after the first unsnapshotted entry, in
        // the middle of this burst. A timer restarted by each sync would fire only 200 ms after the last one, and the
        // snapshot is read 60 ms after it, so it would still be at `firstTail`. (It may already hold the whole burst:
        // the burst outlasts two intervals, so a second write can land just after the last edit. That's fine, and
        // asserting it doesn't made this test flaky.)
        for i in 0..<8 {
            await edit(store, "edit \(i)")
            try await Task.sleep(for: .milliseconds(60))
        }
        let mid = try XCTUnwrap(snapshot(store)).cursor
        XCTAssertGreaterThan(mid, firstTail, "written during the burst")
        let ok = try await waitForSnapshot(store, at: store.cursor)
        XCTAssertTrue(ok, "and again for the rest of the burst")

        // And once the tail is empty again it stays quiet.
        let quiet = try XCTUnwrap(snapshot(store))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(try snapshot(store)?.modified, quiet.modified)
    }

    /// A crash (no `persistNow`) with a long tail: launch replays it to the state the app had, the same as a full
    /// replay, and pending ops survive.
    func testCrashWithALongTailReplaysToTheSameState() async throws {
        let server = StubServer()
        let dir = tempDirectory("snapshot-crash")
        dirs.append(dir)
        var store: Store? = makeStore(server, dir: dir)
        await edit(store!, "before the snapshot")
        store!.persistNow()
        let snapCursor = store!.cursor
        for i in 0..<450 { store!.createTask(title: "task \(i)") }
        store!.cancelScheduledSync()
        await store!.sync()
        let list = store!.createList(name: "Later")
        for t in store!.projection.openTasks(in: Seed.inboxListID).ids.prefix(30) { store!.setTitle(t, "renamed \(t)") }
        store!.cancelScheduledSync()
        await store!.sync()
        store!.createTask(title: "still pending", in: list)
        store!.cancelScheduledSync()
        let expectedConfirmed = store!.projection.confirmed
        let expectedCursor = store!.cursor
        let expectedPending = store!.projection.pending.map(\.op)
        XCTAssertEqual(expectedCursor - snapCursor, 481, "a tail under the limit: no snapshot since")
        // The crash: the queued file writes reached the disk, the snapshot was never rewritten.
        store!.persistence.flush()
        XCTAssertEqual(try snapshot(store!)?.cursor, snapCursor)
        store = nil

        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.source, .snapshot(tail: 481))
        XCTAssertEqual(loaded.cursor, expectedCursor)
        XCTAssertEqual(loaded.confirmed, expectedConfirmed)
        XCTAssertEqual(loaded.pending.map(\.op), expectedPending)

        let reopened = makeStore(server, dir: dir)
        XCTAssertEqual(reopened.projection.confirmed, expectedConfirmed)
        XCTAssertEqual(reopened.snapshotCursor, snapCursor, "the tail is still under the limit")
        assertMatchesRebuild(reopened.projection, "reopened")
        await reopened.sync()
        XCTAssertTrue(reopened.projection.pending.isEmpty)
        XCTAssertEqual(reopened.cursor, server.head)

        // The same files without the snapshot: a full replay gives the same state.
        reopened.persistence.flush()
        try FileManager.default.removeItem(at: reopened.persistence.snapshotURL)
        let replayed = Persistence(directory: dir).loadSync()
        XCTAssertEqual(replayed.source, .fullReplay(reason: "no snapshot"))
        XCTAssertEqual(replayed.confirmed, reopened.projection.confirmed)
    }

    /// Launch with a tail at or past the limit (a crash after a long session) writes the snapshot at once.
    func testLaunchWithATailPastTheLimitWritesTheSnapshot() async throws {
        let server = StubServer()
        let store = makeStore(server)
        await edit(store, "a")
        store.persistNow()
        for i in 0..<20 { store.createTask(title: "t\(i)") }
        store.cancelScheduledSync()
        await store.sync()
        store.persistence.flush()
        let dir = store.persistence.directory
        XCTAssertEqual(Persistence(directory: dir).loadSync().source, .snapshot(tail: 20))

        let reopened = makeStore(server, dir: dir, policy: SnapshotPolicy(tailLimit: 10, interval: .seconds(3600)))
        XCTAssertEqual(try snapshot(reopened)?.cursor, reopened.cursor)
        XCTAssertEqual(Persistence(directory: dir).loadSync().source, .snapshot(tail: 0))
    }
}
