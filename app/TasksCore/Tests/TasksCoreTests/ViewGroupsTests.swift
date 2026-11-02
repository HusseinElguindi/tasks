import XCTest
@testable import TasksCore

/// ViewGroups holds the Mac's rules (app/Tasks/TaskList/ViewLayout.swift, RowDates.swift), so these are the Mac's
/// outputs as it shows them today.
final class ViewGroupsTests: XCTestCase {
    // 2026-11-02 is a Monday.
    let today = date("2026-11-02")

    func testUpDayIsTheEarlierDate() {
        XCTAssertNil(ViewGroups.upDay(when: nil, deadline: nil))
        XCTAssertEqual(ViewGroups.upDay(when: date("2026-11-05"), deadline: nil), date("2026-11-05"))
        XCTAssertEqual(ViewGroups.upDay(when: nil, deadline: date("2026-11-04")), date("2026-11-04"))
        XCTAssertEqual(ViewGroups.upDay(when: date("2026-11-05"), deadline: date("2026-11-04")), date("2026-11-04"))
        XCTAssertEqual(ViewGroups.upDay(when: date("2026-11-03"), deadline: date("2026-11-09")), date("2026-11-03"))
    }

    func testUpcomingAlwaysShowsTheNextSevenDays() {
        XCTAssertEqual(ViewGroups.upcomingDays(today: today).map(\.string),
                       ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09"])
    }

    func testUpcomingGroups() {
        func g(_ d: String, _ t: CalendarDate? = nil) -> ViewGroups.Group { ViewGroups.upcoming(date(d), today: t ?? today) }
        XCTAssertEqual(g("2026-11-03"), .init(id: "d:2026-11-03", kind: .day, day: date("2026-11-03"), name: "Tomorrow", sub: "Nov 3"))
        XCTAssertEqual(g("2026-11-04"), .init(id: "d:2026-11-04", kind: .day, day: date("2026-11-04"), name: "Wednesday", sub: "Nov 4"))
        // The seventh day is still a day of its own.
        XCTAssertEqual(g("2026-11-09"), .init(id: "d:2026-11-09", kind: .day, day: date("2026-11-09"), name: "Monday", sub: "Nov 9"))
        // Then months: the rest of the seventh day's month is "Later in" it.
        XCTAssertEqual(g("2026-11-10"), .init(id: "m:2026-11", kind: .month, day: nil, name: "Later in November", sub: nil))
        XCTAssertEqual(g("2026-11-30"), .init(id: "m:2026-11", kind: .month, day: nil, name: "Later in November", sub: nil))
        XCTAssertEqual(g("2026-12-01"), .init(id: "m:2026-12", kind: .month, day: nil, name: "December", sub: nil))
        XCTAssertEqual(g("2027-01-15"), .init(id: "m:2027-1", kind: .month, day: nil, name: "January 2027", sub: nil))

        // A week that runs into December: "Later in" is December's.
        let nov28 = date("2026-11-28")
        XCTAssertEqual(g("2026-11-29", nov28).name, "Tomorrow")
        XCTAssertEqual(g("2026-11-30", nov28).name, "Monday")
        XCTAssertEqual(g("2026-12-05", nov28), .init(id: "d:2026-12-05", kind: .day, day: date("2026-12-05"), name: "Saturday", sub: "Dec 5"))
        XCTAssertEqual(g("2026-12-06", nov28), .init(id: "m:2026-12", kind: .month, day: nil, name: "Later in December", sub: nil))

        // And into the next year: the month carries its year.
        let dec28 = date("2026-12-28")
        XCTAssertEqual(g("2026-12-31", dec28), .init(id: "d:2026-12-31", kind: .day, day: date("2026-12-31"), name: "Thursday", sub: "Dec 31"))
        XCTAssertEqual(g("2027-01-04", dec28).kind, .day)
        XCTAssertEqual(g("2027-01-05", dec28), .init(id: "m:2027-1", kind: .month, day: nil, name: "Later in January 2027", sub: nil))
        XCTAssertEqual(g("2027-02-01", dec28), .init(id: "m:2027-2", kind: .month, day: nil, name: "February 2027", sub: nil))
    }

    func testUpcomingOrder() {
        typealias K = ViewGroups.UpcomingKey
        let a = K(id: "a", day: date("2026-11-03"), rank: 2, order: "a5")
        let b = K(id: "b", day: date("2026-11-04"), rank: 0, order: "a0")
        let c = K(id: "c", day: date("2026-11-03"), rank: 1, order: "a9")
        let d = K(id: "d", day: date("2026-11-03"), rank: 2, order: "a1")
        let e = K(id: "e", day: date("2026-11-03"), rank: 2, order: "a1")
        // By day, then list rank, then the key, ties by id.
        XCTAssertEqual([a, b, c, d, e].shuffled().sorted(by: ViewGroups.upcomingPrecedes).map(\.id), ["c", "d", "e", "a", "b"])
    }

    func testPastGroups() {
        func g(_ d: String) -> ViewGroups.Group { ViewGroups.past(date(d), today: today) }
        XCTAssertEqual(g("2026-11-02"), .init(id: "d:2026-11-02", kind: .day, day: date("2026-11-02"), name: "Today", sub: "Nov 2"))
        XCTAssertEqual(g("2026-11-01"), .init(id: "d:2026-11-01", kind: .day, day: date("2026-11-01"), name: "Yesterday", sub: "Nov 1"))
        XCTAssertEqual(g("2026-10-27"), .init(id: "d:2026-10-27", kind: .day, day: date("2026-10-27"), name: "Tuesday", sub: "Oct 27"))
        // A week ago is its month's.
        XCTAssertEqual(g("2026-10-26"), .init(id: "m:2026-10", kind: .month, day: nil, name: "October", sub: nil))
        XCTAssertEqual(g("2026-10-01"), .init(id: "m:2026-10", kind: .month, day: nil, name: "October", sub: nil))
        XCTAssertEqual(g("2025-12-15"), .init(id: "m:2025-12", kind: .month, day: nil, name: "December 2025", sub: nil))
    }

    /// A completion or deletion stamped ahead of today (another device's clock) joins today's group, the same group.
    func testPastPutsAStampAheadOfTodayInToday() {
        let todays = ViewGroups.past(today, today: today)
        XCTAssertEqual(todays, .init(id: "d:2026-11-02", kind: .day, day: date("2026-11-02"), name: "Today", sub: "Nov 2"))
        XCTAssertEqual(ViewGroups.past(date("2026-11-03"), today: today), todays)
        XCTAssertEqual(ViewGroups.past(date("2027-01-10"), today: today), todays)
    }

    func testRingCue() {
        typealias C = ViewGroups.RingCue
        func cue(when w: String? = nil, deadline d: String? = nil, inToday: Bool = false) -> C {
            C(when: w.map(date), deadline: d.map(date), today: today, inToday: inToday)
        }
        XCTAssertEqual(C(), cue())
        XCTAssertNil(C().deadline)
        XCTAssertFalse(C().planned)
        XCTAssertEqual(cue(deadline: "2026-10-30").deadline, .late)
        XCTAssertEqual(cue(deadline: "2026-11-02").deadline, .due)
        XCTAssertNil(cue(deadline: "2026-11-03").deadline)
        XCTAssertTrue(cue(when: "2026-11-02").planned)
        XCTAssertTrue(cue(when: "2026-10-20").planned)
        XCTAssertFalse(cue(when: "2026-11-03").planned)
        // In Today every task is planned, so the ring doesn't say it; the deadline's tone still shows.
        XCTAssertFalse(cue(when: "2026-11-02", inToday: true).planned)
        XCTAssertEqual(cue(when: "2026-11-02", deadline: "2026-11-02", inToday: true), C(when: nil, deadline: date("2026-11-02"), today: today, inToday: true))
        // Both: the double ring.
        let both = cue(when: "2026-11-01", deadline: "2026-11-02")
        XCTAssertEqual(both.deadline, .due)
        XCTAssertTrue(both.planned)
        // A deadline that has arrived doesn't make the task "planned" (it isn't Today.datesArrived).
        XCTAssertFalse(cue(deadline: "2026-11-01").planned)
    }

    func testNames() {
        XCTAssertEqual(ViewGroups.weekday(date("2026-11-08")), "Sunday")
        XCTAssertEqual(ViewGroups.weekday(date("2026-11-07")), "Saturday")
        XCTAssertEqual(ViewGroups.month(year: 2026, month: 12, today: today), "December")
        XCTAssertEqual(ViewGroups.month(year: 2027, month: 1, today: today), "January 2027")
    }
}
