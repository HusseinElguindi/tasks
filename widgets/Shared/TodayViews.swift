import SwiftUI
import WidgetKit
import TasksCore
import TasksTheme

// The Today widget's sizes, after the mock-ups (https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi: TodaySmall,
// TodayMedium, TodayLarge), at the iPhone's sizes. Every cue carries words as well as colour, and the tiles and the
// sun are the accented group, so the widget stays legible on tinted and clear home screens (WIDGETS.md §3.6).

/// The widget's metrics: the mock-ups' margins, with rows a little tighter than theirs, since the room the counts took
/// (the user: no counts) goes to more tasks.
enum WM {
    static let top: CGFloat = 14, side: CGFloat = 16, bottom: CGFloat = 12
    static let header: CGFloat = 20
    static let row: CGFloat = 22
    static let groupLabel: CGFloat = 18
    static let groupGap: CGFloat = 6
    static let box: CGFloat = 18
    static let allDoneLine: CGFloat = 20
    /// The small size's rows: a ring and a title.
    static let smallRow: CGFloat = 16, smallGap: CGFloat = 3
}

// MARK: - Small

/// "☀ Today", then as many of Today's open tasks as fit, each with its ring cue. No count (the user, 2026-11-06).
struct TodaySmallView: View {
    let s: TodaySnapshot
    @Environment(\.widgetPalette) private var p

    /// How many rows fit in `height`.
    static func fit(_ height: CGFloat) -> Int { max(0, Int((height + WM.smallGap) / (WM.smallRow + WM.smallGap))) }

    var body: some View {
        if s.openCount == 0 { AllDoneView(s: s, compact: true) } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Sun(size: 13)
                    Text("Today").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.ink)
                }
                .frame(height: WM.header)
                .accessibilityAddTraits(.isHeader)
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: WM.smallGap) {
                        ForEach(s.open.prefix(Self.fit(g.size.height))) { r in
                            HStack(spacing: 7) {
                                Ring(cue: r.cue, size: 10, line: 1.5)
                                Text(r.title).font(.system(size: 13)).foregroundStyle(p.ink).lineLimit(1)
                            }
                            .frame(height: WM.smallRow)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(r.spoken)
                        }
                    }
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Medium

/// The header, then as many open rows as fit in Today's order (five at the iPhone's size); checked rows drop out to
/// make room (WIDGETS.md Q4).
struct TodayMediumView: View {
    let s: TodaySnapshot

    /// How many rows fit in `height`.
    static func fit(_ height: CGFloat) -> Int { max(0, Int(height / WM.row)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TodayHeader(s: s, showsDate: false)
            if s.openCount == 0 {
                AllDoneView(s: s, compact: false)
            } else {
                GeometryReader { g in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(s.open.prefix(Self.fit(g.size.height))) { r in TaskRowView(r: r, trailing: .tile) }
                    }
                }
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
                        if s.openCount == 0 { AllDoneLine() }
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

/// What fits in the large widget's height: whole groups and rows from the top, then the Completed group once every
/// open row is in. What doesn't fit is left out without a "N more" line, which would be a count (the user: none).
struct LargeFit {
    var groups: [TodaySnapshot.Group] = []
    var done: [TodaySnapshot.Row] = []
    /// Open rows that didn't fit.
    var hidden = 0

    init(_ s: TodaySnapshot, height: CGFloat) {
        var left = height
        if s.openCount == 0 { left -= WM.allDoneLine + WM.groupGap }
        var shown = 0
        for g in s.groups {
            // Room for the label and at least one row.
            let n = min(g.rows.count, max(0, Int((left - WM.groupLabel) / WM.row)))
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

    /// The height the fit takes, for the tests.
    var height: CGFloat {
        let label = WM.groupLabel + WM.groupGap
        return groups.reduce(0) { $0 + label + CGFloat($1.rows.count) * WM.row }
            + (done.isEmpty ? 0 : label + CGFloat(done.count) * WM.row)
    }
}

// MARK: - Pieces

/// "☀ Today", then the date (large) and the + that opens a new task in Today. No count (the user, 2026-11-06).
struct TodayHeader: View {
    let s: TodaySnapshot
    let showsDate: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 7) {
            Sun(size: 13)
            Text("Today").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if showsDate {
                Text(DateLabel.long(s.date, today: s.date))
                    .font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1)
            }
            Link(destination: DeepLink.new(list: nil).url) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(p.inkSecondary)
                    .frame(width: WM.header, height: WM.header)
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
                    // Its name first, up to a third of the row; the title takes what's left.
                    Text(r.list.name).font(.system(size: 12)).foregroundStyle(p.inkTertiary).lineLimit(1)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
            }
            .frame(height: WM.row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String { r.spoken + ", " + r.list.name }
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

/// Nothing open today: the lit sun and "All done" when something was done today (COLOR.md §4's moment, drawn still),
/// else the plain sun and "Nothing today". No count of what was done (the user: no counts).
struct AllDoneView: View {
    let s: TodaySnapshot
    let compact: Bool
    @Environment(\.widgetPalette) private var p

    var body: some View {
        VStack(spacing: compact ? 6 : 4) {
            Spacer(minLength: 0)
            Sun(size: compact ? 30 : 24, filled: !s.done.isEmpty)
            Text(Self.words(s)).font(.system(size: compact ? 15 : 14, weight: .semibold)).foregroundStyle(p.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func words(_ s: TodaySnapshot) -> String { s.done.isEmpty ? "Nothing today" : "All done" }
}

/// The large widget's "All done" over today's Completed group.
struct AllDoneLine: View {
    @Environment(\.widgetPalette) private var p

    var body: some View {
        HStack(spacing: 6) {
            Sun(size: 12, filled: true)
            Text("All done").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
        }
        .frame(height: WM.allDoneLine)
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
