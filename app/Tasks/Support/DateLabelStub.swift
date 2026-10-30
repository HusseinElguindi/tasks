import Foundation
import TasksCore

// TEMPORARY: TasksCore's DateLabel (in progress) replaces this.
enum DateLabel {
    enum Tone { case neutral, due, late }
    private static let wd = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let mo = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static func monthDay(_ d: CalendarDate) -> String { "\(mo[d.month - 1]) \(d.day)" }
    static func mdy(_ d: CalendarDate, today: CalendarDate) -> String { monthDay(d) + (d.year != today.year ? ", \(d.year)" : "") }
    static func long(_ d: CalendarDate, today: CalendarDate) -> String { wd[d.weekday - 1] + ", " + mdy(d, today: today) }
    static func whenChip(_ d: CalendarDate, today: CalendarDate) -> String {
        let n = today.days(until: d)
        if n <= 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n < 7 { return wd[d.weekday - 1] }
        return mdy(d, today: today)
    }
    static func deadlineChip(_ d: CalendarDate, today: CalendarDate) -> (text: String, tone: Tone) {
        let n = today.days(until: d)
        if n < 0 { return ("Overdue · \(-n)d", .late) }
        if n == 0 { return ("Due today", .due) }
        if n == 1 { return ("Tomorrow", .neutral) }
        if n < 7 { return (wd[d.weekday - 1], .neutral) }
        return (mdy(d, today: today), .neutral)
    }
}

enum DatePhrase {
    static func weekend(from today: CalendarDate) -> CalendarDate {
        let w = today.weekday
        if w == 7 || w == 1 { return today }
        return today.adding(days: 7 - w)
    }
    static func nextWeek(from today: CalendarDate) -> CalendarDate {
        let w = today.weekday
        var n = (2 - w + 7) % 7
        if n == 0 { n = 7 }
        return today.adding(days: n)
    }
}
