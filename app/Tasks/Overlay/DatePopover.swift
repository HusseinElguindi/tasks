import AppKit
import SwiftUI
import TasksCore

// The date popover (INTERACTIONS-v2 §11 "The popover (288pt)", §16, §18.8, §21), ported 1:1 from the prototype:
// template dc:200–211, `openPicker` dc:1114–1124, the keys dc:1737–1766, the view model dc:2032–2054, and
// css:317–342 (with the surface css:56–58/74 and "Popover in" css:371).
//
// Top to bottom, inside 8pt of padding on a 288pt `surface-popover`: the field (28), the quick picks 8 below (22, then
// 2), the month row (8 / 22 / 4), the grid (a 20pt weekday row and six 28pt weeks, 2 apart) and the footer under a
// hairline (6 above it, 8 inside). 343pt in all; placement uses the prototype's 344.

/// Places the popover for `picker` in the window's overlay layer (`OverlayLayer`): 6pt under its anchor, left-aligned
/// with it and kept 8pt inside the window, flipped above the anchor when it wouldn't fit (dc:1120–1122).
struct DatePopoverHost: View {
    let store: Store
    @Bindable var window: WindowState
    let picker: Overlays.Picker
    let windowSize: CGSize

    static let width: CGFloat = 288
    /// The prototype's `ph`, used only to place it (the drawn popover is 343).
    static let placementHeight: CGFloat = 344

    /// Top-left in window coordinates (top-left origin). `clamp(v, lo, hi)` is the prototype's `max(lo, min(hi, v))`.
    static func origin(anchor: CGRect, in size: CGSize) -> CGPoint {
        let x = max(8, min(size.width - width - 8, anchor.minX))
        var y = anchor.maxY + 6
        if y + placementHeight > size.height - 8 { y = max(8, anchor.minY - placementHeight - 6) }
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        let o = Self.origin(anchor: picker.anchor, in: windowSize)
        DatePopover(store: store, window: window, picker: picker)
            .id(picker.token)
            .padding(.leading, o.x)
            .padding(.top, o.y)
            // No exit animation (§21): it goes the moment the request does.
            .transition(.identity)
    }
}

// MARK: - State

/// What the popover shows (the prototype's `state.picker`): the text, the highlighted day, the month shown.
@MainActor
@Observable
private final class DatePickModel {
    let field: Overlays.Picker.Field
    let ids: [EntityID]
    let today: CalendarDate
    /// The selected tasks' date when they all share it (dc:1119): the ring, Clear and ⌫-to-clear depend on it.
    let cur: CalendarDate?
    /// The first task's other date (its deadline while picking When, and the reverse): the dot.
    let other: CalendarDate?
    /// How "11/9" reads in the user's locale (read once: it builds a date format).
    private static let order = DatePhrase.numericOrder(for: .current)

    var text = ""
    /// The highlighted day: what Return sets.
    var hot: CalendarDate
    /// The 1st of the month shown.
    var month: CalendarDate
    /// The text reads as no date: nothing is highlighted and Return does nothing.
    var none = false

    init(store: Store, picker: Overlays.Picker) {
        let p = store.projection
        today = p.day.date
        field = picker.field
        ids = picker.ids
        let tasks = picker.ids.compactMap { p.task($0) }
        let value: (TaskItem) -> CalendarDate? = picker.field == .when ? { $0.when } : { $0.deadline }
        let first = tasks.first
        let v0 = first.flatMap(value)
        cur = tasks.allSatisfy { value($0) == v0 } ? v0 : nil
        other = picker.field == .when ? first?.deadline : first?.when
        hot = cur ?? today
        month = (cur ?? today).firstOfMonth
    }

    /// Typing moves the highlighted day (and the month) to what the text means; clearing it puts it back (dc:1739–1747).
    func typed(_ new: String) {
        text = new
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            none = false
            hot = cur ?? today
            month = hot.firstOfMonth
        } else if let hit = DatePhrase.match(new, today: today, numericOrder: Self.order) {
            none = false
            hot = hit
            month = hit.firstOfMonth
        } else {
            none = true
        }
    }

    /// ← → a day, ↑ ↓ a week; the month follows (dc:1753).
    func move(days n: Int) {
        hot = hot.adding(days: n)
        month = hot.firstOfMonth
        none = false
    }

    /// ‹ › change only the month shown (dc:1764).
    func showMonth(_ delta: Int) {
        month = DatePhrase.adding(months: delta, to: month)
    }

    var placeholder: String {
        field == .when ? "When: try tom, fri, 3d, nov 9" : "Deadline: try fri, nov 9, 2w"
    }

    /// Today · Tomorrow · Next Week, and Clear when the tasks share a date (dc:2045–2046).
    var quick: [Quick] {
        var q = [Quick(label: "Today", date: today), Quick(label: "Tomorrow", date: today.adding(days: 1)),
                 Quick(label: "Next Week", date: DatePhrase.nextWeek(from: today))]
        if cur != nil { q.append(Quick(label: "Clear", date: nil)) }
        return q
    }

    struct Quick: Identifiable {
        let label: String
        /// nil: Clear.
        let date: CalendarDate?
        var id: String { label }
    }

    /// The six weeks shown, from the locale's first weekday (the prototype starts on Sunday).
    func days(firstWeekday: Int) -> [CalendarDate] {
        let lead = (month.weekday - firstWeekday + 7) % 7
        var d = month.adding(days: -lead)
        var out = [d]
        out.reserveCapacity(42)
        for _ in 1..<42 {
            d = d.nextDay
            out.append(d)
        }
        return out
    }

    /// "Fri, Nov 6 · in 7 days"; a deadline "Due Sun, Nov 1 · tomorrow", and a past one "… · 1 day overdue"; or
    /// "No date matches “xyz”" (§24, dc:2926). With a `hint`, the hint takes the relative words' place.
    var preview: String {
        if none { return "No date matches “" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "”" }
        let date = (field == .deadline ? "Due " : "") + DateLabel.long(hot, today: today)
        if hint != nil { return date }
        let words = field == .deadline && hot < today ? DateLabel.deadlineWords(hot, today: today) : DateLabel.relative(hot, today: today)
        return date + " · " + words
    }

    /// A When after the deadline, or a deadline before the When: a note, not a rule (SPEC §2 has none; §24, dc:2924).
    var hint: String? {
        guard !none, let other else { return nil }
        if field == .when, hot > other { return "after the deadline" }
        if field == .deadline, hot < other { return "before the When" }
        return nil
    }
}

private extension CalendarDate {
    var firstOfMonth: CalendarDate { CalendarDate(year: year, month: month, day: 1) ?? self }

    var nextDay: CalendarDate {
        if day < CalendarDate.daysIn(month: month, year: year) { return CalendarDate(year: year, month: month, day: day + 1) ?? self }
        if month < 12 { return CalendarDate(year: year, month: month + 1, day: 1) ?? self }
        return CalendarDate(year: year + 1, month: 1, day: 1) ?? self
    }
}

// MARK: - The popover

private enum Metrics {
    static let inner: CGFloat = 272          // 288 − 2 × 8
    static let cell: CGFloat = inner / 7     // ≈ 38.9
    static let letters = ["S", "M", "T", "W", "T", "F", "S"]  // Sunday first, like `CalendarDate.weekday`
}

private struct DatePopover: View {
    let store: Store
    let window: WindowState
    @State private var model: DatePickModel
    @State private var shown = false
    @State private var fieldRef = FieldRef()
    @Environment(\.tk) private var tk

    init(store: Store, window: WindowState, picker: Overlays.Picker) {
        self.store = store
        self.window = window
        _model = State(initialValue: DatePickModel(store: store, picker: picker))
    }

    private var actions: WindowActions { WindowActions(store: store, window: window) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            quickPicks
                .padding(.top, 8)
                .padding(.bottom, 2)
            monthRow
            grid
            footer
        }
        .padding(8)
        .frame(width: DatePopoverHost.width, alignment: .topLeading)
        .background { Surface() }
        // A press anywhere on the popover stays in it and leaves the keys in the field (dc:1765).
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .circular))
        .onTapGesture { fieldRef.focus() }
        // A click in it counts even while the window isn't key, as the press outside does (`PressCatcher`).
        .modifier(FirstMouse())
        // Popover in (css:371): 120 ms, cubic-bezier(0, 0, 0.2, 1), opacity 0 → 1, y −3 → 0, scale 0.985 → 1.
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.985)
        .offset(y: shown ? 0 : -3)
        .onAppear {
            #if DEBUG
            DebugPicker.current = model
            #endif
            withAnimation(Self.popIn) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose a date")
        .accessibilityAddTraits(.isModal)
    }

    private static var popIn: Animation? {
        #if DEBUG
        if DebugPicker.slow > 0, !TK.Motion.reduce { return .timingCurve(0, 0, 0.2, 1, duration: 0.12 * DebugPicker.slow) }
        #endif
        return TK.Motion.popoverIn
    }

    // MARK: Applying (dc:1749–1761)

    /// Sets the date on every task and gives the keys back to the window; the focused pane stays (§11).
    private func apply(_ date: CalendarDate?) {
        let a = actions
        a.setDate(model.ids, model.field, date)
        a.focus(window.focus)
    }

    private func key(_ k: DateTypingField.Key) {
        switch k {
        case .left: model.move(days: -1)
        case .right: model.move(days: 1)
        case .up: model.move(days: -7)
        case .down: model.move(days: 7)
        case .deleteEmpty: if model.cur != nil { apply(nil) }
        case .returnKey: if !model.none { apply(model.hot) }
        case .escape: actions.closePicker()
        }
    }

    // MARK: The field (css:318–319)

    private var field: some View {
        HStack(spacing: 0) {
            // The date it sets: the calendar for When, the flag for Deadline (§24).
            GlyphView(glyph: model.field == .when ? .calendar : .flag, size: 14, color: tk.inkTertiary.swiftUI)
            DateFieldView(placeholder: model.placeholder, ref: fieldRef,
                          onText: { model.typed($0) }, onKey: { key($0) })
                .padding(.leading, 7)
                .frame(maxWidth: .infinity)
                // Measured against the prototype: its input's text sits half a point higher than the centered field.
                .offset(y: -0.5)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(tk.fillControl.swiftUI, in: RoundedRectangle(cornerRadius: 8, style: .circular))
    }

    // MARK: Quick picks (css:320–325)

    private var quickPicks: some View {
        HStack(spacing: 6) {
            ForEach(model.quick) { q in
                QuickPick(label: q.label, clear: q.date == nil,
                          hot: q.date != nil && q.date == model.hot && !model.text.isEmpty) {
                    apply(q.date)
                }
            }
        }
    }

    // MARK: The month (css:326–329)

    private var monthRow: some View {
        HStack(spacing: 0) {
            Text(DateLabel.monthTitle(year: model.month.year, month: model.month.month))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tk.ink.swiftUI)
                .lineLimit(1)
            Spacer(minLength: 0)
            MonthArrow(glyph: .chevronLeft, label: "Previous month") {
                model.showMonth(-1)
                fieldRef.focus()
            }
            MonthArrow(glyph: .chevronRight, label: "Next month") {
                model.showMonth(1)
                fieldRef.focus()
            }
        }
        .frame(height: 22)
        .padding(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 2))
    }

    // MARK: The grid (css:330–337)

    private var grid: some View {
        let first = Calendar.current.firstWeekday
        let days = model.days(firstWeekday: first)
        let m = model
        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Metrics.letters[(first - 1 + i) % 7])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tk.inkTertiary.swiftUI)
                        .frame(width: Metrics.cell, height: 20)
                        .offset(y: 0.5)
                }
            }
            .accessibilityHidden(true)
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = days[week * 7 + i]
                        DayCell(date: d, today: m.today,
                                out: d.year != m.month.year || d.month != m.month.month,
                                isToday: d == m.today, isCur: d == m.cur, isOther: d == m.other, otherIsDeadline: m.field == .when,
                                isHot: d == m.hot && !m.none) {
                            apply(d)
                        }
                    }
                }
            }
        }
    }

    // MARK: The footer (css:338–341)

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(tk.lineSeparator.swiftUI).frame(height: 1)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(model.preview)
                        .foregroundStyle((model.none ? tk.inkTertiary : tk.ink).swiftUI)
                    // "· after the deadline": the dot in `ink-tertiary`, the note in `attention` (css:536–537).
                    if let hint = model.hint {
                        Text("· ").foregroundColor(tk.inkTertiary.swiftUI) + Text(hint).foregroundColor(tk.attention.swiftUI)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("↩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tk.inkTertiary.swiftUI)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 16)
            .padding(EdgeInsets(top: 8, leading: 4, bottom: 2, trailing: 4))
        }
        .padding(.top, 6)
    }
}

// MARK: - Controls

private struct FirstMouse: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.allowsWindowActivationEvents(true) } else { content }
    }
}

/// `surface-popover` with `shadow-popover` (css:57, 74): a 0.5pt ring outside the edge plus `0 12 32`. The shadow is
/// cast by the surface alone (a shadow on the whole popover would be cast by each day and capsule in it).
private struct Surface: View {
    @Environment(\.tk) private var tk

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        ZStack {
            shape.fill(tk.popover.swiftUI)
            shape.stroke(tk.shadowPopoverRing.swiftUI, lineWidth: 0.5).padding(-0.25)
        }
        .compositingGroup()
        .shadow(color: tk.shadowPopover.swiftUI, radius: 16, x: 0, y: 12)
    }
}

/// A quick pick (css:322–325): 22 tall, padding 9, radius 11, `fill-control`, 12pt `ink` (Clear `ink-secondary`).
/// Hover: `fill-track`, all of it brightened 1.12 (light 0.97); the pick matching the typing: `accent-tint` /
/// `accent-text`. Background, color and brightness ease on `icon`.
private struct QuickPick: View {
    let label: String
    let clear: Bool
    let hot: Bool
    let action: () -> Void
    @Environment(\.tk) private var tk
    @State private var hovered = false

    var body: some View {
        let b = hovered ? tk.buttonHoverBrightness : 1
        let bg = (hot ? tk.accentTint : hovered ? tk.fillTrack : tk.fillControl).brightness(b)
        let fg = (hot ? tk.accentText : clear ? tk.inkSecondary : tk.ink).brightness(b)
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(fg.swiftUI)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(bg.swiftUI, in: Capsule(style: .circular))
            .contentShape(Capsule(style: .circular))
            .animation(TK.Motion.icon, value: hovered)
            .animation(TK.Motion.icon, value: hot)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// ‹ › (css:329): 22×22, radius 6, a 12pt chevron in `ink-secondary`; hover: `hover` fill (eased on `icon`) and `ink`
/// (at once: only the fill has a transition).
private struct MonthArrow: View {
    let glyph: Glyph
    let label: String
    let action: () -> Void
    @Environment(\.tk) private var tk
    @State private var hovered = false

    var body: some View {
        GlyphView(glyph: glyph, size: 12, color: (hovered ? tk.ink : tk.inkSecondary).swiftUI)
            .frame(width: 22, height: 22)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill((hovered ? tk.hover : .clear).swiftUI)
                    .animation(TK.Motion.icon, value: hovered)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .circular))
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// A day (css:333–337): a 28pt capsule a seventh of the grid wide, 12pt tabular. Other months `ink-quiet`; today
/// `accent-text` semibold; the current date a 1.5pt inset `accent` ring; the other date a 4pt dot 3pt from the
/// bottom, by kind: a deadline `attention`, a When `ink-tertiary` (§24); the highlighted day `accent` with
/// `on-accent` semibold and no ring. Hover: `hover`. Only the fill eases (`icon`), as in the CSS.
private struct DayCell: View {
    let date: CalendarDate
    let today: CalendarDate
    let out: Bool
    let isToday: Bool
    let isCur: Bool
    let isOther: Bool
    let otherIsDeadline: Bool
    let isHot: Bool
    let action: () -> Void
    @Environment(\.tk) private var tk
    @State private var hovered = false

    var body: some View {
        let state = isHot ? 2 : hovered ? 1 : 0
        let fill: NSColor = state == 2 ? tk.accent : state == 1 ? tk.hover : .clear
        let ink: NSColor = isHot ? tk.onAccent : isToday ? tk.accentText : out ? tk.inkQuiet : tk.ink
        Text(String(date.day))
            .font(.system(size: 12, weight: isHot || isToday ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(ink.swiftUI)
            .frame(width: Metrics.cell, height: 28)
            .background {
                Capsule(style: .circular).fill(fill.swiftUI).animation(TK.Motion.icon, value: state)
            }
            .overlay {
                if isCur && !isHot { Capsule(style: .circular).strokeBorder(tk.focus.swiftUI, lineWidth: 1.5) }
            }
            .overlay(alignment: .bottom) {
                if isOther {
                    Circle().fill((otherIsDeadline ? tk.attention : tk.inkTertiary).swiftUI).frame(width: 4, height: 4).padding(.bottom, 3)
                }
            }
            .contentShape(Capsule(style: .circular))
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(DateLabel.long(date, today: today))
            .accessibilityAddTraits(isHot ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}

// MARK: - The field

/// The popover's field, for the arrows and the month buttons to give the keys back to.
@MainActor
private final class FieldRef {
    weak var field: DateTypingField?
    func focus() { field?.takeKeys() }
}

private struct DateFieldView: NSViewRepresentable {
    let placeholder: String
    let ref: FieldRef
    let onText: (String) -> Void
    let onKey: (DateTypingField.Key) -> Void

    func makeNSView(context: Context) -> DateTypingField {
        let f = DateTypingField()
        ref.field = f
        return f
    }

    func updateNSView(_ f: DateTypingField, context: Context) {
        ref.field = f
        f.onText = onText
        f.onKey = onKey
        f.style(context.environment.tk, placeholder: placeholder)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView f: DateTypingField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: f.intrinsicContentSize.height)
    }
}

/// The text field (§11, §18.6): 13pt `ink` on nothing, its placeholder `ink-tertiary`. It takes the keys when it
/// appears. It never needs its caret keys: ← → ↑ ↓ (with any modifier, as the prototype reads `e.key`) move the
/// highlighted day; Return sets it; ⌫ in the empty field clears; Esc closes; Tab stays in the field. ⌘Z is the
/// field's own.
private final class DateTypingField: NSTextField, NSTextFieldDelegate {
    enum Key { case left, right, up, down, deleteEmpty, returnKey, escape }

    var onText: ((String) -> Void)?
    var onKey: ((Key) -> Void)?
    private let fieldUndo = UndoManager()
    private var palette: TK.Palette?
    private var placeholder = ""

    override class var cellClass: AnyClass? {
        get { DateFieldCell.self }
        set {}
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
        font = .systemFont(ofSize: 13)
        delegate = self
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityLabel("Type a date")
        (cell as? DateFieldCell)?.editor.keyHandler = { [weak self] code, empty in self?.arrowOrDelete(code, empty: empty) ?? false }
    }

    required init?(coder: NSCoder) { fatalError() }

    func style(_ p: TK.Palette, placeholder text: String) {
        guard p != palette || text != placeholder else { return }
        palette = p
        placeholder = text
        textColor = p.ink
        // The placeholder draws a pixel above the typed text; lowered to sit where the prototype's does.
        placeholderAttributedString = NSAttributedString(string: text, attributes: [.foregroundColor: p.inkTertiary, .font: NSFont.systemFont(ofSize: 13),
                                                                                     .baselineOffset: -0.25])
        if let editor = (cell as? DateFieldCell)?.editor {
            editor.insertionPointColor = p.ink
            editor.selectedTextAttributes = [.backgroundColor: p.textSelection]
        }
    }

    /// The field has the keys at once (§11).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        takeKeys()
        // Whatever handled the press that opened it may take the keys back in the same turn; take them after it.
        DispatchQueue.main.async { [weak self] in self?.takeKeys() }
    }

    func takeKeys() {
        guard let w = window, currentEditor() == nil || w.firstResponder !== currentEditor() else { return }
        w.makeFirstResponder(self)
        if let editor = currentEditor() {
            let n = (stringValue as NSString).length
            editor.selectedRange = NSRange(location: n, length: 0)
        }
    }

    /// From the field editor's `keyDown`: the arrows (any modifiers), and ⌫ (any modifiers) when the field is empty.
    private func arrowOrDelete(_ code: UInt16, empty: Bool) -> Bool {
        switch code {
        case 123: onKey?(.left)
        case 124: onKey?(.right)
        case 126: onKey?(.up)
        case 125: onKey?(.down)
        case 51 where empty: onKey?(.deleteEmpty)
        default: return false
        }
        return true
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onKey?(.returnKey)
        case #selector(NSResponder.cancelOperation(_:)):
            onKey?(.escape)
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            break
        case #selector(NSResponder.deleteBackward(_:)) where stringValue.isEmpty:
            onKey?(.deleteEmpty)
        default:
            return false
        }
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        if stringValue.contains(where: \.isNewline) {
            stringValue = stringValue.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
        onText?(stringValue)
    }

    // The field's own undo (§9: inside a text field ⌘Z is the field's). The selector is spelled out: inferred, it's
    // `undoManagerFor:`, which the field editor never calls, so its typing went to another undo manager (v2
    // feedback 13).
    @objc(undoManagerForTextView:) func undoManager(for view: NSTextView) -> UndoManager? { fieldUndo }
    override var undoManager: UndoManager? { fieldUndo }
    @objc func undo(_ sender: Any?) { FieldUndo.undo(fieldUndo) }
    @objc func redo(_ sender: Any?) { FieldUndo.redo(fieldUndo) }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        FieldUndo.validate(item, fieldUndo) ?? super.validateUserInterfaceItem(item)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Gives the field its own field editor, so its selection color, caret and key handling never touch the window's
/// shared one (the rename fields').
private final class DateFieldCell: NSTextFieldCell {
    let editor: DateFieldEditor = {
        let tv = DateFieldEditor(frame: .zero)
        tv.isFieldEditor = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        return tv
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

private final class DateFieldEditor: NSTextView {
    /// (keyCode, the field is empty) → handled.
    var keyHandler: ((UInt16, Bool) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() == false, keyHandler?(event.keyCode, string.isEmpty) == true { return }
        super.keyDown(with: event)
    }
}

// MARK: - Debug

#if DEBUG
/// Debug aid for checking the popover offscreen, with events posted straight to the window (no HID events: nothing
/// moves the real pointer, and the app is never activated). Call `DebugPicker.runIfRequested(store, window)` from a
/// debug hook (e.g. `OverlayLayer`'s `.onAppear`), then launch with:
///
///     -debugPicker when|deadline     opens it 0.8 s after launch
///     -debugPickerTask "A|B"         for these task titles (default: the first open task with a deadline)
///     -debugPickerAnchor x,y,w,h     the anchor in window points from the top left (default: the prototype's chip)
///     -debugPickerSlow 20            "Popover in" this many times slower
///     -debugPickerSteps "type:fri;key:left;click:X,Y;open;wait:200;snap:/a.png;log:/b.txt;hit:X,Y;quit"
///
/// Keys: left right up down delete return esc tab. `open` opens it again for the same tasks. `log` appends the
/// popover's state, the first responder and the tasks' dates. Clicks work with the app in the background because the
/// popover takes the first click; hover can't be posted (tracking areas follow the real pointer).
@MainActor
enum DebugPicker {
    fileprivate static weak var current: DatePickModel?
    private static var ids: [EntityID] = []
    private static var reopen: (() -> Void)?
    static var slow: Double { UserDefaults.standard.double(forKey: "debugPickerSlow") }

    static func runIfRequested(_ store: Store, _ window: WindowState) {
        let d = UserDefaults.standard
        guard let f = d.string(forKey: "debugPicker") else { return }
        let field: Overlays.Picker.Field = f == "deadline" ? .deadline : .when
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let p = store.projection
            var ids: [EntityID] = []
            if let titles = d.string(forKey: "debugPickerTask") {
                ids = titles.split(separator: "|").compactMap { t in p.allTaskIDs.first { p.task($0)?.title == String(t) } }
            } else if let id = p.allTaskIDs.sorted().first(where: { p.task($0)?.deadline != nil && p.task($0)?.completedAt == nil }) {
                ids = [id]
            }
            let a = (d.string(forKey: "debugPickerAnchor") ?? "1078.9,148,52.1,18").split(separator: ",").compactMap { Double($0) }
            guard !ids.isEmpty, a.count == 4 else { NSLog("debugPicker: no task or anchor"); return }
            Self.ids = ids
            reopen = { WindowActions(store: store, window: window).openPicker(field, ids: ids, anchor: CGRect(x: a[0], y: a[1], width: a[2], height: a[3])) }
            reopen?()
            let steps = (d.string(forKey: "debugPickerSteps") ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                for step in steps { await run(step, store: store, window: window) }
            }
        }
    }

    private static func run(_ step: String, store: Store, window: WindowState) async {
        guard let w = window.nsWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "type":
            for ch in arg { key(w, code: 0, chars: String(ch)) }
        case "key":
            switch arg {
            case "left": key(w, code: 123, chars: String(UnicodeScalar(NSLeftArrowFunctionKey)!), flags: [.numericPad, .function])
            case "right": key(w, code: 124, chars: String(UnicodeScalar(NSRightArrowFunctionKey)!), flags: [.numericPad, .function])
            case "up": key(w, code: 126, chars: String(UnicodeScalar(NSUpArrowFunctionKey)!), flags: [.numericPad, .function])
            case "down": key(w, code: 125, chars: String(UnicodeScalar(NSDownArrowFunctionKey)!), flags: [.numericPad, .function])
            case "delete": key(w, code: 51, chars: "\u{7f}")
            case "return": key(w, code: 36, chars: "\r")
            case "esc": key(w, code: 53, chars: "\u{1b}")
            case "tab": key(w, code: 48, chars: "\t")
            default: break
            }
        case "click":
            let xy = arg.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2, let cv = w.contentView else { return }
            let p = cv.convert(NSPoint(x: xy[0], y: cv.isFlipped ? xy[1] : cv.bounds.height - xy[1]), to: nil)
            for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                 pressure: 1) else { continue }
                NSApp.sendEvent(e)
                // SwiftUI's gestures see the press and the release in separate turns.
                try? await Task.sleep(for: .milliseconds(60))
            }
        case "open":
            reopen?()
        case "hit":
            let xy = arg.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2, let cv = w.contentView, let frame = cv.superview else { return }
            let p = cv.convert(NSPoint(x: xy[0], y: cv.isFlipped ? xy[1] : cv.bounds.height - xy[1]), to: nil)
            let v = frame.hitTest(frame.convert(p, from: nil))
            print("hit \(arg) -> \(v.map { "\(type(of: $0))" } ?? "nil")")
        case "wait":
            try? await Task.sleep(for: .milliseconds(Int(arg) ?? 100))
        case "snap":
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
        case "log":
            let p = store.projection
            var line = "key=\(w.isKeyWindow) active=\(NSApp.isActive) open=\(window.overlays.picker != nil)"
            if let m = current, window.overlays.picker != nil {
                line += " text='\(m.text)' hot=\(m.hot) month=\(m.month.year)-\(m.month.month) none=\(m.none) cur=\(m.cur.map { "\($0)" } ?? "-") other=\(m.other.map { "\($0)" } ?? "-")"
            }
            let responder = w.firstResponder
            let inField = (responder as? DateFieldEditor) != nil
            line += " firstResponder=" + (responder.map { "\(type(of: $0))" } ?? "none") + (inField ? "(picker field)" : "")
            line += " focus=\(window.focus) dates=" + ids.compactMap { p.task($0) }.map { "\($0.title):\($0.when.map { "\($0)" } ?? "-")/\($0.deadline.map { "\($0)" } ?? "-")" }.joined(separator: ",")
            line += "\n"
            if let h = FileHandle(forWritingAtPath: arg) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
            else { try? line.write(toFile: arg, atomically: true, encoding: .utf8) }
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
        try? await Task.sleep(for: .milliseconds(120))
    }

    private static func key(_ w: NSWindow, code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        }
    }
}
#endif
