import XCTest
@testable import TasksCore

/// The list mark's short name (`ListName.short`, INTERACTIONS-v2 §22 "The list mark").
final class ListNameTests: XCTestCase {
    func check(_ name: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ListName.short(name), expected, "short(\"\(name)\")", file: file, line: line)
    }

    func testTheUsersCourses() {
        check("SE 463 — Software Project Management, Requirements, and Analysis", "SE 463")
        check("EARTH 121 — Introductory Earth Sciences", "EARTH 121")
        check("ECE 358 — Computer Networks", "ECE 358")
        check("SE 490 — Design Project 1", "SE 490")
        check("CS 489", "CS 489")
        check("Inbox", "Inbox")
    }

    func testEverySeparator() {
        check("SE 463 – Software", "SE 463")       // en dash
        check("SE 463—Software", "SE 463")         // em dash, unspaced
        check("SE 463–Software", "SE 463")         // en dash, unspaced
        check("SE 463 - Software", "SE 463")       // spaced hyphen
        check("SE 463: Software", "SE 463")
        check("SE 463 | Software", "SE 463")
        check("SE 463|Software", "SE 463")
        check("SE 463 · Software", "SE 463")
        check("ECE 358 (Computer Networks)", "ECE 358")
        check("Notes:", "Notes")                   // a colon at the end
        check("Inbox —", "Inbox")
    }

    func testWhatIsNotASeparator() {
        // A hyphen inside a word or without both spaces, a colon inside a time, a parenthesis without a space.
        check("ECE-358", "ECE-358")
        check("e-mail drafts", "e-mail drafts")
        check("Home -garden", "Home -garden")
        check("Standup 10:30", "Standup 10:30")
        check("Lab(s)", "Lab(s)")
        check("Home, garden and car", "Home, garden and car")
        check("CS/SE 463", "CS/SE 463")
    }

    func testTheFirstSeparatorWins() {
        check("SE 463 — Part 1: Intro", "SE 463")
        check("Work: Q4 — planning", "Work")
        check("A - B — C", "A")
    }

    func testASeparatorAtTheStartDoesNotCount() {
        check("— Notes", "— Notes")
        check(": misc", ": misc")
        check("| Work | Home", "Work")
        check("  —  Reading list — 2026", "Reading list")
    }

    func testTooLongGivesTheWholeName() {
        check("Twelve chars — x", "Twelve chars")                                     // 12: kept
        check("Thirteen char — x", "Thirteen char — x")                               // 13: the whole name
        check("Groceries and errands — weekly", "Groceries and errands — weekly")
        // Characters, not bytes or UTF-16: "Café ☕️ 12" is 9.
        check("Café ☕️ 12 — morning", "Café ☕️ 12")
    }

    func testWhitespace() {
        check("  SE 463  —  Software  ", "SE 463")
        check("  Inbox  ", "Inbox")
        check("", "")
        check("   ", "")
        check("—", "—")
    }

    /// A group label's two parts (Undated and Today, §22): the short name, then the rest after the separator.
    func testSplit() {
        func check(_ name: String, _ short: String, _ rest: String?, line: UInt = #line) {
            let p = ListName.split(name)
            XCTAssertEqual(p.short, short, "split(\"\(name)\").short", line: line)
            XCTAssertEqual(p.rest, rest, "split(\"\(name)\").rest", line: line)
        }
        check("SE 463 — Software Project Management, Requirements, and Analysis", "SE 463",
              "Software Project Management, Requirements, and Analysis")
        check("SE 490 — Design Project 1", "SE 490", "Design Project 1")
        check("SE 463: Software", "SE 463", "Software")
        check("SE 463|Software", "SE 463", "Software")
        check("SE 463 - Part 1: Intro", "SE 463", "Part 1: Intro")
        check("ECE 358 (Computer Networks)", "ECE 358", "(Computer Networks)")
        // No separator, too long, nothing after it, a separator at the start: the whole name, nothing quiet.
        check("Inbox", "Inbox", nil)
        check("CS 489", "CS 489", nil)
        check("Groceries and errands — weekly", "Groceries and errands — weekly", nil)
        check("Inbox —", "Inbox", nil)
        check("— Notes", "— Notes", nil)
        check("| Work | Home", "Work", "Home")
        check("", "", nil)
    }
}
