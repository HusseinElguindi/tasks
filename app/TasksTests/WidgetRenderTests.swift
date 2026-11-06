import XCTest
import SwiftUI
import TasksCore

/// The widgets' views (widgets/Shared) at the Mac's sizes, light and dark, from the mock-ups' data, drawn into $SHOTS
/// (default /tmp/tasks-mac-widget-shots) for a look beside the Mac boards (Mac-Dark, Mac-Light). The frame, corners and
/// background are WidgetKit's, so they're drawn here as the desktop would. And what fits: the boards' rows and
/// "N more" at the Mac's sizes.
@MainActor
final class WidgetRenderTests: XCTestCase {
    let dir = ProcessInfo.processInfo.environment["SHOTS"] ?? "/tmp/tasks-mac-widget-shots"

    /// The Mac's widget sizes (the boards' frames).
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)

    static let school = TodaySnapshot.ListInfo(id: "school", name: "School", slot: 0, monogram: "S")
    static let home = TodaySnapshot.ListInfo(id: "home", name: "Home", slot: 2, monogram: "H")
    static let inbox = TodaySnapshot.ListInfo(id: "inbox", name: "Inbox", slot: 6, monogram: "I")

    static func r(_ id: String, _ title: String, _ list: TodaySnapshot.ListInfo, _ cue: TodaySnapshot.Cue,
                  _ chip: (String, DateLabel.Tone)? = nil, when: String? = nil, done: Bool = false) -> TodaySnapshot.Row {
        .init(id: id, title: title, list: list, cue: cue, chip: chip.map { .init(text: $0.0, tone: $0.1) }, done: done,
              when: when)
    }

    /// The boards' Today: eleven open across School, Home and Inbox, and one done (which no widget shows).
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

    /// The boards' School list: three tasks, then the Readings and Lab headings.
    static var schoolList: ListSnapshot {
        func t(_ row: TodaySnapshot.Row) -> WidgetItem { .task(row) }
        return ListSnapshot(list: school, content: .items([
            t(r("1", "Email Prof. Lin about the lab", school, .late, ("2d ago", .late))),
            t(r("2", "Problem set 6", school, .due, ("Due today", .due))),
            t(r("3", "Return library books", school, .planned, when: "Today")),
            .label(id: "h1", name: "Readings", tile: nil),
            t(r("4", "Read chapter 7", school, .planned, when: "Today")),
            t(r("5", "Read chapter 8", school, .none, when: "Mon")),
            .label(id: "h2", name: "Lab", tile: nil),
            t(r("6", "Lab report draft", school, .none, ("7d left", .neutral))),
            t(r("7", "Order lab goggles", school, .none)),
            t(r("8", "Book a bench slot", school, .none, when: "Tue")),
            t(r("9", "Print the safety form", school, .none)),
            t(r("10", "Return the lab key", school, .none)),
            t(r("11", "Ask the TA about grading", school, .none)),
        ]))
    }

    private func write(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, name)
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), name)
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    /// A widget as the desktop draws it: the base colour, 20 pt corners, on the boards' wallpaper.
    private func desktop(_ view: some View, size: CGSize, dark: Bool) -> some View {
        let p = WidgetPalette(dark: dark)
        return view
            .environment(\.widgetPalette, p)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.widgetLinksAsLabels, true)
            .frame(width: size.width, height: size.height)
            .background(p.base)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(14)
            .background(dark ? Color(red: 0x1B / 255, green: 0x1F / 255, blue: 0x24 / 255)
                             : Color(red: 0xCD / 255, green: 0xD3 / 255, blue: 0xD9 / 255))
    }

    func testRenderTheTodayWidget() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let s = Self.sample
        let allDone = TodaySnapshot(date: s.date, groups: [], done: s.done)
        let nothing = TodaySnapshot(date: s.date, groups: [], done: [])
        for (state, snap) in [("today", s), ("alldone", allDone), ("nothing", nothing)] {
            for dark in [true, false] {
                let mode = dark ? "dark" : "light"
                try write(desktop(TodaySmallView(s: snap), size: Self.small, dark: dark), "\(state)-small-\(mode)")
                try write(desktop(TodayMediumView(s: snap),
                                  size: Self.medium, dark: dark), "\(state)-medium-\(mode)")
                try write(desktop(TodayLargeView(s: snap),
                                  size: Self.large, dark: dark), "\(state)-large-\(mode)")
            }
        }
        try write(desktop(SetUpView(), size: Self.small, dark: true), "setup-small-dark")
    }

    func testRenderTheListWidget() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let empty = ListSnapshot(list: Self.school, content: .empty)
        let trash = ListSnapshot(list: Self.home, content: .trash)
        for (state, snap) in [("list", Self.schoolList), ("list-empty", empty), ("list-trash", trash)] {
            for dark in [true, false] {
                let mode = dark ? "dark" : "light"
                try write(desktop(ListMediumView(s: snap),
                                  size: Self.medium, dark: dark), "\(state)-medium-\(mode)")
                try write(desktop(ListLargeView(s: snap),
                                  size: Self.large, dark: dark), "\(state)-large-\(mode)")
            }
        }
    }

    // MARK: The Mac's metrics and what fits (the boards' `mac` numbers)

    func testTheMacMetricsAreTheBoards() {
        XCTAssertEqual(WM.mediumRow, 23)
        XCTAssertEqual(WM.taskTitle, 13)
        XCTAssertEqual(WM.mediumTitle, 14)
        XCTAssertEqual(WM.largeTitle, 15)
        XCTAssertEqual(WM.largeRow, 24)
    }

    func testTheSmallAndMediumSizesShowFiveRows() {
        XCTAssertEqual(TodaySmallView.fit(Self.small.height - 2 * WM.smallTop - WM.smallHeader - WM.smallHeaderGap), 5)
        XCTAssertEqual(MediumRows.fit(Self.medium.height - WM.top - WM.bottom - WM.header - WM.headerGap), 5)
    }

    func testTheLargeSizesFitWholeLinesAndSayHowManyMore() throws {
        let height = Self.large.height - WM.top - WM.bottom - WM.header - WM.largeHeaderGap
        let today = ItemFit(TodayLargeView.items(Self.sample), height: height)
        // The Mac board's Today large: all three groups and ten of the eleven, then "1 more".
        XCTAssertEqual(today.hidden, 1)
        XCTAssertEqual(today.shown.filter(\.isTask).count, 10)
        XCTAssertLessThanOrEqual(today.height, height)

        guard case let .items(items) = Self.schoolList.content else { return XCTFail("the list has tasks") }
        // The Mac board's School list large: all eleven and both headings fit (308 of 328 pt), so no "more".
        let list = ItemFit(items, height: height)
        XCTAssertEqual(list.hidden, 0)
        XCTAssertEqual(list.shown.count, items.count)
        XCTAssertLessThanOrEqual(list.height, height)
        // Two more tasks don't: whole lines, then "2 more".
        let longer = items + [.task(Self.r("12", "Email the TA", Self.school, .none)),
                              .task(Self.r("13", "Clean the bench", Self.school, .none))]
        let over = ItemFit(longer, height: height)
        XCTAssertEqual(over.hidden, 2)
        XCTAssertLessThanOrEqual(over.height, height)
    }
}
