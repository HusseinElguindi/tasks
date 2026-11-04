import SwiftUI
import UIKit
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
        func w(_ t: String) -> CGFloat { Self.width(t, font: font) }
        guard w(s) > width else { return s }
        var lo = 0, hi = s.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if w(String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…") <= width { lo = mid } else { hi = mid - 1 }
        }
        return String(s.prefix(lo)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A text's width in the menu's font.
    static func width(_ s: String, font: UIFont = .preferredFont(forTextStyle: .body)) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - Names and titles in rows

extension View {
    /// One line that, when it doesn't fit, is cut and fades out over its last `length` points instead of ending in an
    /// ellipsis, as the Mac's rows and sidebar do (its `FadeMask`; INTERACTIONS-v2 §12 and §24). A text that fits shows
    /// no fade. The fade is at the text's end: the right for a left-to-right text, the left for a right-to-left one, by
    /// `text`'s first letter (without `text`, the layout's direction decides), and the start stays in view.
    ///
    /// The fade is a mask on the text alone, so the row's fill, a selection or Glass shows through it in either
    /// appearance. VoiceOver reads the whole text; a cut one is one element the size of what shows, and only what shows
    /// takes touches. Cheap in long lists: no GeometryReader and no state. `ViewThatFits` picks the text at its own width
    /// or the cut one, and only a cut text has a mask. The fade is never more than half of what shows (the Mac's list
    /// name, `min(24, width / 2)`), and it grows with Dynamic Type, as the text does.
    func fadeTruncation(_ length: CGFloat, text: String? = nil) -> some View {
        modifier(FadeTruncation(length: length, rightToLeft: text.flatMap(\.startsRightToLeft)))
    }
}

private struct FadeTruncation: ViewModifier {
    let rightToLeft: Bool?
    @ScaledMetric private var length: CGFloat
    @Environment(\.layoutDirection) private var layout

    init(length: CGFloat, rightToLeft: Bool?) {
        _length = ScaledMetric(wrappedValue: length, relativeTo: .body)
        self.rightToLeft = rightToLeft
    }

    func body(content: Content) -> some View {
        let line = content.lineLimit(1).fixedSize(horizontal: true, vertical: false)
        // The side the text starts on stays in view; the other is cut and fades.
        let startsRight = rightToLeft ?? (layout == .rightToLeft)
        ViewThatFits(in: .horizontal) {
            line
            line
                .frame(minWidth: 0, maxWidth: .infinity,
                       alignment: startsRight == (layout == .rightToLeft) ? .leading : .trailing)
                .contentShape(Rectangle())
                .mask { FadeEdge(length: length, onLeft: startsRight) }
                .accessibilityElement(children: .combine)
        }
    }
}

/// The mask: opaque, then clear over the last `length` points (at most half the width) at one side, laid out left to
/// right whatever the layout's direction, since the side is the text's.
private struct FadeEdge: View {
    let length: CGFloat
    let onLeft: Bool
    var body: some View {
        let ramp = LinearGradient(colors: [.black, .clear], startPoint: onLeft ? .trailing : .leading,
                                  endPoint: onLeft ? .leading : .trailing)
            .frame(maxWidth: length)
        HStack(spacing: 0) {
            if onLeft { ramp; Color.black } else { Color.black; ramp }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

extension String {
    /// Whether the text reads right to left, from its first letter (nil when it has none): letters of the Hebrew,
    /// Arabic, Syriac, Thaana, N'Ko and the other right-to-left blocks. Unicode's first strong character, near enough
    /// for a name.
    var startsRightToLeft: Bool? {
        for u in unicodeScalars where u.properties.isAlphabetic {
            switch u.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: return true
            default: return false
            }
        }
        return nil
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
/// accent and draws the mark; checked here, it sparks (COLOR.md §4, the Mac's `CheckLayer` and `SparkLayer`).
struct Checkbox: View {
    let checked: Bool
    /// Its task's title, for VoiceOver: "Complete: ECE 358 lab report, overdue" (the Mac's checkbox label).
    var title: String? = nil
    var cue = ViewGroups.RingCue()
    var readOnly = false
    var placeholder = false
    var size: CGFloat = Metric.check
    /// Checked on this device, just now (the box, a swipe, the menu, the sheet's box): it sparks as it checks. A check
    /// that syncs in from elsewhere just shows the box done.
    var sparks = false
    /// One of several a bulk Complete checks at once: the screen gives one haptic for them all (§3).
    var quiet = false
    var action: () -> Void = {}
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the checks made here, each of which runs the spark once; and every check or uncheck, for the pop.
    @State private var sparkRuns = 0
    @State private var pops = 0

    /// The Mac's lengths scale with the box: k = its size ÷ 16 (1.375 on a row, 1.5 in the sheet).
    private var k: CGFloat { size / 16 }

    var body: some View {
        Button(action: action) {
            KeyframeAnimator(initialValue: CheckMoment(), trigger: sparkRuns) { m in
                KeyframeAnimator(initialValue: 1.0, trigger: pops) { scale in
                    box(m)
                        .overlay { Spark(moment: m, k: k, color: p.spark).allowsHitTesting(false) }
                        .scaleEffect(scale)
                } keyframes: { _ in
                    // Checked or unchecked, it pops from 0.8 on `snappy` (§8).
                    KeyframeTrack {
                        MoveKeyframe(0.8)
                        SpringKeyframe(1, duration: 0.3, spring: .snappy(duration: 0.2))
                    }
                }
            } keyframes: { _ in
                CheckMoment.spark
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        // The trigger counts, not `checked`, so the keyframes needn't know which way it went: a check made here sparks
        // and pops; an uncheck pops; a check from elsewhere just shows. Under Reduce Motion nothing runs.
        .onChange(of: checked) { _, now in
            // The haptic is UIKit's: `.sensoryFeedback` stays silent in a UIHostingConfiguration cell, which is where
            // the rows' boxes live since the collection view.
            if !quiet { Haptic.check(now) }
            guard !reduceMotion, !now || sparks else { return }
            if now { sparkRuns += 1 }
            pops += 1
        }
        .buttonStyle(CheckPressStyle())
        .disabled(readOnly || placeholder)
        .accessibilityLabel(label)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func box(_ m: CheckMoment) -> some View {
        // Checked, the fill and the ring go from the spark to the accent (520 ms ease-out) and the mark draws in
        // (160 ms, after 40); unchecked, the fill and the mark go out in 160 ms. A check from elsewhere just shows.
        let on = p.spark.mix(with: p.accent, by: 1 - m.heat)
        let draw: Animation? = checked ? (sparks ? .easeOut(duration: 0.16).delay(0.04) : nil) : .easeOut(duration: 0.16)
        return ZStack {
            Circle().fill(checked ? on : .clear)
                .motion(checked ? nil : .easeOut(duration: 0.16), value: checked)
            Circle().strokeBorder(checked ? on : ringColor, lineWidth: 1.5)
                .motion(checked ? nil : .easeOut(duration: 0.16), value: checked)
            if !checked && cue.planned && cue.deadline != nil {
                Circle().strokeBorder(p.plan, lineWidth: 1.25).padding(size * 0.19)
            }
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(p.onAccent, style: StrokeStyle(lineWidth: 2.2 * k * 0.85, lineCap: .round, lineJoin: .round))
                .padding(size * 0.06)
                .motion(draw, value: checked)
        }
        .frame(width: size, height: size)
        .opacity(placeholder ? 0.7 : readOnly ? 0.6 : 1)
    }

    /// "Complete: Buy milk, overdue, planned for today"; "Mark not done: Buy milk" (the Mac's `TaskRowView`, with its
    /// `CheckLayer.Cue.words`).
    private var label: String {
        guard let title else { return checked ? "Completed" : "Complete" }
        if checked { return "Mark not done: " + title }
        let words = (cue.deadline == .late ? ", overdue" : cue.deadline == .due ? ", due today" : "")
            + (cue.planned ? ", planned for today" : "")
        return "Complete: " + title + words
    }

    private var ringColor: Color {
        if placeholder { return p.inkQuiet }
        if let d = cue.deadline { return d == .late ? p.danger : p.attention }
        if cue.planned { return p.plan }
        return p.lineField
    }
}

/// Pressed, the box scales to 0.86 (80 ms ease-out) and comes back on `snappy`. Not under Reduce Motion: it stays at its
/// size.
private struct CheckPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.86 : 1)
            .motion(configuration.isPressed ? .easeOut(duration: 0.08) : Motion.snappy, value: configuration.isPressed)
    }
}

/// One check's moment: the box's warmth (1 = the spark's colour), and the spark's ring and rays, each as its progress
/// along its curve. At rest everything is 0.
struct CheckMoment {
    var heat: Double = 0
    var ring: CGFloat = 0
    var ringAlpha: Double = 0
    var rays: CGFloat = 0
    var raysAlpha: Double = 0

    /// A check made here: the warm fill (520 ms ease-out), the ring (460 ms) and the rays (560 ms, their opacity
    /// peaking at 22%), on the Mac's curve.
    @KeyframesBuilder<CheckMoment>
    static var spark: some Keyframes<CheckMoment> {
        KeyframeTrack(\.heat) {
            MoveKeyframe(1)
            LinearKeyframe(0, duration: 0.52, timingCurve: .easeOut)
        }
        KeyframeTrack(\.ring) {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.46, timingCurve: Motion.flight)
        }
        KeyframeTrack(\.ringAlpha) {
            MoveKeyframe(0.95)
            LinearKeyframe(0, duration: 0.46, timingCurve: Motion.flight)
        }
        KeyframeTrack(\.rays) {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.56, timingCurve: Motion.flight)
        }
        KeyframeTrack(\.raysAlpha) {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.56 * 0.22, timingCurve: Motion.flight)
            LinearKeyframe(0, duration: 0.56 * 0.78, timingCurve: Motion.flight)
        }
    }
}

/// The spark that leaves a box as it's checked (`.check .spark`, the Mac's `SparkLayer`), in the Mac's 16-unit lengths
/// × k: a ring of radius 9 going from 0.9× to 2.1× as its stroke thins from 2.5 to 0.4, and eight rays every 45° from
/// 11 to 17 out (the odd four 11.03 to 15.98), 1.75 wide with round caps, from 0.55× and −8° to 1.2×. At its widest it
/// reaches 20.4k from the centre, 28pt on a row: past the 48pt row by 4, so it's drawn unclipped.
private struct Spark: View {
    let moment: CheckMoment
    let k: CGFloat
    let color: Color

    var body: some View {
        let reach = 21 * k
        Canvas { ctx, size in
            guard moment.ringAlpha > 0.001 || moment.raysAlpha > 0.001 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            if moment.ringAlpha > 0.001 {
                let r = 9 * k * (0.9 + 1.2 * moment.ring)
                let w = k * (2.5 - 2.1 * moment.ring)
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(ring, with: .color(color.opacity(moment.ringAlpha)), lineWidth: w * (0.9 + 1.2 * moment.ring))
            }
            if moment.raysAlpha > 0.001 {
                let scale = 0.55 + 0.65 * moment.rays
                let turn = -8 * .pi / 180 * (1 - moment.rays)
                var rays = Path()
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4 + turn, (cs, sn) = (cos(a), sin(a))
                    let (r0, r1): (CGFloat, CGFloat) = i % 2 == 0 ? (11, 17) : (11.03, 15.98)
                    rays.move(to: CGPoint(x: c.x + cs * r0 * k * scale, y: c.y + sn * r0 * k * scale))
                    rays.addLine(to: CGPoint(x: c.x + cs * r1 * k * scale, y: c.y + sn * r1 * k * scale))
                }
                ctx.stroke(rays, with: .color(color.opacity(moment.raysAlpha)),
                           style: StrokeStyle(lineWidth: 1.75 * k * scale, lineCap: .round))
            }
        }
        .frame(width: 2 * reach, height: 2 * reach)
        .accessibilityHidden(true)
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

/// A row's press: its own rounded fill, instant in, quick out. Selection uses the same shape. With `fadesOut`, the
/// selected fill fades out over 300 ms ease-out when it goes (the phone's row whose details just closed, as in Mail
/// and Settings), so you can see which row you came from; it comes in at once.
///
/// In select mode (`picked`, §3) the fill is the same, with no animation either way (IX §5: selection never animates),
/// and selected neighbours join: the corners they share go square. The rows sit on a 48pt pitch with no gap, so there's
/// none to fill (the Mac fills its 2pt one).
struct RowStyle: ButtonStyle {
    var selected = false
    var focused = true
    var fadesOut = false
    var picked = false
    var joinTop = false
    var joinBottom = false
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        let r = Metric.rowRadius
        configuration.label
            .background {
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: joinTop ? 0 : r, bottomLeadingRadius: joinBottom ? 0 : r,
                                           bottomTrailingRadius: joinBottom ? 0 : r, topTrailingRadius: joinTop ? 0 : r,
                                           style: .continuous)
                        .fill(p.fillRowSelected)
                        .opacity(picked ? 1 : 0)
                        .animation(nil, value: picked)
                        .animation(nil, value: joinTop)
                        .animation(nil, value: joinBottom)
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(configuration.isPressed ? p.press : selected ? (focused ? p.fillRowSelected : p.fillRowSelectedDim) : .clear)
                        .motion(configuration.isPressed ? nil : .easeOut(duration: 0.085), value: configuration.isPressed)
                        .motion(fadesOut && !selected ? .easeOut(duration: 0.3) : nil, value: selected)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
    }
}

/// Pane's capsule buttons: primary, tinted, neutral, destructive.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, tinted, neutral, destructive }
    var kind: Kind = .neutral
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(CapsuleFace(kind: kind, height: height, pressed: configuration.isPressed))
    }
}

/// A capsule button's look, for a menu's label as well (a menu's label takes no button style).
struct CapsuleFace: ViewModifier {
    let kind: CapsuleButtonStyle.Kind
    let height: CGFloat
    var pressed = false
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(bg, in: Capsule())
            .overlay { if pressed { Capsule().fill(Color.black.opacity(0.14)) } }
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

extension View {
    func capsuleFace(_ kind: CapsuleButtonStyle.Kind, height: CGFloat = 32) -> some View {
        modifier(CapsuleFace(kind: kind, height: height))
    }
}

// MARK: - Group label

struct GroupLabel: View {
    let title: String
    var sub: String? = nil
    var quiet = false
    /// A drag in Upcoming is over its day (the Mac's `dayTarget`): the name in accent-text.
    var hot = false
    /// The air above it: none when an edge row (`Line.edge`) holds it.
    var top: CGFloat = GroupLabel.air
    var bottom: CGFloat = 6
    static let air: CGFloat = 18
    @Environment(\.palette) private var p
    var body: some View {
        // Cut off, the name and the day's date fade out at their ends, as a title does (the Mac's GroupLabelView).
        HStack(spacing: 6) {
            Text(title).font(Typo.label).foregroundStyle(hot ? p.accentText : quiet ? p.inkQuiet : p.inkTertiary)
                .fadeTruncation(Metric.titleFade, text: title)
            if let sub {
                Text(sub).font(Typo.quiet).foregroundStyle(p.inkQuiet).fadeTruncation(Metric.titleFade, text: sub)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.leading, Metric.rowPad + 2)
        .padding(.top, top)
        .padding(.bottom, bottom)
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

/// A box's haptic, from UIKit's generators: a check is `.success`, an uncheck `.selection` (§3).
enum Haptic {
    @MainActor static func check(_ checked: Bool) {
        if checked { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UISelectionFeedbackGenerator().selectionChanged() }
    }
}
