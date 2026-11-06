import SwiftUI
import WidgetKit
import TasksCore

// The lock screen's widgets (WIDGETS.md §1.1, MVP 4), read-only, as the user asked: Today's open tasks first, no counts
// ("I want to prioritize showing the list items"), and a New Task button. The lock screen draws them vibrant (the
// wallpaper's tint, one ink), so every cue is in words or shape, never in colour alone. Mock-ups: Lock-Dark,
// Lock-Light (https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi), with the counts and the gauge taken out.

/// Today on the lock screen: the first open task in the date line (inline), or as many as fit (rectangular). Both open
/// Today. The same provider as the home screen's Today: the feed, at now and at the next midnights.
struct TodayLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetGroup.Kind.todayLock, provider: TodayProvider()) { entry in
            TodayLockView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Today’s tasks, first things first.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}

struct TodayLockView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryInline { LockInlineView(content: entry.content) } else {
                LockRectangularView(content: entry.content)
            }
        }
        .widgetURL(DeepLink.today.url)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// What the lock screen says about Today: the open tasks in Today's order, each with a word when it's urgent, or why
/// there are none. Pure, so it's tested without a lock screen.
struct LockToday: Hashable {
    struct Row: Hashable, Identifiable {
        let id: EntityID
        let title: String
        /// "2d ago" for a deadline past, "Due" for one today; nil otherwise (the ring alone).
        let word: String?
    }

    let rows: [Row]
    /// When there are no rows: "All done" (something was completed today), "Nothing today", or the set-up line.
    let empty: String?

    init(_ content: TodayEntry.Content) {
        switch content {
        case .setUp:
            rows = []
            empty = "Open Tasks to set up"
        case let .today(s):
            rows = s.open.map { r in
                let word: String? = switch r.cue {
                case .late: r.chip?.text
                case .due: "Due"
                case .planned, .none: nil
                }
                return Row(id: r.id, title: r.title, word: word)
            }
            empty = rows.isEmpty ? (s.done.isEmpty ? "Nothing today" : "All done") : nil
        }
    }

    /// How many rows fit in `height`.
    static func fit(_ height: CGFloat) -> Int { max(1, Int((height + LM.gap) / (LM.row + LM.gap))) }

    /// The rows as VoiceOver reads them: "Email Prof. Lin, 2d ago. Problem set 6, Due."
    func spoken(_ rows: [Row]) -> String {
        rows.map { [$0.title, $0.word].compactMap { $0 }.joined(separator: ", ") }.joined(separator: ". ")
    }
}

/// The lock screen's metrics.
enum LM {
    static let row: CGFloat = 18
    static let gap: CGFloat = 1
    static let ring: CGFloat = 9
}

/// The date line: "☀ Email Prof. Lin" (the system cuts it to fit).
struct LockInlineView: View {
    let content: TodayEntry.Content

    var body: some View {
        let t = LockToday(content)
        let first = t.rows.first
        Label {
            if let first { Text(first.title) } else { Text(t.empty ?? "") }
        } icon: {
            Image(systemName: first == nil && t.empty == "All done" ? "sun.max.fill" : "sun.max")
        }
        .accessibilityLabel(first.map { "Today: " + t.spoken([$0]) } ?? (t.empty ?? ""))
    }
}

/// As many of Today's open tasks as fit, each with its ring and the word for an urgent one; no header and no count.
struct LockRectangularView: View {
    let content: TodayEntry.Content

    var body: some View {
        let t = LockToday(content)
        if let empty = t.empty {
            HStack(spacing: 6) {
                Image(systemName: empty == "All done" ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 15, weight: .semibold))
                Text(empty).font(.system(size: 15, weight: .semibold)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            GeometryReader { g in
                let shown = Array(t.rows.prefix(LockToday.fit(g.size.height)))
                VStack(alignment: .leading, spacing: LM.gap) {
                    ForEach(shown) { r in LockRow(r: r) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today: " + t.spoken(shown))
            }
        }
    }
}

struct LockRow: View {
    let r: LockToday.Row

    var body: some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(lineWidth: 1.5).frame(width: LM.ring, height: LM.ring)
            Text(r.title).font(.system(size: 14)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let w = r.word {
                Text(w).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
            }
        }
        .frame(height: LM.row)
    }
}

// MARK: - New Task

/// The lock screen's circular New Task: a + that opens the app on a new task in Today.
struct NewTaskLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetGroup.Kind.newTask, provider: StillProvider()) { _ in
            NewTaskLockView()
        }
        .configurationDisplayName("New Task")
        .description("Opens Tasks on a new task.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct NewTaskLockView: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 26, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(DeepLink.new(list: nil).url)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .accessibilityLabel("New task")
    }
}

/// One entry, never reloaded: for a widget that shows no data.
struct StillProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
        completion(Entry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}
