import XCTest

/// Drives the app the way a person would and saves a screenshot at each step to $SHOTS (default /tmp/tasks-shots).
final class FlowTests: XCTestCase {
    var app: XCUIApplication!
    let dir: String = ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/tasks-shots"

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        // The sample lists and tasks, seeded fresh in a scratch store at each launch (never the app's data), in Dark and
        // Classic whatever an earlier run chose in Settings (launch arguments win over saved settings).
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic"]
        // TEST_RUNNER_LIST_CONTAINER=cv: the rows on the UICollectionView path (ListContainer), during the migration.
        if let c = ProcessInfo.processInfo.environment["LIST_CONTAINER"] { app.launchEnvironment["LIST_CONTAINER"] = c }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    /// Steps taken while a row's long-press menu is up. On a row that can be dragged the app never reports its
    /// animations finished while the menu is open, so XCTest waits out its 60 s timeout before and after each step
    /// there. Inside `menuOpen` a step waits only for the app's event loop to go idle, not for its animations.
    /// `idleAnimationWaitEnabled` is XCUIApplication's own switch for that (private); if an Xcode drops it, the
    /// steps run as before, only slower.
    func menuOpen(_ steps: () -> Void) {
        let on = app.responds(to: NSSelectorFromString("setIdleAnimationWaitEnabled:"))
        if on { app.setValue(false, forKey: "idleAnimationWaitEnabled") }
        defer { if on { app.setValue(true, forKey: "idleAnimationWaitEnabled") } }
        steps()
    }

    func testAddTask() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
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
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: '")).element(boundBy: 0).tap()
        usleep(400_000)
        shot("flow-complete-checked")
        usleep(1_500_000)   // the rows settle 1.5 s after the check; the notice lasts 5 s
        shot("flow-complete-moved")
        app.buttons["Undo"].firstMatch.tap()
        sleep(1)
        shot("flow-complete-undone")
    }

    func testSwipe() {
        app.launch()
        app.buttons["PHYS 122"].firstMatch.tap()
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
        app.buttons["School"].firstMatch.tap()
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
        menuOpen {
            app.buttons["Errands"].firstMatch.press(forDuration: 1.0)
            sleep(1)
            shot("flow-list-menu")
            app.buttons["Delete List"].firstMatch.tap()
        }
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
        app.buttons["School"].firstMatch.tap()
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
        app.buttons["School"].firstMatch.tap()
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
        app.buttons["School"].firstMatch.tap()
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
        app.buttons["School"].firstMatch.tap()
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
        menuOpen {
            app.buttons["School"].firstMatch.press(forDuration: 1.0)
            app.buttons["Rename"].firstMatch.tap()
        }
        XCTAssertTrue(app.alerts["Rename List"].waitForExistence(timeout: 3), "the rename alert")
        remoteEdit()
        app.alerts["Rename List"].buttons["Rename"].tap()
        sleep(1)
        // A list's row has no count (only Today's does), so its label is its name.
        XCTAssertTrue(app.buttons["School (from the Mac)"].waitForExistence(timeout: 3), "the synced name stands")
        XCTAssertFalse(app.buttons["School"].exists, "the old name isn't written back")
    }

    /// Leaving the app mid-edit writes only what was typed: an untouched title doesn't go back over one that synced in.
    func testSyncedTitleStandsAfterTheBackground() {
        launch(remote: "s4", title: "Submit MSE 333 A2 (from the Mac)")
        app.buttons["School"].firstMatch.tap()
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

    /// A list's open tasks (School's by default), counted by their boxes on its screen, from Home and back: whether a
    /// task was written.
    /// (Home shows no counts but Today's: the user, 2026-10-31.)
    private func assertOpen(_ n: Int, in list: String = "School", file: StaticString = #filePath, line: UInt = #line) {
        app.buttons[list].firstMatch.tap()
        let boxes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: '"))
        XCTAssertTrue(boxes.firstMatch.waitForExistence(timeout: 3), list, file: file, line: line)
        sleep(1)
        XCTAssertEqual(boxes.count, n, "\(list)'s open tasks", file: file, line: line)
        back()
    }

    /// Return on a title writes it and opens the next row; Return on an empty row ends adding, writing nothing.
    func testAddReturn() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
        add()
        app.typeText("Book a study room for Thursday\n")
        XCTAssertTrue(app.staticTexts["Book a study room for Thursday"].waitForExistence(timeout: 3))
        XCTAssertTrue(draft.waitForExistence(timeout: 3), "the next row opens")
        app.typeText("\n")
        assertNotAdding("Return on an empty row")
        back()
        assertOpen(12)
    }

    /// A tap outside the row (the list's header) drops an empty row and writes a titled one.
    func testAddTapOutside() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
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
        assertOpen(12)
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
        app.buttons["School"].firstMatch.tap()
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
        assertOpen(12)
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
        app.buttons["School"].firstMatch.tap()
        let title = app.staticTexts["Submit MSE 333 A2"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        add()
        let y = settledFrame(title).midY
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: '")).allElementsBoundByIndex.first { abs($0.frame.midY - y) < 12 }
        XCTAssertNotNil(box, "the task's box")
        box?.tap()
        XCTAssertFalse(app.buttons["Undo"].waitForExistence(timeout: 1.5), "nothing completed (no notice)")
        assertNotAdding("tap on a box")
        assertNothingOpened("tap on a box")
        back()
        assertOpen(11)   // still 11 open: nothing completed
    }

    /// Swiping the list down puts the keyboard away and ends adding.
    func testAddSwipeDown() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
        add()
        let start = app.descendants(matching: .any)["listHeader"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)), withVelocity: .fast, thenHoldForDuration: 0)
        assertNotAdding("swipe down")
        back()
        assertOpen(11)
    }

    /// Cancel, in the bar while adding, drops the row with whatever was typed.
    func testAddCancel() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
        add()
        app.typeText("Not this one")
        shot("flow-add-cancel")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        assertNotAdding("Cancel")
        XCTAssertFalse(app.staticTexts["Not this one"].exists, "nothing written")
        XCTAssertTrue(app.buttons["List actions"].exists, "the list's menu is back")
        back()
        assertOpen(11)
    }

    /// Leaving the list ends adding: back home, another view, Settings, and back shows the list as it was. A titled row
    /// is written on the way out (the Mac's "anything else: writes it, then does that").
    func testAddEndsOnLeaving() {
        app.launch()
        // From home: the + adds in the default list (the Inbox).
        let inbox = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch
        add("the + from home")
        back()
        assertOpen(5, in: "Inbox")   // nothing written
        inbox.tap()
        assertNotAdding("back to the Inbox")
        // Into a list, out to Today and Settings, and back.
        back()
        app.buttons["School"].firstMatch.tap()
        add()
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch.tap()
        assertNotAdding("in Today")
        back()
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        app.buttons["School"].firstMatch.tap()
        assertNotAdding("back to School")
        // Typed, then left: written, and the list shows normally.
        add()
        app.typeText("Water the plants")
        back()
        assertOpen(12)
        app.buttons["School"].firstMatch.tap()
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
        app.buttons["School"].firstMatch.tap()
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
        shot("flow-add-ipad-sidebar")
        // Not adding, the sidebar goes where it goes.
        today.tap()
        XCTAssertTrue(app.descendants(matching: .any)["listHeader"].firstMatch.label.hasPrefix("Today"), "Today opens")
    }

    /// The app going to the background ends adding: back in front, the list shows normally (a title was written).
    func testAddEndsInBackground() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
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
        assertOpen(12)
    }

    func testScrollFold() {
        app.launch()
        app.buttons["PHYS 122"].firstMatch.tap()
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
        menuOpen {
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

    // MARK: Long names and titles fade out on rows, as on the Mac

    /// No apostrophe: XCTest splits launch arguments as a shell would, and one swallowed the arguments after it.
    static let longTitle = "Email the TA about the midterm regrade for question 4(b) before the Thursday tutorial"

    /// How strongly a text's end is drawn, against its strongest ink, on a screenshot of `element`: near 0 when the
    /// text fades out there, near 1 when it ends in a letter or an ellipsis. Its end is its last column with any ink
    /// (8% of the strongest, against the commonest colour, the background), and its last 3pt before that are read.
    /// `from` and `upTo` (points) leave out what comes before the text (a row's tile) and after it (a row's count) at
    /// the left and right.
    private func endInk(_ element: XCUIElement, from: CGFloat = 0, upTo: CGFloat = 0) -> Double {
        guard let cg = element.screenshot().image.cgImage else { XCTFail("no screenshot"); return -1 }
        let w = cg.width, h = cg.height, scale = CGFloat(w) / element.frame.width
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // The text's line: the middle 20pt (clear of a capsule's edges at the top and bottom).
        let y0 = max(0, h / 2 - Int(10 * scale)), y1 = min(h, h / 2 + Int(10 * scale))
        var tally: [Int: Int] = [:]
        for y in y0..<y1 { for x in 0..<w { let i = (y * w + x) * 4
            tally[Int(px[i] >> 3) << 10 | Int(px[i + 1] >> 3) << 5 | Int(px[i + 2] >> 3), default: 0] += 1 } }
        let bg = tally.max { $0.value < $1.value }!.key
        let b = [Double((bg >> 10) & 31) * 8 + 4, Double((bg >> 5) & 31) * 8 + 4, Double(bg & 31) * 8 + 4]
        let ink: [Double] = (0..<w).map { x in
            (y0..<y1).map { y -> Double in let i = (y * w + x) * 4
                return (0..<3).map { abs(Double(px[i + $0]) - b[$0]) }.max()! / 255 }.max() ?? 0
        }
        var last = w - 1 - Int(upTo * scale)
        let first = Int(from * scale)
        guard last > first else { XCTFail("no text"); return -1 }
        let peak = ink[first...last].max() ?? 0
        guard peak > 0.2 else { XCTFail("no text drawn: \(peak)"); return -1 }
        while last > first && ink[last] <= peak * 0.08 { last -= 1 }
        return ink[max(first, last - Int(3 * scale))...last].max()! / peak
    }

    private func assertFades(_ e: XCUIElement, _ what: String, from: CGFloat = 0, upTo: CGFloat = 0,
                             file: StaticString = #filePath, line: UInt = #line) {
        let v = endInk(e, from: from, upTo: upTo)
        print("end ink, \(what): \(v)")
        XCTAssertLessThan(v, 0.4, "\(what) fades out at its end (\(v))", file: file, line: line)
    }

    private func assertDoesntFade(_ e: XCUIElement, _ what: String, from: CGFloat = 0, upTo: CGFloat = 0,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let v = endInk(e, from: from, upTo: upTo)
        print("end ink, \(what): \(v)")
        XCTAssertGreaterThan(v, 0.6, "\(what) ends in its letters, with no fade (\(v))", file: file, line: line)
    }

    /// Cut off, a task's title and a list's name fade out at their ends instead of an ellipsis (the user, 2026-11-02;
    /// INTERACTIONS-v2 §24, the Mac's rows). Beside a long list name a long title keeps 156pt (the Mac's 120), and the
    /// name gets what's left, up to 94pt (the Mac's 72) and never under 42 (the Mac's 32). Home's
    /// rows, and iPad's sidebar, its current row too, fade a long name (§12). What fits shows no fade. Dark and Light.
    func testLongNamesFade() {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        if pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if pad { XCUIDevice.shared.orientation = .portrait } }
        for look in ["dark", "light"] {
            app = XCUIApplication()
            app.launchArguments = ["-sampleData", "YES", "-appearance", look, "-style", "classic", "-screen", "upcoming",
                                   "-remoteTask", "s4", "-remoteTitle", Self.longTitle,
                                   "-remoteList", "school-9", "-remoteName", Self.longName]
            app.launch()
            let groceries = app.staticTexts["Get groceries for the week"].firstMatch
            XCTAssertTrue(groceries.waitForExistence(timeout: 10), "Upcoming")
            remoteEdit()
            let title = app.staticTexts[Self.longTitle].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 3), "the long title, whole for VoiceOver")
            sleep(1)
            shot("fade-upcoming-\(look)")
            assertFades(title, "\(look): a long title")
            XCTAssertGreaterThanOrEqual(title.frame.width, 155.5, "\(look): the title keeps 156pt")
            if let name = level(app.staticTexts, Self.longName, with: title) {
                assertFades(name, "\(look): a long list name after a long title")
                // On this row the title's 156pt leaves the name less than its 94: the title keeps exactly 156.
                XCTAssertEqual(title.frame.width, 156, accuracy: 1, "\(look): the title gives way to 156pt, no less")
                XCTAssertGreaterThanOrEqual(name.frame.width, 41.5, "\(look): the name, 42pt or more")
                XCTAssertLessThanOrEqual(name.frame.width, 94.5, "\(look): the name, 94pt at most")
                XCTAssertLessThanOrEqual(title.frame.maxX + 8, name.frame.minX + 0.5, "\(look): 8 apart")
            } else {
                XCTFail("\(look): the long title's list name")
            }
            assertDoesntFade(groceries, "\(look): a title that fits")
            if let errands = level(app.staticTexts, "Errands", with: groceries) {
                assertDoesntFade(errands, "\(look): a list name that fits")
            } else {
                XCTFail("\(look): Errands, after its title")
            }
            // Home on the phone; iPad's sidebar is beside the list.
            if !pad { back() }
            let school = app.buttons[Self.longName].firstMatch
            XCTAssertTrue(school.waitForExistence(timeout: 3), "\(look): the long name's row, whole for VoiceOver")
            shot("fade-home-\(look)")
            // The row's frame takes in the list's 10pt insets. Its name starts after the tile (10 + 10 + 26 + 12), and,
            // with no count after it (the user, 2026-10-31), ends 13 short of the row's edge: read from 52 to 10 short
            // of the frame's edge.
            assertFades(school, "\(look): a long name on Home", from: 52, upTo: 10)
            assertDoesntFade(app.buttons["PHYS 122"].firstMatch, "\(look): a name that fits", from: 52, upTo: 10)
            if pad {
                school.tap()
                sleep(1)
                shot("fade-sidebar-current-\(look)")
                assertFades(school, "\(look): the current row's long name, over its capsule", from: 52, upTo: 10)
            }
            app.terminate()
        }
    }

    /// The sample's list names, as a row in a view that mixes lists shows them after the title.
    private static let listNames = ["Inbox", "School", "PHYS 122", "Tasks app", "Home", "Errands"]

    /// What each row's list name shows in Upcoming, at one text size: whole, cut and fading (then never under 42pt),
    /// or gone (out of sight). The library books' row (Inbox, due tomorrow) gets a long title.
    private func listNamesAfterTitles(_ size: String, file: StaticString = #filePath, line: UInt = #line)
        -> (whole: [String], fading: [String], gone: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "upcoming",
                               "-remoteTask", "i3", "-remoteTitle", Self.longTitle,
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        XCTAssertTrue(app.staticTexts["Tomorrow"].firstMatch.waitForExistence(timeout: 10), "Upcoming", file: file, line: line)
        remoteEdit()
        sleep(1)
        shot("list-names-\(size)")
        var out: ([String], [String], [String]) = ([], [], [])
        let names = app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.listNames)).allElementsBoundByIndex
        for n in names where n.frame.minY > 0 && n.frame.maxY < app.frame.maxY - 120 {
            let w = n.frame.width, what = "\(size): \(n.label) at y \(Int(n.frame.minY)), \(w)pt"
            print("list name, \(what), x \(Int(n.frame.minX))")
            if n.frame.maxX <= 0 { out.2.append(n.label); continue }
            if endInk(n) > 0.6 {
                out.0.append(n.label)
            } else {
                out.1.append(n.label)
                XCTAssertGreaterThanOrEqual(w, 41.5, "\(what): cut, it keeps 42pt", file: file, line: line)
            }
        }
        app.terminate()
        return out
    }

    /// A list's name after a task's title (the user, 2026-11-02; INTERACTIONS-v2 §24) shows whole, or cut to no less
    /// than 42pt (the Mac's 32) and fading, or not at all: never a sliver or a lone "…". PHYS 122 after a title that's
    /// cut shows whole. At the largest text size School, after "Submit MSE 333 A2" and its deadline, goes.
    func testListNameAfterATitleIsWholeFadingOrGone() {
        let normal = listNamesAfterTitles("UICTContentSizeCategoryL")
        XCTAssertTrue(normal.whole.contains("PHYS 122"), "PHYS 122 after a cut title, whole")
        XCTAssertTrue(normal.whole.contains("Inbox"), "Inbox after the long title, whole")
        XCTAssertEqual(normal.gone, [], "at the default size every name shows")
        let largest = listNamesAfterTitles("UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(largest.gone.contains("School"), "at the largest size, School after Submit MSE 333 A2 goes")
        XCTAssertFalse(largest.fading.isEmpty, "and other names are cut, fading")
    }

    // MARK: Drag to reorder (§14, §23)

    /// Long-press, then drag `from` onto the middle of `onto`, as a finger does. The move starts at 0.5 s: by 0.8 s
    /// the row's menu is fully open, and XCTest's drag then stays inside the menu.
    private func drag(_ from: XCUIElement, onto: XCUIElement) {
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: onto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 1)
        sleep(2)
    }

    private func y(_ e: XCUIElement) -> CGFloat { e.frame.midY }

    /// A task dragged over a heading joins that section, right where it's dropped: one op, list and order.
    func testDragATaskIntoAnotherSection() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        XCTAssertTrue(redo.waitForExistence(timeout: 10))
        sleep(1)
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch, exam = heading("Exam prep")
        drag(redo, onto: bench)
        XCTAssertGreaterThan(y(redo), y(bench), "under the row it was dropped on, in Labs")
        XCTAssertLessThan(y(redo), y(exam), "and still above Exam prep")
        XCTAssertGreaterThan(y(redo), y(heading("Labs")), "under Labs")
    }

    /// A heading takes its section: dropped inside Lectures, Labs and its three tasks land before Lectures, the
    /// nearest place a section can go.
    func testDragAHeadingMovesItsSection() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let labs = heading("Labs"), lectures = heading("Lectures")
        XCTAssertTrue(labs.waitForExistence(timeout: 10))
        sleep(1)
        drag(labs, onto: app.staticTexts["Read chapter 15 · oscillations"].firstMatch)
        XCTAssertLessThan(y(labs), y(lectures), "Labs before Lectures")
        for title in ["Lab 3 report · pendulum", "Lab 4 pre-lab · RC circuits", "Book a make-up lab bench"] {
            let t = app.staticTexts[title].firstMatch
            XCTAssertTrue(y(labs) < y(t) && y(t) < y(lectures), "\(title) came along, between Labs and Lectures")
        }
        XCTAssertLessThan(y(app.staticTexts["Buy safety glasses for the lab"].firstMatch), y(labs),
                          "never above the task with no heading")
    }

    /// In Today a task moves within its list's group; dropped in another group, nothing changes.
    func testDragInTodayStaysInItsGroup() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let reply = app.staticTexts["Reply to the landlord about the lease"].firstMatch
        let dentist = app.staticTexts["Call the dentist about a cleaning"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        sleep(1)
        let before = y(reply)
        drag(reply, onto: app.staticTexts["Email TA about midterm regrade"].firstMatch)
        XCTAssertEqual(y(reply), before, accuracy: 1, "dropped in School's group: refused, back where it was")
        XCTAssertLessThan(y(reply), y(dentist))
        drag(reply, onto: dentist)
        XCTAssertGreaterThan(y(reply), y(dentist), "within Inbox's group: under the dentist")
        XCTAssertLessThan(y(reply), y(app.staticTexts["School"].firstMatch), "still in Inbox's group")
    }

    /// Lists reorder on Home; Today and the views stay put.
    func testDragAListOnHome() {
        app.launch()
        let phys = app.buttons["PHYS 122"].firstMatch, school = app.buttons["School"].firstMatch
        XCTAssertTrue(phys.waitForExistence(timeout: 10))
        sleep(1)
        drag(phys, onto: school)
        XCTAssertLessThan(y(phys), y(school), "PHYS 122 above School")
        XCTAssertGreaterThan(y(phys), y(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch), "and under Inbox")
    }

    // MARK: The tapped row (§5; Mail and Settings)

    /// Screenshots taken on another thread while `gesture` runs (XCTest blocks for the length of a gesture), to see
    /// what lasts only a moment: a quick tap's press, a fade.
    private func filming(_ count: Int, _ gesture: () -> Void) -> [CGImage] {
        final class Film: @unchecked Sendable {
            let lock = NSLock()
            var frames: [CGImage] = []
            func add(_ f: CGImage) { lock.lock(); frames.append(f); lock.unlock() }
        }
        let film = Film()
        let thread = Thread { for _ in 0..<count { if let cg = XCUIScreen.main.screenshot().image.cgImage { film.add(cg) } } }
        thread.start()
        usleep(150_000)
        gesture()
        while !thread.isFinished { usleep(20_000) }
        return film.frames
    }

    /// The brightness (0–255) at a point, in the screen's points.
    private func luma(_ cg: CGImage, _ p: CGPoint) -> Int {
        let scale = CGFloat(cg.width) / app.frame.width
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(cg, in: CGRect(x: -Int(p.x * scale), y: -(cg.height - Int(p.y * scale) - 1), width: cg.width, height: cg.height))
        return (Int(px[0]) + Int(px[1]) + Int(px[2])) / 3
    }

    /// How much brighter a row's fill is than the screen beside it (x 4, outside the row's 10pt inset), at `y`, in
    /// the row's empty space at `x`: about 0 at rest, about 27 pressed or selected (Dark).
    private func lift(_ cg: CGImage, x: CGFloat, y: CGFloat) -> Int { luma(cg, CGPoint(x: x, y: y)) - luma(cg, CGPoint(x: 4, y: y)) }

    /// A quick tap shows the press the moment it lands (the list's touch delay is off): caught on Home, where a tap
    /// doesn't select anything that could pass for it. With the delay, a 0.13 s tap never shows it.
    func testAQuickTapShowsThePress() {
        app.launch()
        let row = app.buttons["Errands"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(2)
        let f = row.frame
        var seen = false
        for _ in 0..<3 where !seen {
            let frames = filming(14) { row.press(forDuration: 0.13) }
            let lifts = frames.map { lift($0, x: f.minX + f.width * 0.6, y: f.midY) }
            print("press, lifts \(lifts)")
            seen = lifts.contains { $0 > 12 }
            back()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            sleep(1)
        }
        XCTAssertTrue(seen, "a 0.13 s tap shows the press fill")
    }

    /// A drag that starts on a row scrolls the list and opens nothing.
    func testAScrollThatStartsOnARowOpensNothing() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let row = app.staticTexts["Return the ECE 358 lab kit"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        let y0 = row.frame.midY
        // A finger's drag, 250pt up from the row's middle. (`swipeUp()` on the row's text stays inside its 22pt frame:
        // too short to scroll, it's a tap, with the touch delay or without.)
        let c = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        c.press(forDuration: 0.02, thenDragTo: c.withOffset(CGVector(dx: 0, dy: -250)), withVelocity: .default, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertLessThan(row.frame.midY, y0 - 40, "the list scrolled")
        XCTAssertFalse(app.descendants(matching: .any)["detailList"].exists, "no details opened")
    }

    /// Swipe actions still swipe out, both ways, with the touch delay off.
    func testSwipeActionsStillWork() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let row = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        let mid = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: -130, dy: 0)))
        sleep(1)
        XCTAssertTrue(app.buttons["Delete"].exists && app.buttons["When"].exists, "swiped left: Delete and When")
        mid.withOffset(CGVector(dx: 60, dy: 0)).press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 200, dy: 0)))
        sleep(1)
        let other = app.staticTexts["Book a make-up lab bench"].firstMatch
        let start = other.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 130, dy: 0)))
        sleep(1)
        let complete = app.buttons.matching(NSPredicate(format: "label == 'Complete'")).allElementsBoundByIndex
        XCTAssertTrue(complete.contains { $0.frame.width > 50 && abs($0.frame.midY - other.frame.midY) < 20 },
                      "swiped right: Complete")
        XCTAssertTrue(other.exists && row.exists, "nothing went")
    }

    /// While its details are open the tapped row keeps the selected fill; when they close it fades out (300 ms
    /// ease-out), so the fill is caught part-way, with the screen beside it already back to normal.
    func testTheTappedRowStaysSelectedThenFades() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let row = app.staticTexts["Buy safety glasses for the lab"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        let x = app.frame.maxX - 40, y = row.frame.midY
        let rest = XCUIScreen.main.screenshot().image.cgImage!
        let edge = luma(rest, CGPoint(x: 4, y: y))
        XCTAssertLessThan(abs(lift(rest, x: x, y: y)), 3, "no fill at rest")
        let details = app.descendants(matching: .any)["detailList"]
        var caught = false
        for _ in 0..<3 where !caught {
            row.tap()
            XCTAssertTrue(details.waitForExistence(timeout: 5))
            sleep(1)
            let open = XCUIScreen.main.screenshot().image.cgImage!
            XCTAssertGreaterThan(lift(open, x: x, y: y), 8, "selected while its details are open")
            // Closed by a tap above the sheet.
            let frames = filming(14) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
            XCTAssertFalse(details.exists, "the details closed")
            let seen = frames.map { (edge: luma($0, CGPoint(x: 4, y: y)), lift: lift($0, x: x, y: y)) }
            print("fade, \(seen)")
            caught = seen.contains { abs($0.edge - edge) <= 2 && (4...22).contains($0.lift) }
            sleep(1)
            XCTAssertLessThan(abs(lift(XCUIScreen.main.screenshot().image.cgImage!, x: x, y: y)), 3, "gone once it's faded")
        }
        XCTAssertTrue(caught, "the fill fades out after the details close")
    }

    // MARK: Headings (§23)

    /// A heading's name: a button that renames it.
    private func heading(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "heading").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func headingCount() -> Int { app.descendants(matching: .any).matching(identifier: "heading").count }

    private func openPhys() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10), "PHYS 122")
        sleep(1)
    }

    /// New Heading in the list's menu: at the bottom, named in place. Return writes it; an empty one leaves nothing.
    func testNewHeadingFromTheListMenu() {
        openPhys()
        let before = headingCount()
        app.buttons["List actions"].tap()
        app.buttons["New Heading"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 3), "the new heading's field")
        app.typeText("\n")
        sleep(1)
        XCTAssertFalse(draft.exists, "an empty one ends")
        XCTAssertEqual(headingCount(), before, "and leaves nothing")
        app.buttons["List actions"].tap()
        app.buttons["New Heading"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        app.typeText("Problem sets\n")
        sleep(1)
        let new = heading("Problem sets")
        XCTAssertTrue(new.waitForExistence(timeout: 3), "written")
        XCTAssertEqual(headingCount(), before + 1)
        XCTAssertGreaterThan(y(new), y(app.staticTexts["Ask about problem 7 at office hours"].firstMatch), "at the bottom")
    }

    /// New Heading Above in a task's menu: above it, and it becomes the section's first task. A tap elsewhere writes
    /// it, and only ends adding (the row tapped doesn't open).
    func testNewHeadingAboveATask() {
        openPhys()
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
        menuOpen {
            bench.press(forDuration: 1.0)
            app.buttons["New Heading Above"].tap()
        }
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        app.typeText("Make-ups")
        app.staticTexts["Read chapter 15 · oscillations"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["detailList"].exists, "the tap only ended adding")
        let new = heading("Make-ups")
        XCTAssertTrue(new.waitForExistence(timeout: 3), "written by the tap")
        XCTAssertGreaterThan(y(new), y(app.staticTexts["Lab 4 pre-lab · RC circuits"].firstMatch), "after the task above")
        XCTAssertLessThan(y(new), y(bench), "above its task")
    }

    /// A tap on the name renames it in place; an empty name keeps the old one.
    func testRenameAHeading() {
        openPhys()
        let field = app.textFields["headingName"]
        // A tap on its name does nothing: Rename is in its menu only.
        heading("Labs").tap()
        XCTAssertFalse(field.waitForExistence(timeout: 1.5), "a tap doesn't rename")
        func rename() {
            menuOpen {
                heading("Labs").press(forDuration: 1.0)
                app.buttons["Rename"].tap()
            }
        }
        rename()
        XCTAssertTrue(field.waitForExistence(timeout: 3), "renaming in place")
        XCTAssertEqual(field.value as? String, "Labs")
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "\n")
        sleep(1)
        XCTAssertTrue(heading("Labs").exists, "an empty name keeps the old one")
        rename()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let long = "Labs and tutorials for the whole winter term"
        app.typeText(String(long.dropFirst(4)) + "\n")
        sleep(1)
        XCTAssertTrue(heading(long).waitForExistence(timeout: 3), "renamed")
        // Its menu's New Task item is one line, cut, as the Mac's menus cut a name.
        menuOpen {
            heading(long).press(forDuration: 1.0)
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New Task in “La'")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            XCTAssertTrue((item.label as String).hasSuffix("…”"), "cut: \(item.label)")
            XCTAssertEqual(item.frame.height, app.buttons["Rename"].frame.height, accuracy: 1, "one line")
        }
    }

    /// Add Notes opens the notes editor under the heading; Done writes them, and they show under it.
    func testAHeadingsNotes() {
        openPhys()
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            app.buttons["Add Notes"].tap()
        }
        let editor = app.textViews["headingNotes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "the notes editor, under it")
        app.typeText("Bring the goggles")
        app.buttons["Done"].tap()
        sleep(1)
        let notes = app.staticTexts["Bring the goggles"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 3), "they show under it")
        XCTAssertGreaterThan(y(notes), y(heading("Labs")))
        XCTAssertLessThan(y(notes), y(app.staticTexts["Lab 3 report · pendulum"].firstMatch))
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            XCTAssertTrue(app.buttons["Edit Notes"].waitForExistence(timeout: 3), "now Edit Notes")
            app.buttons["Edit Notes"].tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
    }

    // MARK: Parity batch 1, commit 4 (the Mac's rules: IOS-MAC-PARITY.md)

    /// A list's notes (IX:1540–1543): Add Notes in its menu opens the notes editor under the title; Done writes them;
    /// then it's Edit Notes, and a tap on them edits them too.
    func testAListsNotes() {
        app.launchArguments += ["-screen", "list:home"]
        app.launch()
        XCTAssertTrue(app.buttons["List actions"].waitForExistence(timeout: 10), "Home")
        app.buttons["List actions"].tap()
        app.buttons["Add Notes"].tap()
        let editor = app.textViews["listNotes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "the notes editor, under the title")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "with the caret")
        app.typeText("Measure the hallway")
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertFalse(editor.exists, "Done ends them")
        // The header reads as one element: its title, then its notes.
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        XCTAssertEqual(header.label, "Home, Measure the hallway", "they show under the title")
        app.buttons["List actions"].tap()
        XCTAssertTrue(app.buttons["Edit Notes"].waitForExistence(timeout: 3), "now Edit Notes")
        app.buttons["Edit Notes"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Measure the hallway")
        app.buttons["Done"].tap()
        sleep(1)
        // A tap on them (the header's last line) edits them.
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "a tap on them edits them")
        app.typeText(" first")
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertEqual(header.label, "Home, Measure the hallway first", "written")
    }

    /// The calendar's weeks start on the locale's first weekday (the Mac's DatePopover.swift:327): Monday in the UK,
    /// Sunday in the US.
    func testTheCalendarStartsOnTheLocalesFirstDay() {
        for (locale, monday) in [("en_GB", true), ("en_US", false)] {
            app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-AppleLocale", locale]
            app.launch()
            app.buttons["School"].firstMatch.tap()
            sleep(1)
            app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
            sleep(1)
            app.buttons["When"].firstMatch.tap()
            let m = app.staticTexts["M"].firstMatch
            XCTAssertTrue(m.waitForExistence(timeout: 3), "\(locale): the weekday letters")
            let s = app.staticTexts.matching(identifier: "S").allElementsBoundByIndex.filter { abs($0.frame.midY - m.frame.midY) < 2 }
            XCTAssertEqual(s.count, 2, "\(locale): two S's in the row")
            XCTAssertEqual(s.allSatisfy { $0.frame.minX > m.frame.minX }, monday, "\(locale): Monday first is \(monday)")
            app.terminate()
        }
    }

    /// A title is one line (IX:599): Return ends the edit, and a pasted line break becomes a space.
    func testATitleIsOneLine() {
        app.launch()
        app.buttons["School"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        sleep(1)
        editTitle("Submit MSE 333 A2")
        app.typeText(" v2\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "Return ends the edit")
        let field = titleField("Submit MSE 333 A2 v2")
        XCTAssertTrue(field.waitForExistence(timeout: 3), "written, without a line break")
        UIPasteboard.general.string = "Line one\nLine two"
        editTitle("Submit MSE 333 A2 v2")
        field.tap()
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 3), "the edit menu's Paste")
        paste.tap()
        sleep(1)
        // (iOS's smart paste adds the space before it.)
        XCTAssertTrue(titleField("Submit MSE 333 A2 v2 Line one Line two").waitForExistence(timeout: 3),
                      "the pasted line break is a space")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2 v2 Line one Line two"].waitForExistence(timeout: 3))
    }

    private func titleField(_ text: String) -> XCUIElement {
        let view = app.textViews.matching(NSPredicate(format: "value == %@", text)).firstMatch
        return view.exists ? view : app.textFields.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }

    /// Notes hold 20,000 characters (the Mac's NotesView.swift:703): from 18,000 the footer counts them, and typing past
    /// 20,000 stops there with a notice.
    func testNotesStopAt20000() {
        let words = String(repeating: "word ", count: 3_998)   // 19,990 characters
        launch(remote: "s8", notes: words)
        app.buttons["School"].firstMatch.tap()
        sleep(1)
        remoteEdit()
        app.staticTexts["Print ECE 358 formula sheet"].firstMatch.tap()
        sleep(1)
        func footer(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
        XCTAssertTrue(footer("· 19,990 / 20,000").waitForExistence(timeout: 5), "the counter from 18,000")
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'word word'")).firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the notes have the caret")
        app.typeText("abcdefghijkl")
        XCTAssertTrue(app.staticTexts["Notes hold up to 20,000 characters"].waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(footer("· 20,000 / 20,000").waitForExistence(timeout: 3), "cut at 20,000")
    }

    /// A heading with notes folds as one without does (§23): its notes fold up into it with its tasks, and the next
    /// heading closes up on the same curve: filmed, it only ever moves up as it folds and down as it unfolds, and never
    /// past where it ends.
    func testFoldingAHeadingWithNotesDoesntJump() {
        openPhys()
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            app.buttons["Add Notes"].tap()
        }
        XCTAssertTrue(app.textViews["headingNotes"].waitForExistence(timeout: 3))
        app.typeText("Goggles\nLab coat\nThe manual")
        app.buttons["Done"].tap()
        sleep(2)
        assertFoldsWithoutJumps()
    }

    /// The same, with notes that came from another device (two lines, wrapped).
    func testFoldingAHeadingWithSyncedNotesDoesntJump() {
        app.launchArguments += ["-screen", "list:phys"]
        launch(remote: "h-lab", notes: "Goggles, a lab coat and the lab manual, every session; pre-labs are due at the start of the lab.")
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 10), "PHYS 122")
        sleep(1)
        remoteEdit()
        sleep(1)
        assertFoldsWithoutJumps()
    }

    /// Labs has notes starting "Goggles": its fold and unfold, filmed, move Exam prep one way only and never past its end.
    private func assertFoldsWithoutJumps() {
        let notes = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Goggles'")).firstMatch
        XCTAssertTrue(notes.exists, "the notes, under the heading")
        let labs = heading("Labs").frame, exam = heading("Exam prep").frame, notesAt = notes.frame.minY - labs.minY
        XCTAssertLessThan(labs.maxY, y(notes))
        // The rules (a heading's hairline: the same shade straight across) from Labs' down, in points: the gap from
        // Labs' to the last, Exam prep's. (The list may also scroll back to its top as it gets shorter, moving both.)
        let width = app.frame.width, height = app.frame.height
        func gap(_ cg: CGImage) -> CGFloat? {
            let w = cg.width, h = cg.height, scale = CGFloat(w) / width
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            func luma(_ x: Int, _ row: Int) -> Int { let i = (row * w + x) * 4; return (Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])) / 3 }
            let xs = [0.2, 0.35, 0.5, 0.65].map { Int(width * $0 * scale) }
            var rules: [Int] = []
            // Down to 40 above the bottom: the + is right of the columns looked at, and the iPhone 18 Pro has Exam
            // prep's rule below the old 120 (it failed there on List too).
            for row in Int(labs.minY * scale)..<Int((height - 40) * scale) {
                let l = xs.map { luma($0, row) }, bg = luma(Int(4 * scale), row)
                if l.allSatisfy({ abs($0 - bg) >= 6 }), l.max()! - l.min()! <= 3, rules.last.map({ row - $0 > 3 }) ?? true {
                    rules.append(row)
                }
            }
            guard rules.count >= 2 else { return nil }
            return CGFloat(rules.last! - rules.first!) / scale
        }
        func track(_ label: String, folding: Bool) {
            let before = gap(XCUIScreen.main.screenshot().image.cgImage!)
            // A mark to line a recording up with (Tools/film/film.sh, events.py).
            print(String(format: "FILM %@ %.3f", label.replacingOccurrences(of: " ", with: "_"), Date().timeIntervalSince1970))
            let frames = filming(10) { app.buttons[label].tap() }
            sleep(1)
            let after = gap(XCUIScreen.main.screenshot().image.cgImage!)
            let gaps = frames.map(gap)
            print("fold \(label):", before ?? -1, gaps.map { $0 ?? -1 }, after ?? -1)
            guard let before, let after else { return XCTFail("\(label): Labs' and Exam prep's rules") }
            XCTAssertEqual(folding ? before > after + 100 : before + 100 < after, true, "\(label): Exam prep moves")
            var last = before
            for g in gaps {
                guard let g else { XCTFail("\(label): a frame without both rules: \(gaps)"); continue }
                XCTAssertTrue(folding ? g <= last + 1 : g >= last - 1, "\(label): one way only: \(gaps)")
                XCTAssertTrue(folding ? g >= after - 1 : g <= after + 1, "\(label): never past the end: \(gaps)")
                last = g
            }
        }
        track("Collapse Labs", folding: true)
        XCTAssertFalse(notes.exists, "the notes fold away")
        track("Expand Labs", folding: false)
        XCTAssertTrue(notes.waitForExistence(timeout: 3), "and back")
        XCTAssertEqual(heading("Exam prep").frame.minY - heading("Labs").frame.minY, exam.minY - labs.minY, accuracy: 1,
                       "where it was, under Labs")
        XCTAssertEqual(notes.frame.minY - heading("Labs").frame.minY, notesAt, accuracy: 1, "the notes back under it")
    }

    /// The chevron folds the section into the heading, with its open tasks' count after the name, and back.
    func testCollapseAndExpandAHeading() {
        openPhys()
        let lab3 = app.staticTexts["Lab 3 report · pendulum"].firstMatch
        XCTAssertTrue(lab3.exists)
        app.buttons["Collapse Labs"].tap()
        sleep(1)
        XCTAssertFalse(lab3.exists, "folded")
        XCTAssertEqual(heading("Labs").value as? String, "Collapsed, 3 open")
        XCTAssertTrue(app.staticTexts["Make the midterm formula sheet"].exists, "the next section stays")
        app.buttons["Expand Labs"].tap()
        sleep(1)
        XCTAssertTrue(lab3.exists, "back")
        XCTAssertEqual(heading("Labs").value as? String ?? "", "")
    }

    /// New Task in a collapsed heading expands it and adds at the end of its section.
    func testNewTaskInACollapsedHeading() {
        openPhys()
        app.buttons["Collapse Labs"].tap()
        sleep(1)
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            app.buttons["New Task in “Labs”"].tap()
        }
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        app.typeText("Return the multimeter\n")
        sleep(1)
        app.buttons["Cancel"].tap()
        sleep(1)
        let new = app.staticTexts["Return the multimeter"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 3), "expanded, and written")
        XCTAssertGreaterThan(y(new), y(app.staticTexts["Book a make-up lab bench"].firstMatch), "at the end of Labs")
        XCTAssertLessThan(y(new), y(heading("Exam prep")))
    }

    /// A task dropped right under a collapsed heading joins the end of its section, stays folded, and the count goes
    /// up (the Mac's rule).
    func testDropUnderACollapsedHeading() {
        openPhys()
        app.buttons["Collapse Labs"].tap()
        sleep(1)
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        drag(redo, onto: heading("Labs"))
        XCTAssertFalse(redo.exists, "folded into Labs")
        XCTAssertEqual(heading("Labs").value as? String, "Collapsed, 4 open")
        app.buttons["Expand Labs"].tap()
        sleep(1)
        XCTAssertGreaterThan(y(redo), y(app.staticTexts["Book a make-up lab bench"].firstMatch), "at the end of Labs")
        XCTAssertLessThan(y(redo), y(heading("Exam prep")))
    }

    /// Delete Heading takes the heading only: its tasks stay, under the heading above. The notice's Undo brings it back.
    func testDeleteAHeading() {
        openPhys()
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            app.buttons["Delete Heading"].tap()
        }
        XCTAssertTrue(app.staticTexts["Deleted heading “Labs”"].waitForExistence(timeout: 3), "the notice")
        XCTAssertFalse(heading("Labs").exists)
        let lab3 = app.staticTexts["Lab 3 report · pendulum"].firstMatch
        XCTAssertTrue(lab3.exists, "its tasks stay")
        XCTAssertGreaterThan(y(lab3), y(heading("Lectures")), "under the heading above")
        app.buttons["Undo"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(heading("Labs").waitForExistence(timeout: 3), "back")
        XCTAssertLessThan(y(heading("Labs")), y(lab3))
    }

    // MARK: Parity batch 1: the Mac's rules (docs/IOS-MAC-PARITY.md)

    private func notice(beginningWith text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// Move to, out of the list on screen: "Moved to Errands", with Undo (the Mac's `move`).
    func testMoveOutOfAListSaysWhere() {
        app.launchArguments += ["-screen", "list:inbox"]
        app.launch()
        let row = app.staticTexts["Back up the laptop"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Inbox")
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Move to"].firstMatch.tap()
            app.buttons["Errands"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["Moved to Errands"].waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "gone from the Inbox")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "back")
    }

    /// A date that takes a task out of Today says where it went, with Undo; one that keeps it there says nothing.
    func testADateThatLeavesTodaySaysWhere() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let row = app.staticTexts["Reply to the landlord about the lease"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Today")
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Today"].firstMatch.tap()
        }
        sleep(1)
        XCTAssertFalse(app.buttons["Undo"].exists, "still in Today: no notice")
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Tomorrow"].firstMatch.tap()
        }
        XCTAssertTrue(notice(beginningWith: "Scheduled for ").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "gone from Today")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "back")
    }

    /// A task in Trash is put back, a list is restored (the Mac's `TrashVerb`): "Put back “…” in Home". Trash's
    /// header and a deleted list's count are the Mac's. (One deleted
    /// days ago: the sample's deletions today are stamped 11:00, so before then a put back would be older and lose.)
    func testPutBackSaysWhere() {
        app.launchArguments += ["-screen", "trash"]
        app.launch()
        let row = app.staticTexts["Buy a second lamp"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Trash")
        // The Mac's §28: no line under the title; a deleted list counts its open tasks.
        XCTAssertEqual(app.staticTexts["listHeader"].label, "Trash")
        XCTAssertTrue(app.buttons["Winter 2026, deleted list, 1 task"].exists, "a deleted list's open tasks")
        row.swipeRight()
        let button = app.buttons["Put Back"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "the swipe says Put Back")
        button.tap()
        XCTAssertTrue(app.staticTexts["Put back “Buy a second lamp” in Home"].waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "out of Trash")
    }

    // MARK: Trash: Put back in, and a deleted list opened (batch 2 §4)

    /// A task deleted on its own from a live list: its menu has Put Back and Put Back in ▸, whose lists are the live
    /// ones with its own checked. Put back in another goes to its bottom: "Put back “…” in Errands", with Undo.
    func testPutBackInFromTheMenu() {
        app.launchArguments += ["-screen", "trash", "-hold", "YES"]
        app.launch()
        let row = app.staticTexts["Buy a second lamp"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Trash")
        menuOpen {
            row.press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Put Back"].waitForExistence(timeout: 3), "Put Back")
            let into = app.buttons["Put Back in"].firstMatch
            XCTAssertTrue(into.exists, "Put Back in")
            into.tap()
            XCTAssertTrue(app.buttons["Errands"].waitForExistence(timeout: 3), "the live lists")
            XCTAssertTrue(app.buttons["Home"].exists, "its own list")
            XCTAssertFalse(app.buttons["Apartment move"].exists, "no other deleted list")
            app.buttons["Errands"].tap()
        }
        XCTAssertTrue(notice("Put back “Buy a second lamp” in Errands").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "out of Trash")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "back in Trash")
    }

    /// A task whose list is in Trash has nowhere to go back to: Put Back in ▸ only, with its own list there but
    /// disabled ("In Trash").
    func testATaskWhoseListIsInTrashHasOnlyPutBackIn() {
        app.launchArguments += ["-screen", "trash", "-expand", "move", "-hold", "YES"]
        app.launch()
        let row = app.staticTexts["Cancel the old internet plan"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "under its deleted list")
        menuOpen {
            row.press(forDuration: 1.2)
            let into = app.buttons["Put Back in"].firstMatch
            XCTAssertTrue(into.waitForExistence(timeout: 3), "Put Back in")
            XCTAssertFalse(app.buttons["Put Back"].exists, "no Put Back")
            into.tap()
            XCTAssertTrue(app.buttons["School"].waitForExistence(timeout: 3), "the live lists")
            let own = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apartment move'")).firstMatch
            XCTAssertTrue(own.exists, "its own list is there")
            XCTAssertFalse(own.isEnabled, "and disabled")
            app.buttons["School"].tap()
        }
        XCTAssertTrue(notice("Put back “Cancel the old internet plan” in School").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "out of Trash")
    }

    /// The sheet of a task whose list is in Trash: "School  In Trash", and the banner's Put Back in (a menu) and Restore
    /// List. Put back in, the sheet closes.
    func testTheSheetPutsBackIn() {
        app.launchArguments += ["-screen", "trash", "-expand", "move", "-hold", "YES"]
        app.launch()
        let row = app.staticTexts["Return the moving boxes"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "under its deleted list")
        row.tap()
        let words = app.staticTexts["Its list is in Trash. Put it in another list, or restore the list."]
        XCTAssertTrue(words.waitForExistence(timeout: 3), "the banner")
        XCTAssertTrue(app.staticTexts["In Trash"].exists, "the List row")
        XCTAssertTrue(app.buttons["Restore List"].exists, "Restore List")
        let into = app.buttons.matching(NSPredicate(format: "label == 'Put Back in'"))
        XCTAssertEqual(into.count, 2, "the bar's ↶ and the banner's")
        into.element(boundBy: 1).tap()
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3), "Put back in")
        home.tap()
        XCTAssertTrue(notice("Put back “Return the moving boxes” in Home").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(words.waitForNonExistence(timeout: 3), "the sheet closed")
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "out of Trash")
    }

    /// A tap on a deleted list's row opens it, read-only: the banner, "In Trash", deaf rows, no + and no "…". Restore
    /// makes it the live list in place, and back goes to Trash, where its row is gone.
    func testADeletedListOpensAndRestoresInPlace() {
        app.launchArguments += ["-screen", "trash", "-hold", "YES"]
        app.launch()
        let deleted = app.buttons["Apartment move, deleted list, 2 tasks"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 10), "Trash")
        deleted.tap()
        let banner = app.staticTexts["Read-only until you restore it."]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "the banner")
        XCTAssertTrue(app.staticTexts["listHeader"].label.contains("In Trash"), "In Trash after the title")
        XCTAssertTrue(app.buttons["Restore List"].exists, "the bar's ↶")
        XCTAssertFalse(app.buttons["List actions"].exists, "no …")
        XCTAssertFalse(app.buttons["New Task"].exists, "no +")
        let task = app.staticTexts["Cancel the old internet plan"].firstMatch
        XCTAssertTrue(task.exists, "its tasks")
        task.tap()
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 1.5), "a row takes no tap")
        app.buttons["Restore"].tap()
        XCTAssertTrue(notice("Restored Apartment move").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3), "the banner goes")
        XCTAssertTrue(app.buttons["List actions"].waitForExistence(timeout: 3), "the … is back")
        XCTAssertTrue(app.buttons["New Task"].exists, "the + is back")
        XCTAssertFalse(app.staticTexts["listHeader"].label.contains("In Trash"), "In Trash goes")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["listHeader"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["listHeader"].label, "Trash", "back to Trash")
        XCTAssertFalse(deleted.exists, "its row is gone")
    }

    /// A deleted list's row in Trash: its menu has Open and Restore List, and a swipe right says Restore.
    func testADeletedListsRowHasItsMenuAndSwipe() {
        app.launchArguments += ["-screen", "trash", "-hold", "YES"]
        app.launch()
        let deleted = app.buttons["Apartment move, deleted list, 2 tasks"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 10), "Trash")
        menuOpen {
            deleted.press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 3), "Open")
            XCTAssertTrue(app.buttons["Restore List"].exists, "Restore List")
            app.buttons["Open"].tap()
        }
        XCTAssertTrue(app.staticTexts["Read-only until you restore it."].waitForExistence(timeout: 3), "it opens")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(deleted.waitForExistence(timeout: 3), "back in Trash")
        sleep(1)
        deleted.swipeRight()
        let restore = app.buttons["Restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 3), "the swipe says Restore")
        restore.tap()
        XCTAssertTrue(notice("Restored Apartment move").waitForExistence(timeout: 3), "the notice")
        XCTAssertTrue(deleted.waitForNonExistence(timeout: 3), "out of Trash")
    }

    /// The chevron at a deleted list's right expands it in place: its tasks show under it, and Trash stays.
    func testTheChevronExpandsADeletedList() {
        app.launchArguments += ["-screen", "trash"]
        app.launch()
        let deleted = app.buttons["Apartment move, deleted list, 2 tasks"]
        XCTAssertTrue(deleted.waitForExistence(timeout: 10), "Trash")
        XCTAssertFalse(app.staticTexts["Cancel the old internet plan"].exists, "closed")
        deleted.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -23, dy: 0)).tap()
        XCTAssertTrue(app.staticTexts["Cancel the old internet plan"].waitForExistence(timeout: 3), "expanded")
        XCTAssertEqual(app.staticTexts["listHeader"].label, "Trash", "still Trash")
    }

    /// The checkbox names its task and reads the ring (the Mac's label): overdue, due today, planned for today.
    func testTheCheckboxNamesItsTask() {
        app.launchArguments += ["-screen", "list:school"]
        app.launch()
        XCTAssertTrue(app.buttons["Complete: ECE 358 lab report, overdue"].waitForExistence(timeout: 10), "overdue")
        XCTAssertTrue(app.buttons["Complete: Return the ECE 358 lab kit, due today"].exists, "due today")
        XCTAssertTrue(app.buttons["Complete: Pay the MSE 333 field trip fee, due today, planned for today"].exists,
                      "due and planned")
        XCTAssertTrue(app.buttons["Complete: Print ECE 358 formula sheet"].exists, "no cue")
    }

    /// Checked rows stay in place, struck at once, until 1.5 s pass with no further check: a second check restarts the
    /// wait, so both move together (IX:665–669).
    func testChecksSettleTogether() {
        app.launchArguments += ["-screen", "list:school"]
        app.launch()
        let a = app.buttons["Complete: Print ECE 358 formula sheet"]
        let b = app.buttons["Complete: Ask about co-op interview slots"]
        XCTAssertTrue(a.waitForExistence(timeout: 10), "School")
        a.tap()
        let tA = Date()
        b.tap()
        // Past the old 1.1 s, and within 1.5 s of the second check: the first is still in place.
        let wait = 1.25 - Date().timeIntervalSince(tA)
        if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
        XCTAssertTrue(app.buttons["Mark not done: Print ECE 358 formula sheet"].exists,
                      "the first check waits for the second (\(Date().timeIntervalSince(tA)) s)")
        XCTAssertTrue(app.buttons["Mark not done: Ask about co-op interview slots"].exists)
        XCTAssertTrue(app.buttons["Mark not done: Print ECE 358 formula sheet"].waitForNonExistence(timeout: 4), "settled")
        XCTAssertFalse(app.buttons["Mark not done: Ask about co-op interview slots"].exists, "together")
    }

    private func whenLabels() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'When '"))
    }

    /// Only the date that places a row is hidden (the Mac's rule): in Today a When on or before today. A task that's
    /// in Today by its deadline shows a later When.
    func testAWhenShowsUnlessItPlacesTheRow() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let row = app.staticTexts["Return the ECE 358 lab kit"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Today")
        XCTAssertEqual(whenLabels().count, 0, "Today's Whens place their rows")
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Tomorrow"].firstMatch.tap()
        }
        sleep(1)
        XCTAssertTrue(row.exists, "still in Today: due today")
        XCTAssertFalse(app.buttons["Undo"].exists, "so no notice")
        XCTAssertEqual(whenLabels().count, 1, "its When, tomorrow, shows")
    }

    /// Today's Completed group is open by default, and its rows show their list's name. (A task is checked here: the
    /// sample's completion today is stamped 15:00, so before then the group is empty.)
    func testTodaysCompletedIsOpenWithListNames() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let box = app.buttons["Complete: Reply to the landlord about the lease"]
        XCTAssertTrue(box.waitForExistence(timeout: 10), "Today")
        box.tap()
        sleep(3)
        app.swipeUp()
        app.swipeUp()
        let done = app.staticTexts["Reply to the landlord about the lease"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "in the Completed group, open by default")
        XCTAssertTrue(app.buttons["Hide completed tasks"].exists, "open")
        XCTAssertNotNil(level(app.staticTexts, "Inbox", with: done), "its list's name")
    }

    /// In a month group of Completed and Trash a row shows the day after its list ("School · Oct 22").
    func testMonthGroupsShowTheDay() {
        app.launchArguments += ["-screen", "completed"]
        app.launch()
        let done = app.staticTexts["Register for winter courses"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Completed")
        let name = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'School · '")).allElementsBoundByIndex
            .first { abs($0.frame.midY - done.frame.midY) < 12 }
        XCTAssertNotNil(name, "School and the day it was done")
        XCTAssertNotNil(level(app.staticTexts, "School", with: app.staticTexts["Meet the ECE 358 lab group"].firstMatch),
                        "in a day group, the list alone: the group has the day")
    }

    /// Show in <list>, from Today's menu and from the details' header: the list opens with the task.
    func testShowInList() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let lab = app.staticTexts["Lab 3 report · pendulum"].firstMatch
        XCTAssertTrue(lab.waitForExistence(timeout: 10), "Today")
        menuOpen {
            lab.press(forDuration: 1.2)
            app.buttons["Show in PHYS 122"].firstMatch.tap()
        }
        sleep(1)
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        XCTAssertTrue(header.label.hasPrefix("PHYS 122, Waves"), "PHYS 122 opens, with no count by its title: \(header.label)")
        XCTAssertTrue(lab.waitForExistence(timeout: 3) && lab.isHittable, "with the task shown")
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch.tap()
        app.staticTexts["Reply to the landlord about the lease"].firstMatch.tap()
        let show = app.buttons["Show in Inbox"]
        XCTAssertTrue(show.waitForExistence(timeout: 3), "the details' header")
        show.tap()
        sleep(1)
        XCTAssertTrue(header.label.hasPrefix("Inbox"), "the Inbox opens: \(header.label)")
        XCTAssertFalse(app.buttons["When"].exists, "the details closed")
    }

    // MARK: Moments (batch 2, item 5; COLOR.md §4)

    /// How colourful a point is (0–255: the largest channel less the smallest). The dark ground and the inks are grey,
    /// about 0; the spark is the warm accent.
    private func chroma(_ cg: CGImage, _ p: CGPoint) -> Int {
        let scale = CGFloat(cg.width) / app.frame.width
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(cg, in: CGRect(x: -Int(p.x * scale), y: -(cg.height - Int(p.y * scale) - 1), width: cg.width, height: cg.height))
        let c = px.prefix(3).map(Int.init)
        return c.max()! - c.min()!
    }

    /// A box checked here sparks: a ray below the box (19pt under its centre, in the row's empty space) and the row's
    /// warm flash at its far end show in the spark's colour, then go.
    func testCheckingHereSparks() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        sleep(1)
        let c = CGPoint(x: box.frame.midX, y: box.frame.midY)
        let ray = CGPoint(x: c.x, y: c.y + 19), end = CGPoint(x: app.frame.maxX - 40, y: c.y)
        let rest = XCUIScreen.main.screenshot().image.cgImage!
        XCTAssertLessThan(chroma(rest, ray), 12, "no colour under the box at rest")
        XCTAssertLessThan(chroma(rest, end), 12, "no colour at the row's end at rest")
        let frames = filming(14) { box.tap() }
        let seen = frames.map { (ray: chroma($0, ray), end: chroma($0, end)) }
        print("spark, \(seen)")
        // The ray is a 3pt line over the row's flash: it's caught well above the flash beside it.
        XCTAssertTrue(seen.contains { $0.ray > $0.end + 10 }, "a ray of the spark shows under the box")
        XCTAssertTrue(seen.contains { $0.end > 6 }, "the row flashes warm")
        sleep(1)
        let after = XCUIScreen.main.screenshot().image.cgImage!
        XCTAssertLessThan(chroma(after, ray), 12, "the spark is gone")
        XCTAssertLessThan(chroma(after, end), 12, "the flash is gone")
    }

    /// Today all done: once the last check settles, the sun and "All done for today" come first, under the title, and
    /// the Completed group after them.
    func testTodayAllDoneShowsTheSunFirst() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let open = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: '"))
        XCTAssertTrue(open.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        let list = app.collectionViews.firstMatch
        for _ in 0..<60 {
            if open.count == 0 {
                // A collection view's rows off screen aren't in its tree (List's are): once the rows have settled,
                // look again from the top.
                sleep(2)
                list.swipeDown()
                list.swipeDown()
                if open.count == 0 { break }
            }
            if let b = open.allElementsBoundByIndex.first(where: { $0.isHittable && $0.frame.minY > 120 && $0.frame.maxY < app.frame.maxY - 110 }) {
                b.tap()
            } else {
                list.swipeUp()
            }
        }
        XCTAssertEqual(open.count, 0, "every Today task checked")
        let sun = app.staticTexts["All done for today"].firstMatch
        XCTAssertTrue(sun.waitForExistence(timeout: 5), "the all-done block, once the rows settle")
        list.swipeDown()
        list.swipeDown()
        sleep(1)
        let completed = app.buttons.matching(NSPredicate(format: "label == 'Hide completed tasks' OR label BEGINSWITH 'Show '")).firstMatch
        XCTAssertTrue(completed.exists, "the Completed group")
        XCTAssertLessThanOrEqual(sun.frame.maxY, completed.frame.minY, "the sun comes first, the Completed group after it")
        XCTAssertFalse(app.staticTexts["Nothing for today"].exists)
    }

    // MARK: Undo and redo (batch 2, item 1; IX §9)

    private func notice(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// The list's "…" has Undo <step> while there's a step and Redo <step> after an undo; each confirms with a notice,
    /// and the row comes back or goes.
    func testUndoAndRedoFromTheMenu() {
        // Notices stay (-hold): XCTest's queries can take longer than an undo's 1.8 s notice.
        app.launchArguments += ["-screen", "list:phys", "-hold", "YES"]
        app.launch()
        let row = app.staticTexts["Buy safety glasses for the lab"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        let more = app.buttons["List actions"]
        more.tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Undo'")).firstMatch.exists, "no step, no Undo")
        app.buttons["Show Completed"].firstMatch.tap()   // the menu closes; this isn't a change to undo
        sleep(1)
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Delete"].firstMatch.tap()
        }
        sleep(1)
        XCTAssertFalse(row.exists, "deleted")
        more.tap()
        app.buttons["Undo Delete Task"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3), "undone: the row is back")
        XCTAssertTrue(notice("Undo Delete Task").waitForExistence(timeout: 2), "the notice says what was undone")
        more.tap()
        app.buttons["Redo Delete Task"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(row.exists, "redone: the row goes again")
        XCTAssertTrue(notice("Redo Delete Task").waitForExistence(timeout: 2))
    }

    /// Undo from another screen goes back to the one the change was made on, at once, and shows the row.
    func testUndoGoesBackToWhereTheChangeWasMade() {
        // Notices stay (-hold): XCTest's queries can take longer than an undo's 1.8 s notice.
        app.launchArguments += ["-screen", "list:phys", "-hold", "YES"]
        app.launch()
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        sleep(1)
        box.tap()
        sleep(2)
        back()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today'")).firstMatch.tap()
        sleep(1)
        app.buttons["More"].tap()
        app.buttons["Undo Complete"].firstMatch.tap()
        XCTAssertTrue(notice("Undo Complete").waitForExistence(timeout: 2), "the notice says what was undone")
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        XCTAssertTrue(header.label.hasPrefix("PHYS 122"), "back in PHYS 122: \(header.label)")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).firstMatch.exists,
                      "the task is open again, in view")
    }

    /// The notice's Undo is the stack's: it confirms the same way.
    func testTheNoticesUndoConfirms() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        sleep(1)
        box.tap()
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(notice("Undo Complete").waitForExistence(timeout: 2))
        XCTAssertTrue(box.exists, "open again")
    }

    /// ⌘Z and ⇧⌘Z on a hardware keyboard, with nothing being typed.
    func testCommandZUndoesAndRedoes() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let row = app.staticTexts["Buy safety glasses for the lab"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        menuOpen {
            row.press(forDuration: 1.2)
            app.buttons["Delete"].firstMatch.tap()
        }
        sleep(1)
        XCTAssertFalse(row.exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row.waitForExistence(timeout: 3), "⌘Z undoes")
        app.typeKey("z", modifierFlags: [.command, .shift])
        sleep(1)
        XCTAssertFalse(row.exists, "⇧⌘Z redoes")
    }

    /// Typing in a field and leaving it doesn't take the store's steps off the stack.
    func testTypingLeavesTheStepsBelow() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let box = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        sleep(1)
        box.tap()
        sleep(2)
        add()
        app.typeText("Something")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)
        app.buttons["List actions"].tap()
        XCTAssertTrue(app.buttons["Undo Complete"].firstMatch.exists, "the completion is still the step to undo")
    }

    /// In a task's sheet, checking its box confirms in the sheet, where it's seen.
    func testTheSheetShowsItsNotice() {
        app.launchArguments += ["-screen", "list:phys"]
        app.launch()
        let row = app.staticTexts["Buy safety glasses for the lab"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailList"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Buy safety glasses'")).allElementsBoundByIndex
            .first { $0.isHittable }?.tap()
        let undo = app.buttons.matching(NSPredicate(format: "label == 'Undo'")).allElementsBoundByIndex
        XCTAssertTrue(undo.contains { $0.isHittable }, "the notice's Undo shows over the sheet")
    }

    // MARK: Typed dates (batch 2 §2)

    private var dateField: XCUIElement { app.textFields["Date"] }
    private var dateFooter: XCUIElement { app.descendants(matching: .any)["dateFooter"] }
    /// A selected button whose label `op`s `text` (the highlighted day, a tinted pick).
    private func selected(_ op: String, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "isSelected == 1 AND label \(op) %@", text)).firstMatch
    }

    /// "Submit MSE 333 A2" (s4): a When in 2 days, a deadline in 3.
    private func openDate(_ kind: String) {
        app.launchArguments += ["-screen", "\(kind):s4"]
        app.launch()
        XCTAssertTrue(dateField.waitForExistence(timeout: 10), "the field")
        sleep(1)
    }

    /// Typing moves the highlight, and the footer says what Return sets, with the Mac's note for a When after the
    /// deadline. With the on-screen keyboard the sheet goes large and the footer rests on the keyboard. Return sets
    /// the day and closes the sheet.
    func testATypedDateSetsOnReturn() {
        openDate("when")
        let y0 = dateField.frame.minY
        dateField.tap()
        sleep(1)
        let keyboard = app.keyboards.firstMatch
        // Recorded for the suite's report: these run only with the on-screen keyboard.
        XCTContext.runActivity(named: "DATEKEYBOARD on-screen keyboard: \(keyboard.exists ? "shown, checks ran" : "not shown, checks skipped")") { _ in }
        print("DATEKEYBOARD on-screen keyboard \(keyboard.exists ? "shown" : "not shown")")
        if keyboard.exists {
            XCTAssertLessThan(dateField.frame.minY, y0 - 60, "the sheet went large")
            XCTAssertLessThanOrEqual(dateFooter.frame.maxY, keyboard.frame.minY + 1, "the footer is above the keyboard")
        }
        dateField.typeText("5d")
        XCTAssertTrue(dateFooter.label.hasSuffix(" · after the deadline"), dateFooter.label)
        let day = dateFooter.label.components(separatedBy: " · ")[0]
        XCTAssertTrue(selected("BEGINSWITH", day).exists, "the highlighted day")
        dateField.typeText("\n")
        XCTAssertTrue(dateField.waitForNonExistence(timeout: 3), "closed")
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        let when = app.buttons["When"].firstMatch
        XCTAssertTrue(when.waitForExistence(timeout: 5))
        XCTAssertEqual(when.value as? String, day, "set")
    }

    /// Text that reads as no date: no day is highlighted, the footer says so, and Return keeps the sheet. Emptied, the
    /// field shows the task's date again; the pick the text means is tinted.
    func testNoDateMatchKeepsTheSheet() {
        openDate("when")
        let before = dateFooter.label
        dateField.tap()
        dateField.typeText("xyz")
        XCTAssertEqual(dateFooter.label, "No date matches “xyz”")
        XCTAssertFalse(selected("CONTAINS", ",").exists, "no day highlighted")
        dateField.typeText("\n")
        sleep(1)
        XCTAssertTrue(dateField.exists, "Return set nothing")
        dateField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertEqual(dateFooter.label, before, "the task's date again")
        dateField.typeText("tomorrow")
        XCTAssertTrue(selected("==", "Tomorrow").exists, "the pick the text means")
    }

    /// A deadline before the When says so where the relative words were.
    func testADeadlineBeforeTheWhenSaysSo() {
        openDate("deadline")
        XCTAssertTrue(dateFooter.label.hasPrefix("Due "), dateFooter.label)
        dateField.tap()
        dateField.typeText("1d")
        XCTAssertTrue(dateFooter.label.hasPrefix("Due "), dateFooter.label)
        XCTAssertTrue(dateFooter.label.hasSuffix(" · before the When"), dateFooter.label)
    }

    /// A hardware keyboard's arrows move the highlight a day or a week; closing sets nothing. (Page Up, Page Down and
    /// Esc are key commands, but the simulator doesn't pass XCTest's presses of them to the app: they're checked on
    /// the phone.)
    func testTheKeysMoveTheHighlight() {
        openDate("when")
        dateField.tap()
        sleep(1)
        let before = dateFooter.label
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(dateFooter.label.hasSuffix(" · in 3 days"), dateFooter.label)
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertEqual(dateFooter.label, before)
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(dateFooter.label.hasSuffix(" · after the deadline"), dateFooter.label)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(dateField.waitForNonExistence(timeout: 3), "closed")
        app.staticTexts["Submit MSE 333 A2"].firstMatch.tap()
        let when = app.buttons["When"].firstMatch
        XCTAssertTrue(when.waitForExistence(timeout: 5))
        XCTAssertEqual(when.value as? String, before.components(separatedBy: " · ")[0], "nothing set")
    }

    // MARK: Drop edges (Reorder.swift, "Edges")

    /// Long-press `from`, then drag it to the screen's `y`, at its own x.
    private func dragTo(_ from: XCUIElement, y: CGFloat) {
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: from.frame.midX, dy: y))
        start.press(forDuration: 0.5, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 1)
        sleep(2)
    }

    /// The list cell that holds `e`.
    private func cell(_ e: XCUIElement) -> CGRect {
        app.cells.allElementsBoundByIndex.first { $0.frame.contains(CGPoint(x: e.frame.midX, y: e.frame.midY)) }?.frame ?? e.frame
    }

    /// A heading's notes are in its row, so a drag can't open a gap between them: a task dropped on them lands at the
    /// top of its section, under the notes.
    func testADropOnAHeadingsNotesIsTheTopOfItsSection() {
        openPhys()
        menuOpen {
            heading("Labs").press(forDuration: 1.0)
            app.buttons["Add Notes"].tap()
        }
        XCTAssertTrue(app.textViews["headingNotes"].waitForExistence(timeout: 3))
        app.typeText("Goggles\nLab coat")
        app.buttons["Done"].tap()
        sleep(2)
        let notes = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Goggles'")).firstMatch
        XCTAssertTrue(notes.exists)
        XCTAssertEqual(cell(notes), cell(heading("Labs")), "the notes are in the heading's row")
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        dragTo(redo, y: notes.frame.midY)
        let lab3 = app.staticTexts["Lab 3 report · pendulum"].firstMatch
        XCTAssertGreaterThan(y(redo), y(notes), "under the notes")
        XCTAssertLessThan(y(redo), y(lab3), "the top of Labs")
        XCTAssertEqual(cell(notes), cell(heading("Labs")), "still in the heading's row")
    }

    /// A heading with no tasks takes a drop over its row or the air above the next heading: the top of its section.
    func testADropIntoAnEmptyHeading() {
        openPhys()
        menuOpen {
            app.staticTexts["Make the midterm formula sheet"].firstMatch.press(forDuration: 1.0)
            app.buttons["New Heading Above"].tap()
        }
        sleep(1)
        app.typeText("Reading\n")
        sleep(2)
        let exam = heading("Exam prep"), reading = heading("Reading")
        XCTAssertTrue(reading.exists, "Exam prep is empty, between Labs and Reading")
        let bench = app.staticTexts["Book a make-up lab bench"].firstMatch
        // The air above Reading: it belongs to Exam prep's section.
        dragTo(bench, y: cell(reading).minY - 5)
        XCTAssertTrue(y(exam) < y(bench) && y(bench) < y(reading), "in Exam prep")
        let lab4 = app.staticTexts["Lab 4 pre-lab · RC circuits"].firstMatch
        dragTo(lab4, y: cell(exam).midY - 10)
        XCTAssertTrue(y(exam) < y(lab4) && y(lab4) < y(reading), "over the heading: in Exam prep too")
    }

    /// The air above Today's next group is the end of this one (it used to refuse the drop).
    func testADropAtTheEndOfATodayGroup() {
        app.launchArguments += ["-screen", "today"]
        app.launch()
        let reply = app.staticTexts["Reply to the landlord about the lease"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        sleep(1)
        let dentist = app.staticTexts["Call the dentist about a cleaning"].firstMatch
        let school = app.staticTexts["School"].firstMatch
        dragTo(reply, y: cell(dentist).maxY + 12)
        XCTAssertGreaterThan(y(reply), y(dentist), "the end of Inbox")
        XCTAssertLessThan(y(reply), y(school), "still in Inbox's group")
    }

    /// The space under the last list on Home is the end of the lists.
    func testADropAtTheEndOfHomesLists() {
        app.launch()
        let school = app.buttons["School"].firstMatch
        XCTAssertTrue(school.waitForExistence(timeout: 10))
        sleep(1)
        let completed = app.buttons["Completed"].firstMatch
        dragTo(school, y: cell(completed).minY - 6)
        for name in ["PHYS 122", "Tasks app", "Home", "Errands", "Apartment move"] where app.buttons[name].firstMatch.exists {
            XCTAssertGreaterThan(y(school), y(app.buttons[name].firstMatch), "School is under \(name)")
        }
        XCTAssertLessThan(y(school), y(completed), "above Completed")
    }

    // MARK: Rescheduling by drag in Upcoming (IX §22)

    /// Upcoming, with its first days on screen: Tomorrow (Renew the library books, Midterm review session, Watch the
    /// recording, Get groceries), then the day after (Submit MSE 333 A2, Make the midterm formula sheet, Return the
    /// boots), then Past midterms on the third day.
    private func openUpcoming() {
        app.launchArguments += ["-screen", "upcoming"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Return the boots"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
    }

    private func t(_ title: String) -> XCUIElement { app.staticTexts[title].firstMatch }

    /// Dropped on another day, a task's When is that day: it takes its slot there by list order (PHYS 122 between
    /// School and Errands, the recording before the formula sheet in PHYS 122's order), wherever it was dropped.
    func testDragInUpcomingSetsTheDay() {
        openUpcoming()
        let recording = t("Watch the recording on standing waves")
        XCTAssertLessThan(y(recording), y(t("Submit MSE 333 A2")), "on Tomorrow")
        drag(recording, onto: t("Return the boots"))
        XCTAssertLessThan(y(t("Submit MSE 333 A2")), y(recording), "on the day after, under School's")
        XCTAssertLessThan(y(recording), y(t("Make the midterm formula sheet")), "before the formula sheet")
        XCTAssertLessThan(y(t("Make the midterm formula sheet")), y(t("Return the boots")))
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Undo Set When"].waitForExistence(timeout: 3), "one step, the Mac's name")
    }

    /// The drop's step undoes: the task goes back to its day.
    func testUndoAnUpcomingDrag() {
        openUpcoming()
        let recording = t("Watch the recording on standing waves")
        drag(recording, onto: t("Return the boots"))
        XCTAssertLessThan(y(t("Submit MSE 333 A2")), y(recording), "moved")
        app.buttons["More"].tap()
        app.buttons["Undo Set When"].firstMatch.tap()
        sleep(2)
        XCTAssertLessThan(y(recording), y(t("Submit MSE 333 A2")), "back on Tomorrow")
        XCTAssertLessThan(y(t("Midterm review session")), y(recording), "at its old place")
    }

    /// Within its own day nothing is written: a day keeps list order, so the task goes back.
    func testDragWithinAnUpcomingDayChangesNothing() {
        openUpcoming()
        let titles = ["Renew the library books", "Midterm review session", "Watch the recording on standing waves",
                      "Get groceries for the week"]
        let order = { titles.sorted { self.y(self.t($0)) < self.y(self.t($1)) } }
        XCTAssertEqual(order(), titles)
        drag(t("Get groceries for the week"), onto: t("Renew the library books"))
        XCTAssertEqual(order(), titles, "as it was")
        XCTAssertLessThan(y(t("Get groceries for the week")), y(t("Submit MSE 333 A2")), "still on Tomorrow")
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Undo Set When"].exists, "nothing to undo")
    }

    /// A day after the task's deadline takes no drop: its When there wouldn't move it (it reaches Today on its
    /// deadline). Return the boots is due the day after tomorrow.
    func testUpcomingTakesNoDropPastTheDeadline() {
        openUpcoming()
        let boots = t("Return the boots")
        drag(boots, onto: t("Past midterms 2024 and 2025, timed"))
        XCTAssertLessThan(y(boots), y(t("Past midterms 2024 and 2025, timed")), "still on its day")
        XCTAssertLessThan(y(t("Make the midterm formula sheet")), y(boots), "at its place")
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Undo Set When"].exists, "nothing written")
    }

    // MARK: Multi-select (batch 2 §3)

    private var selectTitle: XCUIElement { app.staticTexts["selectTitle"].firstMatch }
    private var selectBar: XCUIElement { app.descendants(matching: .any)["selectBar"].firstMatch }
    private func segment(_ word: String) -> XCUIElement { selectBar.buttons[word].firstMatch }

    /// Opens `screen` and selects these rows from the "…" (`menu`: "List actions" or "More").
    private func select(_ titles: [String], on screen: String, menu: String = "List actions", hold: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments += ["-screen", screen] + (hold ? ["-hold", "YES"] : [])
        app.launch()
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the screen", file: file, line: line)
        sleep(1)
        app.buttons[menu].tap()
        app.buttons["Select"].firstMatch.tap()
        XCTAssertTrue(selectTitle.waitForExistence(timeout: 3), "select mode", file: file, line: line)
        for t in titles { app.staticTexts[t].firstMatch.tap() }
        XCTAssertEqual(selectTitle.label, titles.isEmpty ? "Select Tasks" : "\(titles.count) Selected", file: file, line: line)
    }

    /// Select in the "…" starts with nothing selected; a tap selects a row (its box too) and opens nothing, again
    /// deselects it; Select All takes every open task, then reads Deselect All; Done leaves, and nothing was checked.
    func testSelectFromTheMenuAndLeave() {
        select([], on: "list:school")
        XCTAssertFalse(app.buttons["List actions"].exists, "no … while selecting")
        XCTAssertEqual(app.navigationBars.firstMatch.buttons.element(boundBy: 0).label, "Select All", "no back button")
        XCTAssertTrue(selectBar.exists, "the bar")
        XCTAssertFalse(segment("Complete").isEnabled, "nothing selected: disabled")
        XCTAssertFalse(segment("Delete").isEnabled)
        XCTAssertFalse(app.buttons["New Task"].exists, "the + is gone")
        let row = app.staticTexts["Submit MSE 333 A2"].firstMatch
        row.tap()
        XCTAssertEqual(selectTitle.label, "1 Selected")
        XCTAssertTrue(segment("Complete").isEnabled)
        XCTAssertFalse(app.textViews["Submit MSE 333 A2"].exists, "no sheet")
        // The box takes no tap of its own: it selects the row.
        let kit = app.staticTexts["Return the ECE 358 lab kit"].firstMatch
        kit.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: -23, dy: 0)).tap()
        XCTAssertEqual(selectTitle.label, "2 Selected", "the box selects")
        row.tap()
        XCTAssertEqual(selectTitle.label, "1 Selected", "a second tap deselects")
        let all = app.buttons.matching(NSPredicate(format: "label == 'Select All'"))
        XCTAssertEqual(all.count, 1, "one Select All: \(all.debugDescription)")
        all.firstMatch.tap()
        XCTAssertEqual(selectTitle.label, "11 Selected", "every open task")
        app.buttons["Deselect All"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["Select Tasks"].label, "Select Tasks")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["List actions"].waitForExistence(timeout: 3), "the … is back")
        XCTAssertFalse(selectBar.exists, "the bar goes")
        XCTAssertTrue(app.buttons["New Task"].waitForExistence(timeout: 3), "the + is back")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete: Return the ECE 358 lab kit'")).firstMatch.exists,
                      "its box wasn't checked")
        // The two-finger swipe leaves one-finger scrolling alone.
        let header = app.descendants(matching: .any)["listHeader"].firstMatch
        let y0 = header.frame.minY
        app.swipeUp()
        sleep(1)
        XCTAssertLessThan(header.frame.minY, y0 - 20, "one finger still scrolls")
    }

    /// Complete with a mixed selection completes the open ones: "Completed 2 tasks", with Undo ("Complete 3 Tasks");
    /// select mode ends.
    func testCompleteAMixedSelection() {
        app.launchArguments += ["-completed", "tasks"]
        select(["Sidebar footer: a settings button", "Try Glass on the detail pane", "Theme cards in Settings"], on: "list:tasks")
        XCTAssertEqual(segment("Complete").label, "Complete", "a mixed selection reads Complete")
        segment("Complete").tap()
        XCTAssertTrue(notice("Completed 2 tasks").waitForExistence(timeout: 3), "the open ones")
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        XCTAssertTrue(app.buttons["Mark not done: Try Glass on the detail pane"].exists, "checked")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(notice("Undo Complete 3 Tasks").waitForExistence(timeout: 3), "one step")
        XCTAssertTrue(app.buttons["Complete: Try Glass on the detail pane"].waitForExistence(timeout: 3), "open again")
        XCTAssertTrue(app.buttons["Mark not done: Theme cards in Settings"].exists, "the done one stays done")
    }

    /// In Completed the bar reads Not Done: all of them, one step, "Mark as Not Done", and no notice.
    func testNotDoneInCompleted() {
        select(["Submit ECE 358 lab 3", "Read MSE 333 chapter 6"], on: "completed", menu: "More")
        XCTAssertTrue(segment("Not Done").exists, "Not Done")
        XCTAssertTrue(segment("When").exists && segment("Move").exists && segment("Delete").exists)
        segment("Not Done").tap()
        XCTAssertTrue(app.staticTexts["Submit ECE 358 lab 3"].waitForNonExistence(timeout: 3), "out of Completed")
        XCTAssertFalse(app.staticTexts["Read MSE 333 chapter 6"].exists)
        XCTAssertFalse(app.buttons["Undo"].exists, "no notice")
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Undo Mark as Not Done"].waitForExistence(timeout: 3), "one step")
        app.buttons["Undo Mark as Not Done"].tap()
        XCTAssertTrue(app.staticTexts["Submit ECE 358 lab 3"].waitForExistence(timeout: 3), "back in Completed")
        XCTAssertTrue(app.staticTexts["Read MSE 333 chapter 6"].exists)
    }

    /// When opens the date sheet for all of them ("When · 2 tasks"); a day that takes them out of Today says where,
    /// with Undo ("Set When"); select mode ends. Closing the sheet without a day keeps it.
    func testWhenForASelection() {
        select(["Reply to the landlord about the lease", "Email TA about midterm regrade"], on: "today", menu: "More")
        segment("When").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2 tasks'")).firstMatch.waitForExistence(timeout: 3),
                      "the sheet's title counts them")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(selectTitle.label, "2 Selected", "closed without a day: still selecting")
        segment("When").tap()
        let tomorrow = app.buttons["Tomorrow"].firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 3))
        tomorrow.tap()
        XCTAssertTrue(notice(beginningWith: "Scheduled for ").waitForExistence(timeout: 3), "they left Today")
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        XCTAssertFalse(app.staticTexts["Reply to the landlord about the lease"].exists)
        XCTAssertFalse(app.staticTexts["Email TA about midterm regrade"].exists)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(notice("Undo Set When").waitForExistence(timeout: 3), "one step")
        XCTAssertTrue(app.staticTexts["Reply to the landlord about the lease"].waitForExistence(timeout: 3), "back")
        XCTAssertTrue(app.staticTexts["Email TA about midterm regrade"].exists)
    }

    /// Move out of the list on screen: "Move 2 tasks to", its own list checked and disabled; "Moved 2 tasks to
    /// Errands", with Undo ("Move 2 Tasks").
    func testMoveASelectionOutOfAList() {
        select(["Sidebar footer: a settings button", "Try Glass on the detail pane"], on: "list:tasks")
        segment("Move").tap()
        XCTAssertTrue(app.staticTexts["Move 2 tasks to"].waitForExistence(timeout: 3), "the header")
        XCTAssertFalse(app.buttons["Tasks app"].isEnabled, "their own list")
        app.buttons["Errands"].tap()
        XCTAssertTrue(notice("Moved 2 tasks to Errands").waitForExistence(timeout: 3))
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        XCTAssertTrue(app.staticTexts["Try Glass on the detail pane"].waitForNonExistence(timeout: 3), "gone from Tasks app")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(notice("Undo Move 2 Tasks").waitForExistence(timeout: 3), "one step")
        XCTAssertTrue(app.staticTexts["Try Glass on the detail pane"].waitForExistence(timeout: 3), "back")
    }

    /// In a view the tasks stay, regrouped, and nothing is said (IX §10).
    func testMoveASelectionInAViewStays() {
        select(["Reply to the landlord about the lease", "Email TA about midterm regrade"], on: "today", menu: "More")
        segment("Move").tap()
        XCTAssertTrue(app.staticTexts["Move 2 tasks to"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Inbox"].isEnabled, "not all of them are in Inbox")
        app.buttons["Inbox"].tap()
        sleep(1)
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        let moved = app.staticTexts["Email TA about midterm regrade"].firstMatch
        XCTAssertTrue(moved.exists, "still in Today")
        XCTAssertFalse(notice(beginningWith: "Moved").exists, "no notice")
        // Regrouped: at the end of Inbox's group, above School's.
        XCTAssertGreaterThan(moved.frame.minY, app.staticTexts["Call the dentist about a cleaning"].firstMatch.frame.minY)
        XCTAssertLessThan(moved.frame.minY, app.staticTexts["Review CS 489 lectures 10–14"].firstMatch.frame.minY)
    }

    /// Delete: all at once, "Deleted 3 tasks", with Undo ("Delete 3 Tasks").
    func testDeleteASelection() {
        select(["Ship the When and Deadline pickers", "Sidebar footer: a settings button", "Try Glass on the detail pane"],
               on: "list:tasks")
        segment("Delete").tap()
        XCTAssertTrue(notice("Deleted 3 tasks").waitForExistence(timeout: 3))
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        XCTAssertFalse(app.staticTexts["Sidebar footer: a settings button"].exists, "gone")
        app.buttons["List actions"].tap()
        app.buttons["Undo Delete 3 Tasks"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sidebar footer: a settings button"].waitForExistence(timeout: 3), "back")
        XCTAssertTrue(app.staticTexts["Ship the When and Deadline pickers"].exists)
    }

    /// Trash: Put Back sends each home ("Put back 2 tasks"); with a task whose list is in Trash, Put Back opens Put back
    /// in for all of them ("Put back 2 tasks in School").
    func testPutBackASelection() {
        app.launchArguments += ["-expand", "move"]
        select(["Buy a second lamp", "Try the new notes app"], on: "trash", menu: "More")
        XCTAssertTrue(segment("Put Back in").exists)
        segment("Put Back").tap()
        XCTAssertTrue(notice("Put back 2 tasks").waitForExistence(timeout: 3), "each to its own list")
        XCTAssertFalse(selectTitle.exists, "select mode ends")
        XCTAssertFalse(app.staticTexts["Buy a second lamp"].exists, "out of Trash")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Buy a second lamp"].waitForExistence(timeout: 3), "back in Trash")
        sleep(1)
        app.buttons["More"].tap()
        app.buttons["Select"].firstMatch.tap()
        app.staticTexts["Buy a second lamp"].firstMatch.tap()
        app.staticTexts["Cancel the old internet plan"].firstMatch.tap()
        XCTAssertEqual(selectTitle.label, "2 Selected")
        segment("Put Back").tap()
        let school = app.buttons["School"].firstMatch
        XCTAssertTrue(school.waitForExistence(timeout: 3), "Put back in, for all of them")
        school.tap()
        XCTAssertTrue(notice("Put back 2 tasks in School").waitForExistence(timeout: 3))
    }

    /// A long-press in select mode is the selection's menu, with the pressed row added; closed without a choice, the
    /// row stays selected. Swipes are off.
    func testALongPressAddsToTheSelection() {
        select(["Ship the When and Deadline pickers"], on: "list:tasks")
        let row = app.staticTexts["Try Glass on the detail pane"].firstMatch
        menuOpen {
            row.press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Complete 2 Tasks"].waitForExistence(timeout: 3), "the menu acts on both")
            XCTAssertTrue(app.buttons["Delete 2 Tasks"].exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        }
        sleep(1)
        XCTAssertEqual(selectTitle.label, "2 Selected", "the pressed row joined the selection")
        row.swipeLeft()
        sleep(1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Delete'")).count, 1, "no swipe actions: the bar's only")
        XCTAssertEqual(selectTitle.label, "2 Selected")
    }

    /// A heading isn't selectable and its chevron still folds; the rows it folds away leave the selection.
    func testFoldingLeavesTheSelection() {
        select(["Read chapter 15 · oscillations", "Lab 3 report · pendulum"], on: "list:phys")
        app.staticTexts["Lectures"].firstMatch.tap()
        XCTAssertEqual(selectTitle.label, "2 Selected", "a heading doesn't select")
        app.buttons["Collapse Lectures"].tap()
        sleep(1)
        XCTAssertEqual(selectTitle.label, "1 Selected", "the folded row left")
    }
}
