import AppKit
import SwiftUI
import TasksCore

// The date popover (INTERACTIONS-v2 §11, §16, §18.8, §21, and §25's scrolling calendar at 240pt), ported 1:1 from
// the prototype: template dc:213–233, `openPicker` dc:1515–1526, the keys dc:2605–2618, the footer fit dc:2629–2640,
// the view model dc:3060–3080, and css:317–342 and 521–534 (with the surface css:56–58/74 and "Popover in" css:371).
//
// Top to bottom, inside 8pt of padding on a 240pt `surface-popover`: the field (28), the quick picks 8 below (22, then
// 2), the month row (8 / 16 / 4), the weekday initials (20), the calendar (six 30pt weeks, `WeekCalendar.swift`) and
// the footer under a hairline (6 above it, 8 inside). 337pt in all; placement uses the prototype's 344.

/// Places the popover for `picker` in the window's overlay layer (`OverlayLayer`): 6pt under its anchor, left-aligned
/// with it and kept 8pt inside the window, flipped above the anchor when it wouldn't fit (dc:1120–1122).
struct DatePopoverHost: View {
    let store: Store
    @Bindable var window: WindowState
    let picker: Overlays.Picker
    let windowSize: CGSize

    static let width: CGFloat = 240
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

/// What the popover shows (the prototype's `state.picker`): the text, the highlighted day, the calendar's header.
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
    /// The text reads as no date: nothing is highlighted and Return does nothing.
    var none = false
    /// Where the calendar opens: the month of the tasks' date (today's when they have none), its first week on top.
    let opening: CalendarDate
    /// The month in view and the Today pill, as the calendar reports them while it scrolls.
    var header: CalendarHeader
    /// The latest request for the calendar to move: typing, the keys, Today.
    private(set) var reveal: CalendarReveal?

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
        opening = (cur ?? today).firstOfMonth
        let math = WeekMath(today: today)
        header = math.header(pos: math.monthPos(opening), fallback: opening)
    }

    /// Typing moves the highlighted day to what the text means, and the calendar to its month when it's out of view;
    /// clearing the text puts it back (dc:2594–2603).
    func typed(_ new: String) {
        text = new
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            none = false
            hot = cur ?? today
        } else if let hit = DatePhrase.match(new, today: today, numericOrder: Self.order) {
            none = false
            hot = hit
        } else {
            none = true
            return
        }
        show(hot, .typed)
    }

    /// ← → a day, ↑ ↓ a week (dc:2609–2616); the calendar scrolls the least that shows it.
    func move(days n: Int) {
        hot = CalendarDate(dayNumber: hot.dayNumber + n) ?? hot
        none = false
        show(hot, .key)
    }

    /// Page Up and Page Down: a month, to the same day, clamped (Jan 31 → Feb 28) (dc:2617).
    func move(months n: Int) {
        hot = DatePhrase.adding(months: n, to: hot)
        none = false
        show(hot, .key)
    }

    /// The Today pill: today's month, without picking today.
    func showToday() { show(today, .today) }

    private func show(_ d: CalendarDate, _ why: CalendarReveal.Why) {
        reveal = CalendarReveal(date: d, why: why, seq: (reveal?.seq ?? 0) + 1)
    }

    /// "tom" went with Next Week's room: Tomorrow is a button (§25).
    var placeholder: String {
        field == .when ? "When: try fri, 3d, nov 9" : "Deadline: try fri, nov 9, 2w"
    }

    /// Today · Tomorrow, and Clear when the tasks share a date (dc:3068–3069). Next Week went for the 240pt popover;
    /// "next" still offers it.
    var quick: [Quick] {
        var q = [Quick(label: "Today", date: today), Quick(label: "Tomorrow", date: today.adding(days: 1))]
        if cur != nil { q.append(Quick(label: "Clear", date: nil)) }
        return q
    }

    struct Quick: Identifiable {
        let label: String
        /// nil: Clear.
        let date: CalendarDate?
        var id: String { label }
    }

    /// The last line's candidates, longest first (§25 "The last line", dc:2629–2640): "Fri, Nov 6 · in 7 days" with
    /// ↩; then without ↩; without the weekday; then the date alone. A deadline reads "Due …", a past one "… · 1 day
    /// overdue". With a `hint`, the hint takes the relative words' place, and it always stays. Or "No date matches
    /// “xyz”" with ↩, cut with an ellipsis when long.
    var lines: [Line] {
        if none { return [Line(text: "No date matches “" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "”", kbd: true)] }
        let pre = field == .deadline ? "Due " : ""
        let date = DateLabel.monthDayYear(hot, today: today)
        let long = DateLabel.long(hot, today: today)
        var rel = ""
        if hint == nil {
            rel = " · " + (field == .deadline && hot < today ? DateLabel.deadlineWords(hot, today: today) : DateLabel.relative(hot, today: today))
        }
        return [Line(text: pre + long + rel, kbd: true), Line(text: pre + long + rel, kbd: false),
                Line(text: pre + date + rel, kbd: false), Line(text: pre + date, kbd: false)]
    }

    struct Line {
        let text: String
        /// Shows ↩.
        let kbd: Bool
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
}

// MARK: - The popover

private enum Metrics {
    static let inner: CGFloat = WeekCalendarView.width   // 240 − 2 × 8
    static let cell: CGFloat = inner / 7                  // 32: a 28pt day and 4 between
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
        case .pageUp: model.move(months: -1)
        case .pageDown: model.move(months: 1)
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

    // MARK: The month (css:326–329, 521–524)

    /// The month in view and, once today is more than two weeks out of view, the Today pill (§25). The row keeps the
    /// title's 16pt line either way: the 20pt pill overhangs it by 2pt above and below, so the calendar never moves
    /// when the pill comes and goes (the prototype's row grows by 4pt).
    private var monthRow: some View {
        HStack(spacing: 0) {
            Text(DateLabel.monthTitle(year: model.header.month.year, month: model.header.month.month))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tk.ink.swiftUI)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let up = model.header.todayAbove {
                TodayPill(up: up) {
                    model.showToday()
                    fieldRef.focus()
                }
            }
        }
        .frame(height: 16)
        .padding(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 2))
    }

    // MARK: The calendar (css:332–338, 525–534)

    private var grid: some View {
        let first = Calendar.current.firstWeekday
        let m = model
        return VStack(spacing: 0) {
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
            WeekCalendar(marks: CalendarMarks(today: m.today, cur: m.cur, other: m.other, otherIsDeadline: m.field == .when,
                                              hot: m.none ? nil : m.hot),
                         opening: m.opening, reveal: m.reveal,
                         onPick: { apply($0) },
                         onHeader: { h in if m.header != h { m.header = h } })
                .frame(width: Metrics.inner, height: WeekCalendarView.height)
        }
    }

    // MARK: The footer (css:338–341)

    /// One line, always: the first of the model's candidates that fits 224pt (§25).
    private var footer: some View {
        let lines = model.lines
        return VStack(spacing: 0) {
            Rectangle().fill(tk.lineSeparator.swiftUI).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                ForEach(lines.indices, id: \.self) { i in footerLine(lines[i]) }
            }
            .frame(minHeight: 16)
            .padding(EdgeInsets(top: 8, leading: 4, bottom: 2, trailing: 4))
        }
        .padding(.top, 6)
    }

    private func footerLine(_ line: DatePickModel.Line) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(line.text)
                    .foregroundStyle((model.none ? tk.inkTertiary : tk.ink).swiftUI)
                // "· after the deadline": the dot in `ink-tertiary`, the note in `attention` (css:536–537).
                if let hint = model.hint {
                    Text("· ").foregroundColor(tk.inkTertiary.swiftUI) + Text(hint).foregroundColor(tk.attention.swiftUI)
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if line.kbd {
                Text("↩")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tk.inkTertiary.swiftUI)
                    .accessibilityHidden(true)
            }
        }
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

/// The Today pill (css:522–523): 20 tall, padding 8, `accent-tint` / `accent-text`, 11pt medium and a 10pt arrow 3pt
/// after it, toward today. It scrolls to today's month without picking today.
private struct TodayPill: View {
    let up: Bool
    let action: () -> Void
    @Environment(\.tk) private var tk

    var body: some View {
        HStack(spacing: 3) {
            Text("Today").font(.system(size: 11, weight: .medium))
            Text(up ? "↑" : "↓").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tk.accentText.swiftUI)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(tk.accentTint.swiftUI, in: Capsule(style: .circular))
        .contentShape(Capsule(style: .circular))
        .onTapGesture(perform: action)
        .accessibilityElement()
        .accessibilityLabel("Scroll to today")
        .accessibilityAddTraits(.isButton)
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
/// highlighted day, Page Up and Page Down by a month; Return sets it; ⌫ in the empty field clears; Esc closes; Tab
/// stays in the field. ⌘Z is the field's own.
private final class DateTypingField: NSTextField, NSTextFieldDelegate {
    enum Key { case left, right, up, down, pageUp, pageDown, deleteEmpty, returnKey, escape }

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

    /// From the field editor's `keyDown`: the arrows and Page Up / Down (any modifiers), and ⌫ (any modifiers) when
    /// the field is empty.
    private func arrowOrDelete(_ code: UInt16, empty: Bool) -> Bool {
        switch code {
        case 123: onKey?(.left)
        case 124: onKey?(.right)
        case 126: onKey?(.up)
        case 125: onKey?(.down)
        case 116: onKey?(.pageUp)
        case 121: onKey?(.pageDown)
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
///     -debugPickerRec /f.txt         records the calendar's moves from the start (as `rec`)
///     -debugPickerSteps "type:fri;key:left;click:X,Y;open;wait:200;snap:/a.png;log:/b.txt;hit:X,Y;quit"
///
/// Keys: left right up down pageup pagedown delete return esc tab. `open` opens it again for the same tasks. `log`
/// appends the popover's state, the first responder and the tasks' dates. Clicks work with the app in the background
/// because the popover takes the first click; hover can't be posted (tracking areas follow the real pointer).
///
/// The calendar (§25), with scroll events made in-process and handed to its scroll view (positions in points; + is
/// later): `wheel:N` N notches of a wheel mouse; `drag:D[,N]` a trackpad scroll of D in N steps, with no momentum;
/// `flick:V` a trackpad flick at V points a frame, then its momentum (×0.96 a frame; a scroll view handed these
/// directly ignores the momentum, so this moves only the 4V of the flick itself); `rec:/f.txt` … `recstop` writes a line per
/// move of the calendar (the clip origin, base, pos, the header, the weeks in view and whether every row shows its own
/// week); `cal:/f.txt` appends one such line now; `hover:X,Y` hovers the day at X,Y in the calendar. `bench:open:N:/f.txt` opens the popover N times and writes the
/// main-thread work of each (open, then the window's layout and display forced); `bench:scroll:/f.txt` writes the
/// same for every scroll event since launch.
@MainActor
enum DebugPicker {
    fileprivate static weak var current: DatePickModel?
    static weak var calendar: WeekCalendarView?
    private static var recording: String?
    private static var recStart: CFTimeInterval = 0
    private static var scrollCost: [Double] = []

    /// The calendar's own share of opening: making it, and its first update (`first`), which styles its days.
    private static var built: [Double] = [0, 0]
    static func calendarBuilt(ms: Double, first: Bool) {
        if first { if built[1] == 0 { built[1] = ms } } else { built = [ms, 0] }
    }

    /// Every move of the calendar, from its bounds-change handler (`ms`: that handler's own time).
    static func calendarMoved(_ v: WeekCalendarView, ms: Double) {
        guard let path = recording else { return }
        append(String(format: "%8.1f ", (CACurrentMediaTime() - recStart) * 1000) + state(v) + String(format: " %.3fms", ms), to: path)
    }

    private static func state(_ v: WeekCalendarView) -> String {
        let h = v.header
        let f = v.convert(v.bounds, to: nil)
        return String(format: "clip=%.2f base=%d pos=%.2f frame=%.2f,%.2f,%.2f,%.2f", v.debugClipY, v.base, v.pos, f.minX, f.minY, f.width, f.height)
            + " header=\(h.month.year)-\(h.month.month) pill=\(h.todayAbove.map { $0 ? "up" : "down" } ?? "-")"
            + " anim=\(v.debugAnimating ? 1 : 0) rowsOK=\(v.debugRowsConsistent ? 1 : 0) weeks=\(v.debugWeeks)"
    }

    private static func append(_ line: String, to path: String) {
        let l = line + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(l.utf8)); h.closeFile() }
        else { try? l.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// One scroll event, as a trackpad (points, with its phases) or a wheel mouse (notches) would send it.
    private static func scroll(_ v: WeekCalendarView, _ dy: Double, phase: Int64 = 0, momentum: Int64 = 0, notches: Bool = false) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: notches ? .line : .pixel, wheelCount: 1,
                               wheel1: Int32((-dy).rounded()), wheel2: 0, wheel3: 0) else { return }
        if !notches {
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64((-dy).rounded()))
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -dy)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        }
        guard let e = NSEvent(cgEvent: cg) else { return }
        let t0 = CACurrentMediaTime()
        v.scrollWheel(with: e)
        if let path = recording {
            append(String(format: "event phase=%d momentum=%d dy=%.2f", Int(e.phase.rawValue), Int(e.momentumPhase.rawValue), e.scrollingDeltaY), to: path)
        }
        if let cv = v.window?.contentView {
            cv.layoutSubtreeIfNeeded()
            cv.displayIfNeeded()
        }
        scrollCost.append((CACurrentMediaTime() - t0) * 1000)
    }

    private static func frame() async { try? await Task.sleep(for: .milliseconds(16)) }
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
            if let path = d.string(forKey: "debugPickerRec") {
                recording = path
                recStart = CACurrentMediaTime()
                try? "".write(toFile: path, atomically: true, encoding: .utf8)
            }
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
            case "pageup": key(w, code: 116, chars: String(UnicodeScalar(NSPageUpFunctionKey)!), flags: [.function])
            case "pagedown": key(w, code: 121, chars: String(UnicodeScalar(NSPageDownFunctionKey)!), flags: [.function])
            default: break
            }
        case "wheel":
            guard let v = calendar, let n = Int(arg) else { return }
            scroll(v, Double(n), notches: true)
        case "drag":
            // kCGScrollPhaseBegan 1, Changed 2, Ended 4. `drag:D,N`: in N steps, one a frame (default 10).
            let a = arg.split(separator: ",").compactMap { Double($0) }
            guard let v = calendar, let d = a.first else { return }
            let n = a.count > 1 ? Int(a[1]) : 10
            scroll(v, 0, phase: 1)
            for _ in 0..<n { await frame(); scroll(v, d / Double(n), phase: 2) }
            await frame()
            scroll(v, 0, phase: 4)
        case "flick":
            // kCGMomentumScrollPhaseBegin 1, Continue 2, End 3.
            guard let v = calendar, var speed = Double(arg) else { return }
            scroll(v, 0, phase: 1)
            for _ in 0..<4 { await frame(); scroll(v, speed, phase: 2) }
            await frame()
            scroll(v, 0, phase: 4)
            await frame()
            scroll(v, speed, momentum: 1)
            while abs(speed) >= 0.5 {
                await frame()
                speed *= 0.96
                scroll(v, speed, momentum: 2)
            }
            await frame()
            scroll(v, 0, momentum: 3)
        case "rec":
            recording = arg
            recStart = CACurrentMediaTime()
            try? "".write(toFile: arg, atomically: true, encoding: .utf8)
        case "recstop":
            recording = nil
        case "hover":
            let xy = arg.split(separator: ",").compactMap { Double($0) }
            guard let v = calendar, xy.count == 2 else { return }
            v.debugHover(xy[0], xy[1])
        case "cal":
            guard let v = calendar else { return }
            append(state(v), to: arg)
        case "bench":
            let b = arg.split(separator: ":", maxSplits: 2).map(String.init)
            if b.first == "open", b.count == 3, let n = Int(b[1]) {
                var out: [String] = []
                for _ in 0..<n {
                    WindowActions(store: store, window: window).closePicker()
                    try? await Task.sleep(for: .milliseconds(250))
                    let t0 = CACurrentMediaTime()
                    reopen?()
                    if let cv = w.contentView {
                        cv.layoutSubtreeIfNeeded()
                        cv.displayIfNeeded()
                    }
                    out.append(String(format: "%.3f\t%.3f\t%.3f", (CACurrentMediaTime() - t0) * 1000, built[0], built[1]))
                    try? await Task.sleep(for: .milliseconds(400))
                }
                try? out.joined(separator: "\n").write(toFile: b[2], atomically: true, encoding: .utf8)
            } else if b.first == "scroll", b.count == 2 {
                try? scrollCost.map { String(format: "%.3f", $0) }.joined(separator: "\n").write(toFile: b[1], atomically: true, encoding: .utf8)
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
                line += " text='\(m.text)' hot=\(m.hot) header=\(m.header.month.year)-\(m.header.month.month) pill=\(m.header.todayAbove.map { $0 ? "up" : "down" } ?? "-") none=\(m.none) cur=\(m.cur.map { "\($0)" } ?? "-") other=\(m.other.map { "\($0)" } ?? "-")"
                line += " footer='" + m.lines.map { $0.text + ($0.kbd ? " ↩" : "") }.joined(separator: "|") + "'"
                if let v = calendar { line += " " + state(v) }
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
