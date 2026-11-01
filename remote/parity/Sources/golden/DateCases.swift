import Foundation
import TasksCore

// MARK: - day.json

enum DayCases {
    static let zones = ["America/Toronto", "Europe/London", "Asia/Kolkata", "Australia/Lord_Howe",
                        // Zones whose DST change happens at midnight: a missing or a repeated 00:00.
                        "America/Santiago", "America/Havana"]

    static func build() -> J {
        var instants: [(Int, String)] = []
        for zone in zones {
            let cal = gregorian(zone)
            let tz = TimeZone(identifier: zone)!
            // The 2026 transitions, and each transition's day.
            var transitions: [Date] = []
            var t = Date(timeIntervalSince1970: Double(utcMs(2026, 1, 1)) / 1000)
            while let next = tz.nextDaylightSavingTimeTransition(after: t), next < Date(timeIntervalSince1970: Double(utcMs(2027, 1, 1)) / 1000) {
                transitions.append(next)
                t = next
            }
            var days: [Date] = [Date(timeIntervalSince1970: Double(utcMs(2026, 11, 1, 12)) / 1000),
                                Date(timeIntervalSince1970: Double(utcMs(2026, 12, 31, 12)) / 1000),
                                Date(timeIntervalSince1970: Double(utcMs(2028, 2, 29, 12)) / 1000)]
            for tr in transitions {
                days.append(tr)
                days.append(tr.addingTimeInterval(-86_400))
                days.append(tr.addingTimeInterval(86_400))
                let ms = Int((tr.timeIntervalSince1970 * 1000).rounded())
                instants += [(ms - 1, zone), (ms, zone), (ms + 1, zone)]
            }
            for d in days {
                let day = Day(containing: d, calendar: cal)
                instants += [(day.start - 1, zone), (day.start, zone), (day.start + 1, zone),
                             (day.start + 12 * 3_600_000, zone), (day.end - 1, zone)]
            }
        }
        // Far instants, the epoch and before it.
        for zone in ["America/Toronto", "Asia/Kolkata", "Australia/Lord_Howe"] {
            instants += [(0, zone), (-1, zone), (-86_400_000 * 365, zone), (utcMs(2038, 1, 19, 3, 14, 8), zone),
                         (utcMs(2000, 2, 29, 23, 59, 59, 999), zone), (utcMs(1999, 12, 31, 18, 30), zone),
                         (utcMs(2100, 3, 1, 4, 59, 59, 999), zone)]
        }
        var seen: Set<String> = []
        var cases: [J] = []
        for (now, zone) in instants where seen.insert("\(zone) \(now)").inserted {
            cases.append(.obj(["now": .int(now), "timeZone": .str(zone), "expect": encode(dayOf(now: now, zone: zone))]))
        }
        return .obj(["cases": .arr(cases)])
    }
}

// MARK: - calendar-date.json

enum CalendarCases {
    /// Foundation's gregorian calendar is Julian before 1582-10-15 (and traps on some dates there), so the
    /// Foundation-backed `adding(days:)`, `days(until:)` and `weekday` are only sampled from 1583 on.
    static let first = date("1583-01-01").dayNumber
    static let last = date("9999-12-31").dayNumber

    static func build() -> (J, Int) {
        var parse: [J] = []
        let strings = [
            "2026-10-30", "2024-02-29", "2026-02-29", "1900-02-29", "2000-02-29", "2100-02-29", "2400-02-29",
            "0000-02-29", "0004-02-29", "0100-02-29", "0000-01-01", "0000-00-01", "9999-12-31", "9999-12-32",
            "10000-01-01", "2026-13-01", "2026-00-10", "2026-04-31", "2026-04-30", "2026-06-31", "2026-09-31",
            "2026-11-31", "2026-01-31", "2026-03-31", "2026-05-31", "2026-07-31", "2026-08-31", "2026-10-31",
            "2026-12-31", "2026-02-28", "2026-01-00", "2026-4-03", "2026-04-3", "26-04-03", "2026-04-03T00:00",
            " 2026-04-03", "2026-04-03 ", "2026/04/03", "2026.04.03", "20260403", "", "2026-04-0", "2026-04-033",
            "２０２６-04-03", "2026-04-0３", "2026-01-é", "+026-01-01", "-026-01-01", "2026--1-01", "2026-1--01",
            "2026-0x-01", "2026-04-03\n", "0042-01-05", "1582-10-10", "abcd-ef-gh", "2026-1a-01", "2026_04_03",
            "2026-04-03\u{0}", "٢٠٢٦-04-03", "2026‐04‐03",
        ]
        for s in strings { parse.append(.arr([.str(s), .bool(CalendarDate(s) != nil)])) }

        var rng = Rng(42)
        func randomDate() -> CalendarDate {
            switch rng.int(4) {
            case 0: return CalendarDate(dayNumber: rng.int(in: first...last))!
            case 1: return CalendarDate(dayNumber: rng.int(in: date("1999-01-01").dayNumber...date("2031-12-31").dayNumber))!
            default:
                // A month end or a leap day.
                let y = rng.pick([1600, 1700, 1900, 2000, 2023, 2024, 2025, 2026, 2027, 2028, 2100, 2400, 9999])
                let m = rng.int(in: 1...12)
                return CalendarDate(year: y, month: m, day: CalendarDate.daysIn(month: m, year: y))!
            }
        }

        var add: [J] = []
        let edges: [(String, Int)] = [
            ("2026-12-31", 1), ("2027-01-01", -1), ("2024-02-28", 1), ("2024-02-29", 1), ("2024-03-01", -1),
            ("2026-02-28", 1), ("2026-03-01", -1), ("2000-02-28", 1), ("2100-02-28", 1), ("2026-01-31", 28),
            ("2026-01-31", 29), ("9999-12-30", 1), ("9999-12-31", 0), ("9999-12-31", -1), ("1583-01-02", -1),
            ("1583-01-01", 0), ("2026-11-01", 0), ("2026-11-01", 365), ("2026-11-01", -365), ("2024-02-29", 365),
            ("2024-02-29", 366), ("2024-02-29", -366), ("1970-01-01", -1), ("1969-12-31", 1), ("2026-03-08", 1),
            ("2026-11-01", 1), ("2026-11-01", -1), ("2000-01-01", 146_097), ("2026-11-01", 2_900_000),
        ]
        for (s, n) in edges {
            add.append(.arr([.str(s), .int(n), .str(date(s).adding(days: n).string)]))
        }
        while add.count < 300 {
            let a = randomDate()
            let n = rng.pick([rng.int(in: -3...3), rng.int(in: -40...40), rng.int(in: -1000...1000),
                              rng.int(in: -400_000...400_000), rng.int(in: -3_000_000...3_000_000)])
            let r = a.dayNumber + n
            guard r >= first, r <= last else { continue }
            add.append(.arr([.str(a.string), .int(n), .str(a.adding(days: n).string)]))
        }

        var until: [J] = []
        let untilEdges = [("2026-10-28", "2026-10-30"), ("2026-10-30", "2026-10-28"), ("2026-11-01", "2026-11-01"),
                          ("2026-03-08", "2026-03-09"), ("2026-11-01", "2026-11-02"), ("2024-02-28", "2024-03-01"),
                          ("2026-02-28", "2026-03-01"), ("1583-01-01", "9999-12-31"), ("9999-12-31", "1583-01-01"),
                          ("1970-01-01", "1969-12-31"), ("2000-01-01", "2400-01-01")]
        for (a, b) in untilEdges { until.append(.arr([.str(a), .str(b), .int(date(a).days(until: date(b)))])) }
        while until.count < 200 {
            let a = randomDate(), b = rng.chance(0.5) ? randomDate() : CalendarDate(dayNumber: min(last, max(first, a.dayNumber + rng.int(in: -60...60))))!
            until.append(.arr([.str(a.string), .str(b.string), .int(a.days(until: b))]))
        }

        var weekday: [J] = []
        for s in ["1970-01-01", "2026-10-30", "2026-11-01", "2026-11-07", "1583-01-01", "9999-12-31", "2000-02-29",
                  "2024-02-29", "2100-03-01", "1600-01-01"] {
            weekday.append(.arr([.str(s), .int(date(s).weekday)]))
        }
        while weekday.count < 120 {
            let a = randomDate()
            weekday.append(.arr([.str(a.string), .int(a.weekday)]))
        }

        // The integer arithmetic DatePhrase uses (public, no Foundation), over the whole range.
        var dayNumber: [J] = []
        for s in ["0000-01-01", "0000-02-29", "0000-03-01", "0001-01-01", "0100-03-01", "1582-10-04", "1582-10-15",
                  "1969-12-31", "1970-01-01", "2000-02-29", "2026-11-01", "9999-12-31"] {
            dayNumber.append(.arr([.str(s), .int(date(s).dayNumber)]))
        }
        for _ in 0..<60 {
            let d = CalendarDate(dayNumber: rng.int(in: date("0000-01-01").dayNumber...last))!
            dayNumber.append(.arr([.str(d.string), .int(d.dayNumber)]))
        }
        var fromDayNumber: [J] = []
        for n in [date("0000-01-01").dayNumber - 1, date("0000-01-01").dayNumber, 0, -1, 20_758, last, last + 1,
                  Int(Int32.max), -3_000_000] {
            fromDayNumber.append(.arr([.int(n), .s(CalendarDate(dayNumber: n)?.string)]))
        }

        let count = parse.count + add.count + until.count + weekday.count + dayNumber.count + fromDayNumber.count
        return (.obj(["parse": .arr(parse), "add": .arr(add), "until": .arr(until), "weekday": .arr(weekday),
                      "dayNumber": .arr(dayNumber), "fromDayNumber": .arr(fromDayNumber)]), count)
    }
}
