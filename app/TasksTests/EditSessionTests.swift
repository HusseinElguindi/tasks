import XCTest

/// What an editing session writes when it ends (docs/MAC-EDIT-DURABILITY.md). EditSession.swift is compiled into this
/// bundle, so these run without the app.
final class EditSessionTests: XCTestCase {
    func testAnUntouchedFieldWritesNothing() {
        XCTAssertNil(EditSession.write("T1", original: "T1", current: "T1"))
    }

    /// The bug: the caret sat in "T1", "Remote1" synced in, the edit ended, and "T1" went back over it.
    func testAnUntouchedFieldNeverRevertsAChangeThatSyncedIn() {
        XCTAssertNil(EditSession.write("T1", original: "T1", current: "Remote1"))
    }

    func testTypedTextIsWritten() {
        XCTAssertEqual(EditSession.write("T1X", original: "T1", current: "T1"), "T1X")
    }

    /// Typed text still wins over a concurrent remote change, as last-writer-wins has it.
    func testTypedTextWinsOverAChangeThatSyncedIn() {
        XCTAssertEqual(EditSession.write("T1X", original: "T1", current: "Remote1"), "T1X")
    }

    func testTypingBackToTheOriginalWritesNothing() {
        XCTAssertNil(EditSession.write("T1", original: "T1", current: "Remote1"))
    }

    func testTextThatAlreadyMatchesTheModelWritesNothing() {
        XCTAssertNil(EditSession.write("Remote1", original: "T1", current: "Remote1"))
    }

    /// A new list or heading starts from "" and has no model value yet.
    func testANewEntityWithANameIsWritten() {
        XCTAssertEqual(EditSession.write("Work", original: "", current: nil), "Work")
        XCTAssertNil(EditSession.write("", original: "", current: nil))
    }

    func testEmptyingNotesIsWritten() {
        XCTAssertEqual(EditSession.write("", original: "first note", current: "first note"), "")
    }
}
