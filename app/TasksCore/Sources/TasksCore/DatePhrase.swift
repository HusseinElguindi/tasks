import Foundation

// Typed dates and date labels for the v2 UI (INTERACTIONS-v2 §11, §21), ported from the reference prototype
// (`design/prototype-v2/Main.dc.html`, the date helpers through `matchDate`). Everything here is calendar-date
// arithmetic on `CalendarDate`: `today` is always passed in, and the time zone never matters (SPEC §2).
// The names are English, like the rest of the UI.

/// What the date popover's field reads as (INTERACTIONS-v2 §11 "Typed dates").
public enum DatePhrase {
    /// How "11/9" reads. The app passes the user's locale order (`numericOrder(for:)`); the prototype reads M/D.
    public enum NumericOrder: Sendable { case monthFirst, dayFirst }

    /// The exact reading of the whole text (prototype `parseDate`), nil if it reads as no date.
    public static func parse(_ text: String, today: CalendarDate, numericOrder: NumericOrder = .monthFirst) -> CalendarDate? {
        let s = normalize(text)
        return s.isEmpty ? nil : exact(s, today: today, order: numericOrder)
    }

    /// What the text means while it's typed (prototype `matchDate`): the exact reading, else the first of
    /// Today, Tomorrow, This Weekend, Next Week, Next Month, Monday … Sunday that starts with it
    /// ("t" → Today, "next" → Next Week, "this" → This Weekend).
    public static func match(_ text: String, today: CalendarDate, numericOrder: NumericOrder = .monthFirst) -> CalendarDate? {
        let s = normalize(text)
        guard !s.isEmpty else { return nil }
        if let d = exact(s, today: today, order: numericOrder) { return d }
        guard let phrase = phrases.first(where: { $0.hasPrefix(s) }) else { return nil }
        return exact(phrase, today: today, order: numericOrder)
    }

    /// Whether a locale writes the month or the day first in a numeric date ("M/d" in en_US, "d/M" in en_GB).
    public static func numericOrder(for locale: Locale) -> NumericOrder {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? ""
        var quoted = false  // skip 'literal text' in the pattern
        for c in format {
            if c == "'" { quoted.toggle(); continue }
            if quoted { continue }
            if c == "d" { return .dayFirst }
            if c == "M" || c == "L" { return .monthFirst }
        }
        return .monthFirst
    }

    /// This Weekend: the coming Saturday, or today on a Saturday or Sunday (prototype `weekendOf`).
    public static func weekend(from today: CalendarDate) -> CalendarDate {
        weekendDay(today) ?? .lastDate
    }

    /// Next Week: the next Monday after today, a week away on a Monday (prototype `nextWeekStart`).
    public static func nextWeek(from today: CalendarDate) -> CalendarDate {
        nextWeekday(1, after: today) ?? .lastDate
    }

    /// `months` calendar months on, keeping the day where the month has it and else its last day
    /// (Jan 31 + 1 → Feb 28; prototype `addMonths`). Saturates at the ends of `CalendarDate`'s years 0–9999.
    public static func adding(months: Int, to date: CalendarDate) -> CalendarDate {
        let n = min(max(months, -200_000), 200_000)
        return addingMonths(n, to: date) ?? (n < 0 ? .firstDate : .lastDate)
    }

    // MARK: The grammar (prototype `parseDate`)

    /// The prototype's PHRASES, in its order, as `match` tries them.
    private static let phrases = ["today", "tomorrow", "this weekend", "next week", "next month",
                                  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    private static let numberWords: [Substring: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    private static let weekdayAbbreviations: [Substring: Int] = [
        "mon": 1, "tue": 2, "tues": 2, "wed": 3, "weds": 3, "thu": 4, "thur": 4, "thurs": 4,
        "fri": 5, "sat": 6, "sun": 0,
    ]

    private static let units: Set<Substring> = [
        "d", "day", "days", "w", "wk", "wks", "week", "weeks", "mo", "mos", "month", "months", "m",
        "y", "yr", "yrs", "year", "years",
    ]

    private static let ordinalSuffixes: Set<Substring> = ["", "st", "nd", "rd", "th"]

    /// No unit reaches a representable date from more than this many of it away (years 0–9999 are ~3.65M days),
    /// so a larger count reads as no date instead of overflowing.
    private static let maxCount = 4_000_000

    /// Lowercased, with commas and periods as spaces and runs of whitespace as one space, trimmed (`normDate`).
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "." })
            .joined(separator: " ")
    }

    /// `parseDate` on normalized text. Each step is one of the prototype's patterns, in its order, matched against
    /// the whole text; the pattern is quoted above it. The text is taken word by word: normalized, it has exactly
    /// one space between words, so `\s+` is a word break and `\s*` an optional one. `\d` and `[a-z]` are ASCII.
    private static func exact(_ s: String, today: CalendarDate, order: NumericOrder) -> CalendarDate? {
        switch s {
        case "today", "tod", "tdy", "toda", "now":
            return today
        case "tomorrow", "tom", "tmr", "tmrw", "tomo", "tomor", "tomorr", "tomorro":
            return today.offset(by: 1)
        case "yesterday", "yest":
            return today.offset(by: -1)
        case "weekend", "wknd", "this weekend", "this wknd":
            return weekendDay(today)
        case "next weekend":
            // Saturday of the weekend after this one; on a Saturday or Sunday that's the coming Saturday.
            let w = today.weekdayIndex
            return nextWeekday(6, after: today)?.offset(by: w == 6 || w == 0 ? 0 : 7)
        case "next week", "next wk":
            return nextWeekday(1, after: today)
        case "next month", "next mo":
            return today.month == 12 ? CalendarDate(year: today.year + 1, month: 1, day: 1)
                                     : CalendarDate(year: today.year, month: today.month + 1, day: 1)
        default:
            break
        }
        let words = s.split(separator: " ")

        // (?:in\s+)?(\d+|a|an|one|…|ten)\s*(d|day|days|w|…|years): "3d", "in 2 weeks", "a month", "1y"
        if let (count, unit) = countAndUnit(words) {
            guard let n = numberWords[count] ?? Int(count), n <= maxCount else { return nil }
            switch unit.first {
            case "d": return today.offset(by: n)
            case "w": return today.offset(by: 7 * n)
            case "y": return addingMonths(12 * n, to: today)
            default: return addingMonths(n, to: today)
            }
        }
        // \+(\d+): "+5"
        if words.count == 1, words[0].first == "+", isDigits(words[0].dropFirst()) {
            guard let n = Int(words[0].dropFirst()), n <= maxCount else { return nil }
            return today.offset(by: n)
        }
        // (?:(next|this|on)\s+)?([a-z]+): "fri", "next fri", "this fri", "on fri", "th"
        if let (qualifier, word) = qualifiedWord(words), let w = weekday(named: word) {
            if qualifier == "next" { return nextWeekday(1, after: today)?.offset(by: (w + 6) % 7) }  // weeks start Monday
            return nextWeekday(w, after: today)
        }
        // ([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{2,4}))?: "nov 9", "november 9th", "nov 9 2027"
        if (2...3).contains(words.count), isLetters(words[0]), let day = dayOfMonth(words[1]),
           let year = optionalYear(words.dropFirst(2)), let month = monthNumber(named: words[0]) {
            return resolve(month: month, day: day, year: year, today: today)
        }
        // (\d{1,2})(?:st|nd|rd|th)?\s+([a-z]+)(?:\s+(\d{2,4}))?: "9 nov", "9th november 2027"
        if (2...3).contains(words.count), let day = dayOfMonth(words[0]), isLetters(words[1]),
           let year = optionalYear(words.dropFirst(2)), let month = monthNumber(named: words[1]) {
            return resolve(month: month, day: day, year: year, today: today)
        }
        // (\d{4})-(\d{1,2})-(\d{1,2}): "2026-11-09"
        if words.count == 1, case let p = words[0].split(separator: "-", omittingEmptySubsequences: false),
           p.count == 3, isDigits(p[0], 4...4), isDigits(p[1], 1...2), isDigits(p[2], 1...2) {
            return CalendarDate(year: Int(p[0])!, month: Int(p[1])!, day: Int(p[2])!)
        }
        // (\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?: "11/9", "11/9/27"
        if words.count == 1, case let p = words[0].split(separator: "/", omittingEmptySubsequences: false),
           (2...3).contains(p.count), isDigits(p[0], 1...2), isDigits(p[1], 1...2), let year = optionalYear(p.dropFirst(2)) {
            let (a, b) = (Int(p[0])!, Int(p[1])!)
            return order == .monthFirst ? resolve(month: a, day: b, year: year, today: today)
                                        : resolve(month: b, day: a, year: year, today: today)
        }
        // (?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?: "9", "9th", "the 9th": the next 9th of a month, this one if it isn't past
        if words.count == 1 || (words.count == 2 && words[0] == "the"), let day = dayOfMonth(words[words.count - 1]) {
            guard (1...31).contains(day) else { return nil }
            for k in 0..<3 {
                let total = today.year * 12 + today.month - 1 + k
                if let r = CalendarDate(year: total / 12, month: total % 12 + 1, day: day), r >= today { return r }
            }
            return nil
        }
        return nil
    }

    // MARK: Pieces of the patterns

    /// `(?:in\s+)?(\d+|a|an|one|…|ten)\s*(unit)`: the count and the unit, in one word ("3d", "and") or two ("3 days").
    private static func countAndUnit(_ words: [Substring]) -> (count: Substring, unit: Substring)? {
        var rest = words[...]
        if rest.count > 1, rest.first == "in" { rest = rest.dropFirst() }
        if rest.count == 2 {
            let (count, unit) = (rest[rest.startIndex], rest[rest.startIndex + 1])
            return (isDigits(count) || numberWords[count] != nil) && units.contains(unit) ? (count, unit) : nil
        }
        guard rest.count == 1, let word = rest.first else { return nil }
        let digits = word.prefix(while: isDigit)
        if !digits.isEmpty {
            return units.contains(word.dropFirst(digits.count)) ? (digits, word.dropFirst(digits.count)) : nil
        }
        // At most one number word fits: only "a" and "an" share a start, and no unit starts with "n".
        for count in numberWords.keys where word.hasPrefix(count) && units.contains(word.dropFirst(count.count)) {
            return (count, word.dropFirst(count.count))
        }
        return nil
    }

    /// `(?:(next|this|on)\s+)?([a-z]+)`
    private static func qualifiedWord(_ words: [Substring]) -> (qualifier: Substring?, word: Substring)? {
        if words.count == 1, isLetters(words[0]) { return (nil, words[0]) }
        if words.count == 2, ["next", "this", "on"].contains(words[0]), isLetters(words[1]) { return (words[0], words[1]) }
        return nil
    }

    /// `(\d{1,2})(?:st|nd|rd|th)?`: "9", "09", "9th" (any suffix fits any number, as in the prototype).
    private static func dayOfMonth(_ word: Substring) -> Int? {
        let digits = word.prefix(while: isDigit)
        guard (1...2).contains(digits.count), ordinalSuffixes.contains(word.dropFirst(digits.count)) else { return nil }
        return Int(digits)
    }

    /// `(?:\s+(\d{2,4}))?` on what follows the day: `.some(nil)` when nothing does, nil when it isn't a year.
    private static func optionalYear(_ rest: ArraySlice<Substring>) -> Substring?? {
        if rest.isEmpty { return .some(nil) }
        return rest.count == 1 && isDigits(rest[rest.startIndex], 2...4) ? .some(rest[rest.startIndex]) : nil
    }

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    private static func isDigits(_ s: Substring, _ length: ClosedRange<Int> = 1...Int.max) -> Bool {
        length.contains(s.count) && s.allSatisfy(isDigit)
    }

    private static func isLetters(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isLowercase } }

    /// A month and day with the year as typed (two digits are 20xx), or else the next one that isn't past
    /// (`resolveMonthDay`). A day the month doesn't have is no date.
    private static func resolve(month: Int, day: Int, year: Substring?, today: CalendarDate) -> CalendarDate? {
        if let year {
            let y = Int(year)!
            return CalendarDate(year: y < 100 ? y + 2000 : y, month: month, day: day)
        }
        guard let r = CalendarDate(year: today.year, month: month, day: day) else { return nil }
        return r < today ? CalendarDate(year: today.year + 1, month: month, day: day) : r
    }

    /// 0 = Sunday … 6 = Saturday: a full name, a common abbreviation, or a prefix of two or more letters that
    /// starts only one day ("th", "we"; not "t" or "s").
    private static func weekday(named word: Substring) -> Int? {
        if let i = DateNames.weekdaysLower.firstIndex(where: { $0 == word }) { return i }
        if let i = weekdayAbbreviations[word] { return i }
        guard word.count >= 2 else { return nil }
        let hits = DateNames.weekdaysLower.indices.filter { DateNames.weekdaysLower[$0].hasPrefix(word) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// 1 = January … 12 = December, from a prefix of three or more letters ("nov", "sept", "novem").
    private static func monthNumber(named word: Substring) -> Int? {
        guard word.count >= 3 else { return nil }
        return DateNames.monthsLower.firstIndex(where: { $0.hasPrefix(word) }).map { $0 + 1 }
    }

    /// The next `weekday` (0 = Sunday) strictly after today: a week away when today is that day (`nextWeekday`).
    private static func nextWeekday(_ weekday: Int, after today: CalendarDate) -> CalendarDate? {
        let n = (weekday - today.weekdayIndex + 7) % 7
        return today.offset(by: n == 0 ? 7 : n)
    }

    private static func weekendDay(_ today: CalendarDate) -> CalendarDate? {
        let w = today.weekdayIndex
        return w == 6 || w == 0 ? today : nextWeekday(6, after: today)
    }

    private static func addingMonths(_ n: Int, to date: CalendarDate) -> CalendarDate? {
        let total = date.year * 12 + date.month - 1 + n
        guard total >= 0 else { return nil }
        let (year, month) = (total / 12, total % 12 + 1)
        guard year <= 9999 else { return nil }
        return CalendarDate(year: year, month: month, day: min(date.day, CalendarDate.daysIn(month: month, year: year)))
    }
}

/// How dates read in rows, the detail pane, the popover and the CLI (INTERACTIONS-v2 §24, the "Nd left" wording).
public enum DateLabel {
    /// A deadline's urgency (§24 Tones): late (past), due (today), soon (tomorrow: only its flag is tinted), neutral.
    public enum Tone: Sendable { case neutral, soon, due, late }

    /// How far ahead a date counts in days ("3d left", "in 3d"); farther, it reads as the date (prototype `LEFT_MAX`).
    public static let countdownDays = 14

    /// A row's When: "Today" (today or past: a past When carries forward), "Tomorrow", "in 2d" … "in 14d", then
    /// "Nov 15", or "Jan 3, 2027" in another year. A plan, not a countdown: never "left" (prototype `whenChipText`).
    public static func whenChip(_ d: CalendarDate, today: CalendarDate) -> String {
        let n = today.daysTo(d)
        if n <= 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n <= countdownDays { return "in \(n)d" }
        return monthDayYear(d, today: today)
    }

    /// A Deadline: "2d ago" when overdue, in days at any distance (late); "Due today" (due); "1d left" (soon) …
    /// "14d left", whole days not counting the deadline's own day; then "Nov 15", or "Jan 3, 2027" in another year
    /// (prototype `deadlineChip`).
    public static func deadlineChip(_ d: CalendarDate, today: CalendarDate) -> (text: String, tone: Tone) {
        let n = today.daysTo(d)
        if n < 0 { return ("\(-n)d ago", .late) }
        if n == 0 { return ("Due today", .due) }
        return (n <= countdownDays ? "\(n)d left" : monthDayYear(d, today: today), n == 1 ? .soon : .neutral)
    }

    /// A deadline in words, for tooltips, the detail pane and the CLI: "2 days overdue" (then weeks, months and years,
    /// as `relative`'s past: "10 months overdue", "1 year overdue"), "due today", "1 day left" … "14 days left", then
    /// how far it is ("in 2 weeks") (prototype `dueRelText`, §25).
    public static func deadlineWords(_ d: CalendarDate, today: CalendarDate) -> String {
        let n = today.daysTo(d)
        if n < 0 { return -n == 1 ? "1 day overdue" : pastSpan(-n, oneYear: "1 year") + " overdue" }
        if n == 0 { return "due today" }
        if n <= countdownDays { return n == 1 ? "1 day left" : "\(n) days left" }
        return relative(d, today: today)
    }

    /// A row's date tooltip: "When: Sun, Nov 1 · tomorrow", "Deadline: Sat, Nov 14 · 14 days left" (prototype
    /// `dateTip`).
    public static func tooltip(deadline: Bool, _ d: CalendarDate, today: CalendarDate) -> String {
        (deadline ? "Deadline: " : "When: ") + long(d, today: today) + " · "
            + (deadline ? deadlineWords(d, today: today) : relative(d, today: today))
    }

    /// The full date: "Fri, Nov 6", with ", 2027" in another year (prototype `longDate`).
    public static func long(_ d: CalendarDate, today: CalendarDate) -> String {
        DateNames.weekdays[d.weekdayIndex] + ", " + monthDayYear(d, today: today)
    }

    /// The relative date: "today", "tomorrow", "yesterday"; "in N days" up to 14 days, "in N weeks" under 60, "in N
    /// months" under a year, then "in a year" or "in N years"; the past the same way, "N days ago" under 14 days, then
    /// weeks, months, "a year ago" and "N years ago". N is rounded (prototype `relText`, §24, §25).
    public static func relative(_ d: CalendarDate, today: CalendarDate) -> String {
        let n = today.daysTo(d)
        switch n {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...countdownDays: return "in \(n) days"
        case 15..<60: return "in \(rounded(n, over: 7)) weeks"
        case 60..<365: return "in \(rounded(n, over: 30)) months"
        case 365...: let y = rounded(n, over: 365); return y == 1 ? "in a year" : "in \(y) years"
        default: return pastSpan(-n, oneYear: "a year") + " ago"
        }
    }

    /// How long ago, `d` ≥ 2 days: days under two weeks, then weeks under 60 days, months under a year, then years
    /// (prototype `pastSpan`).
    private static func pastSpan(_ d: Int, oneYear: String) -> String {
        switch d {
        case ..<14: return "\(d) days"
        case ..<60: return "\(rounded(d, over: 7)) weeks"
        case ..<365: return "\(rounded(d, over: 30)) months"
        default: let y = rounded(d, over: 365); return y == 1 ? oneYear : "\(y) years"
        }
    }

    /// "Nov 9" (prototype `md`).
    public static func monthDay(_ d: CalendarDate) -> String {
        DateNames.months[d.month - 1] + " " + String(d.day)
    }

    /// The popover's month: "November 2026". `month` is 1–12.
    public static func monthTitle(year: Int, month: Int) -> String {
        DateNames.monthsLong[month - 1] + " " + String(year)
    }

    /// "Nov 9", or "Nov 9, 2027" when the year isn't today's (prototype `mdy`).
    private static func monthDayYear(_ d: CalendarDate, today: CalendarDate) -> String {
        monthDay(d) + (d.year != today.year ? ", " + String(d.year) : "")
    }

    /// `Math.round(n / d)` for n ≥ 0 (halves round up).
    private static func rounded(_ n: Int, over d: Int) -> Int { (2 * n + d) / (2 * d) }
}

/// The prototype's WD, MO and MOL.
private enum DateNames {
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let weekdaysLower = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthsLong = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
    static let monthsLower = monthsLong.map { $0.lowercased() }
}

// Integer day arithmetic (proleptic Gregorian, H. Hinnant's days_from_civil / civil_from_days). It agrees with
// `adding(days:)`, `days(until:)` and `weekday`, but never traps: typed text can ask for "+99999999", and a date
// past CalendarDate's years 0–9999 is nil here instead of a crash.
extension CalendarDate {
    fileprivate static let firstDate = CalendarDate(year: 0, month: 1, day: 1)!
    fileprivate static let lastDate = CalendarDate(year: 9999, month: 12, day: 31)!

    /// Days since 1970-01-01.
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The date `dayNumber` days after 1970-01-01; nil outside years 0–9999.
    public init?(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (month <= 2 ? 1 : 0), month: month, day: doy - (153 * mp + 2) / 5 + 1)
    }

    /// 0 = Sunday … 6 = Saturday (1970-01-01 was a Thursday).
    var weekdayIndex: Int { ((dayNumber + 4) % 7 + 7) % 7 }

    func offset(by days: Int) -> CalendarDate? { CalendarDate(dayNumber: dayNumber + days) }

    func daysTo(_ other: CalendarDate) -> Int { other.dayNumber - dayNumber }
}
