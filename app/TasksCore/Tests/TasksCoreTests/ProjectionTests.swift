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
    compare(p.completed, fresh.completed, "completed")
    compare(p.today, fresh.today, "today")
    XCTAssertEqual(p.todayDone.ids, fresh.todayDone.ids, "\(ctx): todayDone", file: file, line: line)
    XCTAssertEqual(p.activeLists.ids, fresh.activeLists.ids, "\(ctx): activeLists", file: file, line: line)
    XCTAssertEqual(p.archivedLists.ids, fresh.archivedLists.ids, "\(ctx): archivedLists", file: file, line: line)
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

    func testArchiveMovesOneListAndHidesItsTasksFromToday() {
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
        XCTAssertEqual(p.archivedLists.ids, ["L"])
        XCTAssertEqual(p.openTasks(in: "L").ids, ["a"], "task buckets ignore archive state")
        XCTAssertEqual(p.todayDone.ids, [], "done-today follows the list")
        assertMatchesRebuild(p, "archived")
        p.perform([m.updateList("L", Patch(archivedAt: .some(nil)))])
        XCTAssertEqual(p.todayDone.ids, ["d"])
        assertMatchesRebuild(p, "unarchived")
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
        XCTAssertEqual(p.reject(opID: bad.id), bad)
        XCTAssertEqual(p.task("a")?.title, "x")
        XCTAssertEqual(p.task("a")?.order, "a0")
        XCTAssertEqual(p.task("a")?.notes, "kept")
        assertMatchesRebuild(p, "after reject")
    }

    func testResetConfirmedReplaysPendingOnEmpty() {
        let create = m.createTask("a", list: "L", order: "a0", title: "x")
        let p = Projection(confirmed: AppState.replay([m.createList("L", name: "L", order: "a0"), create]), day: day)
        p.perform([m.updateTask("a", Patch(title: "y")), m.createTask("b", list: "L", order: "a1")])
        let model = p.taskModel("b")!
        p.resetConfirmed()
        XCTAssertNil(p.task("a"), "an update on an unknown id is ignored")
        XCTAssertEqual(p.task("b")?.list, "L")
        XCTAssertEqual(model.list, "L")
        assertMatchesRebuild(p, "after reset")
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
    }

    @MainActor
    final class Mac {
        let name: String
        let projection: Projection
        var cursor = 0
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
            run(seed: seed, macs: seed % 2 == 0 ? 3 : 2, steps: 600)
        }
    }

    func run(seed: UInt64, macs count: Int, steps: Int) {
        var rng = SeededRandom(seed: seed &* 7919)
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "America/Toronto")!
            return c
        }()
        var now = Date(timeIntervalSince1970: 1_761_840_000)
        var day = Day(containing: now, calendar: cal)
        var server = Server()
        let macs = (0..<count).map { Mac(name: "m\($0)", seed: seed * 10 + UInt64($0), day: day) }
        // Every Mac seeds the Inbox on first launch, with its own clock: same op id, different `at`.
        for mac in macs {
            mac.projection.perform([Seed.inboxIfMissing(listExists: { mac.projection.list($0) != nil }, now: mac.maker.next().1)!])
        }

        func check(_ mac: Mac, _ what: String) {
            let p = mac.projection
            // Rows on screen: materialize every list's model and some task models, as views would.
            for id in p.allListIDs { _ = p.listModel(id) }
            for id in p.allTaskIDs where id.hashValue % 3 == 0 { _ = p.taskModel(id) }
            XCTAssertEqual(p.confirmed, AppState.replay(server.log.prefix(mac.cursor)), "seed \(seed) \(mac.name) \(what): confirmed")
            assertMatchesRebuild(p, "seed \(seed) \(mac.name) \(what)")
        }

        func sync(_ mac: Mac, inFlightOps: Bool) {
            let p = mac.projection
            let pushCount = Int.random(in: 0...p.pending.count, using: &rng)
            server.append(Array(p.pending.prefix(pushCount)))
            let limit = Int.random(in: 1...12, using: &rng)
            let page = Array(server.log[mac.cursor..<min(server.log.count, mac.cursor + limit)])
            if inFlightOps { randomOps(mac, day: day, count: Int.random(in: 1...3, using: &rng)) }
            p.confirm(page)
            mac.cursor += page.count
            check(mac, "after sync")
        }

        for step in 0..<steps {
            let mac = macs.randomElement(using: &rng)!
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<5:
                randomOps(mac, day: day, count: Int.random(in: 1...3, using: &rng))
                if step % 7 == 0 { check(mac, "after local ops") }
            case 5..<9:
                sync(mac, inFlightOps: Bool.random(using: &rng))
            default:
                // Time passes; sometimes past midnight.
                now += TimeInterval(Int.random(in: 1...10, using: &rng) * 3600)
                day = Day(containing: now, calendar: cal)
                for mac in macs { mac.projection.setDay(day) }
                check(mac, "after time change")
            }
        }

        // Drain: everyone pushes everything and pulls to the head; all converge.
        for _ in 0..<2 {
            for mac in macs {
                server.append(mac.projection.pending)
                mac.projection.confirm(Array(server.log[mac.cursor...]))
                mac.cursor = server.log.count
                check(mac, "drain")
            }
        }
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
                ops.append(mac.maker.createTask(id, list: list, order: key, title: "t",
                                                when: Bool.random(using: &mac.rng) ? dates.randomElement(using: &mac.rng) : nil,
                                                deadline: Bool.random(using: &mac.rng) ? dates.randomElement(using: &mac.rng) : nil))
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
