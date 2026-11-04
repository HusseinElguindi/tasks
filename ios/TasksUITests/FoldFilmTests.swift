import XCTest

// Film scripts for the fold (§23), not tests: run with Tools/film/film.sh (TEST_RUNNER_FILM=1; skipped otherwise).
// Each step prints "FILM <label> <epoch>" to line the video up with (Tools/film/events.py); rows.py then gives each
// frame's heading rules.
final class FoldFilmTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILM"] != nil, "a film script: Tools/film/film.sh")
    }

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                               "-remoteTask", "h-lab", "-remoteNotes", "Goggles, a lab coat and the lab manual, every session; pre-labs are due at the start of the lab."]
    }

    func mark(_ s: String) { print(String(format: "FILM %@ %.3f", s, Date().timeIntervalSince1970)) }
    func pause() { usleep(1_500_000) }

    func heading(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "heading").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Lectures (no notes) and Labs (with notes, from "another device"), folded and opened twice each.
    func testFilmFold() {
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        for name in ["Lectures", "Labs"] {
            if name == "Labs" {
                mark("notes")
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                     CFNotificationName("com.elguindi.Tasks.test.remote-edit" as CFString), nil, nil, true)
                pause()
            }
            for i in 1...2 {
                mark("collapse_\(name)_\(i)")
                app.buttons["Collapse \(name)"].tap()
                pause()
                mark("expand_\(name)_\(i)")
                app.buttons["Expand \(name)"].tap()
                pause()
            }
        }
    }

    func menuOpen(_ steps: () -> Void) {
        let on = app.responds(to: NSSelectorFromString("setIdleAnimationWaitEnabled:"))
        if on { app.setValue(false, forKey: "idleAnimationWaitEnabled") }
        defer { if on { app.setValue(true, forKey: "idleAnimationWaitEnabled") } }
        steps()
    }

    /// Labs' notes, typed in place (it has none until the remote edit, which isn't posted here), a new line, Done; a tap
    /// back into them and Done; a rename and Cancel. Exam prep's rule, below them, moves with each.
    func testFilmEditing() {
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10))
        sleep(1)
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            mark("addNotes")
            app.buttons["Add Notes"].tap()
        }
        pause()
        mark("type")
        app.typeText("Goggles")
        pause()
        mark("newline")
        app.typeText("\nLab coat")
        pause()
        // The third and fourth lines grow the editor past its least height.
        mark("newline3")
        app.typeText("\nLab manual")
        pause()
        mark("newline4")
        app.typeText("\nPre-lab")
        pause()
        mark("done1")
        app.buttons["Done"].tap()
        pause()
        mark("tapNotes")
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Goggles'")).firstMatch.tap()
        pause()
        mark("done2")
        app.buttons["Done"].tap()
        pause()
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            mark("rename")
            app.buttons["Rename"].tap()
        }
        pause()
        mark("cancel")
        app.buttons["Cancel"].tap()
        pause()
        // The list's notes, under its title: a tap on them, a new line, Done; Edit Notes from its menu, Done.
        // The title, scrolled back into view (the keyboard scrolled the notes above it).
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        for _ in 0..<3 where !header.exists { app.collectionViews.firstMatch.swipeDown() }
        pause()
        mark("listTap")
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap()
        pause()
        mark("listNewline")
        app.typeText("\nBring a calculator")
        pause()
        mark("listDone1")
        app.buttons["Done"].tap()
        pause()
        mark("listMenu")
        app.buttons["List actions"].tap()
        app.buttons["Edit Notes"].tap()
        pause()
        mark("listDone2")
        app.buttons["Done"].tap()
        pause()
    }
}
