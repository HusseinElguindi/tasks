import SwiftUI
import TasksCore
import TasksTheme

// MARK: - List tile

/// The Mac's tile (B, COLOR.md §2): the hue of the list's slot, or of a view, lit with the Mac's finish (TileArt, from
/// TasksTheme), with its monogram or glyph in white. The Mac's regular tile (20×16, radius 4) × 1.3: 26×21 in a row,
/// and at the other scales the nearest whole points (21×17 in the bar, 22×18 in a task's details, 31×25 under a large
/// title), the radius a fifth of the width, so the finish's one-device-pixel hairlines land on pixels.
struct ListTile: View {
    enum Content { case mono(String), symbol(String) }
    let content: Content
    let hue: RGBA
    var scale: CGFloat = 1
    @Environment(\.palette) private var p
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let w = (Metric.tileW * scale).rounded(), h = (Metric.tileH * scale).rounded()
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
        .background {
            // The finish's image is `outset` larger all round, centred: its halo reaches past the frame (the Mac's
            // TileView).
            if let art = TileArt.image(hue: hue, halo: p.tileHalo, size: CGSize(width: w, height: h), radius: w / 5,
                                       scale: displayScale) {
                Image(decorative: art, scale: displayScale)
            }
        }
        .accessibilityHidden(true)
    }
}

extension AppModel {
    /// A view's tile is the Mac's (`Route.tileHue`): Today the accent's, Upcoming magenta, Undated cyan, Completed green,
    /// the Trash the ink slot's graphite. A list's is its slot's, from its id (`ListModel.colorSlot`).
    func tile(for source: Source, palette p: Palette, scale: CGFloat = 1) -> ListTile {
        switch source {
        case .today: ListTile(content: .symbol("sun.max.fill"), hue: p.tileToday, scale: scale)
        case .upcoming: ListTile(content: .symbol("calendar"), hue: p.tile(.magenta), scale: scale)
        case .undated: ListTile(content: .symbol("square.stack"), hue: p.tile(.cyan), scale: scale)
        case .completed: ListTile(content: .symbol("checkmark.circle"), hue: p.tile(.green), scale: scale)
        case .trash: ListTile(content: .symbol("trash"), hue: p.tile(.ink), scale: scale)
        case let .list(id):
            if let l = list(id) { ListTile(content: .mono(l.monogram), hue: p.tile(slot: l.colorSlot), scale: scale) }
            else { ListTile(content: .mono("?"), hue: p.tile(.ink), scale: scale) }
        }
    }
}

// MARK: - Names in menus

/// A name as a menu item shows it: one line, cut with an ellipsis, as the Mac's menus cut a list's name
/// (app/Tasks/Window/Menus.swift `fit`, v2 feedback 16); iOS would wrap a long one to three lines. The Mac cuts at
/// 280pt. A phone's menu is 250pt wide, and with the checkmark column the details' List picker holds 150pt but not
/// 160pt of an item's text (measured on the simulator, 2026-11-02), so names are cut at 145pt in the menu's font
/// (body, so it follows Dynamic Type).
enum MenuName {
    static func fit(_ s: String, width: CGFloat = 145, font: UIFont = .preferredFont(forTextStyle: .body)) -> String {
        func w(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: [.font: font]).width }
        guard w(s) > width else { return s }
        var lo = 0, hi = s.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if w(String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…") <= width { lo = mid } else { hi = mid - 1 }
        }
        return String(s.prefix(lo)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Ending adding

extension View {
    /// While a new task is being added, a tap here only ends adding (the user, 2026-11-02): a typed title is written,
    /// an empty row goes, and the tap goes no further, so the row or control under it doesn't act, as a tap that closes
    /// an open task's sheet doesn't. On the Mac a press elsewhere also does what it presses (INTERACTIONS-v2 §6); this
    /// is a deliberate difference. Only taps are caught: inside a list, a drag still scrolls (which ends adding too, by
    /// putting the keyboard away). `applies` false leaves the view alone (the new-task row itself).
    func endsAddingOnTap(_ applies: Bool = true) -> some View { modifier(EndsAddingOnTap(applies: applies)) }
}

private struct EndsAddingOnTap: ViewModifier {
    let applies: Bool
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.overlay {
            if applies, app.draft != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { app.endDraft() }
                    .accessibilityHidden(true)
            }
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
    var cue = ViewGroups.RingCue()
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
                if !checked && cue.planned && cue.deadline != nil {
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
        if let d = cue.deadline { return d == .late ? p.danger : p.attention }
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

/// The quiet When: glyph and date in ink-tertiary, no capsule (`DateLabel.whenChip`: "Today", "Tomorrow", "in 2d"…).
struct QuietWhen: View {
    let date: CalendarDate
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        let text = DateLabel.whenChip(date, today: app.today)
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 10.5, weight: .medium))
            Text(text).font(Typo.quiet).monospacedDigit()
        }
        .foregroundStyle(p.inkTertiary)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("When \(text)")
    }
}

/// The deadline: the one capsule on a row, so a capsule always means something is due (`DateLabel.deadlineChip`:
/// "2d ago", "Due today", "3d left"…). In Upcoming, on its own day's group, "Due", as on the Mac.
struct DeadlineChip: View {
    let date: CalendarDate
    var groupDay: CalendarDate? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let c = DateLabel.deadlineChip(date, today: app.today)
        let text = date == groupDay ? "Due" : c.text
        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(c.tone == .soon ? p.attention : fg(c.tone))
            Text(text)
                .font(Typo.chip)
                .monospacedDigit()
        }
        .foregroundStyle(fg(c.tone))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(bg(c.tone), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deadline, \(DateLabel.deadlineWords(date, today: app.today))")
    }

    private func fg(_ t: DateLabel.Tone) -> Color { t == .late ? p.danger : t == .due ? p.attention : p.inkSecondary }
    private func bg(_ t: DateLabel.Tone) -> Color { t == .late ? p.dangerTint : t == .due ? p.attentionTint : p.fillControl }
}

/// The detail pane's date capsule: the date ("Fri, Nov 6", `DateLabel.long`, as the Mac's detail pane), or a ghost
/// "Add date".
struct DateChip: View {
    let date: CalendarDate?
    let kind: DateKind
    var active = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 6) {
            if let date {
                Image(systemName: kind == .when ? "calendar" : "flag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor(date))
                Text(DateLabel.long(date, today: app.today))
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

    private func iconColor(_ d: CalendarDate) -> Color {
        if kind == .when { return d <= app.today ? p.plan : p.inkSecondary }
        switch DateLabel.deadlineChip(d, today: app.today).tone {
        case .late: return p.danger
        case .due, .soon: return p.attention
        case .neutral: return p.inkSecondary
        }
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
/// two rings and their trails, and the ink bar. The head is lit as the Mac's is (BrandMark): the tile's finish, round,
/// with no specular strip.
struct LogoMark: View {
    var size: CGFloat = 28
    @Environment(\.palette) private var p
    @Environment(\.displayScale) private var displayScale

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
                // The head's art reaches `outset` past the circle for its halo; the check is cut out of it.
                let head = r(322 - 100, 336 - 100, 200, 200)
                if let art = TileArt.image(hue: p.value(.markHead), halo: p.tileHalo, size: head.size,
                                           radius: head.width / 2, scale: displayScale, specular: false) {
                    let o = TileArt.outset
                    l.draw(Image(decorative: art, scale: displayScale), in: head.insetBy(dx: -o, dy: -o))
                }
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
