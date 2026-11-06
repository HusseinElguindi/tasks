import XCTest
import SwiftUI
import TasksCore

/// Draws the Today widget's sizes in light and dark, at the iPhone's sizes, from the mock-ups' data, into $SHOTS
/// (default /tmp/tasks-widget-shots): a look at the views without a home screen. The widget's own frame and
/// background are WidgetKit's, so they're drawn here as the home screen would (the base colour, 22 pt corners).
@MainActor
final class WidgetRenderTests: XCTestCase {
    let dir = ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/tasks-widget-shots"

    static let sizes: [(String, CGSize)] = [
        ("small", CGSize(width: 158, height: 158)),
        ("medium", CGSize(width: 338, height: 158)),
        ("large", CGSize(width: 338, height: 354)),
    ]

    /// The mock-ups' Today: six open across School, Home and Inbox, and one done.
    static var sample: TodaySnapshot {
        let today = CalendarDate(year: 2026, month: 11, day: 5)!
        let school = TodaySnapshot.ListInfo(id: "school", name: "School", slot: 0, monogram: "S")
        let home = TodaySnapshot.ListInfo(id: "home", name: "Home", slot: 2, monogram: "H")
        let inbox = TodaySnapshot.ListInfo(id: "inbox", name: "Inbox", slot: 6, monogram: "I")
        func r(_ id: String, _ title: String, _ list: TodaySnapshot.ListInfo, _ cue: TodaySnapshot.Cue,
               _ chip: (String, DateLabel.Tone)? = nil, done: Bool = false) -> TodaySnapshot.Row {
            .init(id: id, title: title, list: list, cue: cue, chip: chip.map { .init(text: $0.0, tone: $0.1) }, done: done)
        }
        return TodaySnapshot(date: today, groups: [
            .init(list: school, rows: [
                r("1", "Email Prof. Lin about the lab", school, .late, ("2d ago", .late)),
                r("2", "Problem set 6", school, .due, ("Due today", .due)),
                r("3", "Return library books", school, .planned),
            ]),
            .init(list: home, rows: [
                r("4", "Buy milk", home, .planned),
                r("5", "Call the landlord about the heater", home, .planned),
            ]),
            .init(list: inbox, rows: [r("6", "Book the dentist", inbox, .planned, ("4d left", .neutral))]),
        ], done: [r("7", "Pay the phone bill", home, .none, done: true)])
    }

    func testRenderTheTodayWidget() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let allDone = TodaySnapshot(date: Self.sample.date, groups: [], done: Self.sample.done)
        for (state, s) in [("today", Self.sample), ("alldone", allDone)] {
            for dark in [true, false] {
                for (name, size) in Self.sizes {
                    let p = WidgetPalette(dark: dark)
                    let view = Group {
                        switch name {
                        case "small": TodaySmallView(s: s)
                        case "medium": TodayMediumView(s: s)
                        default: TodayLargeView(s: s)
                        }
                    }
                    .environment(\.widgetPalette, p)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: size.width, height: size.height)
                    .background(p.base)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(12)
                    .background(dark ? Color.black : Color(white: 0.91))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 3
                    let png = try XCTUnwrap(renderer.uiImage?.pngData())
                    try png.write(to: URL(fileURLWithPath: "\(dir)/\(state)-\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
        let setUp = SetUpView().environment(\.widgetPalette, .dark).frame(width: 158, height: 158).background(WidgetPalette.dark.base)
        try XCTUnwrap(ImageRenderer(content: setUp).uiImage?.pngData())
            .write(to: URL(fileURLWithPath: "\(dir)/setup-small-dark.png"))
    }

    func testTheLargeWidgetFitsWhatItCan() {
        let s = Self.sample
        let roomy = LargeFit(s, height: 304)
        XCTAssertEqual(roomy.hidden, 0)
        XCTAssertEqual(roomy.groups.flatMap(\.rows).count, 6)
        XCTAssertEqual(roomy.done.count, 1)
        let tight = LargeFit(s, height: 140)
        XCTAssertGreaterThan(tight.hidden, 0, "a count of what's left out")
        XCTAssertTrue(tight.done.isEmpty, "Completed only after every open row")
        let shown = tight.groups.reduce(CGFloat(0)) { $0 + WM.groupLabel + CGFloat($1.rows.count) * WM.row + WM.groupGap }
        XCTAssertLessThanOrEqual(shown + WM.moreLine, 140)
    }
}
