import XCTest

/// The links the widgets open the app with (tasks://…, widgets/Shared/DeepLink.swift), delivered by the system to the
/// running app, as a tap on a widget delivers them.
final class WidgetLinkTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        expectSimulatorDaemonCrash()
        app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic"]
    }

    private func follow(_ link: String) {
        app.open(URL(string: link)!)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    /// The brightness (0–255) at a point, in the screen's points (FlowTests' `luma`).
    private func luma(_ cg: CGImage, _ p: CGPoint) -> Int {
        let scale = CGFloat(cg.width) / app.frame.width
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(cg, in: CGRect(x: -Int(p.x * scale), y: -(cg.height - Int(p.y * scale) - 1), width: cg.width, height: cg.height))
        return (Int(px[0]) + Int(px[1]) + Int(px[2])) / 3
    }

    /// How much brighter the row's empty space at the right is than the screen beside the row (x 4, outside its 10pt
    /// inset): about 0 at rest, about 27 with the selected fill (Dark), as FlowTests' `lift`.
    private func lift(_ row: XCUIElement) -> Int {
        let cg = XCUIScreen.main.screenshot().image.cgImage!
        let y = row.frame.midY
        return luma(cg, CGPoint(x: app.frame.maxX - 40, y: y)) - luma(cg, CGPoint(x: 4, y: y))
    }

    /// A widget's row opens the task in its list, scrolled to it and highlighted with the selected fill, which then
    /// fades; not its details (the user: "maybe dont open the details, but highlight it as before").
    func testATaskLinkOpensItsListWithTheRowHighlighted() {
        app.launch()
        follow("tasks://task/p1")
        let row = app.staticTexts["Buy safety glasses for the lab"].firstMatch
        XCTAssertTrue(row.appears(timeout: 5), "its list is open")
        XCTAssertTrue(row.isHittable, "scrolled into view")
        XCTAssertTrue(eventually(3) { lift(row) > 8 }, "the row is highlighted")
        XCTAssertFalse(app.descendants(matching: .any)["detailList"].exists, "and no details sheet")
        XCTAssertTrue(eventually(4) { abs(lift(row)) < 3 }, "the highlight fades")
        XCTAssertFalse(app.descendants(matching: .any)["detailList"].exists, "still no details")
    }

    func testAListLinkOpensTheListAndClosesASheet() {
        app.launch()
        // A task's details, open from a widget's row and a tap.
        follow("tasks://task/s4")
        let row = app.staticTexts["Submit MSE 333 A2"].firstMatch
        XCTAssertTrue(row.appears(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["When"].firstMatch.appears(timeout: 5))
        follow("tasks://list/phys-6")
        XCTAssertTrue(app.buttons["When"].firstMatch.vanishes(timeout: 5), "the sheet closed")
        XCTAssertTrue(app.staticTexts["Buy safety glasses for the lab"].firstMatch.appears(timeout: 5))
    }

    func testANewTaskLinkStartsATaskInTheList() {
        app.launch()
        follow("tasks://new?list=school-9")
        XCTAssertTrue(app.staticTexts["ECE 358 lab report"].firstMatch.appears(timeout: 5), "School is open")
        XCTAssertTrue(app.keyboards.firstMatch.appears(timeout: 5), "typing a new task")
        app.typeText("Book a study room\n")
        XCTAssertTrue(app.staticTexts["Book a study room"].firstMatch.appears(timeout: 5))
    }
}
