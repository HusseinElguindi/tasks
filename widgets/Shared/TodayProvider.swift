import WidgetKit
import TasksCore

/// One moment of the Today widget: Today for that moment's day, or why there's nothing to show.
struct TodayEntry: TimelineEntry {
    enum Content: Hashable, Sendable {
        /// No feed: the app hasn't run since the widget was added (or the group is missing).
        case setUp
        case today(TodaySnapshot)
    }
    let date: Date
    let content: Content
}

/// Reads the feed the app wrote (with the widget's own checks from the inbox on top, for piece 3) and computes Today
/// for now and for each of the next three midnights, so Today rolls over on time without the app (WIDGETS.md §3.2,
/// §3.4). The app reloads the timeline after each feed write.
struct TodayProvider: TimelineProvider {
    /// How many midnights ahead the timeline reaches.
    static let midnights = 3

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), content: .today(.placeholder))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        let now = Date()
        completion(TodayEntry(date: now, content: Self.content(Self.overlay(), at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        completion(Self.timeline(overlay: Self.overlay(), now: Date()))
    }

    /// Now, then each of the next midnights; once they're used up the widget asks again (`.atEnd`).
    static func timeline(overlay: WidgetOverlay?, now: Date, calendar: Calendar = .current) -> Timeline<TodayEntry> {
        let start = calendar.startOfDay(for: now)
        let dates = [now] + (1...midnights).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let entries = dates.map { TodayEntry(date: $0, content: content(overlay, at: $0, calendar: calendar)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    static func content(_ overlay: WidgetOverlay?, at date: Date, calendar: Calendar = .current) -> TodayEntry.Content {
        guard let overlay else { return .setUp }
        return .today(TodaySnapshot(overlay, day: Day(containing: date, calendar: calendar)))
    }

    /// The feed, with the inbox's ops applied over it; nil when there's no feed yet.
    static func overlay() -> WidgetOverlay? {
        guard let folder = WidgetGroup.folder, let feed = WidgetFeed.read(at: WidgetFeed.url(in: folder)) else { return nil }
        return WidgetOverlay(feed: feed, ops: WidgetInbox(folder: folder).read().ops)
    }
}

extension TodaySnapshot {
    /// The gallery's stand-in while a widget loads: drawn redacted, so its words never show.
    static let placeholder: TodaySnapshot = {
        let list = ListInfo(id: "placeholder", name: "Inbox", slot: 6, monogram: "I")
        let rows = (0..<6).map { i in
            Row(id: "p\(i)", title: String(repeating: "x", count: 14 + (i * 5) % 11), list: list, cue: .planned,
                chip: nil, done: false)
        }
        return TodaySnapshot(date: CalendarDate(Date()), groups: [Group(list: list, rows: rows)], done: [])
    }()
}
