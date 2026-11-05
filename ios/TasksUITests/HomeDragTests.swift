import XCTest

/// Home's own drag (HomeCollection.swift, T24) and the mechanics both screens share (TaskCollection+Drag.swift): the
/// hold's hand-off to the menu, a move before the lift, the edge autoscroll, back-to-back and fast drops, and a hold let
/// go right after the lift (T28's audit).
final class HomeDragTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-dragProbe", "YES"]
    }

    /// The sample's lists on Home, in order (Winter 2026 and Apartment move are in Trash).
    private let lists = ["School", "PHYS 122", "Tasks app", "Home", "Errands"]
    private func row(_ name: String) -> XCUIElement {
        name == "Inbox" ? app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch : app.buttons[name].firstMatch
    }

    /// The last press, as DragProbe saw it ("-" keys when there's no probe: the screen has gone).
    private func probe() -> [String: String] {
        let q = app.descendants(matching: .any)["dragProbe"].firstMatch
        guard q.exists else { return [:] }
        var out: [String: String] = [:]
        for kv in (q.value as? String ?? "").split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { out[String(p[0])] = String(p[1]) }
        }
        return out
    }

    /// No waiting for animations (FlowTests.menuOpen): back-to-back gestures, and a menu that may open.
    private func quick(_ steps: () -> Void) {
        let on = app.responds(to: NSSelectorFromString("setIdleAnimationWaitEnabled:"))
        if on { app.setValue(false, forKey: "idleAnimationWaitEnabled") }
        defer { if on { app.setValue(true, forKey: "idleAnimationWaitEnabled") } }
        steps()
    }

    private func at(_ e: XCUIElement) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: e.frame.midX, dy: e.frame.midY))
    }

    private func launchHome(_ extra: [String] = []) {
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(row("Errands").waitForExistence(timeout: 10))
        sleep(1)
    }

    /// Every list's row is there, hittable, one under another with no overlap; their names top to bottom.
    @discardableResult
    private func assertRowsSound(_ why: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        var frames: [(String, CGRect)] = []
        for n in ["Inbox"] + lists {
            let e = row(n)
            guard e.exists else { XCTFail("\(why): \(n) is missing", file: file, line: line); continue }
            XCTAssertTrue(e.isHittable, "\(why): \(n) shows", file: file, line: line)
            frames.append((n, e.frame))
        }
        frames.sort { $0.1.minY < $1.1.minY }
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.1.minY, a.1.maxY - 1, "\(why): \(a.0) and \(b.0) overlap", file: file, line: line)
        }
        return frames.map(\.0)
    }

    /// A drop's set-down came with every row at its place: no neighbour still sliding over the dropped row (T28: the
    /// gap's spring outran a fast drop).
    private func assertGapSettled(_ why: String, file: StaticString = #filePath, line: UInt = #line) {
        let left = Double(probe()["gapLeft"] ?? "") ?? .infinity
        XCTAssertLessThan(left, 2, "\(why): a row was still \(left) pt from its place as the copy settled (\(probe()))", file: file, line: line)
    }

    /// Held still, a list's menu opens and no drag begins; lifted then moved slowly (20 pt at 60 pt/s), it drags, the menu
    /// never opens, and nothing opens.
    func testAHoldOpensTheMenuAndAMoveDragsOnHome() {
        launchHome()
        quick {
            row("Errands").press(forDuration: 1.2)
            sleep(1)
            XCTAssertTrue(app.buttons["Rename"].exists, "held still: the list's menu")
            let ev = probe()["ev"] ?? ""
            XCTAssertTrue(ev.contains("lift") && ev.contains("holdMenu"), "it lifted, then the menu took it: \(ev)")
            XCTAssertFalse(ev.contains("begin"), "no drag: \(ev)")
        }
        launchHome()
        let y0 = row("Errands").frame.midY
        let c = at(row("Errands"))
        quick {
            c.press(forDuration: 0.5, thenDragTo: c.withOffset(CGVector(dx: 0, dy: 20)), withVelocity: XCUIGestureVelocity(rawValue: 60),
                    thenHoldForDuration: 1.0)
            sleep(1)
            XCTAssertFalse(app.buttons["Rename"].exists, "moved after the lift: no menu (\(probe()))")
        }
        let ev = probe()["ev"] ?? ""
        XCTAssertTrue(ev.contains("begin") && ev.contains("menuCut"), "a drag, and the menu cut: \(ev)")
        XCTAssertTrue(row("School").exists, "nothing opened")
        XCTAssertEqual(row("Errands").frame.midY, y0, accuracy: 1, "20 pt takes no new slot: home again")
        assertRowsSound("after the slow move")
    }

    /// Lifted and let go at once, before the menu's first stage (about 0.41 s): the copy sets down and nothing opens.
    /// The row's SwiftUI button took that touch's end as a tap, and the list opened (T28, T26 #5).
    func testAHoldLetGoAtTheLiftOpensNothingOnHome() {
        for d in [0.36, 0.38] {
            launchHome()
            quick {
                row("Errands").press(forDuration: d)
                sleep(2)
            }
            let ev = probe()["ev"] ?? ""
            XCTAssertTrue(row("School").exists, "held \(d) s on Errands and let go: Home still shows, the list didn't open (\(ev))")
            if ev.contains("lift") { XCTAssertTrue(ev.contains("holdDown") || ev.contains("holdMenu"), "\(d) s: \(ev)") }
        }
        // A tap still opens it.
        row("Errands").tap()
        XCTAssertTrue(app.navigationBars["Errands"].waitForExistence(timeout: 3), "a tap opens the list")
    }

    /// The same in a list: a task let go right after its lift opens no details, and neither checks it nor opens it.
    func testAHoldLetGoAtTheLiftOpensNothingInAList() {
        app.launchArguments += ["-screen", "list:phys"]
        for d in [0.36, 0.38] {
            app.launch()
            let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
            XCTAssertTrue(redo.waitForExistence(timeout: 10))
            sleep(1)
            quick {
                redo.press(forDuration: d)
                sleep(2)
            }
            XCTAssertFalse(app.descendants(matching: .any)["detailList"].exists, "held \(d) s and let go: no details (\(probe()))")
        }
        app.staticTexts["Redo the worked examples from lecture 9"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailList"].waitForExistence(timeout: 3), "a tap opens its details")
    }

    /// Seven drags back to back, fast, with no wait: every drop lands with the rows at their places, and afterwards
    /// every list shows, in one column, no row hidden or moved.
    func testBackToBackFastDragsOnHome() {
        launchHome()
        let pts = (["Inbox"] + lists).map { at(row($0)) }
        for (a, b) in [(1, 5), (2, 4), (5, 3), (0, 4), (5, 1), (3, 2), (4, 0)] {
            quick {
                pts[a].press(forDuration: 0.45, thenDragTo: pts[b], withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
            }
            usleep(400_000)
            XCTAssertTrue((probe()["ev"] ?? "").contains("drop"), "drag \(a)→\(b) dropped: \(probe())")
            assertGapSettled("drag \(a)→\(b)")
        }
        sleep(2)
        assertRowsSound("after seven fast drags")
    }

    /// Flicked down onto the bar three times and up twice, back to back: each lands at the end or the top of the lists,
    /// with the rows at their places.
    func testFlicksBackToBackOnHome() {
        launchHome()
        let bottom = app.windows.firstMatch.frame.maxY
        for n in ["School", "PHYS 122", "Tasks app"] {
            let s = at(row(n))
            quick {
                s.press(forDuration: 0.45, thenDragTo: s.withOffset(CGVector(dx: 0, dy: bottom - 30 - row(n).frame.midY)),
                        withVelocity: XCUIGestureVelocity(rawValue: 4000), thenHoldForDuration: 0)
            }
            usleep(400_000)
            assertGapSettled("\(n) flicked down")
        }
        sleep(2)
        XCTAssertEqual(assertRowsSound("flicked down"), ["Inbox", "Home", "Errands", "School", "PHYS 122", "Tasks app"])
        for n in ["Errands", "Home"] {
            let s = at(row(n))
            quick {
                s.press(forDuration: 0.45, thenDragTo: s.withOffset(CGVector(dx: 0, dy: -500)),
                        withVelocity: XCUIGestureVelocity(rawValue: 4000), thenHoldForDuration: 0)
            }
            usleep(400_000)
            assertGapSettled("\(n) flicked up")
        }
        sleep(2)
        XCTAssertEqual(assertRowsSound("flicked up"), ["Home", "Errands", "Inbox", "School", "PHYS 122", "Tasks app"])
    }

    /// In the largest text size Home scrolls: a move before the lift scrolls it and lifts nothing; held at the foot a
    /// drag scrolls it down and drops at the end of the lists, held at the top it scrolls back and drops first.
    func testScrollAndEdgeAutoscrollOnHome() {
        launchHome(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let c = at(row("School"))
        c.press(forDuration: 0.2, thenDragTo: c.withOffset(CGVector(dx: 0, dy: -250)), withVelocity: .default, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertGreaterThan(Double(probe()["scroll"] ?? "") ?? 0, 40, "a move before the lift scrolled Home: \(probe())")
        XCTAssertFalse(probe()["ev"]?.contains("lift") == true, "and lifted nothing: \(probe())")
        launchHome()
        let window = app.windows.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        at(row("School")).press(forDuration: 0.5, thenDragTo: origin.withOffset(CGVector(dx: window.midX, dy: window.maxY - 60)),
                                withVelocity: XCUIGestureVelocity(rawValue: 800), thenHoldForDuration: 2.0)
        sleep(2)
        XCTAssertGreaterThan(Double(probe()["scroll"] ?? "") ?? 0, 100, "held at the foot, Home scrolled down: \(probe())")
        XCTAssertEqual(assertRowsSound("autoscrolled down").last, "School", "dropped at the end of the lists")
        at(row("School")).press(forDuration: 0.5, thenDragTo: origin.withOffset(CGVector(dx: window.midX, dy: window.minY + 70)),
                                withVelocity: XCUIGestureVelocity(rawValue: 800), thenHoldForDuration: 2.0)
        sleep(2)
        XCTAssertLessThan(Double(probe()["scroll"] ?? "") ?? 0, -100, "held at the top, back up: \(probe())")
        XCTAssertEqual(assertRowsSound("autoscrolled up").first, "School", "dropped first")
    }

    /// The same fast drops in a list (the shared set-down): the rows are at their places as each copy settles.
    func testBackToBackFastDragsInAList() {
        app.launchArguments += ["-screen", "list:phys", "-dragTrace", "YES"]
        app.launch()
        let redo = app.staticTexts["Redo the worked examples from lecture 9"].firstMatch
        XCTAssertTrue(redo.waitForExistence(timeout: 10))
        sleep(1)
        let names = ["Redo the worked examples from lecture 9", "Read chapter 15 · oscillations", "Lab 3 report · pendulum",
                     "Lab 4 pre-lab · RC circuits", "Book a make-up lab bench"]
        let pts = names.map { at(app.staticTexts[$0].firstMatch) }
        for (a, b) in [(0, 1), (1, 0), (2, 3), (3, 4), (4, 2)] {
            quick {
                pts[a].press(forDuration: 0.45, thenDragTo: pts[b], withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
            }
            usleep(500_000)
            if (probe()["ev"] ?? "").contains("drop") { assertGapSettled("list drag \(a)→\(b)") }
        }
        sleep(2)
        for n in names { XCTAssertTrue(app.staticTexts[n].firstMatch.isHittable, "\(n) shows") }
    }
}
