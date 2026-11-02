import XCTest

/// Drives the app the way a person would and saves a screenshot at each step to $SHOTS (default /tmp/tasks-shots).
final class FlowTests: XCTestCase {
    var app: XCUIApplication!
    let dir: String = ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/tasks-shots"

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // The sample lists and tasks, seeded fresh in a scratch store at each launch (never the app's data), in Dark and
        // Classic whatever an earlier run chose in Settings (launch arguments win over saved settings).
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic"]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testAddTask() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.buttons["New Task"].firstMatch.tap()
        sleep(1)
        app.typeText("Book a study room for Thursday")
        shot("flow-newtask-typing")
        app.typeText("\n")
        sleep(1)
        shot("flow-newtask-committed")
        app.typeText("\n")   // empty title cancels
        sleep(1)
        shot("flow-newtask-done")
    }

    func testCompleteAndUndo() {
        app.launch()
        app.buttons["Today, 13"].firstMatch.tap()
        sleep(1)
        app.buttons.matching(identifier: "Complete").element(boundBy: 0).tap()
        usleep(400_000)
        shot("flow-complete-checked")
        sleep(2)
        shot("flow-complete-moved")
        app.buttons["Undo"].firstMatch.tap()
        sleep(1)
        shot("flow-complete-undone")
    }

    func testSwipe() {
        app.launch()
        app.buttons["PHYS 122, 10"].firstMatch.tap()
        sleep(1)
        let row = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        row.swipeLeft()
        sleep(1)
        shot("flow-swipe-left")
        row.swipeRight()
        sleep(1)
        let row2 = app.staticTexts["Book a make-up lab bench"].firstMatch
        row2.swipeRight()
        sleep(1)
        shot("flow-swipe-right")
    }

    func testDetailAndWhen() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        shot("flow-detail")
        app.buttons["When"].firstMatch.tap()
        sleep(1)
        shot("flow-when")
        app.buttons["Tomorrow"].firstMatch.tap()
        sleep(1)
        shot("flow-detail-after-when")
        app.swipeUp()
        sleep(1)
        shot("flow-detail-large")
    }

    func testDeleteListAndTrash() {
        app.launch()
        app.buttons["Errands, 4"].firstMatch.press(forDuration: 1.0)
        sleep(1)
        shot("flow-list-menu")
        app.buttons["Delete List"].firstMatch.tap()
        sleep(1)
        shot("flow-list-deleted")
        app.buttons["Trash"].firstMatch.tap()
        sleep(1)
        shot("flow-trash")
    }

    /// One theme, the Mac's: Settings changes the appearance and the interface style.
    func testSettingsAppearance() {
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        app.buttons["Dark"].firstMatch.tap()
        sleep(1)
        shot("flow-settings-dark")
        app.buttons["Light"].firstMatch.tap()
        sleep(1)
        shot("flow-settings-light")
        app.buttons["Glass"].firstMatch.tap()
        sleep(1)
        shot("flow-settings-glass")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        shot("flow-home-light-glass")
    }

    /// The title is edited in the details and written when they close (one change, as on the Mac): the row has it.
    func testEditTitle() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        func titled(_ q: XCUIElementQuery) -> XCUIElement {
            q.matching(NSPredicate(format: "value == %@", "Submit MSE 333 A2")).firstMatch
        }
        let field = titled(app.textViews).exists ? titled(app.textViews) : titled(app.textFields)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        // Right of the text: the caret goes to its end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        app.typeText(" v2")
        shot("flow-edit-title")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2 v2"].waitForExistence(timeout: 3))
        shot("flow-edit-title-done")
    }

    func testScrollFold() {
        app.launch()
        app.buttons["PHYS 122, 10"].firstMatch.tap()
        sleep(1)
        app.swipeUp()
        sleep(1)
        shot("flow-scrolled")
    }
}
