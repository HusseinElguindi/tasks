import Foundation
import TasksCore

// MARK: - date-phrase.json

enum PhraseCases {
    static let referenceDays = [
        "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", // Sun … Sat
        "2026-01-31", "2026-02-28", "2024-02-29", "2028-02-29", "2026-04-30", "2026-12-31", "2027-01-01",
        "2025-12-29", "0000-01-01", "9999-12-31",
    ]

    static func phrases() -> [String] {
        var p: [String] = []
        // The exact words.
        p += ["today", "tod", "tdy", "toda", "now", "tomorrow", "tom", "tmr", "tmrw", "tomo", "tomor", "tomorr", "tomorro",
              "yesterday", "yest", "weekend", "wknd", "this weekend", "this wknd", "next weekend", "next week", "next wk",
              "next month", "next mo"]
        // Every prefix, as typed (match falls back to the first phrase that starts with the text).
        for w in ["today", "tomorrow", "this weekend", "next week", "next month", "next weekend", "yesterday",
                  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] {
            for k in 1...w.count { p.append(String(w.prefix(k))) }
        }
        // Count and unit.
        let units = ["d", "day", "days", "w", "wk", "wks", "week", "weeks", "mo", "mos", "month", "months", "m",
                     "y", "yr", "yrs", "year", "years", "h", "dy", "weekss"]
        for c in ["3", "a"] { for u in units { p.append("\(c) \(u)") } }
        for c in ["0", "1", "2", "10", "31", "365", "4000000", "4000001", "99999999999999999999", "an", "one", "two",
                  "five", "ten", "eleven"] {
            for u in ["d", "days", "w", "weeks", "mo", "m", "month", "y", "years", "h"] { p.append("\(c) \(u)") }
        }
        for c in ["0", "1", "3", "12", "a", "an", "one", "ten", "4000001"] {
            for u in ["d", "day", "w", "wk", "mo", "m", "months", "y", "yrs", "h"] { p.append("\(c)\(u)") }
        }
        p += ["and", "ad", "am", "aw", "ay", "amo", "tend", "oned", "twow", "threeweeks", "in 3 days", "in 3d", "in a week",
              "in an hour", "in ten days", "in in 3d", "in 2", "in", "in 1y", "in 0d", "in a", "in month", "3 days ago",
              "3d ago", "in 1 m"]
        p += ["+0", "+1", "+5", "+05", "+30", "+365", "+3650000", "+4000000", "+4000001", "+99999999999999999999",
              "+", "+ 5", "+-5", "+5d", "-5", "++5", "+five"]
        // Weekdays, with and without a qualifier.
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for n in names { for q in ["next ", "this ", "on "] { p.append(q + n) } }
        for a in ["mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun"] {
            p += [a, "next " + a]
        }
        p += ["next mo", "next tu", "next we", "next th", "next fr", "next sa", "next su", "next t", "next s",
              "next thu", "next satu", "this tu", "on th", "last fri", "next next fri", "fri next", "mo", "tu", "we",
              "th", "fr", "sa", "su", "thursd", "satu", "sunda", "mond", "wedn", "tues day", "weds", "frid"]
        // Month names, both orders.
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                      "october", "november", "december"]
        for m in months {
            let ab = String(m.prefix(3))
            p += ["\(m) 1", "\(ab) 15th", "15 \(ab)", "\(ab) 31", "29 \(ab)", "\(ab) 9 2027", "9th \(m) 27"]
        }
        p += ["sept 9", "septe 30", "novem 9", "ja 9", "ju 4", "mar 3", "ma 3", "novembers 9", "nov 0", "nov 00",
              "nov 99", "nov 123", "nov 9 7", "nov 9 027", "nov 9 0099", "nov 9 100", "nov 9 20270", "nov 9 2027 x",
              "nov", "9 nov 2027", "feb 29", "29 feb", "feb 29 2028", "feb 29 2027", "february 30", "the nov 9",
              "nov the 9", "on nov 9", "nov 9st", "nov 9nd", "nov 9xx", "Nov. 9th, 2027", "NOVEMBER 9", "  nov   9  ",
              "nov,9", "nov.9", "nov-9", "9-nov", "9novem", "nov9", "dec 31", "jan 1", "jan 1 0", "jan 1 00", "dec 25 99"]
        // ISO and numeric dates.
        p += ["2026-11-09", "2026-1-9", "2026-01-09", "2026-02-29", "2028-02-29", "2026-02-30", "0000-01-01",
              "9999-12-31", "10000-01-01", "2026-13-01", "2026-11-9-1", "2026-11", "26-11-09", "2026/11/09",
              "2026-11-09 ", "2026–11–09", "2026-011-09"]
        p += ["11/9", "11/9/27", "11/9/2027", "1/2", "01/02", "13/1", "1/13", "31/12", "12/31", "2/29", "29/2",
              "2/29/2027", "2/29/28", "11/9/7", "11/9/02027", "11/", "/9", "11/9/", "0/9", "9/0", "11/31", "31/11",
              "12/32", "11/9/00", "11/9/99", "11/9/100", "11/9/0099", "111/9", "11/099", "1/1", "12/12", "11 / 9",
              "11//9", "11/9/27/1"]
        // The bare day of the month.
        p += ["1", "9", "09", "9th", "1st", "2nd", "3rd", "4th", "21st", "31", "31st", "30", "29", "29th", "28", "0",
              "00", "32", "100", "the 9th", "the 31st", "the 1", "the", "the the 9", "9 th", "9TH", "the 30th", "009"]
        // Case, punctuation and whitespace, Unicode lookalikes, rejects.
        p += ["TODAY", "Today", "  today  ", "to day", "tomorrow.", "tomorrow,", ",fri", "fri.", "\tfri\n",
              "Next  Week", "NEXT FRI", "next\u{00A0}fri", "next\u{3000}fri", "next\u{2003}fri", "\u{0085}fri",
              "\u{FEFF}fri", "fri\u{200B}", "\u{2028}fri", "FRİ", "ＦＲＩ", "１１/９", "e\u{301}", "nov 9\u{301}",
              "fri \u{301}", "\r\nfri", "", "   ", ",", ".", "..", ", ,", "foo", "noon", "eod", "yeste", "tomorrows",
              "todays", "nextweek", "next  week", "this week", "this", "next", "next w", "next we", "next wee",
              "next weeke", "next m", "next mon", "next mont", "on", "o", "n", "x", "q", "z", "Ⅸ", "٩", "9\u{FE0F}",
              "fri\u{0}", "thisweekend"]
        var seen: Set<String> = []
        return p.filter { seen.insert($0).inserted }
    }

    static func build() -> (J, Int) {
        var cases: [J] = []
        for text in phrases() {
            // The order only reads in numeric dates; both orders for any text with a digit in it.
            let orders: [(String, DatePhrase.NumericOrder)] = text.contains(where: { $0.isNumber })
                ? [("md", .monthFirst), ("dm", .dayFirst)] : [("md", .monthFirst)]
            for d in referenceDays {
                for (name, order) in orders {
                    let r = DatePhrase.match(text, today: date(d), numericOrder: order)
                    cases.append(.obj(["text": .str(text), "today": .str(d), "order": .str(name), "expect": .s(r?.string)]))
                }
            }
        }
        return (.obj(["cases": .arr(cases)]), cases.count)
    }
}
