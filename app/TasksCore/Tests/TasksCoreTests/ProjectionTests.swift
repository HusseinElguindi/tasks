import XCTest
@testable import TasksCore

/// Checks an incrementally maintained projection against one rebuilt from scratch: visible entities, every index
/// bucket, placements, and every cached model's values (spec §8 "Rebase", §9).
@MainActor
func assertMatchesRebuild(_ p: Projection, _ context: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
    let fresh = Projection(confirmed: p.confirmed, pending: p.pending, day: p.day)
    let ctx = context()
    for id in p.allTaskIDs.union(fresh.allTaskIDs) where p.task(id) != fresh.task(id) {
        XCTFail("\(ctx): task \(id) visible \(String(describing: p.task(id))) != rebuilt \(String(describing: fresh.task(id)))", file: file, line: line)
    }
    for id in p.allListIDs.union(fresh.allListIDs) where p.list(id) != fresh.list(id) {
        XCTFail("\(ctx): list \(id) differs", file: file, line: line)
    }
    func compare(_ a: [EntityID: Bucket], _ b: [EntityID: Bucket], _ name: String) {
        for list in Set(a.keys).union(b.keys) {
            let x = a[list]?.ids ?? [], y = b[list]?.ids ?? []
            if x != y { XCTFail("\(ctx): \(name)[\(list)] \(x) != rebuilt \(y)", file: file, line: line) }
            if let keys = a[list]?.keys, keys != keys.sorted() { XCTFail("\(ctx): \(name)[\(list)] unsorted", file: file, line: line) }
        }
    }
    compare(p.open, fresh.open, "open")
    compare(p.headings, fresh.headings, "headings")
    compare(p.completed, fresh.completed, "completed")
    compare(p.today, fresh.today, "today")
    XCTAssertEqual(p.todayDone.ids, fresh.todayDone.ids, "\(ctx): todayDone", file: file, line: line)
    XCTAssertEqual(p.activeLists.ids, fresh.activeLists.ids, "\(ctx): activeLists", file: file, line: line)
    XCTAssertEqual(p.deletedLists.ids, fresh.deletedLists.ids, "\(ctx): deletedLists", file: file, line: line)
    XCTAssertEqual(p.taskPlacement, fresh.taskPlacement, "\(ctx): task placements", file: file, line: line)
    XCTAssertEqual(p.listPlacement, fresh.listPlacement, "\(ctx): list placements", file: file, line: line)
    for (id, m) in p.taskModels {
        guard let t = fresh.task(id) else { XCTFail("\(ctx): model for vanished task \(id)", file: file, line: line); continue }
        if !m.matches(t) { XCTFail("\(ctx): task model \(id) is stale", file: file, line: line) }
    }
    for (id, m) in p.listModels {
        guard let l = fresh.list(id) else { XCTFail("\(ctx): model for vanished list \(id)", file: file, line: line); continue }
        if !m.matches(l) { XCTFail("\(ctx): list model \(id) is stale", file: file, line: line) }
    }
}

@MainActor
final class ProjectionTests: XCTestCase {
    var m = OpMaker()
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }()
    lazy var day = Day(containing: Date(timeIntervalSince1970: 1_761_840_000), calendar: cal) // 2025-10-30 12:00 EDT

    func testLocalEditTouchesOneEntityAndOneRow() {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "School", order: "a0")])
        p.perform([m.createTask("a", list: "L", order: "a0", title: "A"), m.createTask("b", list: "L", order: "a1", title: "B")])
        XCTAssertEqual(p.openTasks(in: "L").ids, ["a", "b"])
        let modelA = p.taskModel("a")!
        let modelB = p.taskModel("b")!

        let bucketChanged = Flag()
        let bChanged = Flag()
        withObservationTracking { _ = p.openTasks(in: "L").ids } onChange: { bucketChanged.set() }
        withObservationTracking { _ = modelB.title } onChange: { bChanged.set() }
        p.perform([m.updateTask("a", Patch(title: "A2"))])
        XCTAssertEqual(modelA.title, "A2")
        XCTAssertFalse(bucketChanged.value, "a title edit doesn't touch the list's bucket")
        XCTAssertFalse(bChanged.value, "nor other rows")

        p.perform([m.updateTask("b", Patch(list: "L", order: "Zz"))])
        XCTAssertTrue(bucketChanged.value, "a reorder changes ids")
        XCTAssertEqual(p.openTasks(in: "L").ids, ["b", "a"])
        assertMatchesRebuild(p, "after edits")
    }

    /// Assigning an equal value still notifies with Observation, so models only assign fields that differ.
    func testModelsAssignOnlyChangedFields() {
        let p = Projection(day: day)
        p.perform([m.createTask("a", list: "L", order: "a0", title: "A")])
        let model = p.taskModel("a")!
        let titleChanged = Flag()
        withObservationTracking { _ = model.title } onChange: { titleChanged.set() }
        p.perform([m.updateTask("a", Patch(notes: "n"))])
        p.perform([m.updateTask("a", Patch(title: "A"))])
        XCTAssertFalse(titleChanged.value)
    }

    /// Fast path: the new entries are exactly our own pending ops, in order. Nothing redraws.
    func testFastPathConfirmsWithoutRedraw() {
        let p = Projection(day: day)
        let ops = [m.createList("L", name: "L", order: "a0"), m.createTask("a", list: "L", order: "a0", title: "x")]
        p.perform(ops)
        let model = p.taskModel("a")!
        let changed = Flag()
        withObservationTracking {
            _ = p.openTasks(in: "L").ids
            _ = model.title
            _ = p.activeLists.ids
        } onChange: { changed.set() }
        XCTAssertEqual(p.confirm(ops), .fast)
        XCTAssertFalse(changed.value)
        XCTAssertTrue(p.pending.isEmpty)
        XCTAssertEqual(p.confirmed.tasks["a"]?.title, "x")
        assertMatchesRebuild(p, "fast path")
    }

    /// The spec's "rename T on two Macs" example: the remote rename must not flip the screen, and the final
    /// answer is what the log says.
    func testRemoteRenameDoesNotOverrideLaterLocalRename() {
        var bMaker = OpMaker(counter: 1000)
        let create = m.createTask("T", list: "L", order: "a0", title: "t")
        let a = Projection(confirmed: AppState.replay([create]), day: day)
        let renameB = bMaker.updateTask("T", Patch(title: "Groceries"))
        let renameA = m.updateTask("T", Patch(title: "Shopping"))
        a.perform([renameA])                       // A, offline, renames. Its screen shows "Shopping".
        XCTAssertEqual(a.task("T")?.title, "Shopping")
        // A syncs: the server appends A's op after B's.
        XCTAssertEqual(a.confirm([renameB, renameA]), .general)
        XCTAssertEqual(a.task("T")?.title, "Shopping")
        XCTAssertEqual(a.confirmed.tasks["T"]?.title, "Shopping")
        assertMatchesRebuild(a, "both confirmed")

        // Variant: A's rename was made while the request was in flight, so this page only has B's op.
        let a2 = Projection(confirmed: AppState.replay([create]), day: day)
        a2.perform([renameA])
        a2.confirm([renameB])
        XCTAssertEqual(a2.task("T")?.title, "Shopping")
        XCTAssertEqual(a2.confirmed.tasks["T"]?.title, "Groceries")
        assertMatchesRebuild(a2, "in flight")
    }

    /// Two Macs seed the Inbox with the same op id but their own clocks. The log keeps the first; the second Mac
    /// must take the log's version even though the op id matches its pending head.
    func testSeedWithSameIDButDifferentContentTakesTheLogsVersion() {
        let seedA = Seed.inboxIfMissing(listExists: { _ in false }, now: 100)!
        let seedB = Seed.inboxIfMissing(listExists: { _ in false }, now: 200)!
        let b = Projection(day: day)
        b.perform([seedB, m.updateList(Spec.inbox, Patch(name: "Desk"))])
        let model = b.listModel(Spec.inbox)!
        XCTAssertEqual(model.createdAt, 200)
        XCTAssertEqual(b.confirm([seedA]), .general)
        XCTAssertEqual(b.list(Spec.inbox)?.createdAt, 100)
        XCTAssertEqual(b.list(Spec.inbox)?.name, "Desk")
        XCTAssertEqual(model.createdAt, 100)
        XCTAssertEqual(b.pending.count, 1)
        assertMatchesRebuild(b, "seed dedup")
    }

    func testDeletingAListMovesOneListAndHidesItsTasksFromToday() {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "L", order: "a0"), m.createList("M", name: "M", order: "a1")])
        p.perform([m.createTask("a", list: "L", order: "a0", when: day.date)])
        p.perform([m.createTask("d", list: "L", order: "a1", when: day.date)])
        p.perform([m.updateTask("d", Patch(completedAt: .some(day.start + 1000)))])
        XCTAssertEqual(p.todayTasks(in: "L").ids, ["a"])
        XCTAssertEqual(p.todayDone.ids, ["d"])
        XCTAssertEqual(p.activeLists.ids, ["L", "M"])

        p.perform([m.updateList("L", Patch(archivedAt: .some(5)))])
        XCTAssertEqual(p.activeLists.ids, ["M"])
        XCTAssertEqual(p.deletedLists.ids, ["L"])
        XCTAssertEqual(p.openTasks(in: "L").ids, ["a"], "task buckets ignore whether the list is deleted")
        XCTAssertEqual(p.todayDone.ids, [], "done-today follows the list")
        assertMatchesRebuild(p, "deleted")
        p.perform([m.updateList("L", Patch(archivedAt: .some(nil)))])
        XCTAssertEqual(p.todayDone.ids, ["d"])
        assertMatchesRebuild(p, "restored")
    }

    /// §28: a task in a deleted list counts as deleted; Trash holds the list once, with its tasks under it, and a task
    /// deleted on its own as a row of its own, wherever its list is.
    func testDeletedListsTasksCountAsDeletedAndTrashHoldsTheListOnce() {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "School", order: "a0"), m.createList("M", name: "Inbox", order: "a1")])
        p.perform([m.createTask("a", list: "L", order: "a0", when: day.date), m.createTask("b", list: "L", order: "a1"),
                   m.createTask("h", list: "L", order: "a2", kind: Patch.heading), m.createTask("c", list: "L", order: "a3"),
                   m.createTask("x", list: "M", order: "a0")])
        p.perform([m.updateTask("c", Patch(completedAt: .some(day.start + 1000)))])
        p.perform([m.updateTask("x", Patch(deleted: true))])
        XCTAssertTrue(p.isLive(task: "a"))
        XCTAssertFalse(p.isLive(task: "x"))

        p.perform([m.updateList("L", Patch(archivedAt: .some(m.at + 500)))])
        for id in ["a", "b", "c", "h"] { XCTAssertFalse(p.isLive(task: id), id) }
        XCTAssertFalse(p.task("a")!.deleted, "no cascade: the tasks aren't written")
        XCTAssertTrue(p.isDeleted(list: "L"))
        XCTAssertEqual(p.trash().map(\.item), [.list("L"), .task("x")], "newest deleted first, the list once")
        XCTAssertEqual(p.tasksInDeletedList("L"), ["a", "b", "c"], "open in order, then completed; no heading")
        assertMatchesRebuild(p, "deleted")

        p.perform([m.updateList("L", Patch(archivedAt: .some(nil)))])
        for id in ["a", "b", "c", "h"] { XCTAssertTrue(p.isLive(task: id) || p.task(id)!.completedAt != nil, id) }
        XCTAssertEqual(p.trash().map(\.item), [.task("x")])
        XCTAssertEqual(p.todayTasks(in: "L").ids, ["a"])
        assertMatchesRebuild(p, "restored")
    }

    /// A task deleted before its list is a row of its own in Trash, on its own day, and restoring the list leaves it
    /// deleted (the user's rule, §28).
    func testTaskDeletedBeforeItsListStaysDeletedWhenTheListIsRestored() {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "School", order: "a0")])
        p.perform([m.createTask("a", list: "L", order: "a0"), m.createTask("old", list: "L", order: "a1")])
        p.perform([m.updateTask("old", Patch(deleted: true))])
        let oldAt = p.task("old")!.updatedAt
        p.perform([m.updateList("L", Patch(archivedAt: .some(m.at + 500)))])
        XCTAssertEqual(p.trash().map(\.item), [.list("L"), .task("old")])
        XCTAssertEqual(p.trash().last?.deletedAt, oldAt, "on the day it was deleted")
        XCTAssertEqual(p.tasksInDeletedList("L"), ["a"], "not under the list")

        p.perform([m.updateList("L", Patch(archivedAt: .some(nil)))])
        XCTAssertTrue(p.isLive(task: "a"))
        XCTAssertFalse(p.isLive(task: "old"))
        XCTAssertTrue(p.task("old")!.deleted)
        XCTAssertEqual(p.openTasks(in: "L").ids, ["a"])
        XCTAssertEqual(p.trash().map(\.item), [.task("old")])
        assertMatchesRebuild(p, "restored, the old one still deleted")
    }

    func testMidnightRebuildsToday() {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "L", order: "a0")])
        p.perform([m.createTask("tomorrow", list: "L", order: "a0", when: day.date.adding(days: 1))])
        p.perform([m.createTask("done", list: "L", order: "a1", when: day.date)])
        p.perform([m.updateTask("done", Patch(completedAt: .some(day.end - 1)))])
        XCTAssertEqual(p.todayTasks(in: "L").ids, [])
        XCTAssertEqual(p.todayDone.ids, ["done"])
        let next = Day(containing: Date(timeIntervalSince1970: TimeInterval(day.end) / 1000 + 1), calendar: cal)
        p.setDay(next)
        XCTAssertEqual(p.todayTasks(in: "L").ids, ["tomorrow"])
        XCTAssertEqual(p.todayDone.ids, [])
        assertMatchesRebuild(p, "after midnight")
    }

    func testRejectRebuildsEntity() {
        let p = Projection(day: day)
        p.perform([m.createTask("a", list: "L", order: "a0", title: "x")])
        let bad = m.updateTask("a", Patch(order: "a 0", title: "y"))
        p.perform([bad, m.updateTask("a", Patch(notes: "kept"))])
        XCTAssertEqual(p.task("a")?.order, "a 0")
        XCTAssertEqual(p.reject(opID: bad.id)?.op, bad)
        XCTAssertEqual(p.task("a")?.title, "x")
        XCTAssertEqual(p.task("a")?.order, "a0")
        XCTAssertEqual(p.task("a")?.notes, "kept")
        assertMatchesRebuild(p, "after reject")
    }

    /// 409 recovery: confirmed restarts empty and log + pending become pending. The screen doesn't jump.
    func testRecoverKeepsVisibleState() {
        let log = [m.createList("L", name: "L", order: "a0"), m.createTask("a", list: "L", order: "a0", title: "x"),
                   m.updateTask("a", Patch(when: .some(day.date)))]
        let p = Projection(confirmed: AppState.replay(log), day: day)
        p.perform([m.updateTask("a", Patch(title: "y")), m.createTask("b", list: "L", order: "a1")])
        let model = p.taskModel("a")!
        let before = (p.task("a"), p.task("b"), p.openTasks(in: "L").ids, p.todayTasks(in: "L").ids)
        let titleChanged = Flag()
        withObservationTracking { _ = model.title } onChange: { titleChanged.set() }
        p.recover(pending: log.map(PendingOp.init) + p.pending)
        XCTAssertEqual(p.confirmed, AppState())
        XCTAssertEqual(p.pending.count, 5)
        XCTAssertEqual(p.task("a"), before.0)
        XCTAssertEqual(p.task("b"), before.1)
        XCTAssertEqual(p.openTasks(in: "L").ids, before.2)
        XCTAssertEqual(p.todayTasks(in: "L").ids, before.3)
        XCTAssertFalse(titleChanged.value)
        assertMatchesRebuild(p, "after recover")
        // The log comes back from a restored server in a different order, behind another Mac's op.
        var other = OpMaker(counter: 500)
        let remote = other.updateTask("a", Patch(title: "remote"))
        p.confirm([log[0], remote, log[1]] , touchingAll: true)
        assertMatchesRebuild(p, "recovery page 1")
        p.confirm(p.pending.map(\.op), touchingAll: true)
        XCTAssertTrue(p.pending.isEmpty)
        XCTAssertEqual(p.task("a")?.title, "y")
        assertMatchesRebuild(p, "recovery done")
    }
}

/// Spec §8: two or three simulated Macs make random ops and sync in random orders, with partial pushes, small
/// pages and ops created while a request is in flight. After every sync, visible state, indexes and model values
/// must equal a from-scratch replay of confirmed log + pending; at the end every Mac converges.
@MainActor
final class RebaseTests: XCTestCase {
    struct Server {
        var log: [Op] = []
        var ids: Set<String> = []
        mutating func append(_ ops: [Op]) {
            for op in ops where !ids.contains(op.id) {
                ids.insert(op.id)
                log.append(op)
            }
        }

        /// Restored from an older backup (or wiped, k = 0).
        mutating func restore(to k: Int) {
            log = Array(log.prefix(k))
            ids = Set(log.map(\.id))
        }

        /// The 409 check: `from > head`, or the hash chain at `from − 1` differs (i.e. any earlier entry differs).
        func mismatches(_ macLog: [Op]) -> Bool {
            macLog.count > log.count || !macLog.map(\.id).elementsEqual(log.prefix(macLog.count).map(\.id))
        }
    }

    @MainActor
    final class Mac {
        let name: String
        let projection: Projection
        var cursor = 0
        /// The Mac's log.jsonl (ops only).
        var log: [Op] = []
        var recovering = false
        var maker: OpMaker
        var rng: SeededRandom
        var listIDs: [EntityID] = []
        var counter = 0

        init(name: String, seed: UInt64, day: Day) {
            self.name = name
            projection = Projection(day: day)
            maker = OpMaker(counter: Int(seed) * 1_000_000)
            rng = SeededRandom(seed: seed)
        }

        func freshID(_ prefix: String) -> String {
            counter += 1
            return "\(name)-\(prefix)\(counter)"
        }
    }

    func testRandomInterleavingsMatchFullReplay() {
        for seed: UInt64 in [1, 2, 3, 4] {
            run(seed: seed, macs: seed % 2 == 0 ? 3 : 2, steps: 600, restores: false)
        }
    }

    /// The same, with the server restored to an older point (or wiped) at random moments: Macs that 409 re-push
    /// every op they know (spec §5). The server must end up holding every op id any Mac ever had.
    func testRandomServerRestoresLoseNothing() {
        for seed: UInt64 in [11, 12, 13, 14, 15, 16] {
            run(seed: seed, macs: seed % 2 == 0 ? 3 : 2, steps: 600, restores: true)
        }
    }

    func run(seed: UInt64, macs count: Int, steps: Int, restores: Bool) {
        var rng = SeededRandom(seed: seed &* 7919)
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "America/Toronto")!
            return c
        }()
        var now = Date(timeIntervalSince1970: 1_761_840_000)
        var day = Day(containing: now, calendar: cal)
        var server = Server()
        var everyOpID: Set<String> = []
        func record(_ mac: Mac) { for p in mac.projection.pending { everyOpID.insert(p.op.id) } }
        let macs = (0..<count).map { Mac(name: "m\($0)", seed: seed * 10 + UInt64($0), day: day) }
        // Every Mac seeds the Inbox on first launch, with its own clock: same op id, different `at`.
        for mac in macs {
            mac.projection.perform([Seed.inboxIfMissing(listExists: { mac.projection.list($0) != nil }, now: mac.maker.next().1)!])
            record(mac)
        }

        func check(_ mac: Mac, _ what: String) {
            let p = mac.projection
            // Rows on screen: materialize every list's model and some task models, as views would.
            for id in p.allListIDs { _ = p.listModel(id) }
            for id in p.allTaskIDs where id.hashValue % 3 == 0 { _ = p.taskModel(id) }
            XCTAssertEqual(mac.cursor, mac.log.count)
            XCTAssertEqual(p.confirmed, AppState.replay(mac.log), "seed \(seed) \(mac.name) \(what): confirmed")
            assertMatchesRebuild(p, "seed \(seed) \(mac.name) \(what)")
        }

        /// One request: 409 → recovery; otherwise push a prefix of pending and apply one page.
        func sync(_ mac: Mac, inFlightOps: Bool, fullPush: Bool = false) {
            let p = mac.projection
            if server.mismatches(mac.log) {
                // Recovery: log ops (seq order) then pending, first occurrence of each id; confirmed restarts empty.
                var seen: Set<String> = []
                let queue = (mac.log.map(PendingOp.init) + p.pending).filter { seen.insert($0.op.id).inserted }
                p.recover(pending: queue)
                mac.log = []
                mac.cursor = 0
                mac.recovering = true
                check(mac, "after 409 recovery began")
            }
            let pushCount = fullPush ? min(p.pending.count, 500) : Int.random(in: 0...p.pending.count, using: &rng)
            server.append(p.pending.prefix(pushCount).map(\.op))
            let limit = fullPush ? 1000 : Int.random(in: 1...12, using: &rng)
            let page = Array(server.log[mac.cursor..<min(server.log.count, mac.cursor + limit)])
            if inFlightOps {
                randomOps(mac, day: day, count: Int.random(in: 1...3, using: &rng))
                record(mac)
            }
            p.confirm(page, touchingAll: mac.recovering)
            mac.cursor += page.count
            mac.log += page
            if mac.recovering, mac.cursor == server.log.count, p.pending.isEmpty { mac.recovering = false }
            check(mac, "after sync")
        }

        for step in 0..<steps {
            let mac = macs.randomElement(using: &rng)!
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<5:
                randomOps(mac, day: day, count: Int.random(in: 1...3, using: &rng))
                record(mac)
                if step % 7 == 0 { check(mac, "after local ops") }
            case 5..<9:
                if restores, Int.random(in: 0..<12, using: &rng) == 0 {
                    // Restored from a backup somewhere in the past, sometimes wiped.
                    server.restore(to: Bool.random(using: &rng) ? 0 : Int.random(in: 0...server.log.count, using: &rng))
                }
                sync(mac, inFlightOps: Bool.random(using: &rng))
            default:
                // Time passes; sometimes past midnight.
                now += TimeInterval(Int.random(in: 1...10, using: &rng) * 3600)
                day = Day(containing: now, calendar: cal)
                for mac in macs { mac.projection.setDay(day) }
                check(mac, "after time change")
            }
        }

        // Drain: everyone syncs until nothing is pending and they're at the head; all converge.
        for _ in 0..<3 {
            for mac in macs {
                var guardRail = 0
                while (server.mismatches(mac.log) || !mac.projection.pending.isEmpty || mac.cursor < server.log.count) && guardRail < 1000 {
                    sync(mac, inFlightOps: false, fullPush: true)
                    guardRail += 1
                }
            }
        }
        XCTAssertTrue(everyOpID.isSubset(of: server.ids),
                      "seed \(seed): the server lost \(everyOpID.subtracting(server.ids).count) op ids")
        let first = macs[0].projection
        for mac in macs.dropFirst() {
            let p = mac.projection
            XCTAssertTrue(p.pending.isEmpty)
            XCTAssertEqual(p.confirmed, first.confirmed, "seed \(seed): \(mac.name) converged")
            XCTAssertEqual(p.activeLists.ids, first.activeLists.ids)
            for l in first.activeLists.ids {
                XCTAssertEqual(p.openTasks(in: l).ids, first.openTasks(in: l).ids)
                XCTAssertEqual(p.todayTasks(in: l).ids, first.todayTasks(in: l).ids)
            }
            XCTAssertEqual(p.todayDone.ids, first.todayDone.ids)
        }
        XCTAssertGreaterThan(server.log.count, steps / 3, "seed \(seed): the simulation did real work")
    }

    /// Realistic local actions: creates, edits, completes, deletes, drags (via Ordering), moves, archives, seeding.
    func randomOps(_ mac: Mac, day: Day, count: Int) {
        let p = mac.projection
        for _ in 0..<count {
            var ops: [Op] = []
            let lists = p.allListIDs.sorted()
            let tasks = p.allTaskIDs.sorted()
            let dates = [day.date.adding(days: -2), day.date, day.date.adding(days: 1), day.date.adding(days: 7)]
            switch Int.random(in: 0..<20, using: &mac.rng) {
            case 0:
                ops.append(Seed.inboxIfMissing(listExists: { p.list($0) != nil }, now: mac.maker.next().1)
                           ?? mac.maker.updateList(lists.randomElement(using: &mac.rng)!, Patch(name: "renamed")))
            case 1, 2:
                guard lists.count < 4 else { fallthrough }
                let id = mac.freshID("L")
                let key = Ordering.append([id], after: p.orderedActiveLists()).last?.order ?? "a0"
                ops.append(mac.maker.createList(id, name: "List \(id)", order: key))
            case 3..<7:
                guard let list = lists.randomElement(using: &mac.rng) else { continue }
                let id = mac.freshID("t")
                let key = Bool.random(using: &mac.rng)
                    ? (Ordering.append([id], after: p.orderedOpenTasks(in: list)).last?.order ?? "a0")
                    : "a0" // a duplicate key on purpose: ties are broken by id
                // Some are headings (§23), now and then with dates another client wrote on them.
                ops.append(mac.maker.createTask(id, list: list, order: key, title: "t",
                                                when: Bool.random(using: &mac.rng) ? dates.randomElement(using: &mac.rng) : nil,
                                                deadline: Bool.random(using: &mac.rng) ? dates.randomElement(using: &mac.rng) : nil,
                                                kind: Int.random(in: 0..<5, using: &mac.rng) == 0 ? Patch.heading : nil))
            case 7, 8:
                guard let t = tasks.randomElement(using: &mac.rng) else { continue }
                let c: Int?? = Bool.random(using: &mac.rng)
                    ? .some(nil)
                    : .some([day.start + 5, day.end - 5, day.start - 5, day.end + 5].randomElement(using: &mac.rng)!)
                ops.append(mac.maker.updateTask(t, Patch(completedAt: c)))
            case 9:
                guard let t = tasks.randomElement(using: &mac.rng) else { continue }
                ops.append(mac.maker.updateTask(t, Patch(deleted: Bool.random(using: &mac.rng))))
            case 10, 11:
                // Drag within the list (possibly several tasks), with Ordering computing keys.
                guard let list = lists.randomElement(using: &mac.rng) else { continue }
                let items = p.orderedOpenTasks(in: list)
                guard !items.isEmpty else { continue }
                let moving = Array(items.shuffled(using: &mac.rng).prefix(Int.random(in: 1...min(3, items.count), using: &mac.rng))).map(\.id)
                let anchor: Ordering.Anchor = [.top, .bottom, .after(items.randomElement(using: &mac.rng)!.id),
                                               .before(items.randomElement(using: &mac.rng)!.id)].randomElement(using: &mac.rng)!
                for placed in Ordering.place(moving, at: anchor, in: items) {
                    ops.append(mac.maker.updateTask(placed.id, Patch(list: list, order: placed.order)))
                }
            case 12:
                // Move to another list (lands at the bottom).
                guard let t = tasks.randomElement(using: &mac.rng), let list = lists.randomElement(using: &mac.rng) else { continue }
                for placed in Ordering.append([t], after: p.orderedOpenTasks(in: list)) {
                    ops.append(mac.maker.updateTask(placed.id, Patch(list: list, order: placed.order)))
                }
            case 13, 17:
                guard let l = lists.randomElement(using: &mac.rng) else { continue }
                let archived: Int?? = Bool.random(using: &mac.rng) ? .some(nil) : .some(Int.random(in: 1...1000, using: &mac.rng))
                ops.append(mac.maker.updateList(l, Patch(archivedAt: archived)))
            case 14:
                guard let l = lists.randomElement(using: &mac.rng) else { continue }
                let items = p.orderedActiveLists()
                for placed in Ordering.place([l], at: .top, in: items) {
                    ops.append(mac.maker.updateList(placed.id, Patch(order: placed.order)))
                }
            case 15:
                ops.append(mac.maker.updateTask("ghost", Patch(title: "nobody")))
            default:
                guard let t = tasks.randomElement(using: &mac.rng) else { continue }
                ops.append(mac.maker.updateTask(t, randomTaskPatch(&mac.rng)))
            }
            p.perform(ops)
        }
    }
}
