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
        XCTAssertTrue(heading("Labs").appears(timeout: 10))
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
        XCTAssertTrue(heading("Labs").appears(timeout: 10))
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

// Film scripts for editing notes in place (T33: "some jumps of the text and the surrounding screen", and a Return that
// sometimes doesn't move the caret down until the next character). Run with Tools/film/film.sh <name>
// TasksUITests/NotesEditFilmTests/testFilmHeadingNotes (or …ListNotes); `-editTrace YES` writes each frame's caret,
// editor, cell, next row, offset and inset to tmp/edit-trace.log in the app's container (EditProbe.swift).
final class NotesEditFilmTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILM"] != nil, "a film script: Tools/film/film.sh")
    }

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                               "-editTrace", "YES"]
    }

    func mark(_ s: String) { print(String(format: "FILM %@ %.3f", s, Date().timeIntervalSince1970)) }
    func pause() { usleep(900_000) }

    func heading(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "heading").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    func menuOpen(_ steps: () -> Void) {
        let on = app.responds(to: NSSelectorFromString("setIdleAnimationWaitEnabled:"))
        if on { app.setValue(false, forKey: "idleAnimationWaitEnabled") }
        defer { if on { app.setValue(true, forKey: "idleAnimationWaitEnabled") } }
        steps()
    }

    /// The software keyboard's Return key, as a finger presses it (XCTest's typed "\n" goes in as a hardware key).
    func returnKey(_ label: String) {
        mark(label)
        let key = app.keyboards.buttons["Return"].exists ? app.keyboards.buttons["Return"] : app.keyboards.buttons["return"]
        if key.exists { key.tap() } else { app.typeText("\n") }
        pause()
    }

    /// A key at a time, about as a thumb types (XCTest's one-call typing runs keys 17 ms apart, faster than frames).
    func type(_ label: String, _ s: String) {
        mark(label)
        for c in s { app.typeText(String(c)) }
        pause()
    }

    /// Starts editing, types lines, Returns at the end, in the middle and on an empty last line, deletes lines,
    /// finishes; `editor` is the text view's identifier.
    func script(_ editor: XCUIElement) {
        XCTAssertTrue(editor.appears(timeout: 3))
        pause()
        type("type1", "Goggles")
        returnKey("ret_end1")
        type("type2", "Lab coat")
        returnKey("ret_end2")
        type("type3", "Lab manual")
        returnKey("ret_end3")
        returnKey("ret_empty1")
        returnKey("ret_empty2")
        type("type4", "Pre-lab")
        // In the middle: the caret put after "Lab coat" (the second line's end), then Return.
        mark("tap_middle")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0)).withOffset(CGVector(dx: 0, dy: 32)).tap()
        pause()
        returnKey("ret_middle1")
        returnKey("ret_middle2")
        type("type5", "Calculator")
        // Lines deleted: back to the end, then the delete key held through the last lines.
        mark("tap_end")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.97)).tap()
        pause()
        for i in 1...3 {
            type("del_line\(i)", String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        }
        type("del_empty", String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        mark("done")
        app.buttons["Done"].tap()
        pause()
        pause()
    }

    func testFilmHeadingNotes() {
        app.launch()
        XCTAssertTrue(heading("Labs").appears(timeout: 10))
        sleep(1)
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            mark("addNotes")
            app.buttons["Add Notes"].tap()
        }
        script(app.textViews["headingNotes"])
        // Tapped back into, a Return at the end, Done.
        mark("tapNotes")
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Goggles'")).firstMatch.tap()
        pause()
        returnKey("ret_again")
        mark("done2")
        app.buttons["Done"].tap()
        pause()
    }

    func testFilmListNotes() {
        app.launch()
        XCTAssertTrue(heading("Labs").appears(timeout: 10))
        sleep(1)
        mark("listMenu")
        app.buttons["List actions"].tap()
        app.buttons[app.buttons["Edit Notes"].exists ? "Edit Notes" : "Add Notes"].tap()
        script(app.textViews["listNotes"])
    }
}
