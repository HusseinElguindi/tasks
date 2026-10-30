import XCTest
@testable import TasksCore

/// A log line as the server sends it (hashes are fake but well-formed; the client never checks them).
func entryLine(seq: Int, op: Op) -> Data {
    entryLine(seq: seq, opJSON: op.jsonData)
}

func entryLine(seq: Int, opJSON: Data) -> Data {
    var d = Data(#"{"seq":\#(seq),"received":1761811261234,"hash":"\#(fakeHash(seq))","op":"#.utf8)
    d.append(opJSON)
    d.append(UInt8(ascii: "}"))
    return d
}

func fakeHash(_ seq: Int) -> String { String(format: "%064x", seq + 1) }

func tempDirectory(_ name: String = #function) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TasksCoreTests-\(name.filter { $0.isLetter })-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Snapshot, tail, torn tails, write order, and the 409 recovery's file steps (spec §5, §8).
final class PersistenceTests: XCTestCase {
    var m = OpMaker()
    var dir: URL!

    override func setUp() { dir = tempDirectory(name) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func someOps(_ n: Int) -> [Op] {
        var ops = [m.createList("L", name: "L", order: "a0")]
        for i in 0..<n {
            ops.append(i % 3 == 0 ? m.createTask("t\(i)", list: "L", order: "a\(i % 9 + 1)", title: "task \(i)")
                                  : m.updateTask("t\(i - i % 3)", Patch(title: "edit \(i)")))
        }
        return ops
    }

    /// Writes `ops` as confirmed log entries, the way a sync would.
    func appendLog(_ p: Persistence, _ ops: [Op], from: Int = 0) {
        p.appendLog(ops.enumerated().map { entryLine(seq: from + $0.offset, op: $0.element) }, nextCursor: from + ops.count)
    }

    func testEmptyDirectory() {
        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.confirmed, AppState())
        XCTAssertEqual(loaded.cursor, 0)
        XCTAssertNil(loaded.hash)
        XCTAssertEqual(loaded.source, .empty)
        XCTAssertFalse(loaded.recovering)
    }

    func testSnapshotPlusTailEqualsFullReplay() throws {
        let ops = someOps(300)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        appendLog(p, Array(ops[..<200]))
        p.writeSnapshot(state: AppState.replay(ops[..<200]), cursor: 200, hash: fakeHash(199))
        appendLog(p, Array(ops[200...]), from: 200)
        p.flush()

        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.source, .snapshot(tail: ops.count - 200))
        XCTAssertEqual(loaded.confirmed, AppState.replay(ops))
        XCTAssertEqual(loaded.cursor, ops.count)
        XCTAssertEqual(loaded.hash, fakeHash(ops.count - 1))

        // The same files without the snapshot: a full replay gives the same answer.
        try FileManager.default.removeItem(at: p.snapshotURL)
        let replayed = Persistence(directory: dir).loadSync()
        XCTAssertEqual(replayed.source, .fullReplay(reason: "no snapshot"))
        XCTAssertEqual(replayed.confirmed, loaded.confirmed)
        XCTAssertEqual(replayed.cursor, loaded.cursor)
        XCTAssertEqual(replayed.hash, loaded.hash)
    }

    func testBadSnapshotsFallBackToFullReplay() throws {
        let ops = someOps(60)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        appendLog(p, ops)
        p.writeSnapshot(state: AppState.replay(ops), cursor: ops.count, hash: fakeHash(ops.count - 1))
        p.flush()
        let good = try Data(contentsOf: p.snapshotURL)
        let expected = AppState.replay(ops)

        let cases: [(String, Data)] = [
            ("snapshot undecodable", Data("{\"schema\":1,".utf8)),
            ("snapshot schema 0, want 1", String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"schema\":1", with: "\"schema\":0").data(using: .utf8)!),
            ("log shorter than the snapshot's offset", String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"logOffset\":", with: "\"logOffset\":9").data(using: .utf8)!),
        ]
        for (reason, bytes) in cases {
            try bytes.write(to: p.snapshotURL)
            let loaded = Persistence(directory: dir).loadSync()
            XCTAssertEqual(loaded.source, .fullReplay(reason: reason))
            XCTAssertEqual(loaded.confirmed, expected, reason)
            XCTAssertEqual(loaded.cursor, ops.count)
        }
        // A snapshot whose offset doesn't land on entry `cursor` fails the seq check.
        let p2 = Persistence(directory: dir)
        _ = p2.loadSync()
        p2.writeSnapshot(state: expected, cursor: ops.count, hash: fakeHash(ops.count - 1))
        p2.flush()
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: p.snapshotURL)) as! [String: Any]
        json["cursor"] = 3
        json["logOffset"] = 0
        try JSONSerialization.data(withJSONObject: json).write(to: p.snapshotURL)
        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.source, .fullReplay(reason: "first tail entry isn't seq 3"))
        XCTAssertEqual(loaded.confirmed, expected)
    }

    /// A crash that tears the last line of log.jsonl: that entry is dropped (and refetched), the file is truncated
    /// so the next append starts on a clean line.
    func testTornLogTail() throws {
        let ops = someOps(20)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        appendLog(p, ops)
        p.flush()
        let h = try FileHandle(forWritingTo: p.logURL)
        try h.seekToEnd()
        try h.write(contentsOf: entryLine(seq: ops.count, op: m.updateTask("t0", Patch(title: "torn"))).prefix(30))
        try h.close()

        let p2 = Persistence(directory: dir)
        let loaded = p2.loadSync()
        XCTAssertEqual(loaded.cursor, ops.count)
        XCTAssertEqual(loaded.confirmed, AppState.replay(ops))
        let next = m.updateTask("t0", Patch(title: "after"))
        appendLog(p2, [next], from: ops.count)
        p2.flush()
        let again = Persistence(directory: dir).loadSync()
        XCTAssertEqual(again.cursor, ops.count + 1)
        XCTAssertEqual(again.confirmed.tasks["t0"]?.title, "after")
    }

    func testTornPendingTailAndVerbatimLines() throws {
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        // A pending op written by a newer client: an unknown key and an unknown type. Kept byte for byte.
        let newer = Data(#"{"id":"n1","at":5,"type":"task.update","target":"t","set":{"title":"x","color":"red"}}"#.utf8)
        let newerType = Data(#"{"id":"n2","at":6,"type":"task.pin","target":"t","set":{"pinned":true}}"#.utf8)
        p.appendPending(newer)
        p.appendPending(newerType)
        p.appendPending(m.createTask("t", list: "L", order: "a0").jsonData)
        p.flush()
        let h = try FileHandle(forWritingTo: p.pendingURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data(#"{"id":"torn","at":1,"ty"#.utf8))
        try h.close()

        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.pending.map(\.op.id), ["n1", "n2", "op-000001"])
        XCTAssertEqual(loaded.pending[0].json, newer)
        XCTAssertEqual(loaded.pending[1].json, newerType)
        XCTAssertEqual(loaded.pending[1].op.type, .unknown("task.pin"))
        XCTAssertEqual(SyncRequest.body(from: 0, base: nil, opJSON: loaded.pending.map(\.json)),
                       Data(#"{"from":0,"base":null,"ops":["#.utf8) + newer + Data(",".utf8) + newerType + Data(",".utf8)
                       + loaded.pending[2].json + Data("]}".utf8))
        // The torn line was dropped from the file too.
        XCTAssertEqual(try String(contentsOf: p.pendingURL, encoding: .utf8).split(separator: "\n").count, 3)
    }

    /// Write order within a sync: log, then pending, then snapshot. A crash after the log append but before the
    /// pending rewrite leaves confirmed ops in pending.jsonl; launch finds them in the log tail and drops them.
    func testCrashBetweenLogAppendAndPendingRewrite() {
        let ops = someOps(10)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        for op in ops { p.appendPending(op.jsonData) }
        let extra = m.updateTask("t0", Patch(notes: "still pending"))
        p.appendPending(extra.jsonData)
        appendLog(p, ops)               // the sync confirmed `ops`…
        p.flush()                       // …and the app died before rewriting pending.jsonl.
        let loaded = Persistence(directory: dir).loadSync()
        XCTAssertEqual(loaded.pending.map(\.op), [extra])
        XCTAssertEqual(loaded.confirmed, AppState.replay(ops))
    }

    func testSnapshotSkippedWhenCursorUnchangedOrLogBehind() throws {
        let ops = someOps(10)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        appendLog(p, ops)
        p.writeSnapshot(state: AppState.replay(ops), cursor: ops.count, hash: fakeHash(ops.count - 1))
        p.flush()
        let first = try Data(contentsOf: p.snapshotURL)
        p.writeSnapshot(state: AppState(), cursor: ops.count, hash: nil)   // cursor hasn't moved: skipped
        p.writeSnapshot(state: AppState(), cursor: ops.count + 5, hash: nil) // log isn't there yet: skipped
        p.flush()
        XCTAssertEqual(try Data(contentsOf: p.snapshotURL), first)
    }

    // MARK: 409 recovery file steps

    /// Sets up a Mac with a confirmed log (with a snapshot mid-way) and pending ops, one of them also in the log.
    func recoveryFixture() -> (ops: [Op], pending: [PendingOp], queue: [String]) {
        let ops = someOps(30)
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        appendLog(p, Array(ops[..<20]))
        p.writeSnapshot(state: AppState.replay(ops[..<20]), cursor: 20, hash: fakeHash(19))
        appendLog(p, Array(ops[20...]), from: 20)
        let local = [m.updateTask("t0", Patch(title: "local")), m.createTask("new", list: "L", order: "b0")]
        let pending = ([ops[25]] + local).map(PendingOp.init) // ops[25]: confirmed, but a crash left it pending
        for op in pending { p.appendPending(op.json) }
        p.flush()
        return (ops, pending, ops.map(\.id) + local.map(\.id))
    }

    func testRecoveryQueueIsLogThenPendingDedupedVerbatim() throws {
        let f = recoveryFixture()
        let p = Persistence(directory: dir)
        let loaded = p.loadSync()
        let queue = p.recoverSync(pending: loaded.pending, now: 42, through: 4)
        XCTAssertEqual(queue.map(\.op.id), f.queue)
        // On disk: the queue is pending.jsonl, no snapshot, and the log is moved aside.
        XCTAssertFalse(FileManager.default.fileExists(atPath: p.snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p.logURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("log.jsonl.bak-42").path))
        let relaunched = Persistence(directory: dir).loadSync()
        XCTAssertEqual(relaunched.pending.map(\.op.id), f.queue)
        XCTAssertEqual(relaunched.confirmed, AppState())
        XCTAssertEqual(relaunched.cursor, 0)
        XCTAssertNil(relaunched.hash)
        XCTAssertTrue(relaunched.recovering)
        // Done: backups go.
        let p3 = Persistence(directory: dir)
        _ = p3.loadSync()
        p3.deleteBackups()
        p3.flush()
        XCTAssertFalse(Persistence(directory: dir).loadSync().recovering)
    }

    /// Unknown keys in recovered log ops are re-pushed byte for byte.
    func testRecoveredLogOpsAreVerbatim() throws {
        let p = Persistence(directory: dir)
        _ = p.loadSync()
        let future = Data(#"{"id":"f1","at":9,"type":"task.update","target":"t","set":{"title":"x","color":"teal"}}"#.utf8)
        let unknownType = Data(#"{"id":"f2","at":9,"type":"list.zap","target":"l","set":{}}"#.utf8)
        p.appendLog([entryLine(seq: 0, opJSON: future), entryLine(seq: 1, opJSON: unknownType)], nextCursor: 2)
        p.flush()
        let queue = p.recoverSync(pending: [], now: 1, through: 4)
        XCTAssertEqual(queue.map(\.json), [future, unknownType])
        XCTAssertEqual(SyncRequest.body(from: 0, base: nil, opJSON: queue.map(\.json)),
                       Data(#"{"from":0,"base":null,"ops":["#.utf8) + future + Data(",".utf8) + unknownType + Data("]}".utf8))
    }

    /// A crash after each recovery step: relaunch, then (if the log is still there) the next sync 409s again and
    /// recovery reruns. Every path ends with the same recovery queue, so no op is lost.
    @MainActor
    func testCrashAfterEachRecoveryStep() throws {
        let f = recoveryFixture()
        let files = ["log.jsonl", "pending.jsonl", "snapshot.json"]
        let original = try files.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
        for step in 1...4 {
            // Restore the pre-recovery files.
            for url in (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) {
                try FileManager.default.removeItem(at: url)
            }
            for (name, data) in zip(files, original) { try data.write(to: dir.appendingPathComponent(name)) }

            let p = Persistence(directory: dir)
            let before = p.loadSync()
            _ = p.recoverSync(pending: before.pending, now: 7, through: step) // …crash.

            let relaunched = Persistence(directory: dir)
            let loaded = relaunched.loadSync()
            let logStillThere = FileManager.default.fileExists(atPath: relaunched.logURL.path)
            XCTAssertEqual(logStillThere, step < 4, "step \(step)")
            // Visible state after relaunch (confirmed + pending) still shows everything.
            let visible = Projection(confirmed: loaded.confirmed, pending: loaded.pending, day: Day(containing: Date()))
            XCTAssertEqual(visible.task("new")?.order, "b0", "step \(step)")
            XCTAssertEqual(visible.task("t0")?.title, "local", "step \(step)")
            // Finish: a still-present log means the next sync 409s and recovery reruns from log + pending.
            let queue = logStillThere
                ? relaunched.recoverSync(pending: loaded.pending, now: 8, through: 4)
                : loaded.pending
            XCTAssertEqual(queue.map(\.op.id), f.queue, "step \(step)")
            XCTAssertTrue(Persistence(directory: dir).loadSync().recovering, "step \(step)")
        }
    }
}
