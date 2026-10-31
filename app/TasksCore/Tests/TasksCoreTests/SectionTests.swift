import XCTest
@testable import TasksCore

/// Headings and a list's notes (design/INTERACTIONS-v2.md §23): a heading is a task with `kind: "heading"`, and a
/// list's text is its `notes`. The reducer is unchanged; the queries leave headings out.
@MainActor
final class SectionTests: XCTestCase {
    private var m = OpMaker()
    private let day = Day(containing: Date(timeIntervalSince1970: 1_761_840_000))

    // MARK: Wire and reducer

    func testKindOnTheWire() throws {
        let json = #"{"id":"o1","at":1,"type":"task.create","target":"h","set":{"list":"L","order":"a0","title":"Labs","kind":"heading"}}"#
        let o = op(json)
        XCTAssertEqual(o.set.kind, "heading")
        XCTAssertEqual(String(decoding: o.jsonData, as: UTF8.self), json)
        // Patch's Codable keeps it too (pending.jsonl round trips through it).
        let again = try JSONDecoder().decode(Patch.self, from: JSONEncoder().encode(o.set))
        XCTAssertEqual(again, o.set)
        // A wrong type is dropped, not fatal (rule 6).
        XCTAssertNil(op(#"{"id":"o2","at":1,"type":"task.create","target":"t","set":{"list":"L","order":"a0","kind":7}}"#).set.kind)
    }

    func testReducerReadsKindOnCreateOnly() {
        var s = AppState()
        s.apply(m.createTask("h", list: "L", order: "a0", title: "Labs", kind: Patch.heading))
        s.apply(m.createTask("t", list: "L", order: "a1", title: "Task"))
        s.apply(m.createTask("u", list: "L", order: "a2", title: "Future", kind: "section"))
        XCTAssertTrue(s.tasks["h"]!.isHeading)
        XCTAssertFalse(s.tasks["t"]!.isHeading)
        XCTAssertFalse(s.tasks["u"]!.isHeading, "an unknown kind reads as a task")
        // An update never changes it, whatever it carries.
        s.apply(m.updateTask("t", Patch(title: "T", kind: Patch.heading)))
        s.apply(m.updateTask("h", Patch(title: "Lab work", kind: "task")))
        XCTAssertFalse(s.tasks["t"]!.isHeading)
        XCTAssertTrue(s.tasks["h"]!.isHeading)
        XCTAssertEqual(s.tasks["h"]!.title, "Lab work")
    }

    func testListNotesAndTheirInverse() {
        var s = AppState()
        let create = Op(id: "c", at: 1, type: .listCreate, target: "L", set: Patch(order: "a0", notes: "Course notes", name: "PHYS 122"))
        s.apply(create)
        XCTAssertEqual(s.lists["L"]!.notes, "Course notes")
        let before = s.lists["L"]
        let update = m.updateList("L", Patch(notes: "**New**"))
        s.apply(update)
        XCTAssertEqual(s.lists["L"]!.notes, "**New**")
        let inverse = Inverse.of(update, beforeList: before, id: "i", at: 9)!
        XCTAssertEqual(inverse.set, Patch(notes: "Course notes"))
        // Without notes in the create, a list has none.
        s.apply(m.createList("M", name: "Home", order: "a1"))
        XCTAssertEqual(s.lists["M"]!.notes, "")
    }

    func testSnapshotKeepsHeadingsAndListNotes() throws {
        var s = AppState()
        s.apply(Op(id: "c", at: 1, type: .listCreate, target: "L", set: Patch(order: "a0", notes: "n", name: "L")))
        s.apply(m.createTask("h", list: "L", order: "a0", title: "Labs", kind: Patch.heading))
        let back = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(Persistence.schema, 2, "AppState gained isHeading and list notes: old snapshots must replay")
    }

    // MARK: Queries

    private func projection() -> Projection {
        let p = Projection(day: day)
        p.perform([m.createList("L", name: "PHYS 122", order: "a0")])
        p.perform([
            m.createTask("t0", list: "L", order: "a0", title: "Before any heading"),
            m.createTask("h1", list: "L", order: "a1", title: "Labs", kind: Patch.heading),
            m.createTask("t1", list: "L", order: "a2", title: "Lab 1", when: day.date),
            m.createTask("t2", list: "L", order: "a3", title: "Lab 2"),
            m.createTask("h2", list: "L", order: "a4", title: "Exams", kind: Patch.heading),
            m.createTask("t3", list: "L", order: "a5", title: "Midterm"),
        ])
        return p
    }

    func testHeadingsAreRowsButNotCountedOrInToday() {
        let p = projection()
        XCTAssertEqual(p.openTasks(in: "L").ids, ["t0", "h1", "t1", "t2", "h2", "t3"])
        XCTAssertEqual(p.headings(in: "L").ids, ["h1", "h2"])
        XCTAssertEqual(p.openTaskCount(in: "L"), 4)
        XCTAssertEqual(p.todayTasks(in: "L").ids, ["t1"])
        // A heading with dates (another client wrote them) still never shows in Today, and a completion leaves it a row.
        let m2 = m.updateTask("h1", Patch(when: .some(day.date), completedAt: .some(day.start + 1)))
        p.perform([m2])
        XCTAssertEqual(p.todayTasks(in: "L").ids, ["t1"])
        XCTAssertEqual(p.openTasks(in: "L").ids, ["t0", "h1", "t1", "t2", "h2", "t3"])
        XCTAssertTrue(p.todayDone.ids.isEmpty)
        XCTAssertTrue(p.completedTasks(in: "L").ids.isEmpty)
        p.perform([m.updateTask("h2", Patch(deleted: true))])
        XCTAssertEqual(p.headings(in: "L").ids, ["h1"])
        XCTAssertEqual(p.openTaskCount(in: "L"), 4)
        assertMatchesRebuild(p, "headings")
        // Midnight keeps them out too.
        p.setDay(Day(containing: Date(timeIntervalSince1970: 1_761_840_000 + 86_400)))
        XCTAssertFalse(p.todayTasks(in: "L").ids.contains("h1"))
        assertMatchesRebuild(p, "after midnight")
    }

    func testSectionsIncludeCompletedTasks() {
        let p = projection()
        p.perform([m.updateTask("t2", Patch(completedAt: .some(day.start + 1)))])
        XCTAssertEqual(p.section(of: "h1"), ["h1", "t1", "t2"])
        XCTAssertEqual(p.section(of: "h2"), ["h2", "t3"])
        XCTAssertEqual(p.section(of: "t1"), [], "a task has no section")
        XCTAssertEqual(p.heading(of: "t0"), nil)
        XCTAssertEqual(p.heading(of: "t2"), "h1")
        XCTAssertEqual(p.heading(of: "t3"), "h2")
        XCTAssertEqual(p.heading(of: "h2"), nil)
    }

    // MARK: Store

    private var dirs: [URL] = []
    override func tearDown() { for d in dirs { try? FileManager.default.removeItem(at: d) } }

    private func store() -> Store {
        let d = tempDirectory("sections-\(dirs.count)")
        dirs.append(d)
        let p = Persistence(directory: d)
        let s = Store(loaded: p.loadSync(), persistence: p, transport: HTTPSyncTransport())
        s.cancelScheduledSync()
        return s
    }

    func testStoreActions() {
        let s = store()
        let p = s.projection
        let list = s.createList(name: "PHYS 122")
        let a = s.createTask(title: "A", in: list)!
        let b = s.createTask(title: "B", in: list)!
        // Above the first selected row; the op says kind heading.
        let h = s.createHeading(title: "Labs", in: list, at: .before(b))!
        XCTAssertEqual(p.openTasks(in: list).ids, [a, h, b])
        XCTAssertEqual(s.projection.pending.last?.op.set.kind, "heading")
        XCTAssertEqual(String(decoding: s.projection.pending.last!.json, as: UTF8.self).contains(#""kind":"heading""#), true)
        // The end of a section.
        let h2 = s.createHeading(title: "Exams", in: list)!
        let c = s.createTask(title: "C", in: list, at: .after(b))!
        XCTAssertEqual(p.openTasks(in: list).ids, [a, h, b, c, h2])
        // Headings are skipped by completing, dates and Move to.
        let other = s.createList(name: "Home")
        XCTAssertFalse(s.toggleComplete([h]))
        XCTAssertFalse(s.setWhen([h], day.date))
        XCTAssertFalse(s.setDeadline([h], day.date))
        XCTAssertFalse(s.move([h], to: other))
        XCTAssertTrue(s.toggleComplete([h, b]))
        XCTAssertNil(p.task(h)!.completedAt)
        XCTAssertNotNil(p.task(b)!.completedAt)
        // List notes.
        XCTAssertTrue(s.setNotes(list: list, "Lectures **MWF**"))
        XCTAssertFalse(s.setNotes(list: list, "Lectures **MWF**"))
        XCTAssertEqual(p.listModel(list)?.notes, "Lectures **MWF**")
    }

    func testMoveSectionCarriesCompletedTasks() {
        let s = store()
        let p = s.projection
        let list = s.createList(name: "L")
        let t0 = s.createTask(title: "t0", in: list)!
        let h1 = s.createHeading(title: "Labs", in: list)!
        let t1 = s.createTask(title: "t1", in: list)!
        let t2 = s.createTask(title: "t2", in: list)!
        let h2 = s.createHeading(title: "Exams", in: list)!
        let t3 = s.createTask(title: "t3", in: list)!
        s.toggleComplete([t2])
        // Labs after Exams: the section moves whole, its completed task with it.
        XCTAssertTrue(s.moveSection(h1, at: .bottom))
        XCTAssertEqual(p.openTasks(in: list).ids, [t0, h2, t3, h1, t1])
        XCTAssertEqual(p.section(of: h1), [h1, t1, t2])
        // Unchecking puts it back under its heading.
        s.toggleComplete([t2])
        XCTAssertEqual(p.openTasks(in: list).ids, [t0, h2, t3, h1, t1, t2])
        // Back before Exams; where it already is, nothing is written.
        XCTAssertTrue(s.moveSection(h1, at: .before(h2)))
        XCTAssertEqual(p.openTasks(in: list).ids, [t0, h1, t1, t2, h2, t3])
        let before = p.pending.count
        XCTAssertFalse(s.moveSection(h1, at: .before(h2)))
        XCTAssertEqual(p.pending.count, before)
        assertMatchesRebuild(p, "sections")
    }
}
