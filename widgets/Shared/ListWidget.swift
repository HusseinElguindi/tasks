import AppIntents
import SwiftUI
import WidgetKit
import TasksCore

// The List widget (WIDGETS.md §1.1, MVP 3; mock-ups ListMedium, ListLarge): one list's open tasks in its order, read-only.
// Medium shows five rows; large shows as many as fit, with its headings as small labels and "N more". The list is
// the widget's configuration (Edit Widget), chosen from the feed's live lists; that's configuration, not an action, so
// it needs no entitlement. A tap opens the list; the + a new task in it.

// MARK: - The list, as the widget draws it

/// A list's open tasks from the feed, in its order, with the headings among them; or why there are none.
struct ListSnapshot: Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case items([WidgetItem])
        /// The list has no open tasks.
        case empty
        /// The list isn't in the feed: deleted, in the Trash, or gone.
        case trash
    }

    let list: TodaySnapshot.ListInfo
    let content: Content
    /// Whether the feed holds all of the list's open tasks. It carries the first `WidgetFeed.listTopCount`, so when
    /// that many are there, there may be more than it knows, and "N more" reads "N+ more".
    let complete: Bool

    init(list: TodaySnapshot.ListInfo, content: Content, complete: Bool = true) {
        self.list = list
        self.content = content
        self.complete = complete
    }

    init(_ overlay: WidgetOverlay, list id: EntityID, name: String? = nil, day: Day) {
        let today = day.date
        guard overlay.lists.contains(where: { $0.id == id }) else {
            let n = name ?? ""
            self.init(list: .init(id: id, name: n.isEmpty ? "Untitled" : n, slot: 6,
                                  monogram: TodaySnapshot.monogram(for: n)), content: .trash)
            return
        }
        let info = TodaySnapshot.info(id, in: overlay)
        // Completed tasks are gone from the widgets (the user); so is a heading with nothing open under it.
        var items: [WidgetItem] = []
        for t in overlay.top(of: id) where t.completedAt == nil {
            if t.isHeading {
                if let last = items.last, !last.isTask { items.removeLast() }
                let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(.label(id: t.id, name: title.isEmpty ? "Untitled" : title, tile: nil))
            } else {
                items.append(.task(TodaySnapshot.row(t, list: info, today: today, showsWhen: true)))
            }
        }
        while let last = items.last, !last.isTask { items.removeLast() }
        let tasks = items.filter(\.isTask).count
        self.init(list: info, content: items.isEmpty ? .empty : .items(items),
                  complete: tasks < WidgetFeed.listTopCount)
    }

    /// The tasks alone, for medium (no labels).
    var rows: [TodaySnapshot.Row] {
        guard case let .items(items) = content else { return [] }
        return items.compactMap { if case let .task(r) = $0 { r } else { nil } }
    }

    /// "3 more", or "3+ more" when the feed may not hold them all.
    func more(_ n: Int) -> String { complete ? "\(n) more" : "\(n)+ more" }
}

// MARK: - Choosing the list

/// A list the widget can show: one of the feed's live lists, in sidebar order.
struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()

    let id: EntityID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ListQuery: EntityQuery {
    /// The feed's lists; one that's gone keeps its id, so the widget can say it's in the Trash.
    func entities(for identifiers: [ListEntity.ID]) async throws -> [ListEntity] {
        let lists = Self.lists()
        return identifiers.map { id in lists.first { $0.id == id } ?? ListEntity(id: id, name: "Deleted List") }
    }

    func suggestedEntities() async throws -> [ListEntity] { Self.lists() }

    /// A new widget shows the first list in the sidebar.
    func defaultResult() async -> ListEntity? { Self.lists().first }

    static func lists(in folder: URL? = WidgetGroup.folder) -> [ListEntity] {
        guard let folder, let feed = WidgetFeed.read(at: WidgetFeed.url(in: folder)) else { return [] }
        return feed.lists.map { ListEntity(id: $0.id, name: $0.name.isEmpty ? "Untitled" : $0.name) }
    }
}

/// The List widget's configuration: which list.
struct SelectListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a List"
    static let description = IntentDescription("The list the widget shows.")

    @Parameter(title: "List") var list: ListEntity?

    init() {}

    init(list: ListEntity?) { self.list = list }
}

// MARK: - The timeline

struct ListEntry: TimelineEntry {
    enum Content: Hashable, Sendable {
        /// No feed yet.
        case setUp
        case list(ListSnapshot)
    }
    let date: Date
    let content: Content
}

/// The feed for the chosen list, at now and at the next midnights (its cues and When words change with the day). The
/// app reloads it after each feed write, as it does Today.
struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: Date(), content: .list(.placeholder))
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> ListEntry {
        let now = Date()
        return ListEntry(date: now, content: Self.content(TodayProvider.overlay(), list: configuration.list, at: now))
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<ListEntry> {
        Self.timeline(overlay: TodayProvider.overlay(), list: configuration.list, now: Date())
    }

    static func timeline(overlay: WidgetOverlay?, list: ListEntity?, now: Date,
                         calendar: Calendar = .current) -> Timeline<ListEntry> {
        let start = calendar.startOfDay(for: now)
        let dates = [now] + (1...TodayProvider.midnights).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let entries = dates.map { ListEntry(date: $0, content: content(overlay, list: list, at: $0, calendar: calendar)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The chosen list, or the sidebar's first when none is chosen yet.
    static func content(_ overlay: WidgetOverlay?, list: ListEntity?, at date: Date,
                        calendar: Calendar = .current) -> ListEntry.Content {
        guard let overlay, let id = list?.id ?? overlay.lists.first?.id else { return .setUp }
        return .list(ListSnapshot(overlay, list: id, name: list?.name, day: Day(containing: date, calendar: calendar)))
    }
}

extension ListSnapshot {
    /// The gallery's stand-in while a widget loads: drawn redacted.
    static let placeholder: ListSnapshot = {
        let list = TodaySnapshot.ListInfo(id: "placeholder", name: "Inbox", slot: 6, monogram: "I")
        let rows = (0..<10).map { i in
            WidgetItem.task(.init(id: "p\(i)", title: String(repeating: "x", count: 14 + (i * 5) % 11), list: list,
                                  cue: .none, chip: nil, done: false))
        }
        return ListSnapshot(list: list, content: .items(rows))
    }()
}

// MARK: - The widget

struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetGroup.Kind.list, intent: SelectListIntent.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry)
        }
        .configurationDisplayName("List")
        .description("A list’s tasks, in its order.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct ListWidgetView: View {
    let entry: ListEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = WidgetPalette.of(scheme)
        Group {
            switch entry.content {
            case .setUp:
                SetUpView()
                    .widgetURL(DeepLink.today.url)
            case let .list(s):
                Group {
                    if family == .systemLarge { ListLargeView(s: s) } else { ListMediumView(s: s) }
                }
                .widgetURL(s.content == .trash ? DeepLink.today.url : DeepLink.list(s.list.id).url)
            }
        }
        .environment(\.widgetPalette, p)
        .containerBackground(p.base, for: .widget)
    }
}

/// The list's tile, name and +, then its first five open tasks.
struct ListMediumView: View {
    let s: ListSnapshot

    var body: some View {
        WidgetFrame(gap: WM.headerGap) {
            ListHeader(s: s)
        } content: {
            switch s.content {
            case .items: MediumRows(rows: s.rows, trailing: .none)
            case .empty, .trash: ListEmptyView(s: s)
            }
        }
    }
}

/// The list's tile, name and +, then its tasks in order with its headings as labels, as many as fit, and "N more".
struct ListLargeView: View {
    let s: ListSnapshot

    var body: some View {
        WidgetFrame(gap: WM.largeHeaderGap) {
            ListHeader(s: s)
        } content: {
            switch s.content {
            case let .items(items): LargeItems(items: items, more: s.more)
            case .empty, .trash: ListEmptyView(s: s)
            }
        }
    }
}

struct ListHeader: View {
    let s: ListSnapshot

    var body: some View {
        // A list in the Trash takes no new tasks: its + opens one in Today.
        let target: DeepLink = s.content == .trash ? .new(list: nil) : .new(list: s.list.id)
        WidgetHeader(title: s.list.name, newTask: target, newTaskLabel: "New task in \(s.list.name)") {
            Tile(list: s.list, width: 20, height: 16)
        }
    }
}

/// "No tasks", or "This list is in Trash".
struct ListEmptyView: View {
    let s: ListSnapshot

    var body: some View {
        EmptyStateView(text: s.content == .trash ? "This list is in Trash" : "No tasks", sun: nil, compact: false)
    }
}
