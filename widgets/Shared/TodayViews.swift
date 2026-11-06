import SwiftUI
import WidgetKit
import TasksCore
import TasksTheme

// The widgets' views, after the approved mock-ups (https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi: TodaySmall,
// TodayMedium, TodayLarge, ListMedium, ListLarge), at the iPhone's sizes. Read-only (the user, 2026-11-06): a row
// opens the app at that task, highlighted in its list; the rest opens Today or the list; the + opens a new task. No
// counts, and no completed tasks: the room goes to the open ones. Every cue carries words or shape as well as colour,
// and the tiles and the sun are the accented group, so the widgets stay legible on tinted and clear home screens
// (WIDGETS.md §3.6).

/// The widgets' metrics, by the mock-ups' numbers.
enum WM {
    static let top: CGFloat = 14, side: CGFloat = 16, bottom: CGFloat = 12
    /// Medium and large: the header, and the gap under it.
    static let header: CGFloat = 24, headerGap: CGFloat = 2, largeHeaderGap: CGFloat = 4
    static let ring: CGFloat = 16
    #if os(macOS)
    // The Mac boards (Mac-Dark/Light, `mac`): the system's 170 / 364 × 170 / 364 × 382 sizes, a 14 pt title in medium
    // (15 in large, as the iPhone), 13 pt task titles, and 23 pt rows in medium.
    static let mediumRow: CGFloat = 23
    static let mediumTitle: CGFloat = 14
    static let taskTitle: CGFloat = 13
    #else
    static let mediumRow: CGFloat = 21
    static let mediumTitle: CGFloat = 15
    static let taskTitle: CGFloat = 14
    #endif
    static let largeTitle: CGFloat = 15
    static let largeRow: CGFloat = 24
    /// A group's or a heading's label in large.
    static let label: CGFloat = 22
    static let more: CGFloat = 18
    /// Small: a 20 pt header, 8 under it, then 18 pt rows 3 apart with a 10 pt ring.
    static let smallTop: CGFloat = 14
    static let smallHeader: CGFloat = 20, smallHeaderGap: CGFloat = 8
    static let smallRow: CGFloat = 18, smallGap: CGFloat = 3, smallRing: CGFloat = 10
}

// MARK: - Today

/// "☀ Today", then as many of Today's open tasks as fit (five at the iPhone's size), each with its ring cue.
struct TodaySmallView: View {
    let s: TodaySnapshot
    @Environment(\.widgetPalette) private var p

    /// How many rows fit in `height`.
    static func fit(_ height: CGFloat) -> Int { max(0, Int((height + WM.smallGap) / (WM.smallRow + WM.smallGap))) }

    var body: some View {
        if s.openCount == 0 { AllDoneView(s: s, compact: true) } else {
            VStack(alignment: .leading, spacing: WM.smallHeaderGap) {
                HStack(spacing: 6) {
                    Sun(size: 14)
                    Text("Today").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.ink)
                }
                .frame(height: WM.smallHeader)
                .accessibilityAddTraits(.isHeader)
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: WM.smallGap) {
                        ForEach(s.open.prefix(Self.fit(g.size.height))) { r in
                            HStack(spacing: 7) {
                                Ring(cue: r.cue, size: WM.smallRing, line: 1.5)
                                Text(r.title).font(.system(size: 12.5)).foregroundStyle(p.ink).lineLimit(1)
                            }
                            .frame(height: WM.smallRow)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(r.spoken)
                        }
                    }
                }
            }
            .padding(.vertical, WM.smallTop)
            .padding(.horizontal, WM.side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The header (sun, Today, +), then as many open rows as fit in Today's order (five at the iPhone's size), each with
/// its capsule and its list's tile.
struct TodayMediumView: View {
    let s: TodaySnapshot

    var body: some View {
        WidgetFrame(gap: WM.headerGap) {
            WidgetHeader(title: "Today", newTask: .new(list: nil), newTaskLabel: "New task in Today") { Sun(size: 14) }
        } content: {
            if s.openCount == 0 {
                AllDoneView(s: s, compact: false)
            } else {
                MediumRows(rows: s.open, trailing: .tile)
            }
        }
    }
}

/// The header with the date, then Today grouped by list, as the app's Today, as many as fit, and a quiet "N more"
/// when they don't (the user: "n more is good").
struct TodayLargeView: View {
    let s: TodaySnapshot

    /// Today's rows under their lists' labels.
    static func items(_ s: TodaySnapshot) -> [WidgetItem] {
        s.groups.flatMap { g in [.label(id: g.list.id, name: g.list.name, tile: g.list)] + g.rows.map(WidgetItem.task) }
    }

    var body: some View {
        WidgetFrame(gap: WM.largeHeaderGap) {
            WidgetHeader(title: "Today", date: DateLabel.long(s.date, today: s.date), newTask: .new(list: nil),
                         newTaskLabel: "New task in Today", titleSize: WM.largeTitle) { Sun(size: 14) }
        } content: {
            if s.openCount == 0 {
                AllDoneView(s: s, compact: false)
            } else {
                LargeItems(items: Self.items(s), more: { "\($0) more" })
            }
        }
    }
}

// MARK: - Shared layout

/// A medium or large widget's frame: the margins, the header, then the content below it.
struct WidgetFrame<Header: View, Content: View>: View {
    let gap: CGFloat
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            header
            content
        }
        .padding(.top, WM.top)
        .padding(.horizontal, WM.side)
        .padding(.bottom, WM.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "☀ Today" or a list's tile and name, then the date (Today large) and the + that opens a new task there.
struct WidgetHeader<Icon: View>: View {
    let title: String
    var date: String? = nil
    let newTask: DeepLink
    let newTaskLabel: String
    /// The title's size: medium's or large's (WM; the same on the iPhone).
    var titleSize: CGFloat = WM.mediumTitle
    @ViewBuilder let icon: Icon
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(title).font(.system(size: titleSize, weight: .semibold)).foregroundStyle(p.ink).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let date {
                Text(date).font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1)
            }
            WidgetLink(destination: newTask.url) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(p.fillControl, in: Circle())
            }
            .padding(.leading, date == nil ? 0 : 6)
            .accessibilityLabel(newTaskLabel)
        }
        .frame(height: WM.header)
    }
}

/// As many rows as fit, 21 pt each (23 on the Mac).
struct MediumRows: View {
    let rows: [TodaySnapshot.Row]
    let trailing: TaskRowView.Trailing

    /// How many rows fit in `height`.
    static func fit(_ height: CGFloat) -> Int { max(0, Int(height / WM.mediumRow)) }

    var body: some View {
        GeometryReader { g in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.prefix(Self.fit(g.size.height))) { r in
                    TaskRowView(r: r, trailing: trailing, height: WM.mediumRow)
                }
            }
        }
    }
}

/// One line of a large widget: a label (a list's tile and name in Today, a heading's name in a list), or a task.
enum WidgetItem: Hashable, Sendable, Identifiable {
    case label(id: EntityID, name: String, tile: TodaySnapshot.ListInfo?)
    case task(TodaySnapshot.Row)

    var id: String {
        switch self {
        case let .label(id, _, _): "label:" + id
        case let .task(r): "task:" + r.id
        }
    }

    var isTask: Bool { if case .task = self { true } else { false } }
    var height: CGFloat { isTask ? WM.largeRow : WM.label }
}

/// What fits in a large widget's height, as the mock-ups fit it: whole lines from the top, never a label with no row
/// under it; when some tasks are left out, room for "N more" at the bottom.
struct ItemFit {
    let shown: [WidgetItem]
    /// Tasks left out.
    let hidden: Int

    init(_ items: [WidgetItem], height: CGFloat) {
        let total = items.filter(\.isTask).count
        func fit(_ budget: CGFloat) -> [WidgetItem] {
            var out: [WidgetItem] = []
            var used: CGFloat = 0
            for it in items {
                guard used + it.height <= budget else { break }
                used += it.height
                out.append(it)
            }
            while let last = out.last, !last.isTask { out.removeLast() }
            return out
        }
        var out = fit(height)
        if out.filter(\.isTask).count < total { out = fit(height - WM.more) }
        shown = out
        hidden = total - out.filter(\.isTask).count
    }

    var height: CGFloat { shown.reduce(0) { $0 + $1.height } + (hidden > 0 ? WM.more : 0) }
}

/// A large widget's lines, as many as fit, and "N more" at the bottom when some don't.
struct LargeItems: View {
    let items: [WidgetItem]
    /// The words for the tasks left out ("3 more").
    let more: (Int) -> String

    var body: some View {
        GeometryReader { g in
            let fit = ItemFit(items, height: g.size.height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(fit.shown) { it in
                    switch it {
                    case let .label(_, name, tile): ItemLabel(name: name, tile: tile)
                    case let .task(r): TaskRowView(r: r, trailing: .none, height: WM.largeRow)
                    }
                }
                Spacer(minLength: 0)
                if fit.hidden > 0 { MoreLine(text: more(fit.hidden)) }
            }
        }
    }
}

// MARK: - Pieces

/// A `Link` in a widget. Drawn off screen (the Mac's render tests), AppKit's ImageRenderer can't draw a `Link` and puts
/// a placeholder in its place, so there `\.widgetLinksAsLabels` draws the label alone.
struct WidgetLink<Label: View>: View {
    let destination: URL
    @ViewBuilder let label: Label
    @Environment(\.widgetLinksAsLabels) private var asLabels

    var body: some View {
        if asLabels { label } else { Link(destination: destination) { label } }
    }
}

private struct WidgetLinksAsLabelsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Draw `WidgetLink`s as their labels (render tests only; the widgets keep their links).
    var widgetLinksAsLabels: Bool {
        get { self[WidgetLinksAsLabelsKey.self] }
        set { self[WidgetLinksAsLabelsKey.self] = newValue }
    }
}

/// A task's row: its ring, its title, its When in words (a list), its deadline capsule, and its list's tile (Today
/// medium). A link to the task in the app: its list, scrolled to it, the row highlighted (`tasks://task/<id>`); the
/// rest of the widget opens Today or the list.
struct TaskRowView: View {
    enum Trailing { case none, tile }
    let r: TodaySnapshot.Row
    let trailing: Trailing
    let height: CGFloat
    @Environment(\.widgetPalette) private var p

    var body: some View {
        WidgetLink(destination: DeepLink.task(r.id).url) { content }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trailing == .tile ? r.spoken + ", " + r.list.name : r.spoken)
    }

    private var content: some View {
        HStack(spacing: 10) {
            Ring(cue: r.cue, size: WM.ring, line: 1.5)
            Text(r.title).font(.system(size: WM.taskTitle)).foregroundStyle(p.ink).lineLimit(1)
            if let w = r.when {
                Text(w).font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
            if let c = r.chip { DeadlineCapsule(chip: c) }
            if trailing == .tile { Tile(list: r.list, width: 16, height: 13) }
        }
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

struct Ring: View {
    let cue: TodaySnapshot.Cue
    let size: CGFloat
    let line: CGFloat
    @Environment(\.widgetPalette) private var p

    var body: some View {
        Circle().inset(by: line / 2).stroke(p.ring(cue), lineWidth: line)
            .frame(width: size, height: size)
    }
}

/// The deadline capsule: "2d ago" (danger), "Due today" (attention), "4d left" (quiet).
struct DeadlineCapsule: View {
    let chip: TodaySnapshot.Chip
    @Environment(\.widgetPalette) private var p

    var body: some View {
        let (fg, bg): (Color, Color) = switch chip.tone {
        case .late: (p.danger, p.dangerTint)
        case .due: (p.attention, p.attentionTint)
        case .soon, .neutral: (p.inkSecondary, p.fillControl)
        }
        Text(chip.text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(bg, in: Capsule())
            .fixedSize()
    }
}

/// A list's lit tile with its monogram (TasksTheme's finish). On tinted and clear home screens, an outline in the
/// accent group instead, since the finish would come out as a flat block.
struct Tile: View {
    let list: TodaySnapshot.ListInfo
    let width: CGFloat
    let height: CGFloat
    @Environment(\.widgetPalette) private var p
    @Environment(\.displayScale) private var displayScale
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let radius = width / 5
        Text(list.monogram)
            .font(.system(size: 8.5 * width / 16, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background {
                if mode == .fullColor {
                    if let art = TileArt.image(hue: p.tile(slot: list.slot), halo: p.tileHalo,
                                               size: CGSize(width: width, height: height), radius: radius,
                                               scale: displayScale) {
                        Image(decorative: art, scale: displayScale)
                    } else {
                        RoundedRectangle(cornerRadius: radius).fill(p.tile(slot: list.slot).swiftUI)
                    }
                } else {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(lineWidth: 1)
                }
            }
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

/// A label in a large widget, at the foot of its 22 pt: a list's tile and name (Today), or a heading's name (a list).
struct ItemLabel: View {
    let name: String
    let tile: TodaySnapshot.ListInfo?
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 6) {
            if let tile { Tile(list: tile, width: 16, height: 13) }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.inkTertiary)
                .lineLimit(1)
        }
        .padding(.bottom, 3)
        .frame(height: WM.label, alignment: .bottom)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "3 more", quiet, under the rows' titles.
struct MoreLine: View {
    let text: String
    @Environment(\.widgetPalette) private var p

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(p.inkTertiary)
            .frame(height: WM.more)
            .padding(.leading, WM.ring + 10)
    }
}

/// The sun: Today's mark, in the accent.
struct Sun: View {
    let size: CGFloat
    var filled = false
    @Environment(\.widgetPalette) private var p

    var body: some View {
        Image(systemName: filled ? "sun.max.fill" : "sun.max")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(p.accent)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// Nothing open today: the lit sun and "All done" when today's tasks were all completed (COLOR.md §4's moment, drawn
/// still), else the plain sun and "Nothing today".
struct AllDoneView: View {
    let s: TodaySnapshot
    let compact: Bool

    var body: some View {
        EmptyStateView(text: Self.words(s), sun: !s.done.isEmpty, compact: compact)
    }

    nonisolated static func words(_ s: TodaySnapshot) -> String { s.done.isEmpty ? "Nothing today" : "All done" }
}

/// A widget's one line when it has no rows, under the sun (Today: lit or plain) or alone (a list: `sun` nil).
struct EmptyStateView: View {
    let text: String
    var sun: Bool? = false
    let compact: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        VStack(spacing: compact ? 6 : 4) {
            Spacer(minLength: 0)
            if let sun { Sun(size: compact ? 30 : 24, filled: sun) }
            Text(text).font(.system(size: compact ? 15 : 14, weight: .semibold)).foregroundStyle(p.ink)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// No feed yet: the app hasn't been opened since the widget was added.
struct SetUpView: View {
    @Environment(\.widgetPalette) private var p
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: 6) {
            Sun(size: family == .systemSmall ? 26 : 22)
            Text("Open Tasks to set up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.ink)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
