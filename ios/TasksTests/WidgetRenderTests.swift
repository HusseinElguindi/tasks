import XCTest
import SwiftUI
import TasksCore

/// Draws the widgets in light and dark, at the iPhone's sizes, from the mock-ups' data, into $SHOTS (default
/// /tmp/tasks-widget-shots): a look at the views without a home or lock screen. The widget's own frame and background
/// are WidgetKit's, so they're drawn here as the screen would (the base colour and 22 pt corners; the lock screen's
/// glass on a wallpaper, with one ink standing in for its vibrant rendering).
@MainActor
final class WidgetRenderTests: XCTestCase {
    let dir = ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/tasks-widget-shots"

    static let small = CGSize(width: 158, height: 158)
    static let medium = CGSize(width: 338, height: 158)
    static let large = CGSize(width: 338, height: 354)

    static let school = TodaySnapshot.ListInfo(id: "school", name: "School", slot: 0, monogram: "S")
    static let home = TodaySnapshot.ListInfo(id: "home", name: "Home", slot: 2, monogram: "H")
    static let inbox = TodaySnapshot.ListInfo(id: "inbox", name: "Inbox", slot: 6, monogram: "I")

    static func r(_ id: String, _ title: String, _ list: TodaySnapshot.ListInfo, _ cue: TodaySnapshot.Cue,
                  _ chip: (String, DateLabel.Tone)? = nil, when: String? = nil, done: Bool = false) -> TodaySnapshot.Row {
        .init(id: id, title: title, list: list, cue: cue, chip: chip.map { .init(text: $0.0, tone: $0.1) }, done: done,
              when: when)
    }

    /// The mock-ups' Today: eleven open across School, Home and Inbox, and one done (which no widget shows).
    static var sample: TodaySnapshot {
        let today = CalendarDate(year: 2026, month: 11, day: 5)!
        return TodaySnapshot(date: today, groups: [
            .init(list: school, rows: [
                r("1", "Email Prof. Lin about the lab", school, .late, ("2d ago", .late)),
                r("2", "Problem set 6", school, .due, ("Due today", .due)),
                r("3", "Return library books", school, .planned),
                r("4", "Read chapter 7", school, .planned),
            ]),
            .init(list: home, rows: [
                r("5", "Buy milk", home, .planned),
                r("6", "Call the landlord about the heater", home, .planned),
                r("7", "Water the plants", home, .planned),
            ]),
            .init(list: inbox, rows: [
                r("8", "Book the dentist", inbox, .planned, ("4d left", .neutral)),
                r("9", "Reply to Sam about Saturday", inbox, .planned),
                r("10", "Back up the laptop", inbox, .planned),
                r("11", "Pick up the dry cleaning", inbox, .planned),
            ]),
        ], done: [r("d1", "Pay the phone bill", home, .none, done: true)])
    }

    /// The mock-ups' School list: three tasks, then the Readings and Lab headings.
    static var schoolList: ListSnapshot {
        func t(_ row: TodaySnapshot.Row) -> WidgetItem { .task(row) }
        return ListSnapshot(list: school, content: .items([
            t(r("1", "Email Prof. Lin about the lab", school, .late, ("2d ago", .late))),
            t(r("2", "Problem set 6", school, .due, ("Due today", .due))),
            t(r("3", "Return library books", school, .planned, when: "Today")),
            .label(id: "h1", name: "Readings", tile: nil),
            t(r("4", "Read chapter 7", school, .planned, when: "Today")),
            t(r("5", "Read chapter 8", school, .none, when: "in 4d")),
            .label(id: "h2", name: "Lab", tile: nil),
            t(r("6", "Lab report draft", school, .none, ("7d left", .neutral))),
            t(r("7", "Order lab goggles", school, .none)),
            t(r("8", "Book a bench slot", school, .none, when: "in 5d")),
            t(r("9", "Print the safety form", school, .none)),
            t(r("10", "Return the lab key", school, .none)),
            t(r("11", "Ask the TA about grading", school, .none)),
        ]))
    }

    private func write(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let png = try XCTUnwrap(renderer.uiImage?.pngData(), name)
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    /// A home-screen widget as the home screen draws it.
    private func home(_ view: some View, size: CGSize, dark: Bool) -> some View {
        let p = WidgetPalette(dark: dark)
        return view
            .environment(\.widgetPalette, p)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: size.width, height: size.height)
            .background(p.base)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(12)
            .background(dark ? Color.black : Color(white: 0.91))
    }

    func testRenderTheTodayWidget() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let s = Self.sample
        let allDone = TodaySnapshot(date: s.date, groups: [], done: s.done)
        let nothing = TodaySnapshot(date: s.date, groups: [], done: [])
        for (state, snap) in [("today", s), ("alldone", allDone), ("nothing", nothing)] {
            for dark in [true, false] {
                let mode = dark ? "dark" : "light"
                try write(home(TodaySmallView(s: snap), size: Self.small, dark: dark), "\(state)-small-\(mode)")
                try write(home(TodayMediumView(s: snap), size: Self.medium, dark: dark), "\(state)-medium-\(mode)")
                try write(home(TodayLargeView(s: snap), size: Self.large, dark: dark), "\(state)-large-\(mode)")
            }
        }
        try write(home(SetUpView(), size: Self.small, dark: true), "setup-small-dark")
    }

    func testRenderTheListWidget() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let empty = ListSnapshot(list: Self.school, content: .empty)
        let trash = ListSnapshot(list: Self.home, content: .trash)
        for (state, snap) in [("list", Self.schoolList), ("list-empty", empty), ("list-trash", trash)] {
            for dark in [true, false] {
                let mode = dark ? "dark" : "light"
                try write(home(ListMediumView(s: snap), size: Self.medium, dark: dark), "\(state)-medium-\(mode)")
                try write(home(ListLargeView(s: snap), size: Self.large, dark: dark), "\(state)-large-\(mode)")
            }
        }
    }

    func testRenderTheLockScreen() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let s = Self.sample
        let states: [(String, LockToday)] = [
            ("tasks", LockToday(.today(s))),
            ("alldone", LockToday(.today(TodaySnapshot(date: s.date, groups: [], done: s.done)))),
            ("nothing", LockToday(.today(TodaySnapshot(date: s.date, groups: [], done: [])))),
        ]
        for (state, t) in states {
            for dark in [true, false] {
                let ink = dark ? Color.white.opacity(0.94) : Color(white: 0.1).opacity(0.9)
                let glass = dark ? Color.white.opacity(0.10) : Color.white.opacity(0.38)
                let wall = dark ? Color(red: 0.08, green: 0.13, blue: 0.17) : Color(red: 0.85, green: 0.82, blue: 0.78)
                let view = VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Thu 5")
                        LockInlineView(t: t)
                    }
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 344, alignment: .center)
                    HStack(spacing: 10) {
                        LockRectangularView(t: t)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(width: 172, height: 76)
                            .background(glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        LockGlyphView(symbol: "plus.circle", size: 30, weight: .regular, label: "New task")
                            .frame(width: 76, height: 76).background(glass, in: Circle())
                        LockGlyphView(symbol: "sun.max", size: 32, weight: .light, label: "Open Today")
                            .frame(width: 76, height: 76).background(glass, in: Circle())
                    }
                }
                .foregroundStyle(ink)
                .environment(\.colorScheme, dark ? .dark : .light)
                .padding(20)
                .background(wall)
                try write(view, "lock-\(state)-\(dark ? "dark" : "light")")
            }
        }
    }

    // MARK: What fits

    func testTheSmallAndMediumSizesShowFiveRows() {
        // The iPhone's sizes, less their margins and headers (the mock-ups' numbers).
        XCTAssertEqual(TodaySmallView.fit(158 - 2 * WM.smallTop - WM.smallHeader - WM.smallHeaderGap), 5)
        XCTAssertEqual(MediumRows.fit(158 - WM.top - WM.bottom - WM.header - WM.headerGap), 5)
    }

    func testTheLargeSizesFitWholeLinesAndSayHowManyMore() throws {
        let height = 354 - WM.top - WM.bottom - WM.header - WM.largeHeaderGap
        let today = ItemFit(TodayLargeView.items(Self.sample), height: height)
        XCTAssertEqual(today.hidden, 2, "the mock-up's \"2 more\"")
        XCTAssertEqual(today.shown.filter(\.isTask).count, 9)
        XCTAssertEqual(today.shown.filter { !$0.isTask }.count, 3, "School, Home and Inbox")
        XCTAssertLessThanOrEqual(today.height, height)

        guard case let .items(items) = Self.schoolList.content else { return XCTFail("the list has tasks") }
        let list = ItemFit(items, height: height)
        XCTAssertEqual(list.hidden, 2)
        XCTAssertLessThanOrEqual(list.height, height)

        let few = ItemFit(Array(items.prefix(4)), height: height)
        XCTAssertEqual(few.hidden, 0, "no \"more\" when everything fits")
        XCTAssertEqual(few.shown.map(\.id), ["task:1", "task:2", "task:3"], "a label with nothing under it goes")

        let tight = ItemFit(items, height: 60)
        XCTAssertEqual(tight.shown.count, 1, "room for one row and the \"more\" line")
        XCTAssertEqual(tight.hidden, 10)
    }
}
