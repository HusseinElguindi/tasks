import AppKit
import XCTest

/// The list's large title (§23; design/TITLE-RENAME.md, direction B): one wrapping field draws the name at rest and
/// while it's renamed, and the layout leaves room for the lines `TitleLayout` counts. If the two ever broke lines
/// differently, a name would be cut off or leave an empty line, and renaming would move it.
@MainActor
final class TitleLayoutTests: XCTestCase {
    private let course = "SE 463 — Software Project Management, Requirements, and Analysis"

    func testOneLineIsTheThirtyPointLineItAlwaysWas() {
        XCTAssertEqual(TitleLayout.measure("PHYS 122", width: 500).lines, 1)
        XCTAssertEqual(TitleLayout.lineBox("PHYS 122", width: 500), 30)
    }

    func testALongNameWrapsAndEachLineAddsTwentySix() {
        let m = TitleLayout.measure(course, width: 300)
        XCTAssertGreaterThan(m.lines, 1)
        XCTAssertEqual(TitleLayout.lineBox(course, width: 300), CGFloat(m.lines) * 26 + 4)
        XCTAssertLessThanOrEqual(m.lastWidth, 300)
    }

    func testAnEmptyNameStillTakesALine() {
        XCTAssertEqual(TitleLayout.lineBox("", width: 300), 30)
    }

    /// The measure the layout uses agrees with the field that draws the name, at rest, at several widths.
    func testTheMeasureMatchesTheFieldsOwnLines() {
        let names = [course, "PHYS 122", "CS 489 — Introduction to Natural Language Processing (Fall 2026, Section 001)",
                     String(repeating: "A list name that keeps going well past any width a pane could give it ", count: 3)]
        for width in [180.0, 260.0, 340.0, 456.0, 620.0, 900.0] as [CGFloat] {
            for name in names {
                let f = field(name, width: width)
                let drawn = f.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: f.frame.width, height: 10_000)).height
                let lines = TitleLayout.measure(name, width: width).lines
                XCTAssertEqual(Int((drawn / TitleLayout.lineHeight).rounded()), lines, "\(name.prefix(20))… at \(width)")
            }
        }
    }

    /// The editor gets the same attributes as the name at rest, so nothing moves when renaming starts.
    func testTheTitleAttributesCarryTheTrackingAndTheLineBox() {
        let a = TitleLayout.attributes(.white)
        XCTAssertEqual(a[.kern] as? CGFloat, -0.2)
        XCTAssertEqual((a[.paragraphStyle] as? NSParagraphStyle)?.minimumLineHeight, 26)
        XCTAssertEqual((a[.paragraphStyle] as? NSParagraphStyle)?.maximumLineHeight, 26)
        XCTAssertEqual(a[.font] as? NSFont, TitleLayout.font)
    }

    /// Today's date follows the title where it always did: 9 after the name as the one-line title measured it.
    func testWhatFollowsTheTitleStaysWhereItWas() {
        let m = TitleLayout.measure("Today", width: 500)
        let old = ceil(("Today" as NSString).size(withAttributes: [.font: TitleLayout.font]).width + 0.2 * 5) + 2
        XCTAssertEqual(m.follow, old + 9, accuracy: 1)
    }

    private func field(_ text: String, width: CGFloat) -> InlineField {
        let f = InlineField(frame: NSRect(x: 0, y: 0, width: width + 2 * TitleLayout.inset, height: 26))
        f.makeWrapping(matchingLabels: true)
        f.font = TitleLayout.font
        f.attributedStringValue = NSAttributedString(string: text, attributes: TitleLayout.attributes(.white))
        return f
    }
}

/// A task's and a heading's rename in their rows select in the theme's `text-selection`, as the sidebar's rename and the
/// detail title do, not AppKit's blue (the user, 2026-11-08: "sure yea fix the highlight").
@MainActor
final class InlineFieldSelectionTests: XCTestCase {
    func testTheFieldSelectsInItsSelectionColour() {
        let ember = NSColor(srgbRed: 230 / 255, green: 104 / 255, blue: 61 / 255, alpha: 0.42)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let f = InlineField(frame: NSRect(x: 10, y: 10, width: 200, height: 17))
        f.stringValue = "Write the report"
        f.selectionColor = ember
        w.contentView?.addSubview(f)
        f.focus(.all)
        let editor = f.currentEditor() as? NSTextView
        XCTAssertNotNil(editor)
        XCTAssertEqual(editor?.selectedTextAttributes[.backgroundColor] as? NSColor, ember)
        XCTAssertEqual(editor?.selectedRange(), NSRange(location: 0, length: 16))
    }

    /// A new colour (the theme changed) reaches the editor of a field that already has the keys.
    func testANewColourReachesAFieldBeingEdited() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let f = InlineField(frame: NSRect(x: 10, y: 10, width: 200, height: 17))
        f.stringValue = "Labs"
        w.contentView?.addSubview(f)
        f.focus(.all)
        f.selectionColor = .systemOrange
        XCTAssertEqual((f.currentEditor() as? NSTextView)?.selectedTextAttributes[.backgroundColor] as? NSColor, .systemOrange)
    }
}
