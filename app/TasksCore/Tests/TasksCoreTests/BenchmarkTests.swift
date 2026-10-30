import XCTest
@testable import TasksCore

/// Spec §9 budgets on a generated 10k-task / 100k-op fixture. Timings are app work on the calling thread.
///
/// Budgets are enforced in release builds (`swift test -c release --filter BenchmarkTests`), where a regression
/// fails the test. Debug builds only print the numbers: unoptimized Swift is 5–20× slower and says nothing.
@MainActor
final class BenchmarkTests: XCTestCase {
    static let fixture = BenchFixture()

    /// The median of `runs` timings, in milliseconds.
    func median(_ runs: Int = 9, setup: () -> Void = {}, _ body: () -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<runs {
            setup()
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        return times.sorted()[runs / 2]
    }

    func budget(_ name: String, _ ms: Double, _ limit: Double) {
        print(String(format: "benchmark %@: %.3f ms (budget %.1f ms)", name, ms, limit))
        #if !DEBUG
        XCTAssertLessThanOrEqual(ms, limit, "\(name) is over budget")
        #endif
    }

    /// Launch to data ready: snapshot decode (≤ 60 ms) + tail + pending + index build, ≤ 100 ms, flat in log length.
    func testLaunchFromSnapshot() throws {
        let f = Self.fixture
        var decode: [Double] = []
        let total = median(5) {
            let start = DispatchTime.now().uptimeNanoseconds
            let loaded = Persistence(directory: f.directory).loadSync()
            decode.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            let p = Projection(confirmed: loaded.confirmed, pending: loaded.pending, day: f.day)
            XCTAssertEqual(loaded.source, .snapshot(tail: f.tail))
            XCTAssertEqual(p.allTaskIDs.count, f.taskCount)
        }
        budget("snapshot decode + tail + pending", decode.sorted()[decode.count / 2], 60)
        budget("launch to data ready", total, 100)
    }

    /// Local edit (op → visible): ≤ 1 ms of app work.
    func testLocalEdit() {
        let f = Self.fixture
        let p = Projection(confirmed: f.state, day: f.day)
        let ids = f.openTaskIDs
        for id in ids.prefix(50) { _ = p.taskModel(id) } // rows on screen
        var maker = OpMaker(counter: 9_000_000)
        var i = 0
        let ms = median(101) {
            i += 1
            p.perform([maker.updateTask(ids[i % ids.count], Patch(title: "edit \(i)"))])
        }
        budget("local edit", ms, 1)
    }

    /// A sync applying 1,000 interleaved remote ops: ≤ 10 µs per op (≤ 10 ms).
    func testApplyRemoteOps() {
        let f = Self.fixture
        var maker = OpMaker(counter: 8_000_000)
        var remoteMaker = OpMaker(counter: 7_000_000)
        var p: Projection!
        var page: [Op] = []
        let ids = f.allTaskIDs
        let ms = median(5, setup: {
            p = Projection(confirmed: f.state, day: f.day)
            var local: [Op] = []
            page = []
            for i in 0..<1000 {
                let remote = remoteMaker.updateTask(ids[(i * 37) % ids.count], Patch(title: "remote \(i)"))
                page.append(remote)
                if i % 10 == 0 {
                    let mine = maker.updateTask(ids[(i * 53) % ids.count], i % 20 == 0 ? Patch(completedAt: .some(f.day.start + i))
                                                                                       : Patch(notes: "mine \(i)"))
                    local.append(mine)
                    page.append(mine)
                }
            }
            p.perform(local)
        }) {
            XCTAssertEqual(p.confirm(page), .general)
        }
        budget("apply 1,000 interleaved remote ops", ms, 10)
    }

    /// Drag reorder in a 2,000-task list: keys + one op + one bucket remove/insert, ≤ 1 ms.
    func testReorderInLargeList() {
        let f = Self.fixture
        let p = Projection(confirmed: f.state, day: f.day)
        var maker = OpMaker(counter: 6_000_000)
        let list = f.bigList
        XCTAssertGreaterThanOrEqual(p.openTasks(in: list).count, 2000)
        var i = 0
        let ms = median(101) {
            i += 1
            let items = p.orderedOpenTasks(in: list)
            let moving = items[(i * 7919) % items.count].id
            let anchor = items[(i * 104_729) % items.count].id
            let ops = Ordering.place([moving], at: .after(anchor), in: items)
                .map { maker.updateTask($0.id, Patch(list: list, order: $0.order)) }
            p.perform(ops)
        }
        budget("reorder in a 2,000-task list", ms, 1)
    }

    /// Midnight rollover: rebuild Today, ≤ 5 ms.
    func testMidnightRebuild() {
        let f = Self.fixture
        let p = Projection(confirmed: f.state, day: f.day)
        var flip = false
        let ms = median(9) {
            flip.toggle()
            p.setDay(flip ? f.nextDay : f.day)
        }
        budget("midnight rebuild", ms, 5)
    }

    /// The fallback: a full replay of 100k ops from log.jsonl (spec: about a second, once).
    func testFullReplay() throws {
        let f = Self.fixture
        let copy = tempDirectory()
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: f.directory.appendingPathComponent("log.jsonl"), to: copy.appendingPathComponent("log.jsonl"))
        var source: LoadedState.Source?
        let ms = median(1) {
            source = Persistence(directory: copy).loadSync().source
        }
        XCTAssertEqual(source, .fullReplay(reason: "no snapshot"))
        budget("full replay of 100k ops", ms, 1500)
    }
}

/// 20 lists and 10,000 tasks (85% completed) built by 100,000 ops, written to a data directory with a snapshot
/// 20 entries before the end and a few pending ops.
final class BenchFixture: @unchecked Sendable {
    let directory: URL
    let state: AppState
    let day: Day
    let nextDay: Day
    let taskCount = 10_000
    let tail = 20
    let bigList = "list-0"
    let openTaskIDs: [EntityID]
    let allTaskIDs: [EntityID]

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Toronto")!
        day = Day(containing: Date(timeIntervalSince1970: 1_761_840_000), calendar: cal)
        nextDay = Day(containing: Date(timeIntervalSince1970: TimeInterval(day.end) / 1000 + 3600), calendar: cal)
        var rng = SeededRandom(seed: 2026)
        var m = OpMaker()
        var ops: [Op] = []
        let lists = (0..<20).map { "list-\($0)" }
        for (i, l) in lists.enumerated() { ops.append(m.createList(l, name: "List \(i)", order: "a\(i)")) }
        var keys: [EntityID: String?] = [:]
        let tasks = (0..<taskCount).map { String(format: "task-%05d", $0) }
        for (i, t) in tasks.enumerated() {
            // list-0 holds 2,200 open tasks; the rest spread out.
            let list = i < 2_400 ? lists[0] : lists[1 + i % 19]
            let key = try! FractionalIndex.keyBetween(keys[list] ?? nil, nil)
            keys[list] = key
            let dates = [day.date.adding(days: -3), day.date, day.date.adding(days: 1), nil, nil]
            ops.append(m.createTask(t, list: list, order: key, title: "Task \(i) with a realistic length title",
                                    when: dates.randomElement(using: &rng)!, deadline: dates.randomElement(using: &rng)!))
        }
        // Complete 85% (but keep 2,200 of list-0 open), then edits until 100k ops.
        let completedSet = Set(tasks.enumerated().filter { $0.offset >= 2_200 && $0.offset % 20 != 0 }.map(\.element))
        for t in tasks where completedSet.contains(t) {
            ops.append(m.updateTask(t, Patch(completedAt: .some(day.start - Int.random(in: 0...86_400_000 * 300, using: &rng)))))
        }
        while ops.count < 100_000 - 5 {
            let t = tasks.randomElement(using: &rng)!
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: ops.append(m.updateTask(t, Patch(title: "Edited \(ops.count)")))
            case 1: ops.append(m.updateTask(t, Patch(notes: "Some **notes** \(ops.count)\n- with a list")))
            case 2: ops.append(m.updateTask(t, Patch(when: .some(day.date.adding(days: Int.random(in: -5...5, using: &rng))))))
            default: ops.append(m.updateTask(t, Patch(deadline: .some(nil))))
            }
        }
        let final = AppState.replay(ops)
        state = final
        openTaskIDs = tasks.filter { final.tasks[$0]?.completedAt == nil }
        allTaskIDs = tasks

        directory = tempDirectory("BenchFixture")
        let p = Persistence(directory: directory)
        _ = p.loadSync()
        let cut = ops.count - tail
        p.appendLog(ops[..<cut].enumerated().map { entryLine(seq: $0.offset, op: $0.element) }, nextCursor: cut)
        p.writeSnapshot(state: AppState.replay(ops[..<cut]), cursor: cut, hash: fakeHash(cut - 1))
        p.appendLog(ops[cut...].enumerated().map { entryLine(seq: cut + $0.offset, op: $0.element) }, nextCursor: ops.count)
        for _ in 0..<5 { p.appendPending(m.updateTask(tasks.randomElement(using: &rng)!, Patch(title: "pending")).jsonData) }
        p.flush()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
