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

    /// The notes' text holds still in its row at each Return and each delete, in a heading's notes and in a list's
    /// (T35, the user: "now there is an issue of the the text jumping when pressing return"). The row's content grew
    /// with the new line at once, while its cell kept its height until the spring resized it, and the hosting view
    /// centred it: the text went half a line (11 pt) up in one frame and slid back down with the spring (the user's film:
    /// 12 pt up and back at each Return; CellTop has the fix). XCTest's screenshots come too seldom for a 0.25 s move, so
    /// the script logs every display frame: the text view's top less its cell's, as drawn, must not change (it was 3 pt,
    /// then -7 pt at the first frame after a Return). Returns at the end, on an empty last line and in the middle; then
    /// two deletes (the row shrinking was the same move, down).
    func testTheNotesTextHoldsStillInItsRowAtEachReturn() throws {
        let frames = ["end1", "end2", "end3", "mid1", "mid2", "del1", "del2"]
        for target in ["Labs:notes", "header:notes"] {
            let app = XCUIApplication()
            app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                                   "-debugScriptToken", "uitest", "-debugScript",
                                   "edit:\(target);type:Bring the lab coat;wait:500;ret;frames:400:end1;type:second;wait:300;"
                                   + "ret;frames:400:end2;ret;frames:400:end3;caret:10;wait:300;ret;frames:400:mid1;"
                                   + "caret:-8;wait:300;ret;frames:400:mid2;caret:-1;del;frames:400:del1;del;"
                                   + "frames:400:del2;log:caret;done;wait:300"]
            app.launch()
            // Nothing asked of the app while it runs (about 7 s): each query snapshots its accessibility on the main
            // thread, and polling for the marker left 3 display frames in 400 ms.
            Thread.sleep(forTimeInterval: 9)
            let marker = app.descendants(matching: .any)["debugScript"].firstMatch
            XCTAssertTrue(marker.appears(timeout: 30), "\(target): the script ran to its end")
            XCTAssertEqual(marker.value as? String, "uitest ok", "\(target): with no errors")
            for name in frames {
                let log = try String(contentsOfFile: marker.label + "/\(name).txt", encoding: .utf8)
                // Each frame: "… || NotesTextView x,y,w,h < … < TaskCell x,y,w,h …"
                let offsets = log.split(separator: "\n").compactMap { line -> Double? in
                    guard line.hasPrefix("F "), let chain = line.components(separatedBy: " || ").last else { return nil }
                    let views = chain.components(separatedBy: " < ")
                    func top(_ v: String) -> Double? {
                        v.split(separator: " ").first { $0.filter { $0 == "," }.count == 3 }
                            .flatMap { Double($0.split(separator: ",")[1]) }
                    }
                    guard views.count >= 2, views[0].hasPrefix("NotesTextView"), let cell = views.last(where: { $0.hasPrefix("TaskCell") }),
                          let a = top(views[0]), let b = top(cell) else { return nil }
                    return a - b
                }
                XCTAssertGreaterThan(offsets.count, 10, "\(target) \(name): the frames, with the text view and its cell: \(log.prefix(400))")
                let spread = (offsets.max() ?? 0) - (offsets.min() ?? 0)
                print("NOTESFRAMES \(target) \(name): text view top less its cell's \(offsets.min() ?? .nan)…\(offsets.max() ?? .nan) over \(offsets.count) frames")
                XCTAssertLessThan(spread, 0.5, "\(target) \(name): the text held still in its row (its top less the cell's): \(offsets)")
            }
            // Every step went into the notes: the Returns and the deletes, the middle Returns before the end's empty line.
            let caret = try String(contentsOfFile: marker.label + "/caret.txt", encoding: .utf8)
            XCTAssertTrue(caret.contains("lab coat\\n\\nsecon\\n\""), "\(target): the text typed: \(caret)")
            app.terminate()
        }
    }
}
