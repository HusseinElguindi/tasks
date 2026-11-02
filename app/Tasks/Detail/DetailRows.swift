import AppKit
import SwiftUI
import TasksCore

/// What the pane shows for one task (or the new-task draft), read from the task's model so the pane follows its
/// changes.
struct DetailItem: Equatable {
    var id: EntityID
    var title: String
    var notes: String
    var list: EntityID
    var when: CalendarDate?
    var deadline: CalendarDate?
    var completedAt: Int?
    var createdAt: Int
    var isDraft: Bool

    @MainActor init(_ m: TaskModel) {
        id = m.id
        title = m.title
        notes = m.notes
        list = m.list
        when = m.when
        deadline = m.deadline
        completedAt = m.completedAt
        createdAt = m.createdAt
        isDraft = false
    }

    @MainActor init(_ d: WindowState.Draft) {
        id = d.id
        title = d.title
        notes = ""
        list = d.list
        when = d.when
        deadline = nil
        completedAt = nil
        createdAt = d.createdAt
        isDraft = true
    }
}

// MARK: - The rows (css:261–274, dc:1936–1949)

/// List, When and Deadline: 32 tall, from 12 below the title, from the checkbox's left edge. Each label is an icon
/// centered in the checkbox's column and its word 10 after it (at the title's 26) in `ink-secondary`, in an 81pt
/// column; the value starts 8 after it.
struct DetailProps: View {
    let store: Store
    let window: WindowState
    let items: [DetailItem]
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let ids = items.map(\.id)
        let first = items[0]
        let sameList = items.allSatisfy { $0.list == first.list }
        let list = sameList ? store.projection.listModel(first.list) : nil
        VStack(alignment: .leading, spacing: 0) {
            PropRow(glyph: .lines, label: "List") { _ in
                // A task whose list is in Trash: "School  In Trash" (§28).
                ListPopup(monogram: list?.monogram ?? "…",
                          hue: list.map { tk.tile(slot: $0.colorSlot) } ?? tk.tile(.ink),
                          name: list.map { _ in actions.listName(first.list) } ?? "Mixed",
                          note: list?.isDeleted == true ? "In Trash" : nil) { anchor in
                    popListMenu(ids: ids, current: items.count == 1 ? first.list : nil, anchor: anchor)
                }
            }
            DateRow(field: .when, items: items, store: store, window: window, actions: actions)
            DateRow(field: .deadline, items: items, store: store, window: window, actions: actions)
        }
    }

    /// The same lists as Move to, 6 left of the pop-up and 4 below it (dc:1088–1093).
    private func popListMenu(ids: [EntityID], current: EntityID?, anchor: CGRect) {
        guard let content = window.nsWindow?.contentView else { return }
        let x = anchor.minX - 6, y = anchor.maxY + 4
        let point = NSPoint(x: x, y: content.isFlipped ? y : content.bounds.height - y)
        Menus.popListMenu(ids, current: current, at: point, in: content, actions: actions)
    }
}

/// One 32pt row; `content` gets whether the row is hovered (it reveals a date's ×).
private struct PropRow<Value: View>: View {
    let glyph: Glyph
    let label: String
    @ViewBuilder var content: (Bool) -> Value
    @State private var hovered = false
    @Environment(\.tk) private var tk

    var body: some View {
        HStack(spacing: 0) {
            // The icon centered in the checkbox's 16pt column, the label 10 after it, where the title's text starts
            // (26); 55 for the label, as before (v2 feedback 6, css:263).
            HStack(spacing: 10) {
                GlyphView(glyph: glyph, size: 14, color: tk.inkSecondary.swiftUI)
                    .frame(width: TK.M.check)
                Text(label).font(Font(TK.Font.body)).foregroundStyle(tk.inkSecondary.swiftUI).frame(height: 16)
            }
            .frame(width: 81, alignment: .leading)
            content(hovered)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

/// When or Deadline: a large chip with the full date then the relative date 34 past it (8 of flex gap plus the 26
/// that makes room for the ×, css:262, 270), or a ghost "Add date" / "Mixed".
private struct DateRow: View {
    let field: Overlays.Picker.Field
    let items: [DetailItem]
    let store: Store
    let window: WindowState
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let today = store.projection.dayModel.day.date
        let value: (DetailItem) -> CalendarDate? = { field == .when ? $0.when : $0.deadline }
        let date = value(items[0])
        let mixed = !items.allSatisfy { value($0) == date }
        let ids = items.map(\.id)
        let open = window.overlays.picker?.field == field
        let name = field == .when ? "When" : "Deadline"
        PropRow(glyph: field == .when ? .calendar : .flag, label: name) { hovered in
            HStack(spacing: 0) {
                if mixed {
                    DetailChip(text: "Mixed", glyph: nil, tone: .neutral, ghost: true, pickerOpen: false) { pick(ids) }
                        .background(ChipFrameReporter(field: field, window: window))
                } else if let date {
                    let tone: ChipLayer.Tone = field == .deadline ? toneOf(DateLabel.deadlineChip(date, today: today).tone) : .neutral
                    DetailChip(text: DateLabel.long(date, today: today), glyph: field == .when ? .calendar : .flag,
                               tone: tone, ghost: false, pickerOpen: open) { pick(ids) }
                        .background(ChipFrameReporter(field: field, window: window))
                    ClearDateButton(tip: "Remove \(name)", revealed: hovered, overlays: window.overlays) {
                        actions.setDate(ids, field, nil)
                    }
                    .padding(.leading, 2)
                    Text(relative(date, today: today))
                        .font(Font(TK.Font.small))
                        .foregroundStyle(relativeColor(tone).swiftUI)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: 16)
                        .padding(.leading, 10)
                } else {
                    DetailChip(text: "Add date", glyph: nil, tone: .neutral, ghost: true, pickerOpen: open) { pick(ids) }
                        .background(ChipFrameReporter(field: field, window: window))
                }
            }
        }
    }

    /// The relative words (§24, dc:2805–2807): a deadline's in words ("2 days overdue", "due today", "1 day left");
    /// a When's relative date, and on an open task a past one adds "· still in Today", so it doesn't look missed.
    private func relative(_ date: CalendarDate, today: CalendarDate) -> String {
        if field == .deadline { return DateLabel.deadlineWords(date, today: today) }
        let open = !(items.count == 1 && items[0].completedAt != nil)
        return DateLabel.relative(date, today: today) + (open && date < today ? " · still in Today" : "")
    }

    /// In the deadline's tone: `danger` overdue, `attention` due today, else `ink-tertiary`.
    private func relativeColor(_ tone: ChipLayer.Tone) -> NSColor {
        switch tone {
        case .late: tk.danger
        case .due: tk.attention
        case .neutral, .soon: tk.inkTertiary
        }
    }

    private func pick(_ ids: [EntityID]) {
        actions.openPicker(field, ids: ids, anchor: window.detailChipFrames[field])
    }

    private func toneOf(_ t: DateLabel.Tone) -> ChipLayer.Tone {
        switch t {
        case .neutral: .neutral
        case .soon: .soon
        case .due: .due
        case .late: .late
        }
    }
}

/// Keeps `window.detailChipFrames` on the chip, in window coordinates, for ⌘S / ⇧⌘D from the pane (§11).
private struct ChipFrameReporter: View {
    let field: Overlays.Picker.Field
    let window: WindowState

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { window.detailChipFrames[field] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in window.detailChipFrames[field] = f }
        }
    }
}

// MARK: - The large chip (css:205–215)

/// 22 tall, padding 9, radius 11, 5 between an 11pt icon and 12pt medium text. Neutral `fill-control` /
/// `ink-secondary`; Deadline takes the row chip's tone. Hover brightens it (1.18 dark, 0.96 light) on `icon`; press
/// darkens it to 0.86 at once; while its popover is open it's `accent-tint` / `accent-text`. A ghost chip is
/// transparent with a 1pt `line-separator` ring in `ink-tertiary`; hover gives it the `hover` fill and `ink-secondary`.
struct DetailChip: View {
    let text: String
    let glyph: Glyph?
    let tone: ChipLayer.Tone
    let ghost: Bool
    let pickerOpen: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Color.clear.frame(width: Self.width(text, glyph: glyph), height: TK.M.chipLarge)
        }
        .buttonStyle(DetailChipStyle(text: text, glyph: glyph, tone: tone, ghost: ghost, pickerOpen: pickerOpen, hovered: hovered))
        .onHover { hovered = $0 }
        .accessibilityLabel(text)
    }

    static func width(_ text: String, glyph: Glyph?) -> CGFloat {
        ChipLayer.width(.init(text: text, glyph: glyph, large: true))
    }
}

private struct DetailChipStyle: ButtonStyle {
    let text: String
    let glyph: Glyph?
    let tone: ChipLayer.Tone
    let ghost: Bool
    let pickerOpen: Bool
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let (bg, fg) = colors(pressed: pressed)
        configuration.label
            .overlay(alignment: .leading) {
                HStack(spacing: TK.M.chipLargeGap) {
                    if let glyph { GlyphView(glyph: glyph, size: TK.M.chipIcon, color: (tone == .soon && !pickerOpen ? tk.attention : fg).swiftUI) }
                    Text(text)
                        .font(Font(TK.Font.chipLarge))
                        .foregroundStyle(fg.swiftUI)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: 14)
                }
                .padding(.leading, TK.M.chipLargePad)
            }
            .background(bg.swiftUI, in: Capsule())
            .overlay { if ghost { Capsule().strokeBorder(tk.lineSeparator.swiftUI, lineWidth: 1) } }
            .contentShape(Capsule())
            .animation(pressed ? nil : TK.Motion.icon, value: hovered)
            .animation(pressed ? nil : TK.Motion.icon, value: pressed)
            .animation(TK.Motion.icon, value: pickerOpen)
    }

    private func colors(pressed: Bool) -> (NSColor, NSColor) {
        if pickerOpen { return (tk.accentTint, tk.accentText) }
        if ghost { return hovered ? (tk.hover, tk.inkSecondary) : (.clear, tk.inkTertiary) }
        var bg: NSColor, fg: NSColor
        switch tone {
        case .neutral, .soon: bg = tk.fillControl; fg = tk.inkSecondary
        case .due: bg = tk.attentionTint; fg = tk.attention
        case .late: bg = tk.dangerTint; fg = tk.danger
        }
        let b = pressed ? TK.Palette.pressBrightness : hovered ? tk.chipHoverBrightness : 1
        return (bg.brightness(b), fg.brightness(b))
    }
}

// MARK: - The date's × (css:266–269)

/// 22×22, radius 6, a 12pt × in `ink-tertiary`, 2 after the chip. It fades in with the row's hover (`hoverIn`) and out
/// (`hoverOut`); its own hover is the `hover` fill with `ink-secondary` on `icon`. Tooltip: the name only.
private struct ClearDateButton: View {
    let tip: String
    let revealed: Bool
    let overlays: Overlays
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.tk) private var tk

    var body: some View {
        Button(action: action) {
            Color.clear.frame(width: 22, height: 22)
        }
        .buttonStyle(ClearStyle(hovered: hovered))
        .tipped(tip, overlays: overlays, hovered: $hovered)
        .opacity(revealed ? 1 : 0)
        .animation(revealed ? TK.Motion.hoverIn : TK.Motion.hoverOut, value: revealed)
        .accessibilityLabel(tip)
    }
}

private struct ClearStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((hovered ? tk.hover : .clear).swiftUI, in: RoundedRectangle(cornerRadius: 6))
            .overlay { GlyphView(glyph: .xmark, size: 12, color: (hovered ? tk.inkSecondary : tk.inkTertiary).swiftUI) }
            .contentShape(Rectangle())
            .animation(TK.Motion.icon, value: hovered)
    }
}

// MARK: - The List pop-up (css:271–273)

/// The list's tile and name in `ink`, then ⌃⌄ in `ink-tertiary`; 22 tall, padding 4 / 6, radius 6, 4 left of the
/// value column. Hover: the `hover` fill on `icon`; press: the `press` fill at once.
private struct ListPopup: View {
    let monogram: String
    let hue: NSColor
    let name: String
    var note: String? = nil
    let action: (CGRect) -> Void
    @State private var hovered = false
    @State private var frame: CGRect = .zero
    @Environment(\.tk) private var tk

    var body: some View {
        Button { action(frame) } label: {
            HStack(spacing: 6) {
                TileView(monogram: monogram, hue: hue, size: .small)
                Text(name).font(Font(TK.Font.body)).foregroundStyle(tk.ink.swiftUI).lineLimit(1).frame(height: 16)
                if let note {
                    Text(note).font(Font(TK.Font.small)).foregroundStyle(tk.inkTertiary.swiftUI).lineLimit(1).frame(height: 16)
                }
                GlyphView(glyph: .upDown, size: 12, color: tk.inkTertiary.swiftUI)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(height: 22)
        }
        .buttonStyle(PopupStyle(hovered: hovered))
        .onHover { hovered = $0 }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in frame = f }
        })
        .padding(.leading, -4)
        .accessibilityLabel("List")
        .accessibilityValue(name)
    }
}

private struct PopupStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background((pressed ? tk.press : hovered ? tk.hover : .clear).swiftUI, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .animation(pressed ? nil : TK.Motion.icon, value: hovered)
            .animation(pressed ? nil : TK.Motion.icon, value: pressed)
    }
}
