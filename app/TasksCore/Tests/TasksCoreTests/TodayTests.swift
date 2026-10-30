import XCTest
@testable import TasksCore

final class CalendarDateTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(CalendarDate("2026-10-30")?.string, "2026-10-30")
        XCTAssertEqual(CalendarDate("2024-02-29")?.day, 29)
        XCTAssertNil(CalendarDate("2026-02-29"))
        XCTAssertNil(CalendarDate("1900-02-29"))
        XCTAssertNotNil(CalendarDate("2000-02-29"))
        XCTAssertNil(CalendarDate("2026-13-01"))
        XCTAssertNil(CalendarDate("2026-00-10"))
        XCTAssertNil(CalendarDate("2026-04-31"))
        XCTAssertNil(CalendarDate("2026-4-03"))
        XCTAssertNil(CalendarDate("2026-04-03T00:00"))
        XCTAssertNil(CalendarDate(" 2026-04-03"))
        XCTAssertNil(CalendarDate("２０２６-04-03"))
        XCTAssertEqual(CalendarDate("0042-01-05")?.string, "0042-01-05")
    }

    func testOrderingAndArithmetic() {
        XCTAssertLessThan(date("2026-10-30"), date("2026-10-31"))
        XCTAssertLessThan(date("2026-12-31"), date("2027-01-01"))
        XCTAssertEqual(date("2026-12-31").adding(days: 1), date("2027-01-01"))
        XCTAssertEqual(date("2024-03-01").adding(days: -1), date("2024-02-29"))
        XCTAssertEqual(date("2026-10-28").days(until: date("2026-10-30")), 2)
        XCTAssertEqual(date("2026-10-30").weekday, 6) // Friday
    }

    func testCodable() throws {
        let data = try JSONEncoder().encode([date("2026-11-03")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["2026-11-03"]"#)
        XCTAssertThrowsError(try JSONDecoder().decode([CalendarDate].self, from: Data(#"["2026-11-31"]"#.utf8)))
    }

    /// Travel changes what "today" is, never what a task's dates are.
    func testLocalDateFollowsTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_761_868_800) // 2025-10-31T00:00:00Z
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(CalendarDate(instant, calendar: tokyo), date("2025-10-31"))
        XCTAssertEqual(CalendarDate(instant, calendar: la), date("2025-10-30"))
    }
}

final class TodayTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }()

    func instant(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func ms(_ s: String) -> Int { Int(instant(s).timeIntervalSince1970 * 1000) }

    let list = TaskList(id: "L", name: "L", order: "a0")

    func task(when: String? = nil, deadline: String? = nil, completedAt: Int? = nil, deleted: Bool = false) -> TaskItem {
        TaskItem(id: "t", list: "L", order: "a0", when: when.map(date), deadline: deadline.map(date),
                 completedAt: completedAt, deleted: deleted)
    }

    func testMidnight() {
        let before = Day(containing: instant("2026-10-30T23:59:59-04:00"), calendar: cal)
        let after = Day(containing: instant("2026-10-31T00:00:00-04:00"), calendar: cal)
        XCTAssertEqual(before.date, date("2026-10-30"))
        XCTAssertEqual(after.date, date("2026-10-31"))
        XCTAssertEqual(before.end, after.start)

        let tomorrow = task(when: "2026-10-31")
        XCTAssertFalse(Today.contains(tomorrow, list: list, day: before))
        XCTAssertTrue(Today.contains(tomorrow, list: list, day: after))

        // Completed late on the 30th: shown, dimmed, for the rest of that day; drops out at midnight.
        let done = task(when: "2026-10-30", completedAt: ms("2026-10-30T23:30:00-04:00"))
        XCTAssertTrue(Today.contains(done, list: list, day: before))
        XCTAssertFalse(Today.contains(done, list: list, day: after))
    }

    func testPastWhenCarriesForward() {
        let day = Day(containing: instant("2026-11-05T12:00:00-05:00"), calendar: cal)
        XCTAssertTrue(Today.contains(task(when: "2026-10-01"), list: list, day: day))
        XCTAssertFalse(Today.contains(task(), list: list, day: day))
        XCTAssertFalse(Today.contains(task(when: "2026-11-06"), list: list, day: day))
    }

    /// Both dates set: the task shows if either has arrived (when = Nov 5, deadline = Nov 3 shows on Nov 3).
    func testBothDatesSet() {
        let t = task(when: "2026-11-05", deadline: "2026-11-03")
        XCTAssertFalse(Today.contains(t, list: list, day: Day(containing: instant("2026-11-02T12:00:00-05:00"), calendar: cal)))
        XCTAssertTrue(Today.contains(t, list: list, day: Day(containing: instant("2026-11-03T12:00:00-05:00"), calendar: cal)))
        XCTAssertTrue(Today.contains(t, list: list, day: Day(containing: instant("2026-11-05T12:00:00-05:00"), calendar: cal)))
    }

    func testCompletedYesterdayIsOut() {
        let day = Day(containing: instant("2026-10-30T09:00:00-04:00"), calendar: cal)
        XCTAssertFalse(Today.contains(task(when: "2026-10-29", completedAt: ms("2026-10-29T18:00:00-04:00")), list: list, day: day))
        XCTAssertTrue(Today.contains(task(when: "2026-10-29", completedAt: ms("2026-10-30T08:00:00-04:00")), list: list, day: day))
        // Completed today but with no date that has arrived: not in Today.
        XCTAssertFalse(Today.contains(task(when: "2026-11-29", completedAt: ms("2026-10-30T08:00:00-04:00")), list: list, day: day))
    }

    func testListArchivedMissingOrDeleted() {
        let day = Day(containing: instant("2026-10-30T09:00:00-04:00"), calendar: cal)
        let t = task(when: "2026-10-30")
        XCTAssertTrue(Today.contains(t, list: list, day: day))
        var archived = list
        archived.archivedAt = 1
        XCTAssertFalse(Today.contains(t, list: archived, day: day))
        XCTAssertFalse(Today.contains(t, list: nil, day: day))
        XCTAssertFalse(Today.contains(task(when: "2026-10-30", deleted: true), list: list, day: day))
    }

    /// DST: a 23-hour day still has exact local-midnight bounds.
    func testDSTDayBounds() {
        let day = Day(containing: instant("2026-03-08T12:00:00-04:00"), calendar: cal)
        XCTAssertEqual(day.date, date("2026-03-08"))
        XCTAssertEqual(day.end - day.start, 23 * 3_600_000)
    }

    func testDeadlineStatus() {
        let today = date("2026-10-30")
        XCTAssertEqual(DeadlineStatus(deadline: date("2026-10-28"), today: today), .overdue(days: 2))
        XCTAssertEqual(DeadlineStatus(deadline: today, today: today), .dueToday)
        XCTAssertEqual(DeadlineStatus(deadline: date("2026-11-02"), today: today), .upcoming(date("2026-11-02")))
        XCTAssertNil(DeadlineStatus(deadline: nil, today: today))
    }
}

final class SeedTests: XCTestCase {
    func seed(_ s: AppState, now: Int) -> Op? {
        Seed.inboxIfMissing(listExists: { s.lists[$0] != nil }, now: now)
    }

    func testSeedOp() throws {
        let o = try XCTUnwrap(seed(AppState(), now: 5))
        XCTAssertEqual(o.id, "00000000-0000-0000-0000-000000000002")
        XCTAssertEqual(o.target, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(o.type, .listCreate)
        XCTAssertEqual(o.set, Patch(order: "a0", name: "Inbox"))
    }

    /// Two Macs seeding offline, then syncing in either order, end up with one Inbox; the server dedupes by op id,
    /// and even without dedup the second create would lose.
    func testTwoMacsSeedOffline() {
        let a = seed(AppState(), now: 100)!
        let b = seed(AppState(), now: 200)!
        XCTAssertEqual(a.id, b.id)
        for log in [[a, b], [b, a]] {
            var s = AppState()
            for o in log { s.apply(o) }
            XCTAssertEqual(s.lists.count, 1)
            XCTAssertEqual(s.lists.values.first?.name, "Inbox")
        }
    }

    /// A renamed or archived Inbox survives a re-seed: the seed is a create, and a create never overwrites.
    func testRenamedOrArchivedInboxSurvives() {
        var m = OpMaker()
        var s = AppState()
        s.apply(seed(s, now: 1)!)
        s.apply(m.updateList(Spec.inbox, Patch(name: "Desk", archivedAt: .some(9))))
        XCTAssertNil(seed(s, now: 2))
        // Even if a stale seed op is applied again (e.g. a second Mac without dedup).
        s.apply(Seed.inboxIfMissing(listExists: { _ in false }, now: 3)!)
        XCTAssertEqual(s.lists[Spec.inbox]?.name, "Desk")
        XCTAssertEqual(s.lists[Spec.inbox]?.archivedAt, 9)
    }
}
