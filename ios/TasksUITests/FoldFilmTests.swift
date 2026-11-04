import XCTest

// Film scripts for the fold (§23) on the UICollectionView path, not tests: run with Tools/film/film.sh (TEST_RUNNER_FILM=1;
// skipped otherwise) and TEST_RUNNER_LIST_CONTAINER=cv. Each step prints "FILM <label> <epoch>" to line the video up
// with (Tools/film/events.py); rows.py then gives each frame's heading rules.
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
        if let c = ProcessInfo.processInfo.environment["LIST_CONTAINER"] { app.launchEnvironment["LIST_CONTAINER"] = c }
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
}
