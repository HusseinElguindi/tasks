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

    func testATaskLinkOpensItsListAndDetails() {
        app.launch()
        follow("tasks://task/s4")
        // The details sheet: its date rows.
        XCTAssertTrue(app.buttons["When"].firstMatch.appears(timeout: 5), "the task's details are open")
        XCTAssertTrue(app.staticTexts["Submit MSE 333 A2"].firstMatch.exists)
    }

    func testAListLinkOpensTheListAndClosesASheet() {
        app.launch()
        follow("tasks://task/s4")
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
