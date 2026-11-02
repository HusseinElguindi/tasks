import XCTest
@testable import TasksCore

/// `shownNumbers` is the Mac's numbering (app/Tasks/Detail/NotesMarkdown.swift), so these are the Mac's outputs.
final class MarkdownNumbersTests: XCTestCase {
    private func numbers(_ text: String) -> [Int: Int] { Markdown.parse(text).shownNumbers }

    func testAListNumbersItselfFromItsFirstItem() {
        XCTAssertEqual(numbers("1. a\n1. b\n1. c"), [0: 1, 1: 2, 2: 3])
        XCTAssertEqual(numbers("3. a\n7. b\n1. c"), [0: 3, 1: 4, 2: 5])
        // The delimiter doesn't start a new list.
        XCTAssertEqual(numbers("1) a\n1) b\n1. c"), [0: 1, 1: 2, 2: 3])
    }

    func testEachLevelCountsOnItsOwn() {
        // The nested items count from their own first item; back out, the outer list carries on.
        XCTAssertEqual(numbers("1. a\n  1. b\n  5. c\n2. d"), [0: 1, 1: 1, 2: 2, 3: 2])
        XCTAssertEqual(numbers("1. a\n  4. b\n1. c\n  1. d"), [0: 1, 1: 4, 2: 2, 3: 1])
    }

    func testWhatEndsARun() {
        // A bullet or a checklist item at the level ends its count; the next ordered item starts from its own number.
        XCTAssertEqual(numbers("1. a\n- b\n1. c"), [0: 1, 2: 1])
        XCTAssertEqual(numbers("1. a\n- [ ] b\n5. c"), [0: 1, 2: 5])
        // So does any line that isn't a list item, a blank one included.
        XCTAssertEqual(numbers("1. a\ntext\n1. b"), [0: 1, 2: 1])
        XCTAssertEqual(numbers("1. a\n\n1. b"), [0: 1, 2: 1])
        // A bullet nested under an item doesn't end the outer count.
        XCTAssertEqual(numbers("1. a\n  - b\n1. c"), [0: 1, 2: 2])
    }

    func testNoOrderedItems() {
        XCTAssertEqual(numbers(""), [:])
        XCTAssertEqual(numbers("- a\n- b\ntext"), [:])
    }
}
