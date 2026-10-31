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
        selection.backgroundColor = (m.paneFocused || m.renaming ? palette.sel : palette.selDim).cgColor
        selection.frame = CGRect(x: 0, y: 0, width: width, height: h)
        ring.isHidden = !m.renaming
        ring.borderColor = palette.accent.cgColor
        ring.frame = selection.frame
        // The rule hides while selected or renamed.
        rule.backgroundColor = palette.lineSep.cgColor
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
        name.set(text, font: Self.font, color: m.title.isEmpty ? palette.ink3 : palette.ink)
        let countText = m.collapsed && m.count > 0 ? String(m.count) : ""
        count.set(countText, font: Self.countFont, color: palette.ink3)
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
        if plus.frame.contains(p) { return .plus }
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
        plus.reveal(hovered && !renaming, animated: animated)
        chevron.reveal((hovered || (model?.collapsed ?? false)) && !renaming, animated: animated)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }
}

/// The top of the list pane, scrolling with the rows (§23 The list's title): the list's tile (20×16) or a view's glyph
/// (18pt), 9 apart from the name in 20/26 semibold `ink` with −0.2 tracking, on a 30pt line 4 below the band; Today's
/// date or "Archived" after it in `ink-tertiary`. A list's notes sit 4 below the title, in the notes editor (the list
/// adds it as a subview), with a "Notes" placeholder in `ink-quaternary` that fades in only on hover, while renaming,
/// or with the caret in them.
final class ListTitleView: NSView {
    private let tile = TileLayer()
    private let glyph = GlyphLayer(.sun, size: 18)
    private let title = TextLayer()
    private let sub = TextLayer()
    private let placeholder = TextLayer()
    private var palette = TK.Palette.dark
    private var tracking: NSTrackingArea?
    private(set) var hovered = false
    /// The title's text frame: a double-click there renames the list.
    private(set) var titleFrame: CGRect = .zero
    var onDoubleClickTitle: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    nonisolated(unsafe) static let font: NSFont = NSFont.systemFont(ofSize: 20, weight: .semibold)   // .lhn 600 20/26
    static let kern: CGFloat = -0.2

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        title.truncationMode = .end
        for l in [tile, glyph, title, sub, placeholder] as [CALayer] {
            l.actions = TaskRowView.noActions
            layer.addSublayer(l)
        }
        placeholder.setInstant { placeholder.opacity = 0 }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    struct Content: Equatable {
        /// A list's tile, or Today's and a view's glyph in its colour.
        enum Mark: Equatable { case tile(monogram: String, slot: Int), view(WindowState.Route) }
        var mark: Mark
        var title: String
        var sub: String?
        var renaming = false
    }

    /// Lays out the title line in `width`; the list adds its notes editor at `notesOrigin`.
    func configure(_ c: Content, palette: TK.Palette, width: CGFloat) {
        self.palette = palette
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lineTop: CGFloat = 4
        var x: CGFloat = TK.M.rowInset + TK.M.rowPadLeft
        switch c.mark {
        case .tile(let monogram, let slot):
            glyph.isHidden = true
            tile.isHidden = false
            tile.set(monogram: monogram, color: palette.listColor(slot: slot), palette: palette)
            tile.position = CGPoint(x: x + 10, y: lineTop + 15)
            x += 20 + 9
        case .view(let route):
            tile.isHidden = true
            glyph.isHidden = false
            let g = route.glyph ?? .sun
            if glyph.glyph != g { glyph.set(g, size: 18) }
            glyph.color = route.glyphColor(palette)
            glyph.position = CGPoint(x: x + 9, y: lineTop + 15)
            x += 18 + 9
        }
        // The name keeps up to 160 (all of a shorter one), then the date or "Archived" after it gives way, then the
        // name; both end in an ellipsis, as the prototype's `.lhn` and `.lhs` do (css:441–442, v2 feedback 16).
        let titleNat = ceil(TextLayer.width(c.title, font: Self.font) + abs(Self.kern) * CGFloat(c.title.count)) + 2
        let subNat = c.sub.map { ceil(TextLayer.width($0, font: TK.Font.body)) + 2 } ?? 0
        let avail = max(0, width - x - TK.M.rowInset - TK.M.rowPadRight)
        var subW: CGFloat = 0
        if c.sub != nil {
            subW = titleNat + 9 + subNat <= avail ? subNat : min(subNat, max(0, avail - 9 - min(titleNat, 160)))
            if subW < min(subNat, 40) { subW = 0 }
        }
        let titleW = min(titleNat, max(0, avail - (subW > 0 ? subW + 9 : 0)))
        // The layer's own font sets the line CATextLayer truncates in: the attributed string alone left it at 13pt,
        // and a cut title lost its descenders.
        title.set(c.title, font: Self.font, color: palette.ink)
        title.string = NSAttributedString(string: c.title, attributes: [.font: Self.font, .kern: Self.kern,
                                                                         .foregroundColor: palette.ink])
        title.place(x: x, lineTop: lineTop + 2, lineHeight: 26, width: titleW)
        title.isHidden = c.renaming
        titleFrame = CGRect(x: x, y: lineTop, width: titleW, height: 30)
        if let s = c.sub, subW > 0 {
            sub.isHidden = c.renaming
            sub.truncationMode = .end
            sub.set(s, font: TK.Font.body, color: palette.ink3)
            sub.place(x: x + titleW + 9, lineTop: lineTop + 7 + 1, lineHeight: 16, width: subW)
        } else {
            sub.isHidden = true
        }
        placeholder.set("Notes", font: TK.Font.body, color: palette.inkQ)
        placeholder.place(x: TK.M.rowInset + TK.M.rowPadLeft, lineTop: Self.notesTop, lineHeight: 19, width: 60)
        CATransaction.commit()
    }

    /// The notes editor's top in this view: the title line, then 4.
    static let notesTop: CGFloat = 4 + 30 + 4

    /// Where the title text starts: the rename field goes there.
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
        if let hit = super.hitTest(point), hit !== self { return hit }
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
