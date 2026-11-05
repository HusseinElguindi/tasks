import XCTest

// Film scripts for drag (§14, §23), not tests: run with Tools/film/film.sh (TEST_RUNNER_FILM=1; skipped otherwise). Each
// drag prints "FILM <label> <epoch>" as its press starts, to line the video up with (Tools/film/events.py, vgaps.py);
// rows.py blobs then gives each frame's rows of ink.
final class DragFilmTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILM"] != nil, "a film script: Tools/film/film.sh")
    }

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        // -dragTrace: the app's own frame log of the copy and the row under it (CollectionDrag's DragProbe).
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                               "-dragTrace", "YES", "-dragTraceUIKit", "YES"]
    }

    func mark(_ s: String) { print(String(format: "FILM %@ %.3f", s, Date().timeIntervalSince1970)) }

    func heading(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "heading").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Long-press, then drag `from` to `dx`, `dy` points from its middle, as a finger does (FlowTests' `drag`).
    func drag(_ label: String, _ from: XCUIElement, by dy: CGFloat, dx: CGFloat = 0) {
        mark(label)
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)), withVelocity: .default, thenHoldForDuration: 1)
        sleep(2)
    }

    /// The hold, from touch-down: a task held 0.6 s and dragged slowly onto the bench row (what shows at the lift, and
    /// as the drag begins), then, relaunched, a task held 1.2 s without moving (its long-press menu).
    func testFilmLift() {
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
        mark("lift_drag")
        redo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: bench.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.5)
        sleep(2)
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        mark("menu")
        app.staticTexts["Redo the worked examples from lecture 9"].firstMatch.press(forDuration: 1.2)
        sleep(2)
        // Home: a list dragged slowly, then (relaunched) a list's menu.
        app.launchArguments = app.launchArguments.filter { $0 != "-screen" && $0 != "list:phys" }
        app.launch()
        let phys = app.buttons["PHYS 122"].firstMatch, school = app.buttons["School"].firstMatch
        XCTAssertTrue(phys.waitForExistence(timeout: 10))
        sleep(1)
        mark("home_drag")
        phys.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: school.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.5)
        sleep(2)
        app.launch()
        XCTAssertTrue(phys.waitForExistence(timeout: 10))
        sleep(1)
        mark("home_menu")
        app.buttons["Errands"].firstMatch.press(forDuration: 1.2)
        sleep(2)
    }

    /// Fast flicks of a task onto the bench row, let go as they arrive (FlowTests' testAFastFlickDropsWhereTheFingerLetGo):
    /// UIKit begins some late and ends them with no drop; ours then drops at the finger's slot. Relaunched for each.
    func testFilmFlick() {
        for (n, (hold, speed)) in [(0.5, 4000.0), (0.5, 4000), (0.55, 6000), (0.5, 6000)].enumerated() {
            app.launch()
            XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
            sleep(1)
            let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
            let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
            mark("flick\(n + 1)")
            redo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: hold, thenDragTo: bench.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                       withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: 0)
            sleep(2)
        }
    }

    /// A task into the next section, let go 60 pt right of its column (a drop: it falls back into the row's frame),
    /// Labs up before Lectures (its section folds into the copy, with the count badge; then opens), and the first task
    /// pulled up past its slot and let go there (refused: home).
    func testFilmDrag() {
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
        drag("task_down", redo, by: bench.frame.midY - redo.frame.midY, dx: 60)
        let read = app.staticTexts["Read chapter 15 · oscillations"].firstMatch
        drag("heading_up", heading("Labs"), by: read.frame.midY - heading("Labs").frame.midY)
        // A small nudge opens the row's menu instead, so the list's first task is pulled 60 pt up: the copy is held 6 pt
        // past its slot, the first, which is its own.
        drag("refused", app.staticTexts["Buy safety glasses for the lab"].firstMatch, by: -60)
    }
}
