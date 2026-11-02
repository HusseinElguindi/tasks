import TasksCore
import XCTest
@testable import TasksCLI

/// Headings and a list's notes in the CLI (design/INTERACTIONS-v2.md §23 "Model and sync"): a heading is a task
/// with `kind: "heading"`, shown only by `ls`; completing, dates and Move to fail closed on one.
@MainActor
final class HeadingTests: CLITestCase {
    /// PHYS 122: "Reading" with no heading, then Labs (Lab 1, Lab 2) and Exams (Midterm).
    func seed() async throws -> (labs: String, exams: String) {
        await tasks("list", "add", "PHYS 122")
        for t in ["Reading", "Lab 1", "Lab 2", "Midterm"] { await tasks("add", t, "--list", "PHYS 122") }
        let labs = try await json("heading", "add", "Labs", "--before", try await id("Lab 1"))
        let exams = try await json("heading", "add", "Exams", "--list", "phys 122", "--before", try await id("Midterm"))
        return (try XCTUnwrap(labs["id"]?.stringValue), try XCTUnwrap(exams["id"]?.stringValue))
    }

    func rows(_ list: String = "PHYS 122") async throws -> [String] {
        let l = try await json("ls", list)
        return l["open"]?.arrayValue?.map { ($0["kind"]?.stringValue == "heading" ? "# " : "") + ($0["title"]?.stringValue ?? "") } ?? []
    }

    func expectRows(_ want: [String], _ list: String = "PHYS 122", file: StaticString = #filePath, line: UInt = #line) async throws {
        let got = try await rows(list)
        XCTAssertEqual(got, want, file: file, line: line)
    }

    func testHeadingAddAndLs() async throws {
        let (labs, _) = try await seed()
        try await expectRows(["Reading", "# Labs", "Lab 1", "Lab 2", "# Exams", "Midterm"])
        // The op says kind heading, after title and notes as the client always writes it.
        let create = try XCTUnwrap(server.texts.first { $0.contains(#""title":"Labs""#) })
        XCTAssertTrue(create.contains(#""title":"Labs","notes":"","kind":"heading""#), create)

        let shown = try await json("show", labs)
        XCTAssertEqual(shown["kind"]?.stringValue, "heading")
        XCTAssertEqual(Set(shown.keys), Set(Shapes.task.map(\.name)).subtracting(["listDeleted"]))
        let task = try await json("show", try await id("Lab 1"))
        XCTAssertNil(task["kind"], "a task's JSON is what it was before headings")
        XCTAssertEqual(Set(task.keys), Set(Shapes.task.filter { !$0.optional }.map(\.name)))

        let text = await tasks("ls", "PHYS 122")
        let lines = text.out.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[1].hasPrefix("  ○ ") && lines[1].hasSuffix("Reading"), text.out)
        XCTAssertTrue(lines[2].hasPrefix("  # ") && lines[2].hasSuffix("  Labs"), text.out)
        XCTAssertTrue(lines[3].hasPrefix("    ○ ") && lines[3].hasSuffix("Lab 1"), text.out)
        XCTAssertTrue(lines[5].hasPrefix("  # ") && lines[5].hasSuffix("  Exams"), text.out)

        // --after a heading is after its section; --after a task is right after it; --top is the top.
        await tasks("heading", "add", "Notes", "--after", labs)
        await tasks("heading", "add", "Extra", "--after", try await id("Midterm"))
        await tasks("heading", "add", "First", "--top", "--list", "PHYS 122")
        try await expectRows(["# First", "Reading", "# Labs", "Lab 1", "Lab 2", "# Notes", "# Exams", "Midterm", "# Extra"])
        let summary = await tasks("heading", "add", "Last", "--list", "PHYS 122")
        XCTAssertTrue(summary.out.contains("New Heading \"Last\" in PHYS 122"), summary.out)
        let last = try await rows().last
        XCTAssertEqual(last, "# Last")
    }

    func testHeadingsStayOutOfTheViewsAndCounts() async throws {
        _ = try await seed()
        await tasks("when", "today", try await id("Lab 1"))
        let today = try await json("today")
        let titles = today["groups"]?.arrayValue?.flatMap { $0["tasks"]?.arrayValue ?? [] }.compactMap { $0["title"]?.stringValue }
        XCTAssertEqual(titles, ["Lab 1"])
        let found = try await json("find", "")
        XCTAssertFalse(found.arrayValue!.contains { $0["kind"] != nil }, "find has no headings")
        XCTAssertEqual(found.arrayValue?.count, 4)
        let lists = try await json("lists")
        XCTAssertEqual(lists.arrayValue?.first { $0["name"]?.stringValue == "PHYS 122" }?["open"]?.intValue, 4)
        let listsText = await tasks("lists")
        XCTAssertTrue(listsText.out.contains("PHYS 122  4"), listsText.out)
    }

    func testCompletionDatesAndMoveToFailClosed() async throws {
        let (labs, _) = try await seed()
        let lab1 = try await id("Lab 1")
        await tasks("list", "add", "Home")
        let before = server.ops.count
        for args in [["done", labs], ["undone", labs], ["toggle", lab1, labs], ["when", "fri", labs],
                     ["deadline", "nov 9", lab1, labs], ["move", labs, "--to", "Home"]] {
            var out: [String] = [], err: [String] = []
            let code = await CLI.run(args, env: env(out: { out.append($0) }, err: { err.append($0) }))
            XCTAssertEqual(code, 1, "\(args)")
            XCTAssertTrue(err.joined().contains("Labs is a heading"), "\(args): \(err)")
        }
        XCTAssertEqual(server.ops.count, before, "nothing written")
        let e = try await errorJSON("done", labs)
        XCTAssertEqual(e["type"]?.stringValue, "Invalid")
        let lab1Shown = try await json("show", lab1)
        XCTAssertEqual(lab1Shown["done"], .bool(false))
    }

    func testRenameNotesAndDeleteAHeading() async throws {
        let (labs, _) = try await seed()
        let r = await tasks("rename", labs, "Lab work")
        XCTAssertTrue(r.out.contains("Rename Heading to \"Lab work\""), r.out)
        await tasks("notes", labs, "Bring the **lab book**.")
        let labsShown = try await json("show", labs)
        XCTAssertEqual(labsShown["notes"]?.stringValue, "Bring the **lab book**.")
        let shown = await tasks("show", labs)
        XCTAssertTrue(shown.out.contains("kind      heading"), shown.out)
        XCTAssertTrue(shown.out.contains("2 open tasks under it"), shown.out)
        XCTAssertFalse(shown.out.contains("when"), shown.out)

        // Deleting a heading keeps its tasks, now with no heading above them.
        let d = await tasks("delete", labs)
        XCTAssertTrue(d.out.contains("Delete Heading \"Lab work\""), d.out)
        try await expectRows(["Reading", "Lab 1", "Lab 2", "# Exams", "Midterm"])
        await tasks("restore", labs)
        try await expectRows(["Reading", "# Lab work", "Lab 1", "Lab 2", "# Exams", "Midterm"])
    }

    func testMovingASectionCarriesItsCompletedTasks() async throws {
        let (labs, exams) = try await seed()
        let lab2 = try await id("Lab 2")
        await tasks("done", lab2)
        let m = await tasks("move", labs, "--bottom")
        XCTAssertEqual(m.code, 0, m.err)
        XCTAssertTrue(m.out.contains("Move Heading \"Labs\""), m.out)
        try await expectRows(["Reading", "# Exams", "Midterm", "# Labs", "Lab 1"])
        // The completed task moved with its heading: unchecked, it's back under it.
        await tasks("undone", lab2)
        try await expectRows(["Reading", "# Exams", "Midterm", "# Labs", "Lab 1", "Lab 2"])

        // --up past the previous section; --after a task lands after that task's section.
        await tasks("move", labs, "--up")
        try await expectRows(["Reading", "# Labs", "Lab 1", "Lab 2", "# Exams", "Midterm"])
        await tasks("move", labs, "--after", try await id("Midterm"))
        try await expectRows(["Reading", "# Exams", "Midterm", "# Labs", "Lab 1", "Lab 2"])
        await tasks("move", labs, "--after", try await id("Reading"))
        try await expectRows(["Reading", "# Labs", "Lab 1", "Lab 2", "# Exams", "Midterm"])

        // Where it already is, nothing is written; never inside a section; on its own.
        let before = server.ops.count
        let same = await tasks("move", labs, "--before", exams)
        XCTAssertEqual(same.code, 0, same.err)
        XCTAssertTrue(same.out.contains("No change."), same.out)
        await tasks("move", labs, "--top")
        XCTAssertEqual(server.ops.count, before)
        let inside = await tasks("move", exams, "--before", try await id("Lab 2"))
        XCTAssertEqual(inside.code, 1)
        XCTAssertTrue(inside.err.contains("before another heading"), inside.err)
        let together = await tasks("move", labs, try await id("Midterm"), "--bottom")
        XCTAssertEqual(together.code, 1)
        XCTAssertEqual(server.ops.count, before)

        // A task --after a heading goes to the top of its section; --before one, to the end of the section above.
        await tasks("move", try await id("Midterm"), "--after", labs)
        try await expectRows(["Reading", "# Labs", "Midterm", "Lab 1", "Lab 2", "# Exams"])
        await tasks("move", try await id("Reading"), "--before", exams)
        try await expectRows(["# Labs", "Midterm", "Lab 1", "Lab 2", "Reading", "# Exams"])
        // A task moving one row up past a heading changes section.
        await tasks("move", try await id("Midterm"), "--up")
        try await expectRows(["Midterm", "# Labs", "Lab 1", "Lab 2", "Reading", "# Exams"])
    }

    func testListNotes() async throws {
        _ = try await seed()
        let r = await tasks("list", "notes", "PHYS 122", "Lectures **MWF** 10:30")
        XCTAssertEqual(r.code, 0, r.err)
        XCTAssertTrue(r.out.contains("Edit List Notes on \"PHYS 122\""), r.out)
        let appended = await tasks("list", "notes", "PHYS 122", "--append", "- [ ] Buy the lab book")
        XCTAssertEqual(appended.code, 0, "a Markdown list line isn't a flag: \(appended.err)")
        let l = try await json("ls", "PHYS 122")
        XCTAssertEqual(l["list"]?["notes"]?.stringValue, "Lectures **MWF** 10:30\n- [ ] Buy the lab book")
        XCTAssertEqual(Set(l["list"]?.keys ?? []), Set(Shapes.list.map(\.name)))
        let text = await tasks("ls", "PHYS 122")
        XCTAssertEqual(Array(text.out.split(separator: "\n").prefix(3)),
                       ["PHYS 122", "  Lectures **MWF** 10:30", "  - [ ] Buy the lab book"])
        await tasks("list", "notes", "PHYS 122", "-", stdin: "From stdin")
        let fromStdin = try await json("ls", "PHYS 122")
        XCTAssertEqual(fromStdin["list"]?["notes"]?.stringValue, "From stdin")
        // An op of its own, undone by the log.
        XCTAssertEqual(server.ops.last?.type, .listUpdate)
        XCTAssertEqual(server.ops.last?.set.notes, "From stdin")
        let u = await tasks("undo")
        XCTAssertEqual(u.code, 0, u.err)
        let undone = try await json("ls", "PHYS 122")
        XCTAssertEqual(undone["list"]?["notes"]?.stringValue, "Lectures **MWF** 10:30\n- [ ] Buy the lab book")
        let tooLong = await tasks("list", "notes", "PHYS 122", String(repeating: "x", count: 20_001))
        XCTAssertEqual(tooLong.code, 1)
    }

    func testUsage() async {
        let bare = await tasks("heading")
        XCTAssertEqual(bare.code, 2)
        XCTAssertTrue(bare.err.contains("tasks heading takes add"), bare.err)
        let help = await tasks("heading", "add", "--help")
        XCTAssertTrue(help.out.hasPrefix("tasks heading add <name>"), help.out)
        XCTAssertTrue(help.out.contains("Code mode: tasks.addHeading("), help.out)
        let notes = await tasks("list", "notes", "--help")
        XCTAssertTrue(notes.out.contains("Code mode: tasks.setListNotes("), notes.out)
        let overview = await tasks("help")
        XCTAssertTrue(overview.out.contains("Headings\n  tasks heading add"), overview.out)
    }
}
