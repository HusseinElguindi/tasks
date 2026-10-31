import Foundation

/// "Today" as the Mac sees it: the local calendar date plus the instants where that day starts and ends,
/// so `localDate(completedAt) == today` is two integer comparisons.
public struct Day: Hashable, Sendable {
    public let date: CalendarDate
    /// Epoch ms of local midnight starting `date`.
    public let start: Int
    /// Epoch ms of the next local midnight.
    public let end: Int

    public init(containing now: Date, calendar: Calendar = .current) {
        date = CalendarDate(now, calendar: calendar)
        let startDate = date.startDate(in: calendar)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        start = Int((startDate.timeIntervalSince1970 * 1000).rounded())
        end = Int((endDate.timeIntervalSince1970 * 1000).rounded())
    }

    public func contains(ms: Int) -> Bool { ms >= start && ms < end }
}

/// The Today predicate (spec §4).
public enum Today {
    /// The date half: either date has arrived. A heading never arrives (design/INTERACTIONS-v2.md §23).
    @inline(__always)
    public static func datesArrived(_ t: TaskItem, today: CalendarDate) -> Bool {
        if t.isHeading { return false }
        if let w = t.when, w <= today { return true }
        if let d = t.deadline, d <= today { return true }
        return false
    }

    /// ```
    /// not task.deleted and task.list exists and task.list.archivedAt == nil
    /// and (task.completedAt == nil or localDate(task.completedAt) == today)
    /// and ((task.when != nil and task.when <= today) or (task.deadline != nil and task.deadline <= today))
    /// ```
    public static func contains(_ t: TaskItem, list: TaskList?, day: Day) -> Bool {
        guard !t.deleted, let list, list.archivedAt == nil else { return false }
        if let c = t.completedAt, !day.contains(ms: c) { return false }
        return datesArrived(t, today: day.date)
    }
}

/// The deadline badge a row shows (spec §4): overdue in danger, due today in attention.
public enum DeadlineStatus: Hashable, Sendable {
    case overdue(days: Int)
    case dueToday
    case upcoming(CalendarDate)

    public init?(deadline: CalendarDate?, today: CalendarDate) {
        guard let deadline else { return nil }
        if deadline < today { self = .overdue(days: deadline.days(until: today)) }
        else if deadline == today { self = .dueToday }
        else { self = .upcoming(deadline) }
    }
}
