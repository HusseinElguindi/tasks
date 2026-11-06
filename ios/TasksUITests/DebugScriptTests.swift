import XCTest

/// The in-app debug script (Tasks/App/DebugScript.swift, Tools/script/README.md) end to end: a scripted drag of a
/// heading through our own press, its done marker, and its log.
final class DebugScriptTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// "Exam prep" dragged 160 pt up by the script lands above Labs: lifted, begun and dropped through our press, one
    /// drop, and the log written once the drag is over.
    func testAScriptedHeadingDrag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                               "-dragProbe", "YES", "-debugScriptToken", "uitest",
                               "-debugScript", "drag:Exam prep,-160;wait:800;log:after"]
        app.launch()
        let marker = app.descendants(matching: .any)["debugScript"].firstMatch
        XCTAssertTrue(marker.appears(timeout: 20), "the script ran to its end")
        XCTAssertEqual(marker.value as? String, "uitest ok", "with no errors")
        let exam = app.staticTexts["Exam prep"].firstMatch, labs = app.staticTexts["Labs"].firstMatch
        XCTAssertLessThan(exam.frame.midY, labs.frame.midY, "the heading was dropped above Labs")

        let log = try String(contentsOfFile: marker.label + "/after.txt", encoding: .utf8)
        XCTAssertTrue(log.contains("drops=1"), "one drop, as the probe saw it: \(log)")
        let ev = log.split(whereSeparator: \.isWhitespace).first { $0.hasPrefix("ev=") }.map(String.init) ?? ""
        XCTAssertTrue(ev.hasPrefix("ev=press>lift>") && ev.contains(">begin") && ev.hasSuffix(">drop"),
                      "pressed, lifted, begun and dropped, through our press: \(ev)")
        XCTAssertTrue(log.contains("drag=off"), "the drag is over by the log: \(log)")
        XCTAssertTrue(log.contains("h:h-exam"), "the rows are logged: \(log)")
    }
}
