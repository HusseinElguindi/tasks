import SwiftUI
import WidgetKit
import TasksCore
import TasksTheme

// The Today widget's sizes, after the mock-ups (https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi: TodaySmall,
// TodayMedium, TodayLarge), at the iPhone's sizes. Every cue carries words as well as colour, and the tiles and the
// sun are the accented group, so the widget stays legible on tinted and clear home screens (WIDGETS.md §3.6).

/// The widget's metrics, by the mock-ups' numbers.
enum WM {
    static let top: CGFloat = 14, side: CGFloat = 16, bottom: CGFloat = 12
    static let header: CGFloat = 24
    static let row: CGFloat = 25
    static let groupLabel: CGFloat = 18
    static let groupGap: CGFloat = 6
    static let box: CGFloat = 18
    static let allDoneLine: CGFloat = 20
    static let moreLine: CGFloat = 16
}

// MARK: - Small

struct TodaySmallView: View {
    let s: TodaySnapshot
    @Environment(\.widgetPalette) private var p

    var body: some View {
        if s.openCount == 0 { AllDoneView(s: s, compact: true) } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Sun(size: 13)
                    Text("Today").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.ink)
                }
                .frame(height: 20)
                Text(s.openCount, format: .number)
                    .font(.system(size: 36, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(p.ink)
                    .frame(height: 40, alignment: .leading)
                    .padding(.top, 4)
                    .accessibilityLabel(s.openCount == 1 ? "1 task" : "\(s.openCount) tasks")
                Urgency(s: s).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(s.open.prefix(2)) { r in
                        HStack(spacing: 7) {
                            Ring(cue: r.cue, size: 10, line: 1.5)
                            Text(r.title).font(.system(size: 12.5)).foregroundStyle(p.ink).lineLimit(1)
                        }
                        .frame(height: 16)
                    }
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// "1 overdue · 1 due", each in its colour; nothing when neither.
struct Urgency: View {
    let s: TodaySnapshot
    @Environment(\.widgetPalette) private var p

    var body: some View {
        let late = s.overdueCount, due = s.dueCount
        HStack(spacing: 0) {
            if late > 0 { Text("\(late) overdue").foregroundStyle(p.danger) }
            if late > 0 && due > 0 { Text(" · ").foregroundStyle(p.inkSecondary) }
            if due > 0 { Text("\(due) due").foregroundStyle(p.attention) }
        }
    }
}

// MARK: - Medium

/// The header, the first four open rows in Today's order; checked rows drop out to make room (WIDGETS.md Q4).
struct TodayMediumView: View {
    let s: TodaySnapshot
    static let rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TodayHeader(s: s, showsDate: false)
            if s.openCount == 0 {
                AllDoneView(s: s, compact: false)
            } else {
                ForEach(s.open.prefix(Self.rows)) { r in TaskRowView(r: r, trailing: .tile) }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, WM.top)
        .padding(.horizontal, WM.side)
        .padding(.bottom, WM.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large

/// Today grouped by list, as the app's Today, with today's completed tasks at the end, checked and struck.
struct TodayLargeView: View {
    let s: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: WM.groupGap) {
            TodayHeader(s: s, showsDate: true)
            if s.openCount == 0 && s.done.isEmpty {
                AllDoneView(s: s, compact: false)
            } else {
                GeometryReader { g in
                    let fit = LargeFit(s, height: g.size.height)
                    VStack(alignment: .leading, spacing: WM.groupGap) {
                        if s.openCount == 0 { AllDoneLine(s: s) }
                        ForEach(fit.groups, id: \.id) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                GroupLabel(list: group.list)
                                ForEach(group.rows) { r in TaskRowView(r: r, trailing: .none) }
                            }
                        }
                        if !fit.done.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                GroupLabel(list: nil)
                                ForEach(fit.done) { r in TaskRowView(r: r, trailing: .listName) }
                            }
                        }
                        if fit.hidden > 0 { MoreLine(count: fit.hidden) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.top, WM.top)
        .padding(.horizontal, WM.side)
        .padding(.bottom, WM.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// What fits in the large widget's height: whole groups and rows from the top, the Completed group after them, and
/// a count of the open rows left out.
struct LargeFit {
    var groups: [TodaySnapshot.Group] = []
    var done: [TodaySnapshot.Row] = []
    /// Open rows that didn't fit.
    var hidden = 0

    init(_ s: TodaySnapshot, height: CGFloat) {
        var left = height
        if s.openCount == 0 { left -= WM.allDoneLine + WM.groupGap }
        var shown = 0
        for (i, g) in s.groups.enumerated() {
            let remainingAfter = s.groups[(i + 1)...].reduce(0) { $0 + $1.rows.count }
            // Room for the label and at least one row; a "N more" line once anything is left out.
            let reserve = remainingAfter > 0 ? WM.moreLine + WM.groupGap : 0
            let room = left - WM.groupLabel - reserve
            var n = min(g.rows.count, max(0, Int(room / WM.row)))
            if n < g.rows.count {
                // This group is cut: keep room for the "more" line.
                n = min(g.rows.count, max(0, Int((left - WM.groupLabel - WM.moreLine - WM.groupGap) / WM.row)))
            }
            guard n > 0 else { break }
            groups.append(.init(list: g.list, rows: Array(g.rows.prefix(n))))
            shown += n
            left -= WM.groupLabel + CGFloat(n) * WM.row + WM.groupGap
            if n < g.rows.count { break }
        }
        hidden = s.openCount - shown
        if hidden == 0, !s.done.isEmpty {
            let n = max(0, Int((left - WM.groupLabel) / WM.row))
            done = Array(s.done.prefix(n))
        }
    }
}

// MARK: - Pieces

/// "☀ Today 6", then the date (large) and the + that opens a new task in Today.
struct TodayHeader: View {
    let s: TodaySnapshot
    let showsDate: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 7) {
            Sun(size: 13)
            Text("Today").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.ink)
            if s.openCount > 0 {
                Text(s.openCount, format: .number)
                    .font(.system(size: 15)).monospacedDigit().foregroundStyle(p.inkSecondary)
                    .accessibilityLabel(s.openCount == 1 ? "1 task" : "\(s.openCount) tasks")
            }
            Spacer(minLength: 4)
            if showsDate {
                Text(DateLabel.long(s.date, today: s.date))
                    .font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1)
            }
            Link(destination: DeepLink.new(list: nil).url) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(p.fillControl, in: Circle())
            }
            .padding(.leading, showsDate ? 6 : 0)
            .accessibilityLabel("New task in Today")
        }
        .frame(height: WM.header)
    }
}

/// A task's row: its box, its title, its deadline capsule, and its list's tile (medium) or name (Completed).
struct TaskRowView: View {
    enum Trailing { case none, tile, listName }
    let r: TodaySnapshot.Row
    let trailing: Trailing
    @Environment(\.widgetPalette) private var p

    var body: some View {
        Link(destination: DeepLink.task(r.id).url) {
            HStack(spacing: 10) {
                Box(cue: r.cue, done: r.done)
                Text(r.title)
                    .font(.system(size: 14))
                    .foregroundStyle(r.done ? p.inkSecondary : p.ink)
                    .strikethrough(r.done, color: p.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let c = r.chip { DeadlineCapsule(chip: c) }
                switch trailing {
                case .none: EmptyView()
                case .tile: Tile(list: r.list, width: 16, height: 13)
                case .listName:
                    Text(r.list.name).font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .frame(height: WM.row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        var parts = [r.title]
        if r.done { parts.append("completed") }
        if let c = r.chip { parts.append(c.text) }
        parts.append(r.list.name)
        return parts.joined(separator: ", ")
    }
}

/// The checkbox: a ring in its cue's colour, or the accent's filled box with a check.
struct Box: View {
    let cue: TodaySnapshot.Cue
    let done: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        if done {
            Circle().fill(p.accent)
                .overlay {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(p.onAccent)
                }
                .frame(width: WM.box, height: WM.box)
                .widgetAccentable()
        } else {
            Ring(cue: cue, size: WM.box, line: 1.5)
        }
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

/// A group's label: the list's tile and name, or "Completed".
struct GroupLabel: View {
    let list: TodaySnapshot.ListInfo?
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 6) {
            if let list { Tile(list: list, width: 16, height: 13) }
            Text(list?.name ?? "Completed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.inkTertiary)
                .lineLimit(1)
        }
        .frame(height: WM.groupLabel)
        .accessibilityAddTraits(.isHeader)
    }
}

struct MoreLine: View {
    let count: Int
    @Environment(\.widgetPalette) private var p

    var body: some View {
        Text("\(count) more")
            .font(.system(size: 12))
            .foregroundStyle(p.inkTertiary)
            .frame(height: WM.moreLine)
            .padding(.leading, WM.box + 10)
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

/// Nothing open today: the lit sun and "All done" (COLOR.md §4's moment, drawn still), with what was done.
struct AllDoneView: View {
    let s: TodaySnapshot
    let compact: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        VStack(spacing: compact ? 6 : 4) {
            Spacer(minLength: 0)
            Sun(size: compact ? 30 : 24, filled: true)
            Text("All done").font(.system(size: compact ? 15 : 14, weight: .semibold)).foregroundStyle(p.ink)
            Text(AllDoneLine.words(s))
                .font(.system(size: 12)).foregroundStyle(p.inkSecondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The large widget's "All done" over today's Completed group.
struct AllDoneLine: View {
    let s: TodaySnapshot
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 6) {
            Sun(size: 12, filled: true)
            Text("All done").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
        }
        .frame(height: WM.allDoneLine)
    }

    static func words(_ s: TodaySnapshot) -> String {
        switch s.done.count {
        case 0: "Nothing planned for today"
        case 1: "1 done today"
        case let n: "\(n) done today"
        }
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
