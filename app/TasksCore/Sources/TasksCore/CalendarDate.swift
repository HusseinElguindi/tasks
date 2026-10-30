import Foundation

/// A calendar day with no time and no time zone, serialized as `"YYYY-MM-DD"` (spec §2).
///
/// Stored packed as `yyyymmdd`, so comparing two dates is one integer comparison.
public struct CalendarDate: Hashable, Comparable, Sendable {
    public let packed: Int32

    public var year: Int { Int(packed / 10_000) }
    public var month: Int { Int(packed / 100 % 100) }
    public var day: Int { Int(packed % 100) }

    public init?(year: Int, month: Int, day: Int) {
        guard (0...9999).contains(year), (1...12).contains(month),
              (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
        packed = Int32(year * 10_000 + month * 100 + day)
    }

    /// Parses exactly `"YYYY-MM-DD"` naming a real date; anything else is nil.
    public init?(_ string: String) {
        var s = string
        guard let parsed = s.withUTF8(Self.parse) else { return nil }
        self = parsed
    }

    private static func parse(_ b: UnsafeBufferPointer<UInt8>) -> CalendarDate? {
        guard b.count == 10, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-") else { return nil }
        func num(_ from: Int, _ count: Int) -> Int? {
            var v = 0
            for i in from..<(from + count) {
                let c = b[i]
                guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { return nil }
                v = v * 10 + Int(c - UInt8(ascii: "0"))
            }
            return v
        }
        guard let y = num(0, 4), let m = num(5, 2), let d = num(8, 2) else { return nil }
        return CalendarDate(year: y, month: m, day: d)
    }

    public var string: String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool { a.packed < b.packed }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: Calendar arithmetic (only at the edges: "today", pickers, labels)

    /// The local calendar date of an instant, in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDate {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(from: DateComponents(year: year, month: month, day: day))!
        return CalendarDate(utc.date(byAdding: .day, value: days, to: d)!, calendar: utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: CalendarDate) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let a = utc.date(from: DateComponents(year: year, month: month, day: day))!
        let b = utc.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        return utc.dateComponents([.day], from: a, to: b).day!
    }

    /// 1 = Sunday … 7 = Saturday.
    public var weekday: Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.component(.weekday, from: utc.date(from: DateComponents(year: year, month: month, day: day))!)
    }
}

extension CalendarDate: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = CalendarDate(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a YYYY-MM-DD calendar date: \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

extension CalendarDate: CustomStringConvertible {
    public var description: String { string }
}
