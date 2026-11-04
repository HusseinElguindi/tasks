import XCTest

// Film scripts for drag (§14, §23) on the UICollectionView path, not tests: run with Tools/film/film.sh (TEST_RUNNER_FILM=1;
// skipped otherwise) and TEST_RUNNER_LIST_CONTAINER=cv. Each drag prints "FILM <label> <epoch>" as its press starts, to
// line the video up with (Tools/film/events.py, vgaps.py); rows.py blobs then gives each frame's rows of ink.
final class DragFilmTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILM"] != nil, "a film script: Tools/film/film.sh")
    }

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys"]
        if let c = ProcessInfo.processInfo.environment["LIST_CONTAINER"] { app.launchEnvironment["LIST_CONTAINER"] = c }
    }

    func mark(_ s: String) { print(String(format: "FILM %@ %.3f", s, Date().timeIntervalSince1970)) }

    func heading(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "heading").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Long-press, then drag `from` to `dy` points from its middle, as a finger does (FlowTests' `drag`).
    func drag(_ label: String, _ from: XCUIElement, by dy: CGFloat) {
        mark(label)
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .default, thenHoldForDuration: 1)
        sleep(2)
    }

    /// A task into the next section (a drop), Labs up before Lectures (its section folds into the copy, with the count
    /// badge; then opens), and the first task pulled up past its slot and let go there (refused: home).
    func testFilmDrag() {
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
        drag("task_down", redo, by: bench.frame.midY - redo.frame.midY)
        let read = app.staticTexts["Read chapter 15 · oscillations"].firstMatch
        drag("heading_up", heading("Labs"), by: read.frame.midY - heading("Labs").frame.midY)
        // A small nudge opens the row's menu instead, so the list's first task is pulled 60 pt up: the copy is held 6 pt
        // past its slot, the first, which is its own.
        drag("refused", app.staticTexts["Buy safety glasses for the lab"].firstMatch, by: -60)
    }
}
