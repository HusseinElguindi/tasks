import SwiftUI
import WidgetKit
import TasksCore

// The lock screen's widgets (WIDGETS.md §1.1, MVP 4), read-only, after the approved mock-ups (Lock-Dark, Lock-Light,
// LockStates; https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi): Today's open tasks first and no counts ("I want to
// prioritize showing the list items"), and two round ones, New Task and Today. The lock screen draws them vibrant (the
// wallpaper's tint, one ink), so every cue is in words or shape, never in colour alone.

/// Today on the lock screen: the first open task in the date line (inline), or the first three (rectangular). Both
/// open Today. The same provider as the home screen's Today: the feed, at now and at the next midnights.
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
            if family == .accessoryInline { LockInlineView(t: LockToday(entry.content)) } else {
                LockRectangularView(t: LockToday(entry.content))
            }
        }
        .widgetURL(DeepLink.today.url)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
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
        /// The word as VoiceOver says it: "2 days overdue", "due today".
        let spoken: String?
    }

    /// The rectangular widget's rows.
    static let rectangularRows = 3

    let rows: [Row]
    /// When there are no rows: "All done" (today's tasks were all completed), "Nothing today" (nothing planned), or
    /// the set-up line.
    let empty: String?
    /// Whether the sun is lit: everything for today is done.
    var allDone: Bool { empty == "All done" }

    init(_ content: TodayEntry.Content) {
        switch content {
        case .setUp:
            rows = []
            empty = "Open Tasks to set up"
        case let .today(s):
            rows = s.open.map { r in
                switch r.cue {
                case .late:
                    return Row(id: r.id, title: r.title, word: r.chip?.text, spoken: r.chip?.words ?? "overdue")
                case .due:
                    return Row(id: r.id, title: r.title, word: "Due", spoken: "due today")
                case .planned, .none:
                    return Row(id: r.id, title: r.title, word: nil, spoken: nil)
                }
            }
            empty = rows.isEmpty ? AllDoneView.words(s) : nil
        }
    }

    /// The rows as VoiceOver reads them: "Today: Email Prof. Lin, 2 days overdue. Problem set 6, due today."
    func spoken(_ rows: [Row]) -> String {
        "Today: " + rows.map { [$0.title, $0.spoken].compactMap { $0 }.joined(separator: ", ") }.joined(separator: ". ")
    }
}

/// The date line: "Thu 5 ☀ Email Prof. Lin about the lab" (the system puts the date first and cuts the title to fit).
struct LockInlineView: View {
    let t: LockToday

    var body: some View {
        Label {
            Text(t.rows.first?.title ?? t.empty ?? "")
        } icon: {
            Image(systemName: t.allDone ? "sun.max.fill" : "sun.max")
        }
        .accessibilityLabel(t.rows.first.map { t.spoken([$0]) } ?? "Today: " + (t.empty ?? ""))
    }
}

/// Today's first three open tasks, each with its ring and the word for an urgent one; or the empty state, "☀ Today"
/// over "All done" or "Nothing today".
struct LockRectangularView: View {
    let t: LockToday

    var body: some View {
        Group {
            if let empty = t.empty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: t.allDone ? "sun.max.fill" : "sun.max").font(.system(size: 12, weight: .semibold))
                        Text("Today").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
                    Text(empty).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today: " + empty)
            } else {
                let shown = Array(t.rows.prefix(LockToday.rectangularRows))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { r in LockRow(r: r) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t.spoken(shown))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct LockRow: View {
    let r: LockToday.Row

    var body: some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(lineWidth: 2).frame(width: 10, height: 10)
            Text(r.title).font(.system(size: 14)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let w = r.word {
                Text(w).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
            }
        }
        .frame(height: 20)
    }
}

// MARK: - The round ones

/// The lock screen's round New Task: a circled + that opens the app on a new task in Today.
struct NewTaskLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetGroup.Kind.newTask, provider: StillProvider()) { _ in
            LockGlyphView(symbol: "plus.circle", size: 30, weight: .regular, label: "New task")
                .widgetURL(DeepLink.new(list: nil).url)
        }
        .configurationDisplayName("New Task")
        .description("Opens Tasks on a new task.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// The lock screen's round Today: the sun, which opens Today.
struct TodayCircleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetGroup.Kind.todayCircle, provider: StillProvider()) { _ in
            LockGlyphView(symbol: "sun.max", size: 32, weight: .light, label: "Open Today")
                .widgetURL(DeepLink.today.url)
        }
        .configurationDisplayName("Today")
        .description("Opens Today.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockGlyphView: View {
    let symbol: String
    let size: CGFloat
    let weight: Font.Weight
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            .accessibilityLabel(label)
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
