import CryptoKit
import XCTest
@testable import TasksCore

/// An in-memory `/v1/sync` with the server's rules (spec §5–§7): bearer token, validation basics, `base`/`from`
/// checks with a real SHA-256 hash chain, op-id dedup, contiguous appends, pages capped by count (and optionally
/// by op text size), plus knobs to inject failures, wipe it or restore it to an older point.
final class StubServer: SyncTransport, @unchecked Sendable {
    struct Entry { var seq: Int; var id: String; var text: Data; var hash: String }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var ids: Set<String> = []
    var token = "test-token"
    var pageLimit = 1000
    /// Stop a page once this many bytes of op text are in it (the server's 4M-character cap, scaled down).
    var pageBytes = Int.max
    var maxOps = 500
    /// Responses served before normal handling: (status, body).
    var queued: [(Int, Data)] = []
    /// Ops with these ids fail validation (`invalid_op` at `set.order`).
    var invalidIDs: Set<String> = []
    private(set) var requests: [SyncRequest] = []
    private(set) var rawRequests: [Data] = []

    var log: [Entry] { lock.withLock { entries } }
    var ops: [Op] { log.map { try! JSONDecoder().decode(Op.self, from: $0.text) } }
    var opIDs: Set<String> { lock.withLock { ids } }
    var head: Int { lock.withLock { entries.count } }

    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        let (status, data) = lock.withLock { handle(body, token: config.token) }
        return HTTPSyncTransport.classify(status: status, body: data)
    }

    func wipe() { lock.withLock { entries = []; ids = [] } }

    func restore(to k: Int) {
        lock.withLock {
            entries = Array(entries.prefix(k))
            ids = Set(entries.map(\.id))
        }
    }

    private func error(_ code: String, _ extra: String = "") -> Data {
        Data(#"{"error":"\#(code)","message":"stub"\#(extra)}"#.utf8)
    }

    private func handle(_ body: Data, token: String) -> (Int, Data) {
        rawRequests.append(body)
        if !queued.isEmpty { return queued.removeFirst() }
        guard token == self.token else { return (401, error("bad_token")) }
        guard let request = try? JSONDecoder().decode(SyncRequest.self, from: body),
              let rawOps = try? JSONSlices.arrayElements(named: "ops", in: body),
              (request.base == nil) == (request.from == 0) else { return (400, error("bad_request")) }
        requests.append(request)
        guard rawOps.count <= maxOps else { return (413, error("too_large")) }
        for (i, op) in request.ops.enumerated() where invalidIDs.contains(op.id) {
            return (400, error("invalid_op", #","index":\#(i),"field":"set.order""#))
        }
        guard request.from <= entries.count,
              request.from == 0 || entries[request.from - 1].hash == request.base else { return (409, error("log_mismatch")) }
        for (op, text) in zip(request.ops, rawOps) where ids.insert(op.id).inserted {
            let prev = entries.last?.hash ?? ""
            let hash = SHA256.hash(data: Data((prev + "\n").utf8) + text).map { String(format: "%02x", $0) }.joined()
            entries.append(Entry(seq: entries.count, id: op.id, text: text, hash: hash))
        }
        var out = Data(#"{"entries":["#.utf8)
        var seq = request.from
        var bytes = 0
        while seq < entries.count, seq - request.from < pageLimit, seq == request.from || bytes + entries[seq].text.count <= pageBytes {
            let e = entries[seq]
            if seq > request.from { out.append(UInt8(ascii: ",")) }
            out.append(Data(#"{"seq":\#(e.seq),"received":1761811261234,"hash":"\#(e.hash)","op":"#.utf8))
            out.append(e.text)
            out.append(UInt8(ascii: "}"))
            bytes += e.text.count
            seq += 1
        }
        out.append(Data(#"],"head":\#(entries.count),"more":\#(seq < entries.count)}"#.utf8))
        return (200, out)
    }
}

/// Serves the shared fixture pairs in a scripted order, checking that each request the client sends is the one
/// the fixture expects, byte for byte.
final class FixtureServer: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [FixtureTests.Loaded]
    private(set) var mismatches: [String] = []

    init(_ names: [String]) throws {
        let pairs = try FixtureTests.loadPairs()
        script = try names.map { name in
            guard let p = pairs.first(where: { $0.pair.name == name }) else { throw XCTSkip("missing fixture \(name)") }
            return p
        }
    }

    var remaining: Int { lock.withLock { script.count } }

    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        let next: FixtureTests.Loaded? = lock.withLock {
            guard !script.isEmpty else { mismatches.append("unexpected request \(String(decoding: body, as: UTF8.self))"); return nil }
            let n = script.removeFirst()
            if n.requestBody != body {
                mismatches.append("\(n.pair.name): sent \(String(decoding: body, as: UTF8.self))\nwant \(String(decoding: n.requestBody ?? Data(), as: UTF8.self))")
            }
            return n
        }
        guard let next else { return .transient("no more fixtures") }
        return HTTPSyncTransport.classify(status: next.pair.response.status, body: next.responseBody)
    }
}

@MainActor
final class SyncTests: XCTestCase {
    /// 2025-10-30 08:00:00 UTC, the spec examples' clock (opA's `at`).
    static let t0 = Date(timeIntervalSince1970: 1_761_811_200)
    var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
    }

    func makeStore(_ transport: SyncTransport, dir: URL? = nil, at date: Date = SyncTests.t0) -> Store {
        let d = dir ?? tempDirectory("sync-\(dirs.count)")
        if dir == nil { dirs.append(d) }
        let p = Persistence(directory: d)
        let store = Store(loaded: p.loadSync(), persistence: p, transport: transport,
                          clock: StoreClock(now: { date }, calendar: TodayTests().cal))
        store.config = SyncConfig(url: URL(string: "http://stub.invalid")!, token: "test-token")
        store.cancelScheduledSync()
        return store
    }

    func reopen(_ store: Store, _ transport: SyncTransport) -> Store {
        store.persistNow()
        return makeStore(transport, dir: store.persistence.directory)
    }

    // MARK: Fixture pairs (the shared contract)

    /// Example 1: a fresh Mac pushes the Inbox seed (opA, made by launch) and opB; both come back: the fast path.
    func testFixturePush() async throws {
        let server = try FixtureServer(["01-push"])
        let store = makeStore(server)
        XCTAssertEqual(store.projection.pending.map(\.op), [op(Spec.opAJSON)], "launch seeds the Inbox as opA")
        XCTAssertEqual(store.pendingCount, 1)
        store.perform([op(Spec.opBJSON)])
        XCTAssertEqual(store.pendingCount, 2)
        store.cancelScheduledSync()
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(store.cursor, 2)
        XCTAssertEqual(store.base, Spec.hash1)
        XCTAssertTrue(store.projection.pending.isEmpty)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.syncState, .idle(lastSynced: SyncTests.t0))
        store.persistNow()
        let log = try String(contentsOf: store.persistence.logURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(log[1].contains(#""hash":"\#(Spec.hash1)""#))
    }

    /// Fixture 11: with `attribution` set, `perform` stamps actor and batch on the op, the request carries them
    /// byte for byte as the fixture does, and they come back in the log (and from `readEntries`).
    func testFixturePushWithActor() async throws {
        let server = try FixtureServer(["01-push", "11-push-with-actor"])
        let store = makeStore(server)
        store.perform([op(Spec.opBJSON)])
        store.cancelScheduledSync()
        await store.sync()
        store.attribution = Attribution(actor: "agent:claude-code", batch: "2c1f9e0a-7b3d-4c5e-8f6a-9b0c1d2e3f4a")
        store.perform([Op(id: "3a7f2c1e-8b4d-4e6a-9c5f-1d2e3f4a5b6c", at: 1_761_811_320_000, type: .taskUpdate,
                          target: "9f8e7d6c-5b4a-4321-8fed-cba987654321", set: Patch(when: .some(date("2026-11-06"))))])
        store.cancelScheduledSync()
        XCTAssertEqual(store.projection.pending.last?.op.actor, "agent:claude-code")
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(store.cursor, 3)
        XCTAssertTrue(store.projection.pending.isEmpty)
        let entries = store.persistence.readEntries()
        XCTAssertEqual(entries.map(\.seq), [0, 1, 2])
        XCTAssertEqual(entries.map(\.op.actor), [nil, nil, "agent:claude-code"])
        XCTAssertEqual(entries.last?.op.batch, "2c1f9e0a-7b3d-4c5e-8f6a-9b0c1d2e3f4a")
    }

    /// Fixture 12 (§23): a list's notes and a heading go out byte for byte as the fixture has them, and come back as
    /// a heading and the list's notes.
    func testFixturePushHeadingAndListNotes() async throws {
        let server = try FixtureServer(["01-push", "12-push-heading-and-list-notes"])
        let store = makeStore(server)
        store.perform([op(Spec.opBJSON)])
        store.cancelScheduledSync()
        await store.sync()
        store.perform([
            Op(id: "b1e4c7a2-9d3f-4e8b-8c1a-5f6e7d8c9b0a", at: 1_761_811_330_000, type: .listUpdate, target: Spec.inbox,
               set: Patch(notes: "Things to sort.\n- [ ] **Monday**: groceries")),
            Op(id: "c2f5d8b3-0e4a-4f9c-9d2b-6a7b8c9d0e1f", at: 1_761_811_331_000, type: .taskCreate,
               target: "4c2b8e1d-6f3a-4b7c-9d0e-2a1b3c4d5e6f",
               set: Patch(list: Spec.inbox, order: "Zz", title: "Errands", kind: Patch.heading)),
        ])
        store.cancelScheduledSync()
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(store.cursor, 4)
        XCTAssertTrue(store.projection.pending.isEmpty)
        XCTAssertEqual(store.projection.confirmed.lists[Spec.inbox]?.notes, "Things to sort.\n- [ ] **Monday**: groceries")
        XCTAssertEqual(store.projection.confirmed.tasks["4c2b8e1d-6f3a-4b7c-9d0e-2a1b3c4d5e6f"]?.isHeading, true)
        XCTAssertEqual(store.projection.headings(in: Spec.inbox).ids, ["4c2b8e1d-6f3a-4b7c-9d0e-2a1b3c4d5e6f"])
        XCTAssertEqual(store.projection.openTaskCount(in: Spec.inbox), 1)
    }

    /// Example 2: a second Mac joins a 2,345-entry log; it pages from each new cursor until `more` is false.
    /// (Its own seed is a duplicate of seq 0, so the server answers exactly as for an empty push.)
    func testFixturePagination() async throws {
        let pairs = try FixtureTests.loadPairs().filter { $0.pair.name.hasPrefix("02") }
        final class Pager: SyncTransport, @unchecked Sendable {
            let pairs: [FixtureTests.Loaded]
            var sent: [SyncRequest] = []
            init(_ pairs: [FixtureTests.Loaded]) { self.pairs = pairs }
            func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
                let r = try! JSONDecoder().decode(SyncRequest.self, from: body)
                sent.append(r)
                guard let p = pairs.first(where: { $0.pair.request.body?.from == r.from && $0.pair.request.body?.base == r.base }) else {
                    return .transient("no page for \(r.from)")
                }
                return HTTPSyncTransport.classify(status: 200, body: p.responseBody)
            }
        }
        let pager = Pager(pairs)
        let store = makeStore(pager)
        await store.sync()
        XCTAssertEqual(pager.sent.map(\.from), [0, 1000, 2000])
        XCTAssertEqual(store.cursor, 2345)
        XCTAssertTrue(store.projection.pending.isEmpty, "the seed came back as seq 0 and was confirmed")
        XCTAssertEqual(store.projection.list(Spec.inbox)?.name, "Inbox")
        XCTAssertEqual(store.projection.task("9f8e7d6c-5b4a-4321-8fed-cba987654321")?.title,
                       try FixtureTests.loadLogFile("log-2345.jsonl").last?.op.set.title)
    }

    /// Example 3: ops[1] is invalid. It moves to rejected.jsonl, its entity is rebuilt, the user gets a notice,
    /// and the request is resent at once without it.
    func testFixtureInvalidOp() async throws {
        let server = try FixtureServer(["01-push", "03-invalid-op", "03b-resend-without-rejected"])
        let store = makeStore(server)
        store.perform([op(Spec.opBJSON)])
        await store.sync()
        let pairs = try FixtureTests.loadPairs()
        let ops = try XCTUnwrap(pairs.first { $0.pair.name == "03-invalid-op" }?.pair.request.body?.ops)
        store.perform(ops)
        XCTAssertEqual(store.projection.task("9f8e7d6c-5b4a-4321-8fed-cba987654321")?.order, "a 0")
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(server.remaining, 0)
        XCTAssertEqual(store.notice, "A change couldn't be saved.")
        XCTAssertEqual(store.pendingCount, store.projection.pending.count)
        let task = try XCTUnwrap(store.projection.task("9f8e7d6c-5b4a-4321-8fed-cba987654321"))
        XCTAssertEqual(task.title, "Buy oat milk")
        XCTAssertEqual(task.order, "a0", "the rejected move is gone")
        store.persistNow()
        let rejected = try String(contentsOf: store.persistence.rejectedURL, encoding: .utf8)
        XCTAssertTrue(rejected.contains("8e2f1b3c-5d4e-4f60-9b7c-8d9e0f1a2b3c"))
        XCTAssertTrue(rejected.contains(#""field":"set.order""#))
    }

    /// Example 4: a bad token stops syncing with no retry loop; pending stays; a new token resumes.
    func testFixtureBadToken() async throws {
        let server = try FixtureServer(["01-push", "04-bad-token"])
        let store = makeStore(server)
        store.perform([op(Spec.opBJSON)])
        await store.sync()
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(store.syncState, .checkToken)
        store.requestSync()         // automatic triggers do nothing while stopped
        XCTAssertEqual(store.syncState, .checkToken)
    }

    /// Example 5: a 409, then the recovery re-push: the client's log ops go out verbatim from seq 0, the server
    /// dedups opA and appends opB, and the backups are deleted once nothing is pending.
    func testFixtureLogMismatchRecovery() async throws {
        let server = try FixtureServer(["01-push", "05-log-mismatch", "05b-resync-from-zero"])
        let store = makeStore(server)
        store.perform([op(Spec.opBJSON)])
        await store.sync()
        await store.sync()
        XCTAssertEqual(server.mismatches, [])
        XCTAssertEqual(server.remaining, 0)
        XCTAssertEqual(store.cursor, 3)
        XCTAssertNil(store.recovery)
        XCTAssertEqual(store.projection.task("9f8e7d6c-5b4a-4321-8fed-cba987654321")?.title, "Buy bread")
        store.persistNow()
        let files = try FileManager.default.contentsOfDirectory(atPath: store.persistence.directory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("log.jsonl.bak-") }, "\(files)")
    }

    /// The rest of the error table: bad_request, 404, 405 stop with "Sync error"; 413 halves; 5xx backs off.
    func testFixtureStopsAndClassification() throws {
        let pairs = try FixtureTests.loadPairs()
        func outcome(_ name: String) -> SyncOutcome {
            let p = pairs.first { $0.pair.name == name }!
            return HTTPSyncTransport.classify(status: p.pair.response.status, body: p.responseBody)
        }
        guard case .badRequest = outcome("07-bad-request") else { return XCTFail() }
        guard case .tooLarge = outcome("08-too-many-ops") else { return XCTFail() }
        guard case .misconfigured = outcome("09-not-found") else { return XCTFail() }
        guard case .misconfigured = outcome("10-method-not-allowed") else { return XCTFail() }
        guard case .logMismatch = outcome("06-from-past-head") else { return XCTFail() }
        guard case .transient = HTTPSyncTransport.classify(status: 502, body: Data("<html>Bad gateway</html>".utf8)) else { return XCTFail() }
        guard case .transient = HTTPSyncTransport.classify(status: 500, body: Data(#"{"error":"internal"}"#.utf8)) else { return XCTFail() }
        guard case .transient = HTTPSyncTransport.classify(status: 200, body: Data("not json".utf8)) else { return XCTFail() }
    }

    // MARK: Stub server: the error table's client behavior

    func testStopsOnBadRequestAndMisconfiguredURL() async {
        for (status, code) in [(400, "bad_request"), (404, "not_found"), (405, "method_not_allowed")] {
            let server = StubServer()
            server.queued = [(status, Data(#"{"error":"\#(code)","message":"nope"}"#.utf8))]
            let store = makeStore(server)
            await store.sync()
            XCTAssertEqual(store.syncState, .failed("nope"))
            await store.sync()  // ⌘R-style direct sync retries; automatic triggers don't
            XCTAssertEqual(store.syncState, .idle(lastSynced: SyncTests.t0))
        }
    }

    func testTooLargeHalvesTheBatch() async {
        let server = StubServer()
        server.maxOps = 70
        let store = makeStore(server)
        for i in 0..<300 { store.createTask(title: "t\(i)") }
        await store.sync()
        XCTAssertEqual(store.syncState, .idle(lastSynced: SyncTests.t0))
        XCTAssertTrue(store.projection.pending.isEmpty)
        XCTAssertEqual(server.head, 301)
        // 301 → 413, 150 → 413, 75 → 413, then 37 per request for the rest of the run.
        XCTAssertEqual(Array(server.requests.map(\.ops.count).prefix(5)), [301, 150, 75, 37, 37])
        XCTAssertTrue(server.requests.dropFirst(3).allSatisfy { $0.ops.count <= 37 })
    }

    func testTransientErrorsBackOffDoublingToAMinute() async {
        let server = StubServer()
        server.queued = Array(repeating: (503, Data("<html>busy</html>".utf8)), count: 9)
        let store = makeStore(server)
        var waits: [TimeInterval] = []
        for _ in 0..<9 {
            await store.sync()
            store.cancelScheduledSync()
            guard case .retrying(let at, _) = store.syncState else { return XCTFail("\(store.syncState)") }
            waits.append(at.timeIntervalSince(SyncTests.t0))
        }
        XCTAssertEqual(waits, [1, 2, 4, 8, 16, 32, 60, 60, 60])
        await store.sync()
        XCTAssertEqual(store.syncState, .idle(lastSynced: SyncTests.t0))
        server.queued = [(500, Data(#"{"error":"internal"}"#.utf8))]
        await store.sync()
        guard case .retrying(let at, _) = store.syncState else { return XCTFail() }
        XCTAssertEqual(at.timeIntervalSince(SyncTests.t0), 1, "a success resets the backoff")
        store.cancelScheduledSync()
    }

    /// Pages cut short by size: the client continues from its new cursor (last seq + 1), never from + 1000, and
    /// drops pending ops only when their ids come back.
    func testShortPagesAndOwnOpsPastTheFirstPage() async {
        let server = StubServer()
        let a = makeStore(server)
        for i in 0..<120 { a.createTask(title: String(repeating: "x", count: i * 7)) }
        await a.sync()
        server.pageLimit = 1000
        server.pageBytes = 900  // only a few entries per page
        let b = makeStore(server)
        b.createTask(title: "b's own op lands past the first page")
        let first = server.requests.count
        await b.sync()
        XCTAssertEqual(b.cursor, server.head)
        XCTAssertTrue(b.projection.pending.isEmpty)
        let froms = server.requests[first...].map(\.from)
        XCTAssertGreaterThan(froms.count, 10)
        XCTAssertEqual(froms, Array(Set(froms)).sorted(), "each request starts at the previous page's last seq + 1")
        XCTAssertEqual(b.projection.confirmed, AppState.replay(server.ops))
    }

    // MARK: Two Macs, and 409 recovery against wiped, restored and healthy servers (spec §5, §8)

    /// Every op id either Mac ever made.
    func opIDs(_ stores: [Store]) -> Set<String> {
        var ids: Set<String> = []
        for s in stores {
            s.persistence.flush()
            for p in s.projection.pending { ids.insert(p.op.id) }
            ids.formUnion((try? String(contentsOf: s.persistence.logURL, encoding: .utf8))?
                .split(separator: "\n").compactMap { try? JSONDecoder().decode(LogEntry.self, from: Data($0.utf8)).op.id } ?? [])
        }
        return ids
    }

    func assertConverged(_ stores: [Store], _ server: StubServer, everything ids: Set<String>, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2 { for s in stores { await s.sync() } }
        XCTAssertTrue(ids.isSubset(of: server.opIDs), "server lost \(ids.subtracting(server.opIDs).count) ops", file: file, line: line)
        for s in stores {
            XCTAssertTrue(s.projection.pending.isEmpty, file: file, line: line)
            XCTAssertEqual(s.cursor, server.head, file: file, line: line)
            XCTAssertNil(s.recovery, file: file, line: line)
            XCTAssertEqual(s.projection.confirmed, stores[0].projection.confirmed, file: file, line: line)
            assertMatchesRebuild(s.projection, "converged", file: file, line: line)
        }
    }

    func twoMacs(_ server: StubServer) async -> (Store, Store) {
        let a = makeStore(server)
        let b = makeStore(server)
        let school = a.createList(name: "School")
        a.createTask(title: "Lab report", in: school, when: CalendarDate(SyncTests.t0, calendar: TodayTests().cal))
        a.createTask(title: "Inbox task")
        await a.sync()
        await b.sync()
        b.createTask(title: "From B", in: school)
        b.setTitle(a.projection.openTasks(in: school).ids[0], "Lab report v2")
        await b.sync()
        await a.sync()
        return (a, b)
    }

    func testTwoMacsConverge() async {
        let server = StubServer()
        let (a, b) = await twoMacs(server)
        XCTAssertEqual(a.projection.confirmed, b.projection.confirmed)
        XCTAssertEqual(a.projection.activeLists.ids.count, 2, "one Inbox, though both Macs seeded it")
        await assertConverged([a, b], server, everything: opIDs([a, b]))
    }

    /// A wiped server is rebuilt from the Macs; nothing is lost.
    func testRecoveryFromWipedServer() async {
        let server = StubServer()
        let (a, b) = await twoMacs(server)
        let before = opIDs([a, b])
        server.wipe()
        a.createTask(title: "made after the wipe")
        await a.sync()
        XCTAssertNil(a.recovery)
        XCTAssertEqual(server.head, before.count + 1)
        await assertConverged([a, b], server, everything: before.union(opIDs([a])))
    }

    /// Restored to an older point and grown since: missing ops are re-appended; the Macs converge.
    func testRecoveryFromRestoredServer() async {
        let server = StubServer()
        let (a, b) = await twoMacs(server)
        let before = opIDs([a, b])
        server.restore(to: 3)
        let c = makeStore(server)            // a third Mac grows the restored log
        c.createTask(title: "on the restored server")
        await c.sync()
        b.createTask(title: "b offline edit")
        await b.sync()                       // 409 → re-push everything
        await a.sync()
        await assertConverged([a, b, c], server, everything: before.union(opIDs([a, b, c])))
    }

    /// A healthy server but a damaged local log: everything is deduplicated, nothing appended.
    func testRecoveryFromDamagedClientLog() async throws {
        let server = StubServer()
        let (a, b) = await twoMacs(server)
        let head = server.head
        a.persistNow()
        // Damage: a different hash on the last entry, so `base` no longer matches the server.
        let url = a.persistence.logURL
        var text = try String(contentsOf: url, encoding: .utf8)
        let lastHash = try XCTUnwrap(server.log.last?.hash)
        text = text.replacingOccurrences(of: lastHash, with: String(repeating: "0", count: 64))
        try text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: a.persistence.snapshotURL)
        let a2 = reopen(a, server)
        await a2.sync()
        XCTAssertEqual(server.head, head, "nothing appended")
        XCTAssertNil(a2.recovery)
        await assertConverged([a2, b], server, everything: opIDs([a2, b]))
    }

    /// A relaunch in the middle of a recovery picks it up (from the backups) and finishes it.
    func testRecoverySurvivesRelaunch() async throws {
        let server = StubServer()
        let (a, b) = await twoMacs(server)
        let before = opIDs([a, b])
        server.wipe()
        server.queued = [(409, Data(#"{"error":"log_mismatch"}"#.utf8)), (503, Data())] // recovery starts, then the network drops
        await a.sync()
        a.cancelScheduledSync()
        XCTAssertNotNil(a.recovery)
        let a2 = reopen(a, server)
        XCTAssertEqual(a2.recovery?.confirmed, 0)
        XCTAssertGreaterThan(a2.recovery?.total ?? 0, 0)
        await a2.sync()
        XCTAssertNil(a2.recovery)
        await assertConverged([a2, b], server, everything: before)
    }

    // MARK: Undo

    func testUndoRedoAreNewOps() async {
        let server = StubServer()
        let store = makeStore(server)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let id = store.createTask(title: "x", undoManager: undo)!
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        store.toggleComplete([id], undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertNotNil(store.projection.task(id)?.completedAt)
        undo.undo()
        XCTAssertNil(store.projection.task(id)?.completedAt)
        undo.undo()
        XCTAssertEqual(store.projection.task(id)?.deleted, true, "undoing a create deletes")
        undo.redo()
        XCTAssertEqual(store.projection.task(id)?.deleted, false)
        undo.redo()
        XCTAssertNotNil(store.projection.task(id)?.completedAt)
        XCTAssertEqual(store.projection.pending.count, 1 + 6, "seed + create, complete, 2 undos, 2 redos")
        await store.sync()
        XCTAssertNotNil(store.projection.confirmed.tasks[id]?.completedAt)
    }

    func testArchiveUndoAndDefaultList() {
        let store = makeStore(StubServer())
        let inbox = store.defaultListID!
        let school = store.createList(name: "School")
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.archive(list: inbox, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(store.defaultListID, school, "the next active list takes over")
        undo.undo()
        XCTAssertEqual(store.defaultListID, inbox)
        store.archive(list: inbox)
        store.archive(list: school)
        XCTAssertNil(store.createTask(title: "nowhere to go"))
    }

    func testClampKeepsCharactersWhole() {
        XCTAssertEqual(Store.clamp("abc", 2), "ab")
        XCTAssertEqual(Store.clamp("a🎉b", 2), "a", "a surrogate pair isn't split")
        XCTAssertEqual(Store.clamp("a🎉b", 3), "a🎉")
    }
}

/// The real HTTP transport, against a URLProtocol stub: method, path, headers, body, and error mapping.
final class HTTPTransportTests: XCTestCase {
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
        nonisolated(unsafe) static var seen: [URLRequest] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var r = request
            if r.httpBody == nil, let stream = r.httpBodyStream {
                stream.open()
                var data = Data()
                var buf = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buf, maxLength: buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                }
                r.httpBody = data
            }
            Self.seen.append(r)
            do {
                let (status, body) = try Self.handler!(r)
                let response = HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json; charset=utf-8"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    func transport() -> HTTPSyncTransport {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [Stub.self]
        return HTTPSyncTransport(session: URLSession(configuration: c))
    }

    func testRequestShapeAndClassification() async throws {
        Stub.seen = []
        Stub.handler = { _ in (200, Data(#"{"entries":[],"head":0,"more":false}"#.utf8)) }
        let config = SyncConfig(url: URL(string: "https://tasks.example.workers.dev")!, token: "s3cret")
        let body = SyncRequest.body(from: 0, base: nil, opJSON: [Data(Spec.opAJSON.utf8)])
        guard case .page(let page) = await transport().send(body, config: config) else { return XCTFail() }
        XCTAssertEqual(page.head, 0)
        let r = try XCTUnwrap(Stub.seen.first)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://tasks.example.workers.dev/v1/sync")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(r.httpBody, body)

        Stub.handler = { _ in (401, Data(#"{"error":"bad_token","message":"Missing or invalid bearer token."}"#.utf8)) }
        guard case .badToken = await transport().send(body, config: config) else { return XCTFail() }
        Stub.handler = { _ in throw URLError(.timedOut) }
        guard case .transient = await transport().send(body, config: config) else { return XCTFail() }
        Stub.handler = { _ in throw URLError(.notConnectedToInternet) }
        guard case .transient = await transport().send(body, config: config) else { return XCTFail() }
    }
}
