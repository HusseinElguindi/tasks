import CryptoKit
import TasksCore
import XCTest
@testable import TasksCLI

/// An in-memory `/v1/sync`: token, `from`/`base` with a real hash chain, op-id dedup, pages, and an "offline"
/// switch. Keeps each op's text verbatim, as the server stores it.
final class MemoryServer: SyncTransport, @unchecked Sendable {
    struct Entry { var seq: Int; var text: Data; var hash: String }
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var ids: Set<String> = []
    var offline = false

    var ops: [Op] { lock.withLock { entries.map { try! JSONDecoder().decode(Op.self, from: $0.text) } } }
    var texts: [String] { lock.withLock { entries.map { String(decoding: $0.text, as: UTF8.self) } } }

    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        lock.withLock {
            if offline { return .transient("offline") }
            guard config.token == "test-token" else { return .badToken }
            let request = try! JSONDecoder().decode(SyncRequest.self, from: body)
            let raw = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let rawOps = (raw["ops"] as! [Any]).map { try! JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            guard request.from <= entries.count, request.from == 0 || entries[request.from - 1].hash == request.base else {
                return .logMismatch
            }
            for (op, _) in zip(request.ops, rawOps) where ids.insert(op.id).inserted {
                let text = op.jsonData
                let prev = entries.last?.hash ?? ""
                let hash = SHA256.hash(data: Data((prev + "\n").utf8) + text).map { String(format: "%02x", $0) }.joined()
                entries.append(Entry(seq: entries.count, text: text, hash: hash))
            }
            var out = Data(#"{"entries":["#.utf8)
            for e in entries[request.from...] {
                if e.seq > request.from { out.append(UInt8(ascii: ",")) }
                out.append(Data(#"{"seq":\#(e.seq),"received":1793462400000,"hash":"\#(e.hash)","op":"#.utf8))
                out.append(e.text)
                out.append(UInt8(ascii: "}"))
            }
            out.append(Data(#"],"head":\#(entries.count),"more":false}"#.utf8))
            return HTTPSyncTransport.classify(status: 200, body: out)
        }
    }
}

/// The harness: a fake server, a fixed clock (Sat, Oct 31 2026, Toronto) and a scratch replica per test.
@MainActor
class CLITestCase: XCTestCase {
    var server = MemoryServer()
    var dir: URL!
    var vars: [String: String] = [:]
    /// Sat, Oct 31 2026, noon in Toronto.
    var now = Date(timeIntervalSince1970: 1_793_462_400)
    var stdinIsTTY = false
    var keychainReads = 0
    /// The servers the CLI nudged the app about (`SyncNudge`), in order.
    var nudges: [URL] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-cli-tests-\(UUID().uuidString)")
        vars = ["TASKS_URL": "http://127.0.0.1:1", "TASKS_TOKEN": "test-token", "TASKS_ENV_FILE": "/dev/null",
                "TASKS_DATA_DIR": dir.path, "TASKS_ACTOR": "agent:test", "TASKS_DATE_ORDER": "md"]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }

    func env(stdin: String = "", out: @escaping (String) -> Void, err: @escaping (String) -> Void) -> Environment {
        let date = now
        return Environment(vars: vars, home: dir, transport: server, clock: StoreClock(now: { date }, calendar: calendar),
                           stdinIsTTY: stdinIsTTY, readStdin: { stdin }, out: out, err: err,
                           keychainToken: { [unowned self] in keychainReads += 1; return "keychain-token" }, sleep: { _ in },
                           nudge: { [unowned self] in nudges.append($0) })
    }

    @discardableResult
    func tasks(_ args: String..., stdin: String = "") async -> (code: Int32, out: String, err: String) {
        var out: [String] = [], err: [String] = []
        let code = await CLI.run(args, env: env(stdin: stdin, out: { out.append($0) }, err: { err.append($0) }))
        return (code, out.joined(separator: "\n"), err.joined(separator: "\n"))
    }

    func json(_ args: String...) async throws -> JSON {
        var out: [String] = []
        let code = await CLI.run(args + ["--json"], env: env(out: { out.append($0) }, err: { _ in }))
        XCTAssertEqual(code, 0, "\(args) → \(out)")
        return try JSON.parse(out.joined())
    }

    func id(_ title: String) async throws -> String {
        let found = try await json("find", title)
        return try XCTUnwrap(found.arrayValue?.first?["id"]?.stringValue, "no task \(title)")
    }

    func errorJSON(_ args: String...) async throws -> JSON {
        var out: [String] = []
        let code = await CLI.run(args + ["--json"], env: env(out: { out.append($0) }, err: { _ in }))
        XCTAssertEqual(code, 1)
        return try XCTUnwrap(try JSON.parse(out.joined())["error"])
    }
}

@MainActor
final class CLITests: CLITestCase {

    func testAddTodayAndTheJSONShapes() async throws {
        await tasks("list", "add", "School")
        let milk = try await json("add", "Buy milk", "--today")
        XCTAssertEqual(Set(milk.keys).subtracting(["synced"]), Set(Shapes.task.filter { !$0.optional }.map(\.name)), "no kind on a task")
        XCTAssertEqual(milk["listName"]?.stringValue, "Inbox", "no list means the first list")
        XCTAssertEqual(milk["when"]?.stringValue, "2026-10-31")
        await tasks("add", "Essay", "--list", "school", "--deadline", "2026-10-30")
        await tasks("add", "Later", "--when", "fri")

        let today = try await json("today")
        XCTAssertEqual(today["date"]?.stringValue, "2026-10-31")
        let groups = try XCTUnwrap(today["groups"]?.arrayValue)
        XCTAssertEqual(groups.map { $0["list"]?["name"]?.stringValue }, ["Inbox", "School"], "sidebar order; overdue counts")
        XCTAssertEqual(Set(groups[0]["list"]?.keys ?? []), Set(Shapes.list.map(\.name)))
        XCTAssertEqual(groups[0]["tasks"]?.arrayValue?.map { $0["title"]?.stringValue }, ["Buy milk"])

        let later = try await json("show", try await id("Later"))
        XCTAssertEqual(later["when"]?.stringValue, "2026-11-06")
        let text = await tasks("today")
        XCTAssertTrue(text.out.contains("⚑ 1d ago"), text.out)   // §24: overdue in days, the flag for the capsule
    }

    func testEveryWriteCarriesActorAndOneBatchPerCommand() async throws {
        await tasks("add", "A")
        await tasks("add", "B")
        let a = try await id("A"), b = try await id("B")
        let r = await tasks("when", "fri", a, b)
        XCTAssertEqual(r.code, 0, r.err)
        let ops = server.ops.filter { $0.set.when != nil && $0.type == .taskUpdate }
        XCTAssertEqual(ops.count, 2)
        XCTAssertEqual(Set(ops.map(\.batch)).count, 1)
        XCTAssertEqual(ops.map(\.actor), ["agent:test", "agent:test"])
        XCTAssertTrue(r.out.contains("undo: tasks undo \(ops[0].batch!.prefix(6))"), r.out)
        // The stored text ends with actor and batch, after set.
        XCTAssertTrue(server.texts.last!.hasSuffix(#""actor":"agent:test","batch":"\#(ops[0].batch!)"}"#), server.texts.last!)
    }

    func testRefsFailClosed() async throws {
        await tasks("list", "add", "Work")
        await tasks("list", "add", "work")
        let dup = await tasks("add", "x", "--list", "Work")
        XCTAssertEqual(dup.code, 1)
        XCTAssertTrue(dup.err.contains("matches 2 lists"), dup.err)
        let short = await tasks("done", "abc")
        XCTAssertEqual(short.code, 1)
        XCTAssertTrue(short.err.contains("at least 4"), short.err)
        let missing = await tasks("done", "ffffffff")
        XCTAssertTrue(missing.err.contains("No task ffffffff"), missing.err)

        await tasks("add", "Milk", "--id", "abcd1111-0000-4000-8000-000000000000")
        await tasks("add", "Bread", "--id", "abcd2222-0000-4000-8000-000000000000")
        let ambiguous = try await errorJSON("done", "abcd")
        XCTAssertEqual(ambiguous["type"]?.stringValue, "Ambiguous")
        XCTAssertEqual(ambiguous["candidates"]?.arrayValue?.count, 2)
        let ok = await tasks("done", "abcd1")
        XCTAssertEqual(ok.code, 0, ok.err)
    }

    func testDryRunWritesNothing() async throws {
        await tasks("add", "Milk")
        let before = server.ops.count
        let r = await tasks("when", "tomorrow", try await id("Milk"), "--dry-run")
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("when: — → 2026-11-01 (Tomorrow)"), r.out)
        XCTAssertTrue(r.out.contains("Nothing was written"), r.out)
        XCTAssertEqual(server.ops.count, before)
        let milk = try await json("show", try await id("Milk"))
        XCTAssertEqual(milk["when"], .null)
    }

    func testUndoKeepsLaterEditsUnlessForced() async throws {
        await tasks("add", "Milk")
        let milk = try await id("Milk")
        await tasks("when", "fri", milk)
        await tasks("rename", milk, "Oat milk")
        let batch = server.ops.last { $0.set.when != nil }!.batch!
        vars["TASKS_ACTOR"] = "app-user"
        await tasks("when", "sat", milk)
        vars["TASKS_ACTOR"] = "agent:test"

        let undo = await tasks("undo", String(batch.prefix(6)))
        XCTAssertEqual(undo.code, 0, undo.err)
        XCTAssertTrue(undo.out.contains("kept the later edit to the when"), undo.out)
        let kept = try await json("show", milk)
        XCTAssertEqual(kept["when"]?.stringValue, "2026-11-07")
        XCTAssertEqual(kept["title"]?.stringValue, "Oat milk")

        // Everything was kept, so nothing was written and it can be tried again; an undo that wrote is final.
        let again = await tasks("undo", String(batch.prefix(6)))
        XCTAssertEqual(again.out, "No change.\n  kept the later edit to the when of \(milk.prefix(6)) \"Oat milk\"")
        await tasks("done", milk)
        let done = server.ops.last!.batch!
        await tasks("undo", String(done.prefix(6)))
        let twice = await tasks("undo", String(done.prefix(6)))
        XCTAssertEqual(twice.code, 1)
        XCTAssertTrue(twice.err.contains("already undone"), twice.err)

        // A fresh change, undone with --force, wins over the later edit.
        await tasks("when", "mon", milk)
        let monday = server.ops.last!.batch!
        vars["TASKS_ACTOR"] = "app-user"
        await tasks("when", "tue", milk)
        vars["TASKS_ACTOR"] = "agent:test"
        await tasks("undo", String(monday.prefix(8)), "--force")
        let forced = try await json("show", milk)
        XCTAssertEqual(forced["when"]?.stringValue, "2026-11-07", "back to before Monday's change")
    }

    func testUndoAndRedoWalkTheActorsChanges() async throws {
        await tasks("add", "Milk")
        let milk = try await id("Milk")
        await tasks("done", milk)
        let u = await tasks("undo")
        XCTAssertTrue(u.out.hasPrefix("Undo: Complete \"Milk\""), u.out)
        let open = try await json("show", milk)
        XCTAssertEqual(open["done"], .bool(false))
        let r = await tasks("redo")
        XCTAssertTrue(r.out.hasPrefix("Redo: Complete \"Milk\""), r.out)
        let done = try await json("show", milk)
        XCTAssertEqual(done["done"], .bool(true))
        // Undo again: the redo is the newest change; then the add.
        await tasks("undo")
        await tasks("undo")
        let deleted = try await json("show", milk)
        XCTAssertEqual(deleted["deleted"], .bool(true), "undoing an add deletes the task")
        let log = await tasks("log")
        XCTAssertTrue(log.out.contains("Undo: New Task \"Milk\" in Inbox"), log.out)
    }

    func testOfflineWritesQueueAndExit75() async throws {
        await tasks("add", "Milk")
        server.offline = true
        let r = await tasks("add", "Bread")
        XCTAssertEqual(r.code, 75)
        XCTAssertTrue(r.err.contains("offline"), r.err)
        let read = await tasks("lists")
        XCTAssertEqual(read.code, 75)
        server.offline = false
        let next = await tasks("lists")
        XCTAssertEqual(next.code, 0)
        XCTAssertTrue(server.ops.contains { $0.set.title == "Bread" })
    }

    /// Feedback item 14: the app is nudged after a push the server took, and only then: not after a read, a dry run,
    /// a `--cached` write or a write that couldn't reach the server (it nudges when a later command pushes it).
    func testNudgesTheAppOnlyAfterAPush() async throws {
        let url = URL(string: "http://127.0.0.1:1")!
        await tasks("add", "Milk")
        XCTAssertEqual(nudges, [url])
        await tasks("lists")
        await tasks("add", "Eggs", "--dry-run")
        XCTAssertEqual(nudges.count, 1)
        server.offline = true
        let r = await tasks("add", "Bread")
        XCTAssertEqual(r.code, 75)
        XCTAssertEqual(nudges.count, 1)
        server.offline = false
        await tasks("lists")
        XCTAssertEqual(nudges.count, 2, "the queued write went out with the next command")
        await tasks("add", "Jam", "--cached")
        XCTAssertEqual(nudges.count, 2)
        await tasks("sync")
        XCTAssertEqual(nudges.count, 3)
        XCTAssertEqual(Set(nudges), [url])
    }

    /// A read that pulled leaves the log on disk: the next command starts from there, even offline.
    func testAPullIsPersisted() async throws {
        await tasks("add", "Milk")
        let other = dir.appendingPathComponent("other")
        vars["TASKS_DATA_DIR"] = other.path
        let first = await tasks("lists")
        XCTAssertEqual(first.code, 0)
        // On disk by the time the command returns, not just queued for the background writer.
        let log = try String(contentsOf: other.appendingPathComponent("127.0.0.1:1/log.jsonl"), encoding: .utf8)
        XCTAssertEqual(log.split(separator: "\n").count, server.ops.count)
        server.offline = true
        let status = try await json("status", "--cached")
        XCTAssertEqual(status["cursor"]?.intValue, server.ops.count)
        let found = await tasks("find", "Milk", "--cached")
        XCTAssertTrue(found.out.contains("Milk"), found.out)
    }

    func testKeyMakesAddIdempotent() async throws {
        let a = try await json("add", "Pay rent", "--key", "rent-2026-11")
        let count = server.ops.count
        let b = try await json("add", "Pay rent", "--key", "rent-2026-11")
        XCTAssertEqual(a["id"], b["id"])
        XCTAssertEqual(server.ops.count, count)
        XCTAssertEqual(a["id"]?.stringValue, Context.derivedID("key:rent-2026-11"))
        XCTAssertEqual(a["id"]?.stringValue?.count, 36)
    }

    func testMovesAndPlaces() async throws {
        await tasks("list", "add", "School")
        for t in ["A", "B", "C"] { await tasks("add", t) }
        let (a, b, c) = (try await id("A"), try await id("B"), try await id("C"))
        await tasks("move", c, "--top")
        await tasks("move", a, "--down")
        var inbox = try await json("ls", "Inbox")
        XCTAssertEqual(inbox["open"]?.arrayValue?.map { $0["title"]?.stringValue }, ["C", "B", "A"])
        await tasks("move", a, "--after", c)
        inbox = try await json("ls", "Inbox")
        XCTAssertEqual(inbox["open"]?.arrayValue?.map { $0["title"]?.stringValue }, ["C", "A", "B"])
        await tasks("move", b, c, "--to", "School")
        let school = try await json("ls", "School")
        XCTAssertEqual(school["open"]?.arrayValue?.map { $0["title"]?.stringValue }, ["B", "C"], "in the order given")

        await tasks("list", "archive", "School")
        let refused = await tasks("move", a, "--to", "School")
        XCTAssertEqual(refused.code, 1)
        XCTAssertTrue(refused.err.contains("School is archived; unarchive it first"), refused.err)
        let noop = await tasks("move", a, "--to", "Inbox")
        XCTAssertEqual(noop.out, "No change.")
    }

    func testLimitsFailRatherThanClamp() async throws {
        let long = String(repeating: "x", count: 1001)
        let r = try await errorJSON("add", long)
        XCTAssertEqual(r["type"]?.stringValue, "Limit")
        XCTAssertEqual(r["field"]?.stringValue, "title")
        let empty = try await errorJSON("add", "  ")
        XCTAssertEqual(empty["type"]?.stringValue, "Invalid")
    }

    func testStdinRefsAndNotes() async throws {
        await tasks("add", "Milk")
        await tasks("add", "Bread")
        let ids = await tasks("find", "", "--ids")
        let r = await tasks("done", "-", stdin: ids.out + "\n")
        XCTAssertTrue(r.out.hasPrefix("Complete 2 Tasks"), r.out)
        await tasks("notes", try await id("Milk"), "-", stdin: "line 1\n")
        await tasks("notes", try await id("Milk"), "line 2", "--append")
        let milk = try await json("show", try await id("Milk"))
        XCTAssertEqual(milk["notes"]?.stringValue, "line 1\nline 2")
    }

    func testTokenOrderAndTheKeychainOnlyAtATerminal() throws {
        let file = dir.appendingPathComponent("sync.env")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "API_TOKEN=from-file\nTASKS_URL=http://127.0.0.1:2\n".write(to: file, atomically: true, encoding: .utf8)
        vars["TASKS_ENV_FILE"] = file.path
        var e = env(out: { _ in }, err: { _ in })
        XCTAssertEqual(try Server.resolve(e, override: nil).tokenSource, "TASKS_TOKEN")
        e.vars["TASKS_TOKEN"] = nil
        e.vars["TASKS_URL"] = nil
        let fromFile = try Server.resolve(e, override: nil)
        XCTAssertEqual(fromFile.config.token, "from-file")
        XCTAssertEqual(fromFile.config.url.port, 2)
        try "TASKS_URL=http://127.0.0.1:2\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Server.resolve(e, override: nil))
        XCTAssertEqual(keychainReads, 0, "no Keychain without a terminal: an agent can't answer its dialog")
        e.stdinIsTTY = true
        XCTAssertEqual(try Server.resolve(e, override: nil).tokenSource, "the Tasks app's Keychain item")
        XCTAssertEqual(keychainReads, 1)
    }

    func testOneReplicaPerServerAndNeverTheAppsDirectory() throws {
        let e = env(out: { _ in }, err: { _ in })
        let a = try Server.resolve(e, override: "http://127.0.0.1:8795").directory(e)
        let b = try Server.resolve(e, override: "http://localhost:8795").directory(e)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.lastPathComponent, "127.0.0.1:8795")
        var live = e
        live.vars["TASKS_DATA_DIR"] = nil
        let d = try Server.resolve(live, override: "http://127.0.0.1:8795").directory(live).path
        XCTAssertTrue(d.contains("/Application Support/Tasks CLI/"), d)
    }

    func testTheLockSerializesCommands() throws {
        let replica = dir.appendingPathComponent("r")
        let held = try DirectoryLock(replica)
        XCTAssertThrowsError(try DirectoryLock(replica, wait: 0.1)) { e in
            XCTAssertEqual((e as? CLIError)?.kind, .busy)
        }
        _ = held
    }

    /// Output keys come in the order tasks.d.ts declares them; `kind` only on a heading.
    func testRenderedKeysMatchTheDeclarations() {
        let t = TaskItem(id: "t1", list: "l1", order: "a0", title: "x")
        let h = TaskItem(id: "h1", list: "l1", order: "a1", title: "Labs", isHeading: true)
        let l = TaskList(id: "l1", name: "Inbox", order: "a0")
        var s = AppState()
        s.tasks["t1"] = t
        s.tasks["h1"] = h
        s.lists["l1"] = l
        let r = Render(Projection(confirmed: s, day: Day(containing: now, calendar: calendar)))
        XCTAssertEqual(r.task(t).keys, Shapes.task.filter { !$0.optional }.map(\.name))
        XCTAssertEqual(r.task(h).keys, Shapes.task.map(\.name))
        XCTAssertEqual(r.list(l).keys, Shapes.list.map(\.name))
    }

    func testUsageErrors() async {
        let r = await tasks("add", "Buy", "milk")
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("Quote titles"), r.err)
        let flag = await tasks("today", "--bogus")
        XCTAssertEqual(flag.code, 2)
        let help = await tasks("help", "move")
        XCTAssertTrue(help.out.contains("Example:"), help.out)
    }
}
