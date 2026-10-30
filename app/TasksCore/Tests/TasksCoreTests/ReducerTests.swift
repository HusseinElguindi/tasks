import XCTest
@testable import TasksCore

/// Spec §5 reducer rules, one test per conflict case.
final class ReducerTests: XCTestCase {
    var m = OpMaker()
    let L = "list-1"
    let T = "task-1"

    func testCreateThenFields() {
        var s = AppState()
        XCTAssertEqual(s.apply(m.createList(L, name: "School", order: "a0")), L)
        let create = m.createTask(T, list: L, order: "a0", title: "Lab report", when: date("2026-10-30"))
        XCTAssertEqual(s.apply(create), T)
        let t = s.tasks[T]!
        XCTAssertEqual(t.title, "Lab report")
        XCTAssertEqual(t.when, date("2026-10-30"))
        XCTAssertNil(t.deadline)
        XCTAssertFalse(t.deleted)
        XCTAssertEqual(t.createdAt, create.at)
        XCTAssertEqual(t.updatedAt, create.at)
    }

    /// Rule 1: a create on an id that already exists (live or deleted) is ignored. The first create wins.
    func testSecondCreateIsIgnored() {
        var s = AppState()
        s.apply(m.createTask(T, list: L, order: "a0", title: "first"))
        XCTAssertNil(s.apply(m.createTask(T, list: "other", order: "b0", title: "second")))
        XCTAssertEqual(s.tasks[T]?.title, "first")
        // Even when the existing one is deleted.
        s.apply(m.updateTask(T, Patch(deleted: true)))
        XCTAssertNil(s.apply(m.createTask(T, list: L, order: "a0", title: "third")))
        XCTAssertEqual(s.tasks[T]?.title, "first")
        XCTAssertEqual(s.tasks[T]?.deleted, true)

        s.apply(m.createList(L, name: "A", order: "a0"))
        XCTAssertNil(s.apply(m.createList(L, name: "B", order: "a1")))
        XCTAssertEqual(s.lists[L]?.name, "A")
    }

    /// Rule 2: last write in log order wins per field; concurrent edits to different fields both survive.
    func testLastWriterWinsPerField() {
        var s = AppState()
        s.apply(m.createTask(T, list: L, order: "a0", title: "t"))
        // Mac A renames, Mac B sets a deadline; the log interleaves them.
        s.apply(m.updateTask(T, Patch(title: "A's title")))
        s.apply(m.updateTask(T, Patch(deadline: .some(date("2026-11-03")))))
        s.apply(m.updateTask(T, Patch(title: "B's title")))
        XCTAssertEqual(s.tasks[T]?.title, "B's title")
        XCTAssertEqual(s.tasks[T]?.deadline, date("2026-11-03"))
    }

    /// `null` clears; a missing key leaves the field unchanged.
    func testNullClearsMissingKeeps() {
        var s = AppState()
        s.apply(m.createTask(T, list: L, order: "a0", title: "t", when: date("2026-10-30"), deadline: date("2026-11-01")))
        s.apply(m.updateTask(T, Patch(when: .some(nil))))
        XCTAssertNil(s.tasks[T]?.when)
        XCTAssertEqual(s.tasks[T]?.deadline, date("2026-11-01"))
        XCTAssertEqual(s.tasks[T]?.title, "t")
    }

    /// Rule 3: an update on an unknown id is ignored.
    func testUpdateUnknownIDIgnored() {
        var s = AppState()
        XCTAssertNil(s.apply(m.updateTask("nope", Patch(title: "x"))))
        XCTAssertNil(s.apply(m.updateList("nope", Patch(name: "x"))))
        XCTAssertEqual(s, AppState())
    }

    /// Rule 4: `deleted` and `archivedAt` are ordinary fields; a concurrent edit never brings anything back.
    func testDeleteSticksUnderConcurrentEdits() {
        var s = AppState()
        s.apply(m.createTask(T, list: L, order: "a0", title: "t"))
        s.apply(m.updateTask(T, Patch(deleted: true)))            // Mac A deletes
        s.apply(m.updateTask(T, Patch(title: "edited on B")))     // Mac B edits concurrently
        XCTAssertEqual(s.tasks[T]?.deleted, true)
        XCTAssertEqual(s.tasks[T]?.title, "edited on B")
        s.apply(m.updateTask(T, Patch(deleted: false)))           // only an explicit undo restores it
        XCTAssertEqual(s.tasks[T]?.deleted, false)

        s.apply(m.createList(L, name: "L", order: "a0"))
        s.apply(m.updateList(L, Patch(archivedAt: .some(5))))
        s.apply(m.updateList(L, Patch(name: "renamed")))
        XCTAssertEqual(s.lists[L]?.archivedAt, 5)
        s.apply(m.updateList(L, Patch(archivedAt: .some(nil))))
        XCTAssertNil(s.lists[L]?.archivedAt)
    }

    /// Rule 5: archiving is one field on the list; tasks are not rewritten.
    func testArchiveDoesNotTouchTasks() {
        var s = AppState()
        s.apply(m.createList(L, name: "L", order: "a0"))
        s.apply(m.createTask(T, list: L, order: "a0"))
        let before = s.tasks
        XCTAssertEqual(s.apply(m.updateList(L, Patch(archivedAt: .some(1)))), L)
        XCTAssertEqual(s.tasks, before)
    }

    /// Rule 6: unknown op types and unknown keys are ignored; wrong-typed values are ignored per key.
    func testUnknownTypesKeysAndWrongTypes() throws {
        var s = AppState()
        s.apply(m.createTask(T, list: L, order: "a0", title: "t"))
        XCTAssertNil(s.apply(op(#"{"id":"x1","at":1,"type":"task.archive","target":"task-1","set":{"title":"no"}}"#)))
        XCTAssertEqual(s.tasks[T]?.title, "t")

        let mixed = op(#"{"id":"x2","at":2,"type":"task.update","target":"task-1","set":{"title":5,"notes":"kept","color":"red","when":"2026-02-30","deadline":"2026-03-01","completedAt":"soon","deleted":1}}"#)
        XCTAssertNil(mixed.set.title)
        XCTAssertTrue(mixed.set.when == nil)
        XCTAssertTrue(mixed.set.completedAt == nil)
        XCTAssertNil(mixed.set.deleted)
        XCTAssertEqual(s.apply(mixed), T)
        let t = try XCTUnwrap(s.tasks[T])
        XCTAssertEqual(t.title, "t")
        XCTAssertEqual(t.notes, "kept")
        XCTAssertEqual(t.deadline, date("2026-03-01"))
        XCTAssertNil(t.when)
        XCTAssertNil(t.completedAt)
        XCTAssertFalse(t.deleted)

        // Keys that belong to the other entity type are unknown for this one.
        s.apply(op(#"{"id":"x3","at":3,"type":"task.update","target":"task-1","set":{"name":"list name","archivedAt":5}}"#))
        XCTAssertEqual(s.tasks[T], t.with(updatedAt: 3))
        // `deleted` isn't a create key.
        s.apply(op(#"{"id":"x4","at":4,"type":"task.create","target":"task-2","set":{"list":"l","order":"a0","deleted":true}}"#))
        XCTAssertEqual(s.tasks["task-2"]?.deleted, false)
        // `archivedAt` isn't a list.create key.
        s.apply(op(#"{"id":"x5","at":5,"type":"list.create","target":"list-9","set":{"name":"n","order":"a0","archivedAt":7}}"#))
        XCTAssertNil(s.lists["list-9"]?.archivedAt)
    }

    func testCreateMissingRequiredKeysIgnored() {
        var s = AppState()
        XCTAssertNil(s.apply(op(#"{"id":"x","at":1,"type":"task.create","target":"t","set":{"list":"l"}}"#)))
        XCTAssertNil(s.apply(op(#"{"id":"y","at":1,"type":"task.create","target":"t","set":{"order":"a0"}}"#)))
        XCTAssertNil(s.apply(op(#"{"id":"z","at":1,"type":"list.create","target":"l","set":{"name":"n"}}"#)))
        XCTAssertNil(s.apply(op(#"{"id":"w","at":1,"type":"task.create","target":"t","set":{"list":"l","order":7}}"#)))
        XCTAssertEqual(s, AppState())
    }

    /// Position is written as `list` + `order` together; concurrent moves resolve wholly to the later one.
    func testConcurrentMovesResolveWhole() {
        for reversed in [false, true] {
            var s = AppState()
            var m = OpMaker()
            s.apply(m.createTask(T, list: "A", order: "a0"))
            let moveB = m.updateTask(T, Patch(list: "B", order: "a5"))
            let moveC = m.updateTask(T, Patch(list: "C", order: "Zz"))
            for o in reversed ? [moveC, moveB] : [moveB, moveC] { s.apply(o) }
            let last = reversed ? moveB : moveC
            XCTAssertEqual(s.tasks[T]?.list, last.set.list)
            XCTAssertEqual(s.tasks[T]?.order, last.set.order)
        }
    }

    func testDifferentItemsMovedBothApply() {
        var s = AppState()
        s.apply(m.createTask("x", list: L, order: "a0"))
        s.apply(m.createTask("y", list: L, order: "a1"))
        s.apply(m.updateTask("x", Patch(list: L, order: "a2")))
        s.apply(m.updateTask("y", Patch(list: L, order: "Zz")))
        XCTAssertEqual(s.tasks["x"]?.order, "a2")
        XCTAssertEqual(s.tasks["y"]?.order, "Zz")
    }

    /// Every op followed by its inverse leaves the entity as it was (§8).
    func testInverseRoundTrips() {
        var rng = SeededRandom(seed: 7)
        var m = OpMaker()
        var s = AppState()
        let lists = ["L1", "L2"]
        let tasks = ["t1", "t2", "t3"]
        for l in lists { s.apply(m.createList(l, name: l, order: "a0")) }
        for t in tasks { s.apply(m.createTask(t, list: "L1", order: "a1", title: t)) }
        for i in 0..<2000 {
            let target: Op
            if Bool.random(using: &rng) {
                target = m.updateTask(tasks.randomElement(using: &rng)!, randomTaskPatch(&rng))
                let before = s.tasks[target.target]
                let inverse = Inverse.of(target, beforeTask: before, id: "inv-\(i)", at: target.at + 1)!
                s.apply(target)
                s.apply(inverse)
                XCTAssertTrue(s.tasks[target.target]!.sameContent(as: before!), "op \(target) then \(inverse)")
            } else {
                target = m.updateList(lists.randomElement(using: &rng)!, randomListPatch(&rng))
                let before = s.lists[target.target]
                let inverse = Inverse.of(target, beforeList: before, id: "inv-\(i)", at: target.at + 1)!
                s.apply(target)
                s.apply(inverse)
                XCTAssertTrue(s.lists[target.target]!.sameContent(as: before!), "op \(target) then \(inverse)")
            }
            // Drift the state too, so inverses see varied "before" values.
            s.apply(m.updateTask(tasks.randomElement(using: &rng)!, randomTaskPatch(&rng)))
        }
    }

    func testInverseOfCreateDeletesAndRedoRestores() {
        var s = AppState()
        let create = m.createTask(T, list: L, order: "a0", title: "t")
        let undo = Inverse.of(create, beforeTask: nil, id: "u", at: 9)!
        XCTAssertEqual(undo.set, Patch(deleted: true))
        s.apply(create)
        let before = s.tasks[T]
        let redo = Inverse.of(undo, beforeTask: before, id: "r", at: 10)!
        s.apply(undo)
        XCTAssertEqual(s.tasks[T]?.deleted, true)
        s.apply(redo)
        XCTAssertTrue(s.tasks[T]!.sameContent(as: before!))

        let listCreate = m.createList(L, name: "n", order: "a0")
        XCTAssertEqual(Inverse.of(listCreate, beforeList: nil, id: "u2", at: 11)?.set, Patch(archivedAt: .some(11)))
        // An op that wouldn't apply has no inverse.
        XCTAssertNil(Inverse.of(create, beforeTask: before, id: "u3", at: 1))
        XCTAssertNil(Inverse.of(m.updateTask("ghost", Patch(title: "x")), beforeTask: nil, id: "u4", at: 1))
    }

    func testReplayIsDeterministic() {
        var rng = SeededRandom(seed: 99)
        var m = OpMaker()
        var ops: [Op] = [m.createList("L1", name: "a", order: "a0")]
        for i in 0..<200 { ops.append(m.createTask("t\(i % 50)", list: "L1", order: "a\(i % 9 + 1)")) }
        for _ in 0..<2000 { ops.append(m.updateTask("t\(Int.random(in: 0..<60, using: &rng))", randomTaskPatch(&rng))) }
        XCTAssertEqual(AppState.replay(ops), AppState.replay(ops))
    }
}

func randomTaskPatch(_ rng: inout SeededRandom) -> Patch {
    var p = Patch()
    let dates = [date("2026-10-29"), date("2026-10-30"), date("2026-10-31"), date("2026-12-25")]
    repeat {
        switch Int.random(in: 0..<8, using: &rng) {
        case 0: p.title = ["a", "b", "c", ""].randomElement(using: &rng)!
        case 1: p.notes = ["**n**", "", "x"].randomElement(using: &rng)!
        case 2: p.when = Bool.random(using: &rng) ? .some(nil) : .some(dates.randomElement(using: &rng)!)
        case 3: p.deadline = Bool.random(using: &rng) ? .some(nil) : .some(dates.randomElement(using: &rng)!)
        case 4: p.completedAt = Bool.random(using: &rng) ? .some(nil) : .some(Int.random(in: 1_761_700_000_000...1_761_900_000_000, using: &rng))
        case 5: p.deleted = Bool.random(using: &rng)
        default:
            p.list = ["L1", "L2"].randomElement(using: &rng)!
            p.order = ["a0", "a1", "a0V", "Zz", "b00"].randomElement(using: &rng)!
        }
    } while Bool.random(using: &rng)
    return p
}

func randomListPatch(_ rng: inout SeededRandom) -> Patch {
    var p = Patch()
    repeat {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: p.name = ["Inbox", "School", "Home"].randomElement(using: &rng)!
        case 1: p.order = ["a0", "a1", "Zz"].randomElement(using: &rng)!
        default: p.archivedAt = Bool.random(using: &rng) ? .some(nil) : .some(Int.random(in: 1...1_000, using: &rng))
        }
    } while Bool.random(using: &rng)
    return p
}

extension TaskItem {
    func with(updatedAt: Int) -> TaskItem {
        var t = self
        t.updatedAt = updatedAt
        return t
    }
}
