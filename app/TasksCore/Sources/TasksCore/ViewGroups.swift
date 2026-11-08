import Foundation

/// How the views place, group and order their rows by date, and the checkbox ring's cue (design/INTERACTIONS-v2.md
/// §22, §24): the Mac's rules, moved verbatim from app/Tasks/TaskList/ViewLayout.swift (`ViewItems.upDay`, `ViewNames`,
/// the Upcoming, Completed and Trash buckets of `buildView`) and app/Tasks/TaskList/RowDates.swift (`CheckLayer.Cue`),
/// so every client groups the same way. Pure calendar-date arithmetic: `today` is always passed in.
public enum ViewGroups {
    // MARK: Upcoming

    /// The day a task reaches Today: the earlier of its dates (SPEC §4, either date brings it in).
    public static func upDay(when: CalendarDate?, deadline: CalendarDate?) -> CalendarDate? {
        switch (when, deadline) {
        case let (w?, d?): return min(w, d)
        case let (w?, nil): return w
        case let (nil, d?): return d
        default: return nil
        }
    }

    /// What orders a row in Upcoming: the day it reaches Today, its list's place in the sidebar, its key in its list.
    public struct UpcomingKey: Hashable, Sendable {
        public var id: EntityID
        public var day: CalendarDate
        public var rank: Int
        public var order: String

        public init(id: EntityID, day: CalendarDate, rank: Int, order: String) {
            self.id = id
            self.day = day
            self.rank = rank
            self.order = order
        }
    }

    /// Upcoming's row order: by day, then by list in sidebar order, then by the key in the list.
    public static func upcomingPrecedes(_ a: UpcomingKey, _ b: UpcomingKey) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.rank != b.rank { return a.rank < b.rank }
        return orderPrecedes(a.order, a.id, b.order, b.id)
    }

    /// A group of rows under its label.
    public struct Group: Hashable, Sendable {
        public enum Kind: Hashable, Sendable { case day, month }
        /// "d:2026-11-03" for a day, "m:2026-12" for a month.
        public var id: String
        public var kind: Kind
        /// A day group's day.
        public var day: CalendarDate?
        /// "Tomorrow", "Wednesday", "Later in November", "January 2027"; "Today", "Yesterday", "October".
        public var name: String
        /// A day group's date: "Nov 3".
        public var sub: String?

        public init(id: String, kind: Kind, day: CalendarDate?, name: String, sub: String?) {
            self.id = id
            self.kind = kind
            self.day = day
            self.name = name
            self.sub = sub
        }
    }

    /// The seven days Upcoming always shows, empty or not: tomorrow to a week from today.
    public static func upcomingDays(today: CalendarDate) -> [CalendarDate] {
        (1...7).map { today.adding(days: $0) }
    }

    /// Upcoming's group for a day after today: the next seven days each by name ("Tomorrow", then the weekday), then a
    /// group per month, "Later in" for the rest of the seventh day's month (dc:2269–2296).
    public static func upcoming(_ day: CalendarDate, today: CalendarDate) -> Group {
        let horizon = today.adding(days: 7)
        if day <= horizon {
            let n = today.days(until: day)
            let name = n == 1 ? "Tomorrow" : weekday(day)
            return Group(id: "d:" + day.string, kind: .day, day: day, name: name, sub: DateLabel.monthDay(day))
        }
        let name = (day.year == horizon.year && day.month == horizon.month ? "Later in " : "")
            + month(year: day.year, month: day.month, today: today)
        return Group(id: "m:\(day.year)-\(day.month)", kind: .month, day: nil, name: name, sub: nil)
    }

    /// A day inside one of Upcoming's month groups (ROW-DENSITY.md direction C, the user, 2026-11-08): a month lists
    /// its days too, each with a smaller label ("Wednesday  Nov 18") that takes +, a double-click and a drop like a day
    /// group's, so no row repeats the day it's filed under. Only days with tasks get one. Its id is a day group's
    /// ("d:2026-11-18"), so a day keeps its label as it moves into the first week at midnight.
    public static func upcomingDayInMonth(_ day: CalendarDate) -> Group {
        Group(id: "d:" + day.string, kind: .day, day: day, name: weekday(day), sub: DateLabel.monthDay(day))
    }

    // MARK: Completed and Trash

    /// Completed's and Trash's group for the local day a task was completed or deleted: a group per day for the last
    /// week ("Today", "Yesterday", the weekday), then per month (dc:2297–2313). A stamp ahead of today (another
    /// device's clock) is today's, in today's group (the user, 2026-11-02; the Mac's code read it as its weekday).
    public static func past(_ day: CalendarDate, today: CalendarDate) -> Group {
        let day = min(day, today)
        let n = day.days(until: today)
        if n < 7 {
            let name = n == 0 ? "Today" : n == 1 ? "Yesterday" : weekday(day)
            return Group(id: "d:" + day.string, kind: .day, day: day, name: name, sub: DateLabel.monthDay(day))
        }
        return Group(id: "m:\(day.year)-\(day.month)", kind: .month, day: nil,
                     name: month(year: day.year, month: day.month, today: today), sub: nil)
    }

    // MARK: Names (the prototype's WDL and MOL)

    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]

    /// "December", or "January 2027" in another year.
    public static func month(year: Int, month: Int, today: CalendarDate) -> String {
        months[month - 1] + (year != today.year ? " \(year)" : "")
    }

    /// "Wednesday".
    public static func weekday(_ d: CalendarDate) -> String { weekdays[d.weekday - 1] }

    // MARK: The checkbox ring

    /// An open task's ring (§24): its deadline past (late) or today (due); planned for today when its When is today or
    /// earlier, except in Today, where every task is. Done, trashed and new tasks have none: they take `RingCue()`.
    /// This isn't `Today.datesArrived`: a deadline gives the ring its tone, not "planned".
    public struct RingCue: Hashable, Sendable {
        public enum Deadline: Hashable, Sendable { case late, due }
        public var deadline: Deadline?
        public var planned = false

        public init() {}

        public init(when: CalendarDate?, deadline: CalendarDate?, today: CalendarDate, inToday: Bool) {
            if let d = deadline, d <= today { self.deadline = d < today ? .late : .due }
            planned = !inToday && when.map { $0 <= today } == true
        }
    }
}
