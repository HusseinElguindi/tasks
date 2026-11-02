import Foundation

struct TaskList: Identifiable, Hashable {
    let id: String
    var name: String
    var mono: String
    var hue: ListHue
    var notes: String = ""
    var created: Date
    var deletedAt: Date? = nil
    var order: Int
}

struct Heading: Identifiable, Hashable {
    let id: String
    var listID: String
    var title: String
    var order: Int
}

struct TaskItem: Identifiable, Hashable {
    let id: String
    var title: String
    var notes: String = ""
    var listID: String
    var headingID: String? = nil
    var when: Date? = nil
    var deadline: Date? = nil
    var completedAt: Date? = nil
    var deletedAt: Date? = nil
    var created: Date
    var order: Int
    /// Deleted because its list was: it shows inside the list's row in Trash and comes back with it.
    var deletedWithList = false

    var isDone: Bool { completedAt != nil }
    var isTrashed: Bool { deletedAt != nil }
}

/// What a list pane shows: one of the four views, Today, or a list.
enum Source: Hashable, Identifiable {
    case today, upcoming, undated, completed, trash
    case list(String)

    var id: String {
        switch self {
        case .today: "today"
        case .upcoming: "upcoming"
        case .undated: "undated"
        case .completed: "completed"
        case .trash: "trash"
        case let .list(id): "list:" + id
        }
    }

    init?(id: String) {
        switch id {
        case "today": self = .today
        case "upcoming": self = .upcoming
        case "undated": self = .undated
        case "completed": self = .completed
        case "trash": self = .trash
        default:
            if id.hasPrefix("list:") { self = .list(String(id.dropFirst(5))) } else { return nil }
        }
    }

    var isView: Bool { if case .list = self { false } else { true } }
    /// Completed and Trash have no +.
    var canAdd: Bool { self != .completed && self != .trash }
}

enum DateKind: String, Identifiable { case when, deadline; var id: String { rawValue } }

/// A deadline's urgency: late (past), due (today), soon (tomorrow), later.
enum Tone { case late, due, soon, later }

// MARK: - Days

enum Day {
    static var cal: Calendar { Calendar.current }
    static var today: Date { cal.startOfDay(for: Date()) }
    static func offset(_ n: Int, from d: Date = today) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
    static func diff(_ d: Date) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0 }
    static func start(_ d: Date) -> Date { cal.startOfDay(for: d) }

    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    static func fmt(_ f: String, _ d: Date) -> String {
        if let df = formatters[f] { return df.string(from: d) }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.setLocalizedDateFormatFromTemplate(f)
        formatters[f] = df
        return df.string(from: d)
    }
    static func weekdayShort(_ d: Date) -> String { fmt("EEE", d) }
    static func weekday(_ d: Date) -> String { fmt("EEEE", d) }
    static func monthDay(_ d: Date) -> String {
        cal.component(.year, from: d) == cal.component(.year, from: today) ? fmt("MMM d", d) : fmt("MMM d, yyyy", d)
    }
    static func full(_ d: Date) -> String {
        cal.component(.year, from: d) == cal.component(.year, from: today) ? fmt("EEE MMM d", d) : fmt("EEE MMM d yyyy", d)
    }
    static func month(_ d: Date) -> String { fmt("MMMM", d) }

    /// The quiet When after a title: Today, Tomorrow, a weekday this week, else the date.
    static func whenLabel(_ d: Date) -> String {
        let n = diff(d)
        if n <= 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n < 7 { return weekdayShort(d) }
        return monthDay(d)
    }

    static func tone(_ deadline: Date) -> Tone {
        let n = diff(deadline)
        return n < 0 ? .late : n == 0 ? .due : n == 1 ? .soon : .later
    }

    /// The deadline capsule's words.
    static func deadlineLabel(_ d: Date) -> String {
        let n = diff(d)
        if n < 0 { return "\(-n)d ago" }
        if n == 0 { return "Due today" }
        if n <= 7 { return "\(n)d left" }
        return monthDay(d)
    }

    static func relative(_ d: Date) -> String {
        let n = diff(d)
        switch n {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case let x where x > 1: return "in \(x) days"
        default: return "\(-n) days ago"
        }
    }

    /// A past day as a group label: Today, Yesterday, a weekday this week, else the month.
    static func pastGroup(_ d: Date) -> (key: String, title: String, sub: String?) {
        let n = diff(d)
        if n >= 0 { return ("d0", "Today", monthDay(d)) }
        if n == -1 { return ("d1", "Yesterday", monthDay(d)) }
        if n > -7 { return ("d\(-n)", weekday(d), monthDay(d)) }
        let c = cal.dateComponents([.year, .month], from: d)
        let sameYear = c.year == cal.component(.year, from: today)
        return ("m\(c.year!)-\(c.month!)", sameYear ? month(d) : fmt("MMMM yyyy", d), nil)
    }
}
