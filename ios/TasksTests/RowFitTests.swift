import XCTest
import SwiftUI
import TasksCore
@testable import Tasks

/// `RowFit` (T55): the widths it measures with UIKit's fonts are the ones SwiftUI draws the row's parts at, at several
/// text sizes, and its rule: a row is one line when everything fits, nothing cut.
@MainActor
final class RowFitTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("RowFitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    static let sizes: [UIContentSizeCategory] = [.extraSmall, .large, .extraExtraExtraLarge, .accessibilityLarge,
                                                 .accessibilityExtraExtraExtraLarge]

    /// A SwiftUI view's own width, at the text size `c`.
    private func width<V: View>(_ v: V, _ c: UIContentSizeCategory, app: AppModel? = nil) -> CGFloat {
        let root = Group {
            if let app { v.environment(app) } else { v }
        }
        .environment(\.dynamicTypeSize, DynamicTypeSize(c) ?? .large)
        .fixedSize()
        let host = UIHostingController(rootView: root)
        return host.sizeThatFits(in: CGSize(width: 10_000, height: 1_000)).width
    }

    func testWidthsAreSwiftUIs() async throws {
        let store = await Store.open(directory: dir.appendingPathComponent("data", isDirectory: true))
        let app = AppModel(store: store)
        let m = Measure.shared
        let titles = ["Quiz 2", "ECE 358 lab report", "Review CS 489 lectures 10–14", "Lab 3 report · pendulum",
                      "Submit MSE 333 A2", "Pay the MSE 333 field trip fee", "Wi-Fi: fix the router’s DNS (again)"]
        for c in Self.sizes {
            for s in titles {
                XCTAssertEqual(m.text(s, .body, c: c), width(Text(s).font(Typo.row), c), accuracy: 0.75, "\(c.rawValue): \(s)")
            }
            for s in ["School", "PHYS", "Errands", "Tasks app"] {
                XCTAssertEqual(Metric.markTileW + RowFit.markGap + m.text(s, .footnote, c: c),
                               width(HStack(spacing: RowFit.markGap) {
                                   Color.clear.frame(width: Metric.markTileW, height: 1)
                                   Text(s).font(Typo.quiet)
                               }, c), accuracy: 0.75, "\(c.rawValue): the mark \(s)")
            }
            for s in ["Today", "Tomorrow", "in 10d", "Nov 16"] {
                XCTAssertEqual(RowFit.whenWidth(s, c), width(QuietWhen(text: s), c), accuracy: 0.75, "\(c.rawValue): the When \(s)")
            }
            for (checked, total) in [(3, 8), (10, 12), (0, 1)] {
                var s = NotesSummary()
                s.hasNotes = true; s.checked = checked; s.total = total
                XCTAssertEqual(RowFit.hintWidth("\(checked)/\(total)", c), width(NotesHint(summary: s), c), accuracy: 0.75,
                               "\(c.rawValue): the count")
            }
            XCTAssertEqual(RowFit.hintWidth("", c), width(NotesHint(summary: NotesSummary("Some notes.")), c),
                           accuracy: 0.75, "\(c.rawValue): the notes glyph")
            for days in [-2, 0, 1, 3, 31] {
                let date = app.today.adding(days: days)
                let text = DeadlineChip.label(date, today: app.today, groupDay: nil, upcoming: false).text
                XCTAssertEqual(RowFit.chipWidth(text, c), width(DeadlineChip(date: date, compact: true), c, app: app),
                               accuracy: 0.75, "\(c.rawValue): the capsule \(text)")
            }
            for s in ["Oct 22", "Nov 8"] {
                XCTAssertEqual(m.text(s, .footnote, mono: true, c: c), width(Text(s).font(Typo.quiet).monospacedDigit(), c),
                               accuracy: 0.75, "\(c.rawValue): the day \(s)")
            }
        }
    }

    /// A 393pt phone's row: 373 from the fill's edge to edge.
    static let phone: CGFloat = 373

    func testFitsOrNot() {
        // The user's case: a short title, the notes glyph and "1d left".
        let quiz = RowFit(title: "Quiz 2", hint: "", chip: "1d left")
        XCTAssertTrue(quiz.fits(width: Self.phone, category: .large), "Quiz 2 fits")
        XCTAssertEqual(RowFit.resolve(quiz.signature, width: Self.phone, category: .large), "1")
        // The same parts with a long title.
        var long = quiz
        long.title = "Quiz 2 on the second half of the course, with the practice set"
        XCTAssertFalse(long.fits(width: Self.phone, category: .large), "a long title doesn't")
        XCTAssertEqual(RowFit.resolve(long.signature, width: Self.phone, category: .large), "2")
        // At the largest text size the short one doesn't either.
        let big = RowFit(title: "Quiz 2", when: "Tomorrow", hint: "3/8", chip: "2d left")
        XCTAssertTrue(big.fits(width: Self.phone, category: .large))
        XCTAssertFalse(big.fits(width: Self.phone, category: .accessibilityExtraExtraExtraLarge), "AX5")
        // A heading's task has 30pt less.
        let edge = RowFit(title: "Read chapter 15 · oscillations", when: "Today")
        let w = edge.natural(.large) + RowFit.lead + RowFit.trail + RowFit.slack
        XCTAssertTrue(edge.fits(width: w, category: .large))
        XCTAssertFalse(edge.fits(width: w - 1, category: .large), "the slack, exactly")
        var indented = edge
        indented.indent = true
        XCTAssertFalse(indented.fits(width: w, category: .large), "indented")
        XCTAssertTrue(indented.fits(width: w + RowFit.indentW, category: .large))
        // Nothing for line 2, or the glyph alone: one line, whatever the title.
        let bare = RowFit(title: String(repeating: "A very long title ", count: 8))
        XCTAssertEqual(bare.signature, "1")
        XCTAssertEqual(RowFit(title: bare.title, hint: "").signature, "1", "the glyph alone stays after the title")
        XCTAssertTrue(RowFit(title: bare.title, hint: "").fits(width: Self.phone, category: .large))
        // No width yet: the two-line shape.
        XCTAssertFalse(quiz.fits(width: 0, category: .large))
    }

    /// The signature carries every word that sets the width, and reads back as it was.
    func testSignature() {
        let f = RowFit(title: "Lab 3 report · pendulum", indent: true, mark: "PHYS", day: "Oct 22", when: "Today",
                       hint: "3/8", chip: "1d left")
        XCTAssertEqual(RowFit(signature: f.signature), f)
        let glyph = RowFit(title: "Quiz 2", mark: "", hint: "", chip: "Due")
        XCTAssertEqual(RowFit(signature: glyph.signature), glyph, "empty parts aren't missing ones")
        var more = f
        more.hint = "10/12"
        XCTAssertNotEqual(more.signature, f.signature, "a count changing")
        var renamed = f
        renamed.title += " and the error analysis"
        XCTAssertNotEqual(renamed.signature, f.signature, "a rename")
        XCTAssertNil(RowFit(signature: "1"))
        XCTAssertNil(RowFit.resolve("Goggles", width: Self.phone, category: .large), "not a task's")
    }
}
