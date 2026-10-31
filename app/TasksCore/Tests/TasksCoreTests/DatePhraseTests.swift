import XCTest
@testable import TasksCore

/// INTERACTIONS-v2 §11 "Typed dates", as the prototype's `parseDate` / `matchDate` read them.
final class DatePhraseTests: XCTestCase {
    let fri = date("2026-10-30")
    let sat = date("2026-10-31")
    let sun = date("2026-11-01")
    let mon = date("2026-11-02")

    /// Asserts `parse` reads each text as `expected` from `today`.
    func check(_ texts: [String], _ expected: String?, today: CalendarDate, order: DatePhrase.NumericOrder = .monthFirst,
               file: StaticString = #filePath, line: UInt = #line) {
        for text in texts {
            XCTAssertEqual(DatePhrase.parse(text, today: today, numericOrder: order)?.string, expected,
                           "parse(\"\(text)\") from \(today)", file: file, line: line)
        }
    }

    func checkMatch(_ texts: [String], _ expected: String?, today: CalendarDate,
                    file: StaticString = #filePath, line: UInt = #line) {
        for text in texts {
            XCTAssertEqual(DatePhrase.match(text, today: today)?.string, expected,
                           "match(\"\(text)\") from \(today)", file: file, line: line)
        }
    }

    // MARK: The §11 table

    func testToday() {
        check(["tod", "today", "now", "tdy", "toda", "  Today ", "TODAY.", "Now,"], "2026-10-30", today: fri)
    }

    func testTomorrow() {
        check(["tom", "tmr", "tmrw", "tomorrow", "tomo", "tomor", "tomorr", "tomorro", "Tomorrow"], "2026-10-31", today: fri)
        check(["tom"], "2027-01-01", today: date("2026-12-31"))
    }

    func testYesterday() {
        check(["yesterday", "yest"], "2026-10-29", today: fri)
        check(["yesterday"], "2024-02-29", today: date("2024-03-01"))
    }

    /// The next one after today; on a Friday, "fri" is next Friday.
    func testWeekdays() {
        let expected = ["sun": "2026-11-01", "mon": "2026-11-02", "tue": "2026-11-03", "wed": "2026-11-04",
                        "thu": "2026-11-05", "fri": "2026-11-06", "sat": "2026-10-31"]
        for (word, day) in expected { check([word], day, today: fri) }
        check(["monday", "Monday", "mo", "on mon", "this monday"], "2026-11-02", today: fri)
        check(["tuesday", "tues", "tu"], "2026-11-03", today: fri)
        check(["wednesday", "weds", "we", "wedn"], "2026-11-04", today: fri)
        check(["thursday", "thur", "thurs", "th", "on th"], "2026-11-05", today: fri)
        check(["friday", "fr", "frid", "this fri", "on fri"], "2026-11-06", today: fri)
        check(["saturday", "sa"], "2026-10-31", today: fri)
        check(["sunday", "su"], "2026-11-01", today: fri)
        check(["sun"], "2026-11-08", today: sun)
        check(["sat"], "2026-11-07", today: sat)
    }

    /// A single letter is never a weekday, and a prefix two days share is neither.
    func testAmbiguousWeekdays() {
        check(["t", "s", "m", "w", "f", "thx", "fridays", "next"], nil, today: fri)
    }

    /// Friday of next week, weeks starting Monday.
    func testNextWeekday() {
        check(["next fri", "next friday", "next fr"], "2026-11-06", today: fri)
        check(["next mon"], "2026-11-02", today: fri)
        check(["next sun"], "2026-11-08", today: fri)
        check(["next fri"], "2026-11-13", today: mon)
        check(["next mon"], "2026-11-09", today: mon)
        check(["next mon"], "2026-11-02", today: sun)
        check(["next sun"], "2026-11-08", today: sun)
        check(["next th"], "2026-11-12", today: mon)
    }

    /// Saturday, or today if it's the weekend.
    func testWeekend() {
        check(["weekend", "this weekend", "wknd", "this wknd", "This Weekend"], "2026-10-31", today: fri)
        check(["weekend"], "2026-10-31", today: sat)
        check(["weekend"], "2026-11-01", today: sun)
        check(["weekend"], "2026-11-07", today: mon)
        XCTAssertEqual(DatePhrase.weekend(from: fri), sat)
        XCTAssertEqual(DatePhrase.weekend(from: sat), sat)
        XCTAssertEqual(DatePhrase.weekend(from: sun), sun)
    }

    /// The weekend after this one; on a Saturday or Sunday, the coming Saturday.
    func testNextWeekend() {
        check(["next weekend", "Next  Weekend"], "2026-11-07", today: fri)
        check(["next weekend"], "2026-11-07", today: sat)
        check(["next weekend"], "2026-11-07", today: sun)
        check(["next weekend"], "2026-11-14", today: mon)
        check(["next wknd"], nil, today: fri)
    }

    /// Next Monday; a week away on a Monday.
    func testNextWeek() {
        check(["next week", "next wk"], "2026-11-02", today: fri)
        check(["next week"], "2026-11-02", today: sun)
        check(["next week"], "2026-11-09", today: mon)
        XCTAssertEqual(DatePhrase.nextWeek(from: fri), mon)
        XCTAssertEqual(DatePhrase.nextWeek(from: mon), date("2026-11-09"))
    }

    func testNextMonth() {
        check(["next month", "next mo"], "2026-11-01", today: fri)
        check(["next month"], "2027-01-01", today: date("2026-12-15"))
        check(["next month"], "2026-02-01", today: date("2026-01-31"))
    }

    func testRelative() {
        check(["3d", "3 d", "3 day", "3 days", "in 3 days", "in 3d", "three days"], "2026-11-02", today: fri)
        check(["0d", "in 0 days"], "2026-10-30", today: fri)
        check(["2w", "2 wk", "2wks", "in 2 weeks", "two weeks"], "2026-11-13", today: fri)
        check(["1m", "1mo", "1 mos", "a month", "an month", "in a month", "1 month", "one month"], "2026-11-30", today: fri)
        check(["1y", "1 yr", "a year", "in 1 year"], "2027-10-30", today: fri)
        check(["2 yrs", "in two years"], "2028-10-30", today: fri)
        check(["in ten days"], "2026-11-09", today: fri)
        check(["+5", "+05"], "2026-11-04", today: fri)
        check(["+0"], "2026-10-30", today: fri)
        check(["in 3", "3 mon", "+", "+ 5", "in3d", "-5"], nil, today: fri)
    }

    /// Months keep the day where the month has it, else take its last day.
    func testMonthEnds() {
        check(["1m"], "2027-02-28", today: date("2027-01-31"))
        check(["1m"], "2028-02-29", today: date("2028-01-31"))
        check(["1m"], "2026-04-30", today: date("2026-03-31"))
        check(["1m"], "2027-01-31", today: date("2026-12-31"))
        check(["1y"], "2029-02-28", today: date("2028-02-29"))
        check(["4y"], "2032-02-29", today: date("2028-02-29"))
        check(["13 months"], "2028-02-29", today: date("2027-01-31"))
        XCTAssertEqual(DatePhrase.adding(months: 1, to: date("2027-01-31")), date("2027-02-28"))
        XCTAssertEqual(DatePhrase.adding(months: -1, to: date("2026-03-31")), date("2026-02-28"))
        XCTAssertEqual(DatePhrase.adding(months: -1, to: date("2026-01-15")), date("2025-12-15"))
        XCTAssertEqual(DatePhrase.adding(months: -13, to: date("2026-01-15")), date("2024-12-15"))
        XCTAssertEqual(DatePhrase.adding(months: 0, to: fri), fri)
        XCTAssertEqual(DatePhrase.adding(months: 24, to: date("2024-02-29")), date("2026-02-28"))
    }

    /// That date; without a year, the next one that isn't past.
    func testMonthAndDay() {
        check(["nov 9", "Nov 9", "9 nov", "november 9th", "nov 9th", "9th november", "novem 9", "nov. 9", "nov 9st"],
              "2026-11-09", today: fri)
        check(["nov 9 2027", "nov 9, 2027", "nov 9 27", "9 nov 2027", "9th november 2027", "Nov 9th, 2027"],
              "2027-11-09", today: fri)
        check(["oct 30"], "2026-10-30", today: fri)
        check(["oct 29", "29 oct"], "2027-10-29", today: fri)
        check(["nov 9"], "2027-11-09", today: date("2026-11-10"))
        check(["sept 9", "sep 9", "september 9"], "2027-09-09", today: fri)
        check(["jan 4"], "2027-01-04", today: fri)
        check(["dec 25"], "2026-12-25", today: fri)
        check(["mar 3", "3 mar"], "2027-03-03", today: fri)
        check(["may 1"], "2027-05-01", today: fri)
        check(["jun 1"], "2027-06-01", today: fri)
        check(["jul 1"], "2027-07-01", today: fri)
        check(["nov 9 2020"], "2020-11-09", today: fri)  // a typed year may be past
        check(["nov 9 099", "nov 9 0099"], "2099-11-09", today: fri)
    }

    func testISODates() {
        check(["2026-11-09", "2026-11-9"], "2026-11-09", today: fri)
        check(["2026-01-09"], "2026-01-09", today: fri)  // an ISO date is taken as typed, past or not
        check(["2026-02-29", "2026-13-01", "2026-00-10", "2026-11-31", "26-11-09"], nil, today: fri)
        check(["2028-02-29"], "2028-02-29", today: fri)
    }

    /// "11/9" in the user's order; the prototype reads M/D.
    func testNumericDates() {
        check(["11/9"], "2026-11-09", today: fri)
        check(["11/9"], "2027-09-11", today: fri, order: .dayFirst)
        check(["9/11"], "2026-11-09", today: fri, order: .dayFirst)
        check(["9/11"], "2027-09-11", today: fri)
        check(["11/9/27", "11/9/2027"], "2027-11-09", today: fri)
        check(["9/11/27"], "2027-11-09", today: fri, order: .dayFirst)
        check(["10/30"], "2026-10-30", today: fri)
        check(["13/1", "0/5", "2/30", "11/31", "11/9/7"], nil, today: fri)
        check(["13/1"], "2027-01-13", today: fri, order: .dayFirst)
        check(["11.9", "11-9"], nil, today: fri)
    }

    /// The next 9th of a month.
    func testDayOfMonth() {
        check(["9", "9th", "the 9th", "the 9", "09", "9TH"], "2026-11-09", today: fri)
        check(["30", "30th"], "2026-10-30", today: fri)
        check(["31", "31st"], "2026-10-31", today: fri)
        check(["29", "29th"], "2026-11-29", today: fri)
        check(["1", "1st", "the 1st"], "2026-11-01", today: fri)
        check(["2nd"], "2026-11-02", today: fri)
        check(["3rd"], "2026-11-03", today: fri)
        check(["0", "00", "32", "99", "the", "the 9 th", "9 th"], nil, today: fri)
        // A day the coming months don't have is skipped: Feb 30 doesn't exist.
        check(["30"], "2027-03-30", today: date("2027-01-31"))
        check(["29"], "2027-03-29", today: date("2027-01-31"))
        check(["29"], "2028-02-29", today: date("2028-01-31"))
        check(["31"], "2026-12-31", today: date("2026-11-30"))
        check(["31"], "2026-05-31", today: date("2026-04-01"))
        // Across the new year (the prototype gives no date here: its validYMD rejects month 12 and 13).
        check(["9"], "2027-01-09", today: date("2026-12-10"))
        check(["30"], "2027-01-30", today: date("2026-12-31"))
        check(["5"], "2026-12-05", today: date("2026-11-30"))
    }

    func testInvalidDates() {
        check(["feb 30", "feb 31", "apr 31", "nov 0", "nov 32", "nov 31", "30 feb"], nil, today: fri)
        // Feb 29 reads only in a year that has it; without a year it's this year's or next year's.
        check(["feb 29"], nil, today: fri)
        // Like the prototype, a Feb 29 this year doesn't have isn't looked for in later years.
        check(["feb 29"], nil, today: date("2027-03-01"))
        check(["feb 29"], nil, today: date("2028-03-01"))
        check(["feb 29"], "2028-02-29", today: date("2028-01-15"))
        check(["feb 29 2028", "29 feb 28"], "2028-02-29", today: fri)
        check(["feb 29 2027"], nil, today: fri)
    }

    func testNotDates() {
        check(["", "   ", ",", "xyz", "a", "in", "this", "next", "nov", "ma 9", "ju 9", "foo 9", "fri 9", "the",
               "today tomorrow", "next next week", "constructor"], nil, today: fri)
        // Digits and letters are ASCII only, as in the prototype's \d and [a-z].
        check(["９", "nov ９", "１１/９", "fri\u{301}", "1\u{301}", "ｆｒｉ"], nil, today: fri)
    }

    /// Any whitespace separates words, as JavaScript's \s does.
    func testWhitespace() {
        check(["\u{A0}fri\u{A0}", "fri\t", "\nfri"], "2026-11-06", today: fri)
        check(["nov\u{A0}9", "nov\t 9", "nov,9", "nov.9"], "2026-11-09", today: fri)
        check(["next\u{2003}week"], "2026-11-02", today: fri)
    }

    /// The prototype's number words are a regex alternation, so these read too ("and" is "an" + "d").
    func testNumberWordQuirks() {
        check(["and", "ad", "an d", "oned"], "2026-10-31", today: fri)
        check(["am", "a m"], "2026-11-30", today: fri)
        check(["tend"], "2026-11-09", today: fri)
    }

    /// Counts too large for any representable date read as no date instead of trapping.
    func testHugeCounts() {
        check(["+99999999", "99999999999999999999d", "in 99999 years", "in 9000 years", "4000001d", "in 999999 weeks"],
              nil, today: fri)
        check(["in 7000 years"], "9026-10-30", today: fri)
        check(["tomorrow", "1d", "next week", "fri", "next month", "1m", "weekend"], nil, today: date("9999-12-31"))
        check(["dec 30"], nil, today: date("9999-12-31"))
        check(["today", "dec 31", "31"], "9999-12-31", today: date("9999-12-31"))
        check(["yesterday"], nil, today: date("0000-01-01"))
        XCTAssertEqual(DatePhrase.adding(months: 1, to: date("9999-12-15")), date("9999-12-31"))
        XCTAssertEqual(DatePhrase.adding(months: -1, to: date("0000-01-15")), date("0000-01-01"))
        XCTAssertEqual(DatePhrase.adding(months: .max, to: fri), date("9999-12-31"))
        XCTAssertEqual(DatePhrase.adding(months: .min, to: fri), date("0000-01-01"))
        XCTAssertEqual(DatePhrase.nextWeek(from: date("9999-12-31")), date("9999-12-31"))
        XCTAssertEqual(DatePhrase.weekend(from: date("9999-12-31")), date("9999-12-31"))
    }

    // MARK: matchDate: the exact reading, else the first phrase the text begins

    func testMatch() {
        checkMatch(["th", "thu", "thurs"], "2026-11-05", today: fri)                  // exact: a unique prefix
        checkMatch(["t", "to", "T", " t "], "2026-10-30", today: fri)                 // Today
        checkMatch(["tom", "tomorrow"], "2026-10-31", today: fri)
        checkMatch(["n", "ne", "next", "next ", "next w", "next wee", "Next Week"], "2026-11-02", today: fri)
        checkMatch(["next we"], "2026-11-04", today: fri)                             // exact: next week's Wednesday
        checkMatch(["next m", "next mo", "next mont", "next month"], "2026-11-01", today: fri)
        checkMatch(["next mon"], "2026-11-02", today: fri)                            // exact: next week's Monday
        checkMatch(["next mon"], "2026-11-09", today: mon)
        checkMatch(["next mont"], "2026-12-01", today: mon)
        checkMatch(["thi", "this", "this w", "this week", "this weekend"], "2026-10-31", today: fri)
        checkMatch(["s"], "2026-10-31", today: fri)                                   // Saturday comes before Sunday
        checkMatch(["m"], "2026-11-02", today: fri)
        checkMatch(["w"], "2026-11-04", today: fri)
        checkMatch(["f"], "2026-11-06", today: fri)
        checkMatch(["nov 9", "9"], "2026-11-09", today: fri)
        checkMatch(["3"], "2026-11-03", today: fri)
        checkMatch(["", "  ", "a", "in", "in 3", "nov", "xyz", "next weeke", "the", "this weekendx"], nil, today: fri)
    }

    func testParseIsExact() {
        XCTAssertNil(DatePhrase.parse("t", today: fri))
        XCTAssertNil(DatePhrase.parse("this", today: fri))
        XCTAssertNil(DatePhrase.parse("next", today: fri))
        XCTAssertEqual(DatePhrase.match("t", today: fri), fri)
    }

    // MARK: Locale order

    func testNumericOrderForLocale() {
        XCTAssertEqual(DatePhrase.numericOrder(for: Locale(identifier: "en_US")), .monthFirst)
        XCTAssertEqual(DatePhrase.numericOrder(for: Locale(identifier: "en_GB")), .dayFirst)
        XCTAssertEqual(DatePhrase.numericOrder(for: Locale(identifier: "de_DE")), .dayFirst)
        XCTAssertEqual(DatePhrase.numericOrder(for: Locale(identifier: "fr_FR")), .dayFirst)
        XCTAssertEqual(DatePhrase.numericOrder(for: Locale(identifier: "ja_JP")), .monthFirst)
    }

    // MARK: Purity

    /// The process's time zone doesn't change any reading.
    func testTimeZoneIndependent() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        let texts = ["today", "tom", "fri", "next fri", "weekend", "next weekend", "next week", "next month", "3d",
                     "1m", "1y", "nov 9", "11/9", "2026-11-09", "9th", "+5"]
        let reference = texts.map { DatePhrase.parse($0, today: fri) }
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata", "America/St_Johns"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            XCTAssertEqual(texts.map { DatePhrase.parse($0, today: fri) }, reference, zone)
            XCTAssertEqual(DateLabel.long(fri, today: fri), "Fri, Oct 30", zone)
        }
    }

    /// The integer day arithmetic agrees with CalendarDate's Foundation-based arithmetic.
    func testDayArithmeticMatchesCalendarDate() {
        var rng = SeededRandom(seed: 7)
        let base = date("1900-01-01")
        for _ in 0..<2_000 {
            let a = base.adding(days: Int.random(in: 0..<110_000, using: &rng))
            let n = Int.random(in: -5_000...5_000, using: &rng)
            XCTAssertEqual(a.offset(by: n), a.adding(days: n), "\(a) + \(n)")
            XCTAssertEqual(a.daysTo(a.adding(days: n)), n, "\(a) + \(n)")
            XCTAssertEqual(a.weekdayIndex, a.weekday - 1, "\(a)")
            XCTAssertEqual(CalendarDate(dayNumber: a.dayNumber), a)
        }
        XCTAssertEqual(date("1970-01-01").dayNumber, 0)
        XCTAssertEqual(date("0000-01-01").offset(by: -1), nil)
        XCTAssertEqual(date("9999-12-31").offset(by: 1), nil)
        XCTAssertEqual(date("0000-03-01").offset(by: -1), date("0000-02-29"))  // year 0 is a leap year
    }
}

/// INTERACTIONS-v2 §24 (the "Nd left" wording) and §21 "Relative dates".
final class DateLabelTests: XCTestCase {
    let today = date("2026-10-30")  // a Friday

    func testWhenChip() {
        XCTAssertEqual(DateLabel.whenChip(date("2026-10-28"), today: today), "Today")      // past carries forward
        XCTAssertEqual(DateLabel.whenChip(date("2025-06-01"), today: today), "Today")      // past, another year
        XCTAssertEqual(DateLabel.whenChip(today, today: today), "Today")
        XCTAssertEqual(DateLabel.whenChip(date("2026-10-31"), today: today), "Tomorrow")
        XCTAssertEqual(DateLabel.whenChip(date("2026-11-01"), today: today), "in 2d")
        XCTAssertEqual(DateLabel.whenChip(date("2026-11-13"), today: today), "in 14d")     // the last counted day
        XCTAssertEqual(DateLabel.whenChip(date("2026-11-14"), today: today), "Nov 14")     // 15 days: the date
        XCTAssertEqual(DateLabel.whenChip(date("2026-12-31"), today: today), "Dec 31")
        XCTAssertEqual(DateLabel.whenChip(date("2027-01-04"), today: today), "Jan 4, 2027")
        XCTAssertEqual(DateLabel.whenChip(date("2027-01-01"), today: date("2026-12-28")), "in 4d")  // across the year
        XCTAssertEqual(DateLabel.whenChip(date("2027-01-20"), today: date("2026-12-28")), "Jan 20, 2027")
    }

    func testDeadlineChip() {
        func chip(_ s: String, _ t: CalendarDate? = nil) -> String {
            let c = DateLabel.deadlineChip(date(s), today: t ?? today)
            return "\(c.text) \(c.tone)"
        }
        XCTAssertEqual(chip("2026-10-28"), "2d ago late")
        XCTAssertEqual(chip("2026-10-29"), "1d ago late")
        XCTAssertEqual(chip("2025-10-30"), "365d ago late")   // days at any distance
        XCTAssertEqual(chip("2026-10-30"), "Due today due")
        XCTAssertEqual(chip("2026-10-31"), "1d left soon")    // the day before: its own day isn't counted
        XCTAssertEqual(chip("2026-11-01"), "2d left neutral")
        XCTAssertEqual(chip("2026-11-13"), "14d left neutral")
        XCTAssertEqual(chip("2026-11-14"), "Nov 14 neutral")
        XCTAssertEqual(chip("2027-01-04"), "Jan 4, 2027 neutral")
        XCTAssertEqual(chip("2027-01-02", date("2026-12-31")), "2d left neutral")
        XCTAssertEqual(chip("2026-12-30", date("2027-01-02")), "3d ago late")
    }

    func testDeadlineWords() {
        func words(_ n: Int) -> String { DateLabel.deadlineWords(today.adding(days: n), today: today) }
        XCTAssertEqual(words(-1), "1 day overdue")
        XCTAssertEqual(words(-2), "2 days overdue")
        XCTAssertEqual(words(-13), "13 days overdue")
        XCTAssertEqual(words(-16), "2 weeks overdue")
        XCTAssertEqual(words(0), "due today")
        XCTAssertEqual(words(1), "1 day left")
        XCTAssertEqual(words(13), "13 days left")
        XCTAssertEqual(words(14), "14 days left")
        XCTAssertEqual(words(15), "in 2 weeks")
        XCTAssertEqual(words(64), "in 2 months")
    }

    func testTooltip() {
        XCTAssertEqual(DateLabel.tooltip(deadline: false, date("2026-10-31"), today: today), "When: Sat, Oct 31 · tomorrow")
        XCTAssertEqual(DateLabel.tooltip(deadline: true, date("2026-11-13"), today: today), "Deadline: Fri, Nov 13 · 14 days left")
        XCTAssertEqual(DateLabel.tooltip(deadline: true, date("2026-10-28"), today: today), "Deadline: Wed, Oct 28 · 2 days overdue")
        XCTAssertEqual(DateLabel.tooltip(deadline: true, date("2027-01-02"), today: today), "Deadline: Sat, Jan 2, 2027 · in 2 months")
    }

    func testLong() {
        XCTAssertEqual(DateLabel.long(date("2026-11-06"), today: today), "Fri, Nov 6")
        XCTAssertEqual(DateLabel.long(today, today: today), "Fri, Oct 30")
        XCTAssertEqual(DateLabel.long(date("2027-01-04"), today: today), "Mon, Jan 4, 2027")
        XCTAssertEqual(DateLabel.long(date("2025-12-25"), today: today), "Thu, Dec 25, 2025")
    }

    func testRelative() {
        func rel(_ n: Int) -> String { DateLabel.relative(today.adding(days: n), today: today) }
        XCTAssertEqual(rel(0), "today")
        XCTAssertEqual(rel(1), "tomorrow")
        XCTAssertEqual(rel(-1), "yesterday")
        XCTAssertEqual(rel(2), "in 2 days")
        XCTAssertEqual(rel(7), "in 7 days")
        XCTAssertEqual(rel(13), "in 13 days")
        XCTAssertEqual(rel(14), "in 14 days")   // days up to 14 (§24)
        XCTAssertEqual(rel(15), "in 2 weeks")
        XCTAssertEqual(rel(17), "in 2 weeks")   // 2.43
        XCTAssertEqual(rel(18), "in 3 weeks")   // 2.57
        XCTAssertEqual(rel(59), "in 8 weeks")   // 8.43
        XCTAssertEqual(rel(60), "in 2 months")
        XCTAssertEqual(rel(74), "in 2 months")  // 2.47
        XCTAssertEqual(rel(75), "in 3 months")  // 2.5 rounds up, like Math.round
        XCTAssertEqual(rel(364), "in 12 months")
        XCTAssertEqual(rel(365), "in a year")
        XCTAssertEqual(rel(547), "in a year")    // 1.499
        XCTAssertEqual(rel(548), "in 2 years")
        XCTAssertEqual(rel(-2), "2 days ago")
        XCTAssertEqual(rel(-13), "13 days ago")
        XCTAssertEqual(rel(-14), "2 weeks ago")
        XCTAssertEqual(rel(-59), "8 weeks ago")
        XCTAssertEqual(rel(-60), "9 weeks ago")  // 8.57; the past never reads in months
        XCTAssertEqual(rel(-365), "52 weeks ago")
    }

    func testMonthDayAndTitle() {
        XCTAssertEqual(DateLabel.monthDay(date("2026-11-09")), "Nov 9")
        XCTAssertEqual(DateLabel.monthDay(date("2027-01-04")), "Jan 4")
        XCTAssertEqual(DateLabel.monthDay(date("2026-12-31")), "Dec 31")
        XCTAssertEqual(DateLabel.monthTitle(year: 2026, month: 11), "November 2026")
        XCTAssertEqual(DateLabel.monthTitle(year: 2027, month: 1), "January 2027")
        XCTAssertEqual(DateLabel.monthTitle(year: 2026, month: 9), "September 2026")
    }
}
