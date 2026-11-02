import SwiftUI

// MARK: - List tile

/// The Mac's tile colours (B, COLOR.md §2): the hue of the list's slot, or of a view, with its monogram or glyph in
/// white. Flat: the Mac's lit finish (TileArt) comes with the shared theme code, not copied.
struct ListTile: View {
    enum Content { case mono(String), symbol(String) }
    let content: Content
    let hue: Color
    var scale: CGFloat = 1

    var body: some View {
        let w = Metric.tileW * scale, h = Metric.tileH * scale
        ZStack {
            switch content {
            case let .mono(m):
                Text(m)
                    .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
            case let .symbol(s):
                Image(systemName: s)
                    .font(.system(size: 12.5 * scale, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: w, height: h)
        .background(hue, in: RoundedRectangle(cornerRadius: 5 * scale, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension Store {
    /// A view's tile is the Mac's (`Route.tileHue`): Today the accent's, Upcoming magenta, Undated cyan, Completed green,
    /// the Trash the ink slot's graphite.
    @MainActor func tile(for source: Source, palette p: Palette, scale: CGFloat = 1) -> ListTile {
        switch source {
        case .today: ListTile(content: .symbol("sun.max.fill"), hue: p.tileToday, scale: scale)
        case .upcoming: ListTile(content: .symbol("calendar"), hue: p.tile(.magenta), scale: scale)
        case .undated: ListTile(content: .symbol("square.stack"), hue: p.tile(.cyan), scale: scale)
        case .completed: ListTile(content: .symbol("checkmark.circle"), hue: p.tile(.green), scale: scale)
        case .trash: ListTile(content: .symbol("trash"), hue: p.tile(.ink), scale: scale)
        case let .list(id):
            if let l = list(id) { ListTile(content: .mono(l.mono), hue: p.tile(l.hue), scale: scale) }
            else { ListTile(content: .mono("?"), hue: p.tile(.ink), scale: scale) }
        }
    }
}

// MARK: - Checkbox

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        // tasks-v2.css's ck: M3.8 8.4l2.7 2.7 5.7-6.2, in a 16pt box.
        let s = r.width / 16
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 3.8 * s, y: r.minY + 8.4 * s))
        p.addLine(to: CGPoint(x: r.minX + 6.5 * s, y: r.minY + 11.1 * s))
        p.addLine(to: CGPoint(x: r.minX + 12.2 * s, y: r.minY + 4.9 * s))
        return p
    }
}

/// A 22pt ring. Its cue: danger when overdue, attention when due today, `plan` (blue: COLOR.md §1 split it from the warm
/// accent) when planned for today and seen outside Today; both at once is the double ring. Checking fills it with the
/// accent and draws the mark.
struct Checkbox: View {
    let checked: Bool
    var cue: Store.Cue = .init(tone: nil, planned: false)
    var readOnly = false
    var placeholder = false
    var size: CGFloat = Metric.check
    var action: () -> Void = {}
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(checked ? p.accent : .clear)
                Circle().strokeBorder(checked ? p.accent : ringColor, lineWidth: 1.5)
                if !checked && cue.planned && cue.tone != nil {
                    Circle().strokeBorder(p.plan, lineWidth: 1.25).padding(size * 0.19)
                }
                CheckShape()
                    .trim(from: 0, to: checked ? 1 : 0)
                    .stroke(p.onAccent, style: StrokeStyle(lineWidth: 2.2 * size / 16 * 0.85, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.06)
            }
            .frame(width: size, height: size)
            .opacity(placeholder ? 0.7 : readOnly ? 0.6 : 1)
            .keyframeAnimator(initialValue: 1.0, trigger: checked) { v, s in
                v.scaleEffect(s)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(checked ? 0.8 : 1.0, duration: 0.06)
                    SpringKeyframe(1.0, duration: 0.3, spring: .snappy)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckPressStyle())
        .disabled(readOnly || placeholder)
        .animation(.easeOut(duration: 0.16), value: checked)
        .sensoryFeedback(trigger: checked) { _, new in new ? .success : .selection }
        .accessibilityLabel(checked ? "Completed" : "Complete")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private var ringColor: Color {
        if placeholder { return p.inkQuiet }
        if let t = cue.tone { return t == .late ? p.danger : p.attention }
        if cue.planned { return p.plan }
        return p.lineField
    }
}

private struct CheckPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Dates on a row

/// The quiet When: glyph and date in ink-tertiary, no capsule.
struct QuietWhen: View {
    let date: Date
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 10.5, weight: .medium))
            Text(Day.whenLabel(date)).font(Typo.quiet).monospacedDigit()
        }
        .foregroundStyle(p.inkTertiary)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("When \(Day.whenLabel(date))")
    }
}

/// The deadline: the one capsule on a row, so a capsule always means something is due.
struct DeadlineChip: View {
    let date: Date
    var large = false
    @Environment(\.palette) private var p

    var body: some View {
        let tone = Day.tone(date)
        HStack(spacing: large ? 5 : 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: large ? 11 : 9.5, weight: .semibold))
                .foregroundStyle(tone == .soon ? p.attention : fg(tone))
            Text(large ? Day.monthDay(date) : Day.deadlineLabel(date))
                .font(large ? Typo.chipLarge : Typo.chip)
                .monospacedDigit()
        }
        .foregroundStyle(fg(tone))
        .padding(.horizontal, large ? 11 : 8)
        .frame(height: large ? 30 : 22)
        .background(bg(tone), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deadline \(Day.deadlineLabel(date))")
    }

    private func fg(_ t: Tone) -> Color { t == .late ? p.danger : t == .due ? p.attention : p.inkSecondary }
    private func bg(_ t: Tone) -> Color { t == .late ? p.dangerTint : t == .due ? p.attentionTint : p.fillControl }
}

/// The detail pane's date capsule: the date, or a ghost "Add date".
struct DateChip: View {
    let date: Date?
    let kind: DateKind
    var active = false
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 6) {
            if let date {
                Image(systemName: kind == .when ? "calendar" : "flag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor(date))
                Text(kind == .when ? whenText(date) : Day.full(date))
            } else {
                Text("Add date")
            }
        }
        .font(Typo.chipLarge)
        .foregroundStyle(active ? p.accentText : date == nil ? p.inkTertiary : p.ink)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background {
            if active { Capsule().fill(p.accentTint) }
            else if date == nil { Capsule().strokeBorder(p.lineSeparator, lineWidth: 1) }
            else { Capsule().fill(p.fillControl) }
        }
        .contentShape(Capsule())
    }

    private func whenText(_ d: Date) -> String {
        let n = Day.diff(d)
        return n <= 0 ? "Today" : n == 1 ? "Tomorrow" : Day.full(d)
    }
    private func iconColor(_ d: Date) -> Color {
        if kind == .when { return Day.diff(d) <= 0 ? p.accentText : p.inkSecondary }
        let t = Day.tone(d)
        return t == .late ? p.danger : (t == .due || t == .soon) ? p.attention : p.inkSecondary
    }
}

// MARK: - Row press

/// A row's press: its own rounded fill, instant in, quick out. Selection uses the same shape.
struct RowStyle: ButtonStyle {
    var selected = false
    var focused = true
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous)
                    .fill(configuration.isPressed ? p.press : selected ? (focused ? p.fillRowSelected : p.fillRowSelectedDim) : .clear)
                    .animation(configuration.isPressed ? nil : .easeOut(duration: 0.085), value: configuration.isPressed)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
    }
}

/// Pane's capsule buttons: primary, tinted, neutral, destructive.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, tinted, neutral, destructive }
    var kind: Kind = .neutral
    var height: CGFloat = 32
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(bg, in: Capsule())
            .overlay { if configuration.isPressed { Capsule().fill(Color.black.opacity(0.14)) } }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
    private var bg: Color {
        switch kind { case .primary: p.accent; case .tinted: p.accentTint; case .neutral: p.fillTrack; case .destructive: p.dangerTint }
    }
    private var fg: Color {
        switch kind { case .primary: p.onAccent; case .tinted: p.accentText; case .neutral: p.ink; case .destructive: p.danger }
    }
}

// MARK: - Group label

struct GroupLabel: View {
    let title: String
    var sub: String? = nil
    var quiet = false
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(Typo.label).foregroundStyle(quiet ? p.inkQuiet : p.inkTertiary)
            if let sub { Text(sub).font(Typo.quiet).foregroundStyle(p.inkQuiet) }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.leading, Metric.rowPad + 2)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - The 04 · Log mark

/// The app's mark, from the sidebar header's SVG (viewBox 150 150 724 724): an accent head with the check cut out,
/// two rings and their trails, and the ink bar.
struct LogoMark: View {
    var size: CGFloat = 28
    var head: Color? = nil
    @Environment(\.palette) private var p

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 724
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: (x - 150) * s, y: (y - 150) * s, width: w * s, height: h * s)
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat) -> Path {
                Path(ellipseIn: r(cx - rad, cy - rad, rad * 2, rad * 2))
            }
            ctx.fill(Path(r(304, 436, 36, 64)), with: .color(p.markTrail))
            ctx.fill(Path(r(304, 612, 36, 64)), with: .color(p.markTrail))
            ctx.fill(Path(roundedRect: r(462, 524, 280, 64), cornerRadius: 32 * s), with: .color(p.markTrail))
            ctx.fill(Path(roundedRect: r(462, 700, 220, 64), cornerRadius: 32 * s), with: .color(p.markTrail))
            ctx.fill(circle(322, 556, 56), with: .color(p.markRings))
            ctx.fill(circle(322, 732, 56), with: .color(p.markRings))
            ctx.fill(Path(roundedRect: r(462, 296, 340, 80), cornerRadius: 40 * s), with: .color(p.markBar))
            ctx.drawLayer { l in
                l.fill(circle(322, 336, 100), with: .color(head ?? p.markHead))
                l.blendMode = .destinationOut
                var ck = Path()
                ck.move(to: CGPoint(x: (276.5 - 150) * s, y: (339.5 - 150) * s))
                ck.addLine(to: CGPoint(x: (308 - 150) * s, y: (371 - 150) * s))
                ck.addLine(to: CGPoint(x: (367.5 - 150) * s, y: (304.5 - 150) * s))
                l.stroke(ck, with: .color(.black), style: StrokeStyle(lineWidth: 30 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Backgrounds

/// The window behind everything: the ground, or in Glass the ground over a blurred wallpaper.
struct AppBackground: View {
    @Environment(\.palette) private var p
    @Environment(\.interfaceStyle) private var style
    var body: some View {
        ZStack {
            if style == .glass {
                Wallpaper().blur(radius: 50).opacity(p.isDark ? 1 : 0.85)
                p.ground.opacity(p.isDark ? 0.72 : 0.66)
            } else {
                p.ground
            }
        }
        .ignoresSafeArea()
    }
}

/// themes.css's Glass wallpaper: clay, harbour blue and moss over plum.
struct Wallpaper: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Color(.sRGB, red: 0x5A / 255, green: 0x4E / 255, blue: 0x6E / 255)
                RadialGradient(colors: [Color(.sRGB, red: 0xC9 / 255, green: 0x74 / 255, blue: 0x3F / 255), .clear],
                               center: UnitPoint(x: 0.18, y: 0.3), startRadius: 0, endRadius: max(w, h) * 0.55)
                RadialGradient(colors: [Color(.sRGB, red: 0x3E / 255, green: 0x6F / 255, blue: 0xB0 / 255), .clear],
                               center: UnitPoint(x: 0.8, y: 0.2), startRadius: 0, endRadius: max(w, h) * 0.5)
                RadialGradient(colors: [Color(.sRGB, red: 0x4F / 255, green: 0x8F / 255, blue: 0x6A / 255), .clear],
                               center: UnitPoint(x: 0.7, y: 0.9), startRadius: 0, endRadius: max(w, h) * 0.6)
            }
        }
    }
}

extension View {
    /// A floating control's surface: Liquid Glass, tinted when given a colour.
    @ViewBuilder func floatingGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if let tint {
            glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
        } else {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }

    func hairline(_ color: Color, leading: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(color).frame(height: 1).padding(.leading, leading).padding(.trailing, trailing)
        }
    }
}
