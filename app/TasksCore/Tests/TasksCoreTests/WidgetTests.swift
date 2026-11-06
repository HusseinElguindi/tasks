import XCTest
@testable import TasksCore

/// The widgets' shared files (design/WIDGETS.md §3.2–3.3): the feed, the overlay, the inbox and the nudge name.
@MainActor
final class WidgetFeedTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func instant(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func ms(_ s: String) -> Int { Int(instant(s).timeIntervalSince1970 * 1000) }

    /// Thursday 2026-11-05 in New York. Today + 14 is 2026-11-19.
    var day: Day { Day(containing: instant("2026-11-05T12:00:00-05:00"), calendar: cal) }

    /// List A has 12 undated fillers (b0…c1) with a heading among them, then the dated edge cases (d…), so the
    /// edges aren't in A's tops and show the date rule alone. B is short; C is in Trash.
    func fixture() -> Projection {
        var m = OpMaker()
        var ops: [Op] = [
            m.createList("A", name: "School", order: "a0"),
            m.createList("B", name: "Home", order: "a1"),
            m.createList("C", name: "Old", order: "a2"),
        ]
        let fillers = ["b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "c0", "c1"]
        for o in fillers { ops.append(m.createTask("A-\(o)", list: "A", order: o, title: o)) }
        ops.append(m.createTask("A-head", list: "A", order: "b45", title: "Section", kind: Patch.heading))
        ops.append(m.createTask("A-tail-head", list: "A", order: "c5", title: "Late section", kind: Patch.heading))
        ops += [
            m.createTask("when-14", list: "A", order: "d0", when: date("2026-11-19")),
            m.createTask("deadline-14", list: "A", order: "d1", deadline: date("2026-11-19")),
            m.createTask("when-15", list: "A", order: "d2", when: date("2026-11-20")),
            m.createTask("deadline-15", list: "A", order: "d3", deadline: date("2026-11-20")),
            m.createTask("overdue", list: "A", order: "d4", deadline: date("2026-10-01")),
            m.createTask("when-today", list: "A", order: "d5", when: date("2026-11-05")),
            m.createTask("when-tomorrow", list: "A", order: "d6", when: date("2026-11-06")),
            m.createTask("done-today", list: "A", order: "d7", when: date("2026-11-05")),
            m.createTask("done-today-undated", list: "A", order: "d8"),
            m.createTask("done-yesterday", list: "A", order: "d9", when: date("2026-11-04")),
            m.createTask("done-today-deleted", list: "A", order: "e0", when: date("2026-11-05")),
            m.createTask("deleted", list: "A", order: "e1", when: date("2026-11-05")),
            m.createTask("B-today", list: "B", order: "a0", when: date("2026-11-05")),
            m.createTask("B-undated", list: "B", order: "a1"),
            m.createTask("C-today", list: "C", order: "a0", when: date("2026-11-05")),
        ]
        ops += [
            m.updateTask("done-today", Patch(completedAt: .some(ms("2026-11-05T09:00:00-05:00")))),
            m.updateTask("done-today-undated", Patch(completedAt: .some(ms("2026-11-05T00:00:00-05:00")))),
            m.updateTask("done-yesterday", Patch(completedAt: .some(ms("2026-11-04T23:59:59-05:00")))),
            m.updateTask("done-today-deleted", Patch(completedAt: .some(ms("2026-11-05T10:00:00-05:00")))),
            m.updateTask("done-today-deleted", Patch(deleted: true)),
            m.updateTask("deleted", Patch(deleted: true)),
            m.updateList("C", Patch(archivedAt: .some(ms("2026-11-01T10:00:00-05:00")))),
        ]
        return Projection(confirmed: AppState.replay(ops), day: day)
    }

    func testSelection() {
        let p = fixture()
        let feed = WidgetFeed.make(from: p, day: day, now: instant("2026-11-05T12:30:00-05:00"))
        XCTAssertEqual(feed.schema, 1)
        XCTAssertEqual(feed.written, ms("2026-11-05T12:30:00-05:00"))
        XCTAssertEqual(feed.lists, [
            WidgetFeed.List(id: "A", name: "School", order: "a0", slot: ListModel.slot(for: "A")),
            WidgetFeed.List(id: "B", name: "Home", order: "a1", slot: ListModel.slot(for: "B")),
        ])

        let tops = ["A-b0", "A-b1", "A-b2", "A-b3", "A-b4", "A-head", "A-b5", "A-b6", "A-b7", "A-b8", "A-b9", "A-c0", "A-c1"]
        XCTAssertEqual(feed.listTops["A"], tops, "12 tasks with the heading among them; c5's heading and the rest stay out")
        XCTAssertEqual(feed.listTops["B"], ["B-today", "B-undated"])
        XCTAssertNil(feed.listTops["C"], "a list in Trash has no tops")

        let dated = ["when-14", "deadline-14", "overdue", "when-today", "when-tomorrow", "B-today"]
        let doneToday = ["done-today", "done-today-undated"]
        let expected = Set(tops + ["B-undated"] + dated + doneToday)
        XCTAssertEqual(Set(feed.tasks.map(\.id)), expected)
        XCTAssertEqual(feed.tasks.map(\.id), feed.tasks.map(\.id).sorted(), "sorted by id")
        for id in ["when-15", "deadline-15", "done-yesterday", "done-today-deleted", "deleted", "C-today", "A-tail-head"] {
            XCTAssertFalse(feed.tasks.contains { $0.id == id }, id)
        }
        XCTAssertEqual(feed.tasks.first { $0.id == "done-today" }, p.task("done-today"), "TaskItem as the projection has it")
    }

    /// The widget's Today, computed from the feed alone, is the app's Today: for the feed's own day, and for the next
    /// days, as the provider's midnight entries compute them without the app.
    func testTodayMatchesTheApp() {
        let p = fixture()
        let feed = WidgetFeed.make(from: p, day: day)
        let overlay = WidgetOverlay(feed: feed)
        var d = day
        for _ in 0..<3 {
            let appOpen = p.activeLists.ids.flatMap { p.todayTasks(in: $0).ids }
            let appDone = p.todayDone.ids
            let widget = overlay.today(d)
            XCTAssertEqual(widget.open.map(\.id), appOpen, "open on \(d.date)")
            XCTAssertEqual(widget.done.map(\.id), appDone, "done on \(d.date)")
            d = Day(containing: Date(timeIntervalSince1970: Double(d.end) / 1000 + 3600), calendar: cal)
            p.setDay(d)
        }
        XCTAssertEqual(overlay.today(day).open.map(\.id), ["overdue", "when-today", "B-today"])
        XCTAssertEqual(overlay.today(day).done.map(\.id), ["done-today"])
        let tomorrow = Day(containing: instant("2026-11-06T12:00:00-05:00"), calendar: cal)
        XCTAssertEqual(overlay.today(tomorrow).open.map(\.id), ["overdue", "when-today", "when-tomorrow", "B-today"])
        XCTAssertEqual(overlay.today(tomorrow).done.map(\.id), [])
    }

    func testRoundTrip() throws {
        let folder = WidgetFolder.url(in: scratch(), debug: true)
        let url = WidgetFeed.url(in: folder)
        XCTAssertNil(WidgetFeed.read(at: url), "missing")
        let feed = WidgetFeed.make(from: fixture(), day: day)
        try feed.write(at: url) // creates the folder
        XCTAssertEqual(WidgetFeed.read(at: url), feed)
        XCTAssertEqual(url.lastPathComponent, "widget-feed.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Tasks Dev")

        // A second write replaces it.
        var next = feed
        next.written += 1
        next.tasks.removeLast()
        try next.write(at: url)
        XCTAssertEqual(WidgetFeed.read(at: url), next)

        // Not readable: a newer schema, or not a feed.
        next.schema = WidgetFeed.currentSchema + 1
        try next.write(at: url)
        XCTAssertNil(WidgetFeed.read(at: url))
        try Data("{\"schema\":1}".utf8).write(to: url)
        XCTAssertNil(WidgetFeed.read(at: url))
    }

    func testFolders() {
        let group = URL(fileURLWithPath: "/tmp/group", isDirectory: true)
        XCTAssertEqual(WidgetFolder.url(in: group, debug: false).path, "/tmp/group/Tasks")
        XCTAssertEqual(WidgetFolder.url(in: group, debug: true).path, "/tmp/group/Tasks Dev")
        XCTAssertEqual(WidgetFolder.url(in: group), WidgetFolder.url(in: group, debug: true), "tests build with DEBUG")
        XCTAssertEqual(WidgetInbox(folder: WidgetFolder.url(in: group, debug: false)).url.path,
                       "/tmp/group/Tasks/widget-inbox.jsonl")
    }

    func testNudgeName() {
        XCTAssertEqual(WidgetNudge.name(debug: false), "com.elguindi.Tasks.widget")
        XCTAssertEqual(WidgetNudge.name(debug: true), "com.elguindi.Tasks.widget.dev")
        XCTAssertNotEqual(WidgetNudge.name(debug: false), SyncNudge.base)
        XCTAssertEqual(WidgetNudge.name, WidgetNudge.name(debug: true))
    }

    /// The widget's taps on top of the feed (§3.3, §4 Q4).
    func testOverlay() {
        let feed = WidgetFeed.make(from: fixture(), day: day)
        let at = instant("2026-11-05T13:00:00-05:00")
        let check = WidgetInbox.setCompleted("when-today", true, now: at)
        var overlay = WidgetOverlay(feed: feed, ops: [check])

        XCTAssertEqual(overlay.task("when-today")?.completedAt, ms("2026-11-05T13:00:00-05:00"))
        XCTAssertEqual(overlay.today(day).open.map(\.id), ["overdue", "B-today"])
        XCTAssertEqual(overlay.today(day).done.map(\.id), ["done-today", "when-today"], "oldest first")
        XCTAssertEqual(WidgetOverlay(feed: feed).task("when-today")?.completedAt, nil, "the feed itself is untouched")

        // The List widget: the checked row stays in its place, completed.
        let checkTop = WidgetInbox.setCompleted("A-b2", true, now: at)
        overlay.apply(checkTop)
        let rows = overlay.top(of: "A")
        XCTAssertEqual(rows.map(\.id), feed.listTops["A"])
        XCTAssertNotNil(rows[2].completedAt)

        // A second tap un-checks: it settles on the last tap's state.
        overlay.apply(WidgetInbox.setCompleted("when-today", false, now: at.addingTimeInterval(1)))
        XCTAssertEqual(overlay.today(day).open.map(\.id), ["overdue", "when-today", "B-today"])
        XCTAssertNil(overlay.task("when-today")?.completedAt)

        // An op on a task the feed doesn't have is ignored, as the reducer ignores any late update.
        let before = overlay.state
        overlay.apply(WidgetInbox.setCompleted("not-in-feed", true, now: at))
        XCTAssertEqual(overlay.state, before)

        XCTAssertEqual(overlay.top(of: "C"), [], "a list in Trash")
        XCTAssertEqual(overlay.top(of: "nope"), [])
    }

    func testSetCompletedOp() {
        let at = instant("2026-11-05T13:00:00-05:00")
        let op = WidgetInbox.setCompleted("t1", true, now: at, id: "op-1", batch: "b-1")
        XCTAssertEqual(String(decoding: op.jsonData, as: UTF8.self),
                       #"{"id":"op-1","at":\#(ms("2026-11-05T13:00:00-05:00")),"type":"task.update","target":"t1","set":{"completedAt":\#(ms("2026-11-05T13:00:00-05:00"))},"actor":"widget","batch":"b-1"}"#)
        let off = WidgetInbox.setCompleted("t1", false, now: at)
        XCTAssertEqual(off.set, Patch(completedAt: .some(nil)))
        XCTAssertEqual(off.id, off.id.lowercased())
        XCTAssertNotNil(UUID(uuidString: off.id))
        XCTAssertNotNil(off.batch.flatMap { UUID(uuidString: $0) })
        XCTAssertNotEqual(off.id, WidgetInbox.setCompleted("t1", false, now: at).id)
    }

    func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

final class WidgetInboxTests: XCTestCase {
    func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-inbox-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    static func check(_ n: Int, writer: Int = 0) -> Op {
        WidgetInbox.setCompleted("t\(n)", true, now: Date(timeIntervalSince1970: 1_793_900_000 + Double(n)),
                                 id: "w\(writer)-\(n)", batch: "b")
    }

    func testAppendReadRemove() throws {
        let inbox = WidgetInbox(folder: scratch())
        XCTAssertTrue(inbox.read().isEmpty, "no file yet")
        try inbox.removeDrained(inbox.read()) // nothing to do

        try inbox.append(Self.check(1))
        try inbox.append([Self.check(2), Self.check(3)])
        let drain = inbox.read()
        XCTAssertEqual(drain.ops, [Self.check(1), Self.check(2), Self.check(3)])
        let text = try String(contentsOf: inbox.url, encoding: .utf8)
        XCTAssertEqual(text, [Self.check(1), Self.check(2), Self.check(3)].map { String(decoding: $0.jsonData, as: UTF8.self) + "\n" }.joined(),
                       "canonical JSON, one op per line")

        // A tap lands between the drain's read and its removal: it stays.
        try inbox.append(Self.check(4))
        try inbox.removeDrained(drain)
        XCTAssertEqual(inbox.read().ops, [Self.check(4)])

        try inbox.removeDrained(inbox.read())
        XCTAssertTrue(inbox.read().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.url.path), "removed when empty")
    }

    func testBadLinesAreSkipped() throws {
        let inbox = WidgetInbox(folder: scratch())
        try inbox.append(Self.check(1))
        let h = try FileHandle(forWritingTo: inbox.url)
        h.seekToEndOfFile()
        h.write(Data("not json\n\n{\"id\":\"x\"}\n".utf8))
        try h.close()
        try inbox.append(Self.check(2))
        XCTAssertEqual(inbox.read().ops, [Self.check(1), Self.check(2)])
        try inbox.removeDrained(WidgetInbox.Drain(ops: [Self.check(1)]))
        XCTAssertEqual(try String(contentsOf: inbox.url, encoding: .utf8),
                       String(decoding: Self.check(2).jsonData, as: UTF8.self) + "\n", "bad lines go with a rewrite")
    }

    /// Two writers append while a drainer reads and removes, each with its own descriptors (as the widget's process
    /// and the app's are): every op is drained exactly once or still waiting, and no line is torn.
    func testTwoWritersAndADrainer() throws {
        let folder = scratch()
        let perWriter = 300
        let drained = Locked<[Op]>([])
        let done = Locked(0)
        let group = DispatchGroup()
        for w in 0..<2 {
            DispatchQueue.global().async(group: group) {
                let inbox = WidgetInbox(folder: folder)
                for n in 0..<perWriter {
                    try! inbox.append(Self.check(n, writer: w))
                }
                done.withLock { $0 += 1 }
            }
        }
        DispatchQueue.global().async(group: group) {
            let inbox = WidgetInbox(folder: folder)
            while true {
                let finished = done.withLock { $0 } == 2
                let d = inbox.read()
                drained.withLock { $0 += d.ops }
                try! inbox.removeDrained(d)
                if finished { break }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        let inbox = WidgetInbox(folder: folder)
        let all = drained.withLock { $0 } + inbox.read().ops
        let ids = all.map(\.id)
        XCTAssertEqual(ids.count, 2 * perWriter)
        XCTAssertEqual(Set(ids).count, ids.count, "nothing drained twice")
        for w in 0..<2 {
            let mine = all.filter { $0.id.hasPrefix("w\(w)-") }
            XCTAssertEqual(mine, (0..<perWriter).map { Self.check($0, writer: w) }, "each writer's ops in its order, whole")
        }
    }

    /// An append waits while another descriptor holds the lock (flock locks belong to the open file description, so
    /// this is what another process holding it looks like).
    func testAppendWaitsForTheLock() throws {
        let inbox = WidgetInbox(folder: scratch())
        try inbox.append(Self.check(0))
        let fd = open(inbox.lockURL.path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let appended = expectation(description: "append ran")
        DispatchQueue.global().async {
            try! inbox.append(Self.check(1))
            appended.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.3)
        let held = try Data(contentsOf: inbox.url) // not read(): that would wait for the lock too
        XCTAssertEqual(WidgetInbox.ops(in: held).map(\.id), ["w0-0"], "nothing appended while the lock is held")
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        wait(for: [appended], timeout: 5)
        XCTAssertEqual(inbox.read().ops.map(\.id), ["w0-0", "w0-1"])
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&value) } }
}
