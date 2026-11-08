import AppKit
import QuartzCore
import TasksCore

// Headings and the top of the list pane (design/INTERACTIONS-v2.md §23, css:434–481).

/// What a heading row shows. Rebound only when this changes.
struct HeadingModel: Equatable {
    var id: EntityID
    var title: String
    var collapsed = false
    /// Its open tasks, shown after the name while collapsed.
    var count = 0
    var selected = false
    var paneFocused = true
    var renaming = false
    var dragSource = false
    /// In a deleted list opened from Trash: no + (nothing is added there), only the chevron (§28).
    var readOnly = false
}

/// A heading row: on the 32pt pitch in the row's 30pt shape, 10 in from the pane's sides. The name is 13/16 semibold
/// `ink` at the checkbox's edge, a 1pt `line-sep` rule runs along the bottom 10 in from each end, and hovering
/// reveals + and the chevron at the right, 22×22, 2 apart, 5 from the edge (Rex's group headers). A collapsed heading
/// keeps its chevron and shows its open tasks' count 8 after the name.
///
/// The + and the chevron are their own parts: the list asks `part(at:)` before anything else, so a press on them never
/// selects the row or starts a drag, whether they're fading or fully shown (§23 "Bugs the prototype had").
final class HeadingRowView: NSView {
    enum Part: Equatable { case body, plus, chevron }

    private(set) var model: HeadingModel?
    private var palette = TK.Palette.dark
    private let selection = CALayer()
    private let ring = CALayer()
    private let name = TextLayer()
    private let count = TextLayer()
    private let rule = CALayer()
    let plus = IconButtonLayer(.plus, size: 22, glyphSize: 12)
    /// A 12pt glyph from the first frame in both states: only its rotation changes (§23).
    let chevron = IconButtonLayer(.chevronRight, size: 22, glyphSize: 12)
    private var hovered = false
    private var hoveredPart: Part?
    private var chevronDown: Bool?
    private(set) var nameFrame: CGRect = .zero

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    nonisolated(unsafe) static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)       // .hrow .ht 600 13/16
    nonisolated(unsafe) static let countFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium) // .hct

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        selection.cornerRadius = TK.M.rowRadius
        ring.cornerRadius = TK.M.rowRadius
        ring.borderWidth = 1.5
        name.truncationMode = .end
        for l in [selection, ring, rule, name, count, plus, chevron] as [CALayer] {
            l.actions = TaskRowView.noActions
            layer.addSublayer(l)
        }
        plus.reveal(false, animated: false)
        chevron.reveal(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    /// The list handles the pointer (it selects on mouse-down and drags); the row only draws.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    #if DEBUG
    /// Debug (v2 feedback 20): the heading as drawn.
    var debugFrameState: String {
        "heading '\(name.text)' count=\(count.isHidden ? "-" : count.text) chevron=\(chevronDown.map { $0 ? "down" : "right" } ?? "-")"
            + " revealed=\(chevron.revealed ? 1 : 0)"
    }
    #endif

    func configure(_ m: HeadingModel, palette: TK.Palette, width: CGFloat, animated: Bool) {
        let paletteChanged = palette != self.palette || model == nil
        self.palette = palette
        let old = model
        model = m
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let h = TK.M.row
        // Selected: the row's fill (a heading never joins a task's selection block). Renaming: the row's editing look.
        selection.isHidden = !(m.selected || m.renaming)
        selection.backgroundColor = (m.paneFocused || m.renaming ? palette.fillRowSelected : palette.fillRowSelectedDim).cgColor
        selection.frame = CGRect(x: 0, y: 0, width: width, height: h)
        ring.isHidden = !m.renaming
        ring.borderColor = palette.focus.cgColor
        ring.frame = selection.frame
        // The rule hides while selected or renamed.
        rule.backgroundColor = palette.lineSeparator.cgColor
        rule.frame = CGRect(x: 10, y: h - 1, width: max(0, width - 20), height: 1)
        rule.isHidden = m.selected || m.renaming
        // + and the chevron: 5 from the right, 2 apart, centered.
        let chevX = width - TK.M.rowPadRight - 22
        chevron.frame = CGRect(x: chevX, y: (h - 22) / 2, width: 22, height: 22)
        plus.frame = CGRect(x: chevX - 2 - 22, y: (h - 22) / 2, width: 22, height: 22)
        if paletteChanged {
            plus.setPalette(palette)
            chevron.setPalette(palette)
        }
        // The name, then the count; both stop before the buttons.
        let text = m.title.isEmpty ? "New Heading" : m.title
        name.set(text, font: Self.font, color: m.title.isEmpty ? palette.inkTertiary : palette.ink)
        let countText = m.collapsed && m.count > 0 ? String(m.count) : ""
        count.set(countText, font: Self.countFont, color: palette.inkTertiary)
        let countW = countText.isEmpty ? 0 : TextLayer.width(countText, font: Self.countFont) + 8
        let room = max(0, plus.frame.minX - 8 - TK.M.rowPadLeft - countW)
        let nameW = min(room, ceil(name.textWidth) + 1)
        name.place(x: TK.M.rowPadLeft, lineTop: (h - 16) / 2 - 0.5, lineHeight: 16, width: nameW)
        nameFrame = CGRect(x: TK.M.rowPadLeft, y: (h - 16) / 2 - 0.5, width: max(nameW, room), height: 16)
        name.isHidden = m.renaming
        count.isHidden = countText.isEmpty || m.renaming
        count.place(x: TK.M.rowPadLeft + nameW + 8, lineTop: (h - 14) / 2, lineHeight: 14, width: countW + 2)
        CATransaction.commit()
        // The chevron points down when open and right when collapsed, turning in 200 ms ease-out.
        let down = !m.collapsed
        if chevronDown != down {
            let angle = down ? CGFloat.pi / 2 : 0
            if chevronDown != nil, animated, !TK.CA.reduce {
                chevron.glyph.animate("transform.rotation.z", to: angle, TK.CA.chevronT)
            } else {
                chevron.glyph.setInstant { chevron.glyph.setValue(angle, forKeyPath: "transform.rotation.z") }
            }
            chevronDown = down
        }
        if old?.collapsed != m.collapsed || old?.renaming != m.renaming { updateReveal(animated: animated) }
        if old?.dragSource != m.dragSource {
            layer?.setInstant { layer?.opacity = m.dragSource ? 0 : 1 }
        }
        setAccessibilityLabel(text + (m.collapsed ? ", collapsed, \(m.count) open" : ""))
        setAccessibilitySelected(m.selected)
    }

    /// The part under a point in the row's coordinates: the buttons first, whatever their fade.
    func part(at p: CGPoint) -> Part {
        guard let m = model, !m.renaming else { return .body }
        if chevron.frame.contains(p) { return .chevron }
        if plus.frame.contains(p), !m.readOnly { return .plus }
        return .body
    }

    func setHover(row: Bool, part: Part?) {
        if hovered != row {
            hovered = row
            updateReveal(animated: true)
        }
        let p = row ? part : nil
        guard p != hoveredPart else { return }
        hoveredPart = p
        plus.hovered = p == .plus
        chevron.hovered = p == .chevron
    }

    func setPressed(_ part: Part?) {
        plus.pressed = part == .plus
        chevron.pressed = part == .chevron
    }

    /// Hover fades both in on `hoverIn` and out on `hoverOut`; a collapsed heading keeps its chevron. Renaming hides them.
    private func updateReveal(animated: Bool) {
        let renaming = model?.renaming ?? false
        plus.reveal(hovered && !renaming && !(model?.readOnly ?? false), animated: animated)
        chevron.reveal((hovered || (model?.collapsed ?? false)) && !renaming, animated: animated)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
}

/// The top of the list pane, scrolling with the rows (§23 The list's title): the list's or the view's tile (20×16),
/// 9 apart from the name in 20/26 semibold `ink` with −0.2 tracking, on a 30pt line 4 below the band; Today's
/// date or "In Trash" after it in `ink-tertiary`. A long name wraps onto more lines (`TitleLayout`), the tile staying on
/// the first. A list's notes sit 4 below the title, in the notes editor (the list adds it as a subview), with a "Notes"
/// placeholder in `ink-quaternary` that fades in only on hover, while renaming, or with the caret in them.
///
/// The name is always drawn by `field`, a wrapping `InlineField`: at rest it takes no keys and no presses; renaming
/// makes it editable in place (the list sets that up), so nothing is swapped and nothing moves (design/TITLE-RENAME.md,
/// direction B).
final class ListTitleView: NSView {
    private let tile = TileLayer()
    let field = InlineField(frame: .zero)
    private let sub = TextLayer()
    private let placeholder = TextLayer()
    private var palette = TK.Palette.dark
    private var tracking: NSTrackingArea?
    private(set) var hovered = false
    /// The title's text frame: a double-click there renames the list.
    private(set) var titleFrame: CGRect = .zero
    /// The title line's height (30 for one line of text, 26 more for each further line).
    private(set) var lineBox: CGFloat = TitleLayout.line
    var onDoubleClickTitle: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    #if DEBUG
    var debugTitle: String { field.stringValue + (sub.text.isEmpty ? "" : " | " + sub.text) }
    #endif

    nonisolated(unsafe) static let font: NSFont = TitleLayout.font
    static let kern: CGFloat = TitleLayout.kern

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        for l in [tile, sub, placeholder] as [CALayer] {
            l.actions = TaskRowView.noActions
            layer.addSublayer(l)
        }
        placeholder.setInstant { placeholder.opacity = 0 }
        field.makeWrapping(matchingLabels: true)
        field.font = Self.font
        field.isEditable = false
        field.isSelectable = false
        field.setAccessibilityLabel("List name")
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    struct Content: Equatable {
        /// A list's tile, or Today's and a view's (its glyph on its hue).
        enum Mark: Equatable { case tile(monogram: String, slot: Int), view(WindowState.Route) }
        var mark: Mark
        var title: String
        var sub: String?
        var renaming = false
    }

    /// Where the name starts, and the width it wraps in, in a pane `width` wide.
    static func textX(_ c: Content) -> CGFloat { TK.M.rowInset + TK.M.rowPadLeft + 20 + 9 }
    static func textWidth(_ c: Content, width: CGFloat) -> CGFloat {
        max(1, width - textX(c) - TK.M.rowInset - TK.M.rowPadRight)
    }

    /// The title line's height for `text` (the name, or what's being typed) in a pane `width` wide.
    static func lineBox(_ c: Content, text: String, width: CGFloat) -> CGFloat {
        TitleLayout.lineBox(text, width: textWidth(c, width: width))
    }

    /// Lays out the title line in `width`; the list adds its notes editor at `notesTop`. While the name is renamed
    /// the field keeps what's typed and the line follows its height (`text`, what's being typed).
    func configure(_ c: Content, palette: TK.Palette, width: CGFloat, text: String? = nil) {
        let paletteChanged = palette != self.palette
        self.palette = palette
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lineTop: CGFloat = 4
        let x0: CGFloat = TK.M.rowInset + TK.M.rowPadLeft
        switch c.mark {
        case .tile(let monogram, let slot):
            tile.set(monogram: monogram, hue: palette.tile(slot: slot), palette: palette)
        case .view(let route):
            // B: a view's glyph is a tile too, white on the view's hue (color.css `.lht > span.vg`).
            tile.set(monogram: nil, hue: route.tileHue(palette), palette: palette, glyph: route.glyph ?? .sun)
        }
        // On the first line, however many the name takes.
        tile.position = CGPoint(x: x0 + 10, y: lineTop + 15)
        let x = Self.textX(c)
        let avail = Self.textWidth(c, width: width)
        let shown = text ?? c.title
        let m = TitleLayout.measure(shown, width: avail)
        lineBox = TitleLayout.lineBox(shown, width: avail)
        // The field spans the line, so it breaks lines where `TitleLayout` measured them; a press only renames on the
        // name itself (one line: its natural width).
        let textH = CGFloat(m.lines) * TitleLayout.lineHeight
        let ff = CGRect(x: x - TitleLayout.inset, y: lineTop + (TitleLayout.line - TitleLayout.lineHeight) / 2,
                        width: avail + 2 * TitleLayout.inset, height: textH)
        if field.frame != ff { field.frame = ff }
        if !field.isEditing {
            restyle(c.title, color: palette.ink, force: paletteChanged)
        }
        titleFrame = CGRect(x: x, y: lineTop, width: m.lines > 1 ? avail : min(avail, m.lastWidth + 2), height: lineBox)
        // The date or "In Trash" goes 9 after the last line, and gives way there (css:441–442, v2 feedback 16).
        if let s = c.sub, !c.renaming {
            let subNat = ceil(TextLayer.width(s, font: TK.Font.body)) + 2
            let room = avail - m.follow
            let subW = min(subNat, max(0, room))
            if subW >= min(subNat, 40) {
                sub.isHidden = false
                sub.truncationMode = .end
                sub.set(s, font: TK.Font.body, color: palette.inkTertiary)
                let lastTop = lineTop + CGFloat(m.lines - 1) * TitleLayout.lineHeight
                sub.place(x: x + m.follow, lineTop: lastTop + 7 + 1, lineHeight: 16, width: subW)
            } else {
                sub.isHidden = true
            }
        } else {
            sub.isHidden = true
        }
        placeholder.set("Notes", font: TK.Font.body, color: palette.inkQuiet)
        placeholder.place(x: x0, lineTop: notesTop, lineHeight: 19, width: 60)
        CATransaction.commit()
    }

    /// Puts the title's attributes back on what the field shows: at rest, and the moment a rename ends (the field
    /// editor hands back plain text in the cell's font, which would draw a frame without the tracking or line box).
    func restyle(_ text: String? = nil, color: NSColor? = nil, force: Bool = false) {
        guard !field.isEditing else { return }
        let want = NSAttributedString(string: text ?? field.stringValue, attributes: TitleLayout.attributes(color ?? palette.ink))
        if force || !field.attributedStringValue.isEqual(to: want) { field.attributedStringValue = want }
    }

    /// The field editor's look while renaming: the title's attributes on its text and for typing, Ember selection, an
    /// `ink` caret (§16).
    func styleEditor() {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let a = TitleLayout.attributes(palette.ink)
        editor.insertionPointColor = palette.ink
        editor.selectedTextAttributes = [.backgroundColor: palette.textSelection]
        editor.defaultParagraphStyle = TitleLayout.paragraph
        if let storage = editor.textStorage, storage.length > 0 {
            var same = true
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, _, stop in
                if attrs[.kern] as? CGFloat != TitleLayout.kern || attrs[.baselineOffset] as? CGFloat != TitleLayout.baselineOffset
                    || attrs[.foregroundColor] as? NSColor != palette.ink {
                    same = false
                    stop.pointee = true
                }
            }
            if !same {
                let sel = editor.selectedRanges
                storage.setAttributes(a, range: NSRange(location: 0, length: storage.length))
                editor.selectedRanges = sel
            }
        }
        editor.typingAttributes = a
    }

    /// The notes editor's top in this view: the title line, then 4.
    var notesTop: CGFloat { 4 + lineBox + 4 }

    /// Where the title text starts.
    var titleX: CGFloat { titleFrame.minX }

    /// "Notes" over an empty list's notes line: on hover, while renaming, or with the caret in it (css:448–450).
    func showPlaceholder(_ on: Bool, animated: Bool) {
        let to: Float = on ? 1 : 0
        guard placeholder.opacity != to else { return }
        if animated && !TK.CA.reduce {
            placeholder.animate("opacity", to: to, on ? TK.CA.hoverInT : TK.CA.hoverOutT)
        } else {
            placeholder.setInstant { placeholder.opacity = to }
        }
    }

    // MARK: Pointer: the title takes a double-click; the rest is the list's (its notes editor takes its own).

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let p = convert(point, from: sv)
        // At rest the name is this view's (a double-click renames); while it's renamed, the field's (a press moves
        // the caret).
        if let hit = super.hitTest(point), hit !== self, hit !== field || field.isEditing { return hit }
        return titleFrame.contains(p) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClickTitle?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; onHover?(false) }
}
