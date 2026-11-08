import XCTest

/// `UndoStep` (Tasks/Window/UndoStep.swift), `WindowActions.undoable`'s group: it names the step while the group is
/// open, so it holds on an undo manager that doesn't group by event. Named after the group closed, such a manager has
/// no group to name and throws an Objective-C exception; under a Swift Task that the run loop swallowed, it left the
/// main thread's executor record stale and crashed the next MainActor check (SyncCloud's body, 2026-11-08).
@MainActor
final class UndoStepTests: XCTestCase {
    private final class Box { var value = 0 }

    private func step(_ um: UndoManager, _ box: Box, to value: Int) -> Bool {
        UndoStep.run(um, name: "Move") {
            let old = box.value
            box.value = value
            um.registerUndo(withTarget: box) { $0.value = old }
            return true
        }
    }

    func testAManagerThatDoesntGroupByEventGetsANamedStep() {
        let um = UndoManager()
        um.groupsByEvent = false
        let box = Box()
        XCTAssertTrue(step(um, box, to: 1))
        XCTAssertEqual(um.groupingLevel, 0)
        XCTAssertTrue(um.canUndo)
        XCTAssertEqual(um.undoActionName, "Move")
        um.undo()
        XCTAssertEqual(box.value, 0)
    }

    func testInsideAnOuterGroupTheStepIsNamedAsBefore() {
        // As in the app: the window's manager groups by event, so its step is inside the event's group.
        let um = UndoManager()
        um.groupsByEvent = false
        let box = Box()
        um.beginUndoGrouping()
        XCTAssertTrue(step(um, box, to: 1))
        um.endUndoGrouping()
        XCTAssertEqual(um.undoActionName, "Move")
        um.undo()
        XCTAssertEqual(box.value, 0)
    }

    func testAStepThatDidNothingIsNotNamed() {
        let um = UndoManager()
        um.groupsByEvent = false
        XCTAssertFalse(UndoStep.run(um, name: "Move") { false })
        XCTAssertEqual(um.groupingLevel, 0)
        XCTAssertEqual(um.undoActionName, "")
    }
}
