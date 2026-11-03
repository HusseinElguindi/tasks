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

    // MARK: An edit writes only what the user changed (the Mac's rule, INTERACTIONS-v2 §7)

    /// Launches with a change "from another device" for `task`, made each time `remoteEdit()` posts (RemoteEdit.swift).
    private func launch(remote task: String, title: String? = nil, notes: String? = nil) {
        app.launchArguments += ["-remoteTask", task]
        if let title { app.launchArguments += ["-remoteTitle", title] }
        if let notes { app.launchArguments += ["-remoteNotes", notes] }
        app.launch()
    }

    /// The other device's change lands now, mid-edit.
    private func remoteEdit() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName("com.elguindi.Tasks.test.remote-edit" as CFString), nil, nil, true)
        sleep(1)
    }

    /// The details' title field, by its text, with the caret at its end.
    private func editTitle(_ text: String) {
        func titled(_ q: XCUIElementQuery) -> XCUIElement { q.matching(NSPredicate(format: "value == %@", text)).firstMatch }
        let field = titled(app.textViews).exists ? titled(app.textViews) : titled(app.textFields)
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the title field")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the title has the caret")
    }

    /// The caret sits in the title, untouched, while another device renames the task: closing the details writes
    /// nothing, so the rename stands (before, the old title went back over it).
    func testSyncedTitleStandsAfterAnUntouchedEdit() {
        launch(remote: "s4", title: "Submit MSE 333 A2 (from the Mac)")
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        editTitle("Submit MSE 333 A2")
        remoteEdit()
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2 (from the Mac)"].waitForExistence(timeout: 3), "the synced title stands")
        XCTAssertFalse(app.staticTexts["Submit MSE 333 A2"].exists, "the old title isn't written back")
    }

    /// Typed text is written, and wins over a rename that synced in meanwhile (the log's last writer wins).
    func testTypedTitleWinsOverASyncedOne() {
        launch(remote: "s4", title: "Submit MSE 333 A2 (from the Mac)")
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        editTitle("Submit MSE 333 A2")
        app.typeText(" v2")
        remoteEdit()
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2 v2"].waitForExistence(timeout: 3), "the typed title is written")
        XCTAssertFalse(app.staticTexts["Submit MSE 333 A2 (from the Mac)"].exists)
    }

    /// The caret sits in the notes, untouched, while another device changes them: closing the details writes nothing.
    func testSyncedNotesStandAfterAnUntouchedEdit() {
        launch(remote: "s2", notes: "Synced from the Mac.")
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Email TA about midterm regrade"].firstMatch.tap()
        sleep(1)
        let notes = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Question 4(b)'")).firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 3), "the notes at rest")
        notes.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the notes have the caret")
        remoteEdit()
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Email TA about midterm regrade"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Synced from the Mac."].waitForExistence(timeout: 3), "the synced notes stand")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Question 4(b)'")).firstMatch.exists,
                       "the old notes aren't written back")
    }

    /// Rename List left as it was while another device renames the list: Rename writes nothing, so that name stands.
    func testSyncedListNameStandsAfterAnUntouchedRename() {
        app.launchArguments += ["-remoteList", "school-9", "-remoteName", "School (from the Mac)"]
        app.launch()
        app.buttons["School, 11"].firstMatch.press(forDuration: 1.0)
        app.buttons["Rename"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Rename List"].waitForExistence(timeout: 3), "the rename alert")
        remoteEdit()
        app.alerts["Rename List"].buttons["Rename"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["School (from the Mac), 11"].waitForExistence(timeout: 3), "the synced name stands")
    }

    /// Leaving the app mid-edit writes only what was typed: an untouched title doesn't go back over one that synced in.
    func testSyncedTitleStandsAfterTheBackground() {
        launch(remote: "s4", title: "Submit MSE 333 A2 (from the Mac)")
        app.buttons["School, 11"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        editTitle("Submit MSE 333 A2")
        remoteEdit()
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2 (from the Mac)"].waitForExistence(timeout: 3), "the synced title stands")
        XCTAssertFalse(app.staticTexts["Submit MSE 333 A2"].exists, "the old title isn't written back")
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
        // The + rides the keyboard, so after adding ends it slides back down: tap its middle once it has stopped (XCUITest
        // otherwise may pick a point near its frame's corner, outside the round button).
        let plus = app.buttons["New Task"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 3), "\(why): the +", file: file, line: line)
        _ = settledFrame(plus)
        plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

    /// A tap outside the row (the list's header) drops an empty row and writes a titled one.
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

    /// Still on the list, as it is when not adding: no task's details, no other screen.
    private func assertNothingOpened(_ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.buttons["When"].waitForExistence(timeout: 1.5), "no task's details: \(why)", file: file, line: line)
        XCTAssertTrue(app.buttons["List actions"].exists, "still on the list: \(why)", file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)["listHeader"].firstMatch.label.hasPrefix("School"),
                      "still on School: \(why)", file: file, line: line)
    }

    /// While adding, a tap on another task only ends adding (the user, 2026-11-02): the task doesn't open and its box
    /// doesn't check; a typed title is written, an empty row dropped. (On the Mac the press also does what it presses.)
    func testAddTapOnARowOnlyEndsAdding() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        let row = app.staticTexts["Submit MSE 333 A2"].firstMatch
        add()
        row.tap()
        assertNotAdding("tap on a task, empty")
        assertNothingOpened("tap on a task, empty")
        add("the + again")
        app.typeText("Return the library books")
        row.tap()
        assertNotAdding("tap on a task, titled")
        assertNothingOpened("tap on a task, titled")
        XCTAssertTrue(app.staticTexts["Return the library books"].exists, "a titled row is written")
        shot("flow-add-tap-row")
        // Not adding, the same tap opens the task, as always.
        row.tap()
        XCTAssertTrue(app.buttons["When"].waitForExistence(timeout: 3), "the task opens when not adding")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        back()
        assertCount("School, 12")
    }

    /// An element's frame once it has stopped moving (the new row slides the rows below it down).
    private func settledFrame(_ e: XCUIElement) -> CGRect {
        var last = e.frame
        for _ in 0..<15 {
            usleep(200_000)
            let f = e.frame
            if f == last { return f }
            last = f
        }
        return last
    }

    /// While adding, a tap on another task's box only ends adding: nothing completes.
    func testAddTapOnABoxOnlyEndsAdding() {
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        let title = app.staticTexts["Submit MSE 333 A2"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        add()
        let y = settledFrame(title).midY
        let box = app.buttons.matching(identifier: "Complete").allElementsBoundByIndex.first { abs($0.frame.midY - y) < 12 }
        XCTAssertNotNil(box, "the task's box")
        box?.tap()
        XCTAssertFalse(app.buttons["Undo"].waitForExistence(timeout: 1.5), "nothing completed (no notice)")
        assertNotAdding("tap on a box")
        assertNothingOpened("tap on a box")
        back()
        assertCount("School, 11")   // still 11 open: nothing completed
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

    /// iPad: while adding, a tap in the sidebar (a view, Settings) only ends adding and opens nothing (the user,
    /// 2026-11-02); the next tap there goes where it goes, and the list shows normally.
    func testAddEndsFromSidebar() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("The sidebar is iPad's.") }
        // Landscape: the three panes side by side (in portrait the sidebar is an overlay that a tap outside closes).
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        app.buttons["School, 11"].firstMatch.tap()
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch
        add()
        today.tap()
        assertNotAdding("tap on Today, empty")
        assertNothingOpened("tap on Today, empty")
        add("the + again")
        app.typeText("Water the plants")
        app.buttons["Settings"].firstMatch.tap()
        assertNotAdding("tap on Settings, titled")
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 1.5), "Settings didn't open")
        assertNothingOpened("tap on Settings, titled")
        XCTAssertTrue(app.staticTexts["Water the plants"].exists, "a titled row is written")
        assertCount("School, 12")
        shot("flow-add-ipad-sidebar")
        // Not adding, the sidebar goes where it goes.
        today.tap()
        XCTAssertTrue(app.descendants(matching: .any)["listHeader"].firstMatch.label.hasPrefix("Today"), "Today opens")
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

    // MARK: A very long list name

    /// A few long words and one that can't break.
    static let longName = "Thermodynamics and statistical mechanics: problem sets, labs and Pneumonoultramicroscopicsilicovolcanoconiosis"

    /// A menu item for the long name: cut to one line with an ellipsis.
    private var longNameItem: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Thermo' AND label ENDSWITH '…'")).firstMatch
    }

    /// The element of `query` labelled `label` whose middle is level with `other`'s (a bar's, a row's).
    private func level(_ query: XCUIElementQuery, _ label: String, with other: XCUIElement) -> XCUIElement? {
        query.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            .first { abs($0.frame.midY - other.frame.midY) < 12 }
    }

    /// A very long list name (the user, 2026-11-02) stays on one line in a task's details, as on the Mac, where pane
    /// titles end in an ellipsis: the header and the List chip cut it, and the List picker's item is one line, cut too.
    /// Nothing else moves when the list takes the name (another device renames it while the details are open).
    func testLongListNameInDetails() {
        app.launchArguments += ["-screen", "detail:s4", "-remoteList", "school-9", "-remoteName", Self.longName]
        app.launch()
        let chip = app.buttons["detailList"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the details' List chip")
        XCTAssertTrue(chip.label.contains("School"))
        // The bar's last button: Done on the phone, × in iPad's details pane.
        let bar = app.buttons["Hide Details"].exists ? app.buttons["Hide Details"] : app.buttons["Done"]
        XCTAssertTrue(bar.exists, "the details' bar")
        let chipBefore = chip.frame, whenBefore = app.buttons["When"].frame
        remoteEdit()
        XCTAssertTrue(chip.label.contains("Thermodynamics"), "the List chip, renamed")
        sleep(1)
        shot("long-name-details")
        XCTAssertEqual(chip.frame.height, chipBefore.height, accuracy: 1, "the chip stays one line")
        XCTAssertLessThanOrEqual(chip.frame.maxX, bar.frame.maxX, "the chip fits its row")
        XCTAssertEqual(app.buttons["When"].frame.minY, whenBefore.minY, accuracy: 1, "the rows below don't move")
        let header = level(app.staticTexts, Self.longName, with: bar)
        XCTAssertNotNil(header, "the header's name")
        if let header, let delete = level(app.buttons, "Delete", with: bar) {
            XCTAssertLessThan(header.frame.height, 30, "the header's name is one line")
            XCTAssertLessThanOrEqual(header.frame.maxX, delete.frame.minX, "and stops before the bar's buttons")
        }
        chip.tap()
        XCTAssertTrue(longNameItem.waitForExistence(timeout: 3), "the List picker's item, cut with an ellipsis")
        XCTAssertEqual(longNameItem.frame.height, app.buttons["PHYS 122"].firstMatch.frame.height, accuracy: 1,
                       "one line, as the other lists' items")
        shot("long-name-picker")
    }

    /// The same name in a row's Move to menu: one line, cut with an ellipsis, as the Mac's menus cut names.
    func testLongListNameInMoveTo() {
        app.launchArguments += ["-screen", "list:inbox", "-remoteList", "school-9", "-remoteName", Self.longName]
        app.launch()
        let row = app.staticTexts["Look into a standing desk"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the Inbox")
        remoteEdit()
        row.press(forDuration: 1.2)
        let move = app.buttons["Move to"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 3), "the row's menu")
        move.tap()
        XCTAssertTrue(longNameItem.waitForExistence(timeout: 3), "the Move to item, cut with an ellipsis")
        XCTAssertEqual(longNameItem.frame.height, app.buttons["PHYS 122"].firstMatch.frame.height, accuracy: 1,
                       "one line, as the other lists' items")
        shot("long-name-move-to")
    }
}
