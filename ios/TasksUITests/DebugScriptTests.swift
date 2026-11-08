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

    /// A heading's fold moves its rows on the Mac's `layout` spring (critically damped, response 0.25 s), only their
    /// opacity on the fade's curves (T45, the user: "yea use the mac springs"). Lectures folds and opens; the Labs
    /// heading below it, as drawn at each display frame, follows the spring: at 100 ms it's 0.725 of the way (the old
    /// curves: 0.85 collapsing, 150 ms ease-out; 0.28 opening, 220 ms ease-in). Then the chevron tapped twice, 100 ms
    /// apart: the rows turn back where they're drawn (ending the first fold at its end jumped them 53 pt the wrong way,
    /// and then back), and the fold never draws rows over each other (FoldProbe's `fo`).
    func testTheFoldMovesOnTheMacsSpring() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "YES", "-appearance", "dark", "-style", "classic", "-screen", "list:phys",
                               "-dragProbe", "YES", "-debugScriptToken", "uitest", "-debugScript",
                               "wait:1000;film:650:collapse;wait:50;collapse:Lectures;wait:900;film:650:expand;wait:50;"
                               + "collapse:Lectures;wait:900;film:1000:turn;collapse:Lectures;wait:100;collapse:Lectures;"
                               + "wait:1100;log:after"]
        app.launch()
        // Nothing asked of the app while it runs (about 5 s): a query starves its display link (the notes' test below).
        // Each film starts before its tap, so its first frames are at rest.
        Thread.sleep(forTimeInterval: 7)
        let marker = app.descendants(matching: .any)["debugScript"].firstMatch
        XCTAssertTrue(marker.appears(timeout: 30), "the script ran to its end")
        XCTAssertEqual(marker.value as? String, "uitest ok", "with no errors")
        // Each frame: "F <ms> … | h:h-lab x,y,w,h | …": Labs' drawn top.
        func labs(_ name: String) throws -> [(t: Double, y: Double)] {
            let log = try String(contentsOfFile: marker.label + "/\(name).txt", encoding: .utf8)
            var points: [(t: Double, y: Double)] = []
            for line in log.split(separator: "\n") where line.hasPrefix("F ") {
                let parts = line.components(separatedBy: " | ")
                guard let t = Double(line.split(separator: " ")[1]),
                      let lab = parts.first(where: { $0.hasPrefix("h:h-lab ") }),
                      let y = Double(lab.dropFirst(8).split(separator: ",")[1]) else { continue }
                points.append((t, y))
            }
            return points
        }
        let w = 2 * Double.pi / 0.25
        func spring(_ ms: Double) -> Double { ms <= 0 ? 0 : 1 - (1 + w * ms / 1000) * exp(-w * ms / 1000) }
        for name in ["collapse", "expand"] {
            let points = try labs(name)
            XCTAssertGreaterThan(points.count, 20, "\(name): the frames")
            guard let first = points.first, let last = points.last else { continue }
            let y0 = first.y, y1 = last.y
            // Its three rows: the chapter (When "Today", 56), the worked examples (48) and the recording ("Tomorrow", 56).
            XCTAssertEqual(abs(y1 - y0), 160, accuracy: 2, "\(name): Labs moved by Lectures' section")
            // The start that fits the spring best, and how well it fits.
            var best = (error: Double.infinity, t0: 0.0)
            for k in 0...3000 {
                let t0 = first.t + Double(k) / 10
                let e = points.reduce(0) { $0 + pow(y0 + (y1 - y0) * spring($1.t - t0) - $1.y, 2) }
                if e < best.error { best = (e, t0) }
            }
            let rms = (best.error / Double(points.count)).squareRoot()
            // Drawn at 100 ms, between the frames either side.
            let at = best.t0 + 100
            guard let i = points.firstIndex(where: { $0.t >= at }), i > 0 else { XCTFail("\(name): no frame at 100 ms"); continue }
            let a = points[i - 1], b = points[i]
            let y = a.y + (b.y - a.y) * (at - a.t) / max(1, b.t - a.t)
            let progress = (y - y0) / (y1 - y0)
            print("FOLDSPRING \(name): rms \(rms) pt, at 100 ms \(progress) of the way (spring 0.725)")
            XCTAssertLessThan(rms, 1.5, "\(name): the rows follow the Mac's spring")
            XCTAssertTrue((0.65...0.80).contains(progress), "\(name): at 100 ms, \(progress) of the way (spring 0.725)")
        }
        // The double tap: Labs' speed either side of where it turns back (dropping frames under 8 ms apart). Turning
        // where it's drawn, it slows to a stop and comes back (under 900 pt/s here); a jump to the first fold's end
        // first was 2400–5800 pt/s.
        var turn: [(t: Double, y: Double)] = []
        for p in try labs("turn") where turn.last.map({ p.t - $0.t >= 8 }) ?? true { turn.append(p) }
        XCTAssertGreaterThan(turn.count, 30, "the double tap's frames")
        let speeds = zip(turn, turn.dropFirst()).map { ($1.y - $0.y) / ($1.t - $0.t) * 1000 }.filter { abs($0) > 1 }
        let jolt = zip(speeds, speeds.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.map { abs($0) + abs($1) }.max() ?? 0
        print("FOLDSPRING turn: \(jolt) pt/s either side")
        XCTAssertLessThan(jolt, 1500, "the double tap turned the rows back where they were drawn: \(turn.map { Int($0.y) })")
        XCTAssertEqual(turn.last?.y ?? 0, turn.first?.y ?? 1, accuracy: 0.5, "open again at the end")
        let log = try String(contentsOfFile: marker.label + "/after.txt", encoding: .utf8)
        XCTAssertTrue(log.contains("fo=0.0"), "no rows drawn over each other in any fold: \(log)")
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
