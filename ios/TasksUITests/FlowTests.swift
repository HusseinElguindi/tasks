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

    /// Settings ▸ Sync against a local `wrangler dev`: the token typed into the SecureField goes to the Keychain and sync
    /// runs on it; after a relaunch it's still there. Runs only when TEST_RUNNER_SYNC_TEST_TOKEN holds that server's
    /// throwaway token (it never comes from here), and takes no screenshots.
    func testSyncTokenInSettings() throws {
        guard let token = ProcessInfo.processInfo.environment["SYNC_TEST_TOKEN"], !token.isEmpty else {
            throw XCTSkip("No local server token (TEST_RUNNER_SYNC_TEST_TOKEN).")
        }
        app.launchArguments = ["-dataDirectory", "~/Library/Caches/Sync Test", "-serverURL", "http://127.0.0.1:8787",
                               "-appearance", "dark", "-style", "classic"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let field = app.secureTextFields["Token"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(token)
        app.buttons["Save"].firstMatch.tap()
        let synced = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Up to date'")).firstMatch
        XCTAssertTrue(synced.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saved in the Keychain."].exists)

        app.terminate()
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved in the Keychain."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Up to date'")).firstMatch.waitForExistence(timeout: 10))
    }

    // MARK: Adding a task: every way out of the new-task row

    private var draft: XCUIElement { app.textFields["draft"] }

    /// The + opens the new-task row, with the caret in it.
    private func add(_ why: String = "the + opens the new-task row", file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["New Task"].firstMatch.tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 3), why, file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "\(why): keyboard up", file: file, line: line)
    }

    /// No new-task row and no keyboard: the list as it is when not adding.
    private func assertNotAdding(_ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(draft.waitForNonExistence(timeout: 3), "no new-task row: \(why)", file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "no keyboard: \(why)", file: file, line: line)
    }

    private func back() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    /// The home row's count: no task was written.
    private func assertCount(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 3), "home shows \(label)", file: file, line: line)
    }

    /// Return on a title writes it and opens the next row; Return on an empty row ends adding, writing nothing.
    func testAddReturn() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        app.typeText("Book a study room for Thursday\n")
        XCTAssertTrue(app.staticTexts["Book a study room for Thursday"].waitForExistence(timeout: 3))
        XCTAssertTrue(draft.waitForExistence(timeout: 3), "the next row opens")
        app.typeText("\n")
        assertNotAdding("Return on an empty row")
        back()
        assertCount("School, 12")
    }

    /// A tap outside the row (the list's header) drops an empty row and writes a titled one, as a press elsewhere does
    /// on the Mac.
    func testAddTapOutside() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        header.tap()
        assertNotAdding("tap outside, empty")
        add("the + again")
        app.typeText("Return the library books")
        header.tap()
        assertNotAdding("tap outside, titled")
        XCTAssertTrue(app.staticTexts["Return the library books"].exists, "a titled row is written")
        shot("flow-add-tap-outside")
        back()
        assertCount("School, 12")
    }

    /// Swiping the list down puts the keyboard away and ends adding.
    func testAddSwipeDown() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        let start = app.descendants(matching: .any)["listHeader"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)), withVelocity: .fast, thenHoldForDuration: 0)
        assertNotAdding("swipe down")
        back()
        assertCount("School, 11")
    }

    /// Cancel, in the bar while adding, drops the row with whatever was typed.
    func testAddCancel() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        app.typeText("Not this one")
        shot("flow-add-cancel")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        assertNotAdding("Cancel")
        XCTAssertFalse(app.staticTexts["Not this one"].exists, "nothing written")
        XCTAssertTrue(app.buttons["List actions"].exists, "the list's menu is back")
        back()
        assertCount("School, 11")
    }

    /// Leaving the list ends adding: back home, another view, Settings, and back shows the list as it was. A titled row
    /// is written on the way out (the Mac's "anything else: writes it, then does that").
    func testAddEndsOnLeaving() {
        app.launch()
        // From home: the + adds in the default list (the Inbox).
        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch
        let before = inbox.label
        add("the + from home")
        back()
        XCTAssertEqual(inbox.label, before, "nothing written")
        inbox.tap()
        assertNotAdding("back to the Inbox")
        // Into a list, out to Today and Settings, and back.
        back()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch.tap()
        assertNotAdding("in Today")
        back()
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        app.buttons["School, 11"].firstMatch.tap()
        assertNotAdding("back to School")
        // Typed, then left: written, and the list shows normally.
        add()
        app.typeText("Water the plants")
        back()
        assertCount("School, 12")
        app.buttons["School, 12"].firstMatch.tap()
        assertNotAdding("back to School after writing")
        XCTAssertTrue(app.staticTexts["Water the plants"].exists)
    }

    /// iPad: another view or Settings from the sidebar ends adding, and the list shows normally when picked again.
    func testAddEndsFromSidebar() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("The sidebar is iPad's.") }
        // Landscape: the three panes side by side (in portrait the sidebar is an overlay that a tap outside closes).
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch.tap()
        assertNotAdding("in Today")
        app.buttons["School, 11"].firstMatch.tap()
        assertNotAdding("back to School")
        add()
        app.typeText("Water the plants")
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        assertNotAdding("after Settings")
        XCTAssertTrue(app.staticTexts["Water the plants"].exists, "a titled row is written")
        assertCount("School, 12")
        shot("flow-add-ipad-sidebar")
    }

    /// The app going to the background ends adding: back in front, the list shows normally (a title was written).
    func testAddEndsInBackground() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        add()
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        assertNotAdding("background, empty")
        add("the + again")
        app.typeText("Print the lab report")
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        assertNotAdding("background, titled")
        XCTAssertTrue(app.staticTexts["Print the lab report"].exists, "a titled row is written")
        back()
        assertCount("School, 12")
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
