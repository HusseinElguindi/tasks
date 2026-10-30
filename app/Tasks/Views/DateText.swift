import Foundation
import TasksCore

/// Labels for calendar dates, and the typed-date parser in the date popover. Calendar dates have no time zone, so
/// formatting runs in UTC on the date's own year/month/day.
enum DateText {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let weekday = formatter("EEE")
    private static let monthDay = formatter("MMMd")
    private static let monthDayYear = formatter("yMMMd")
    private static let weekdayMonthDay = formatter("EEEMMMd")
    private static let monthYear = formatter("yMMMM")

    static func date(_ d: CalendarDate) -> Date { utc.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12))! }

    /// Row chips: "Today", "Tomorrow", "Mon" within the week ahead, "Nov 9", "Nov 9, 2027".
    static func short(_ d: CalendarDate, today: CalendarDate) -> String {
        let days = today.days(until: d)
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days > 1 && days < 7 { return weekday.string(from: date(d)) }
        return d.year == today.year ? monthDay.string(from: date(d)) : monthDayYear.string(from: date(d))
    }

    /// Detail chips: "Today, Oct 30", "Mon, Nov 2".
    static func long(_ d: CalendarDate, today: CalendarDate) -> String {
        let days = today.days(until: d)
        let md = d.year == today.year ? monthDay.string(from: date(d)) : monthDayYear.string(from: date(d))
        if days == 0 { return "Today, \(md)" }
        if days == 1 { return "Tomorrow, \(md)" }
        return d.year == today.year ? weekdayMonthDay.string(from: date(d)) : monthDayYear.string(from: date(d))
    }

    /// The Today pane's subtitle: "Fri, Oct 30".
    static func header(_ d: CalendarDate) -> String { weekdayMonthDay.string(from: date(d)) }

    static func month(_ d: CalendarDate) -> String { monthYear.string(from: date(d)) }

    static func weekdayName(_ d: CalendarDate) -> String { weekday.string(from: date(d)) }

    /// "In 3 days", "Tomorrow", "Today", "Yesterday", "3 days ago".
    static func relative(_ d: CalendarDate, today: CalendarDate) -> String {
        let days = today.days(until: d)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...: return "In \(days) days"
        default: return "\(-days) days ago"
        }
    }

    /// The next Monday after today.
    static func nextWeek(from today: CalendarDate) -> CalendarDate {
        let offset = (9 - today.weekday) % 7 // weekday: 1 = Sunday … 7 = Saturday; Monday is 2
        return today.adding(days: offset == 0 ? 7 : offset)
    }

    // MARK: Typed dates: "today", "tom", "fri", "next week", "nov 9", "9 nov", "11/9", "2026-11-09", "3d", "2w", "+5"

    static func parse(_ input: String, today: CalendarDate) -> CalendarDate? {
        let s = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let exact = CalendarDate(s) { return exact }
        switch s {
        case "today", "tod", "now": return today
        case "tomorrow", "tom", "tmr", "tmrw": return today.adding(days: 1)
        case "yesterday": return today.adding(days: -1)
        case "next week", "nw": return nextWeek(from: today)
        default: break
        }
        // Offsets: 3d, 2w, +5, in 3 days
        let digits = s.filter(\.isNumber)
        if let n = Int(digits), !digits.isEmpty {
            let rest = s.replacingOccurrences(of: digits, with: "").replacingOccurrences(of: "in", with: "")
                .trimmingCharacters(in: .whitespaces)
            switch rest {
            case "d", "day", "days", "+", "": if s.hasPrefix("+") || rest.hasPrefix("d") { return today.adding(days: n) }
            case "w", "wk", "week", "weeks": return today.adding(days: 7 * n)
            case "m", "mo", "month", "months":
                let total = today.month - 1 + n
                let y = today.year + total / 12, m = total % 12 + 1
                return CalendarDate(year: y, month: m, day: min(today.day, CalendarDate.daysIn(month: m, year: y)))
            default: break
            }
        }
        // Weekdays: the next one (today counts).
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let i = weekdays.firstIndex(where: { s.hasPrefix($0) && s.count <= 9 }) {
            let offset = ((i + 1) - today.weekday + 7) % 7
            return today.adding(days: offset)
        }
        // Month and day, either order, or m/d.
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let words = s.replacingOccurrences(of: ",", with: " ").split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "." })
        var month: Int? = nil, day: Int? = nil, year: Int? = nil
        if words.count >= 2, let m = Int(words[0]), let d = Int(words[1]), (1...12).contains(m) {
            month = m
            day = d
            if words.count >= 3 { year = Int(words[2]) }
        } else {
            for w in words {
                if let i = months.firstIndex(where: { w.hasPrefix($0) }) { month = i + 1 }
                else if let n = Int(w) { if n > 31 { year = n } else if day == nil { day = n } }
            }
        }
        guard let m = month, let d = day else { return nil }
        if let y = year { return CalendarDate(year: y < 100 ? 2000 + y : y, month: m, day: d) }
        guard let thisYear = CalendarDate(year: today.year, month: m, day: d) else { return nil }
        return thisYear >= today ? thisYear : CalendarDate(year: today.year + 1, month: m, day: d)
    }
}
