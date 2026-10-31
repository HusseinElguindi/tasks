import AppKit
import QuartzCore
import TasksCore

/// What a task row shows. Rows are rebound only when this changes.
struct RowModel: Equatable {
    struct Chip: Equatable {
        var field: Overlays.Picker.Field
        var content: ChipLayer.Content
    }

    var id: EntityID
    var title: String
    var untitled: Bool
    var done: Bool
    var draft: Bool
    var chips: [Chip] = []
    /// The notes' hint after the title: a glyph, or the checklist's count (design/MARKDOWN.md §7).
    var notes = NotesSummary()
    /// Today's Completed group: the list's name at the right (css:172).
    var whereText: String?
    var selected = false
    var joinTop = false
    var joinBottom = false
    var paneFocused = true
    var renaming = false
    var dragSource = false
    /// The › may show: not while renaming, on done rows, or with the detail pane open (css:179).
    var openAllowed = true
    var pickerField: Overlays.Picker.Field?
    /// In the Trash (§22, css:425–428): the title in `ink-secondary` (a done one keeps its struck `ink-tertiary`), the
    /// checkbox at 60%, and the checkbox and chips deaf to the pointer.
    var trashed = false
    /// A heading's drag copy (§23, css:479–481): no checkbox, its name semibold at the checkbox's edge.
    var heading = false
}

/// A task row (css:159–188): a 30pt shape, 10 in from the pane's sides, radius 8. Checkbox at 10, the title 10 after
/// it with its last 24pt fading out, chips 8 after the title, the › slot always kept, 5 from the right edge.
final class TaskRowView: NSView {
    enum Part: Equatable { case body, check, chip(Overlays.Picker.Field), open }
    enum Style { case row, lifted }

    private(set) var model: RowModel?
    private var palette = TK.Palette.dark
    private(set) var style: Style = .row

    private let selection = CALayer()
    private let ring = CALayer()
    let check = CheckLayer()
    private let title = TextLayer()
    private let titleMask = FadeMask()
    /// The notes hint, 6 after the title's text: the three-line glyph, or a box glyph and "2/5" (md:67–77).
    private let hintGlyph = GlyphLayer(.notes, size: 11)
    private let hintCount = TextLayer()
    private let strike = CALayer()
    private let whereLabel = TextLayer()
    private var chipLayers: [ChipLayer] = []
    private var chipFrames: [(Overlays.Picker.Field, CGRect)] = []
    let open = IconButtonLayer(.chevronRight, size: TK.M.openButton, glyphSize: 12)
    private(set) var titleFrame: CGRect = .zero

    private var hoveredPart: Part?
    private var rowHovered = false

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    init(style: Style = .row) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        selection.cornerRadius = TK.M.rowRadius
        ring.cornerRadius = TK.M.rowRadius
        ring.borderWidth = 1.5
        ring.isHidden = true
        title.mask = titleMask
        strike.isHidden = true
        layer.addSublayer(selection)
        layer.addSublayer(ring)
        layer.addSublayer(check)
        layer.addSublayer(title)
        layer.addSublayer(hintGlyph)
        layer.addSublayer(hintCount)
        layer.addSublayer(strike)
        layer.addSublayer(whereLabel)
        layer.addSublayer(open)
        open.setInstant { open.opacity = 0 }
        open.reveal(false, animated: false)
        for l in [selection, ring, check, title, hintGlyph, hintCount, strike, whereLabel, open] as [CALayer] { l.actions = Self.noActions }
    }

    required init?(coder: NSCoder) { fatalError() }

    static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(),
                                                "hidden": NSNull(), "opacity": NSNull(), "backgroundColor": NSNull(),
                                                "foregroundColor": NSNull(), "string": NSNull(), "sublayers": NSNull(),
                                                "transform": NSNull(), "borderColor": NSNull(), "mask": NSNull()]

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    // MARK: Binding

    /// Rebinds the row. `animated` is true when the same task was already shown here (a check animates; a recycled
    /// row showing another task doesn't).
    func configure(_ m: RowModel, palette: TK.Palette, width: CGFloat, animated: Bool) {
        let old = model
        let paletteChanged = palette != self.palette
        self.palette = palette
        model = m
        let same = old?.id == m.id && !paletteChanged
        let anim = animated && same

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Selection: the row's own fill, joined across adjacent rows (css:182–186). Never animated.
        if style == .lifted {
            selection.isHidden = false
            selection.backgroundColor = palette.lift.cgColor
            selection.frame = CGRect(x: 0, y: 0, width: width, height: TK.M.row)
            selection.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            selection.isHidden = !m.selected
            selection.backgroundColor = (m.paneFocused ? palette.sel : palette.selDim).cgColor
            selection.frame = CGRect(x: 0, y: 0, width: width, height: TK.M.row + (m.joinBottom ? 2 : 0))
            var corners: CACornerMask = []
            if !m.joinTop { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
            if !m.joinBottom { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
            selection.maskedCorners = corners
        }
        // Renaming: the selected fill plus a 1.5pt inset accent ring (§7).
        ring.isHidden = !m.renaming
        ring.borderColor = palette.accent.cgColor
        ring.frame = CGRect(x: 0, y: 0, width: width, height: TK.M.row)

        // Checkbox at x 10, centered.
        check.position = CGPoint(x: TK.M.rowPadLeft + TK.M.check / 2, y: TK.M.row / 2)
        CATransaction.commit()
        check.set(on: m.done, placeholder: m.draft, palette: palette, animated: anim)
        // `set` puts the opacity back each time; a trashed row's box is at 60%.
        if m.trashed { check.setInstant { check.opacity = 0.6 } }
        check.isHidden = m.heading

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Right side, from the edge in: padding 5 (10 lifted), the › slot (22) and 4, chips, 8, the where label.
        let padRight: CGFloat = style == .lifted ? 10 : TK.M.rowPadRight
        var right = width - padRight
        if style == .row {
            open.position = CGPoint(x: right - TK.M.openButton / 2, y: TK.M.row / 2)
            open.setPalette(palette)
            right -= TK.M.openButton + TK.M.openGap
        }
        while chipLayers.count < m.chips.count {
            let c = ChipLayer()
            c.actions = Self.noActions
            c.setScaleDeep(window?.backingScaleFactor ?? 2)
            layer?.addSublayer(c)
            chipLayers.append(c)
        }
        var chipsWidth: CGFloat = 0
        for (i, c) in m.chips.enumerated() {
            chipsWidth += ChipLayer.width(c.content) + (i > 0 ? TK.M.chipSpacing : 0)
        }
        var x = right - chipsWidth
        chipFrames = []
        for (i, layer) in chipLayers.enumerated() {
            guard i < m.chips.count else { layer.isHidden = true; continue }
            let c = m.chips[i]
            layer.isHidden = false
            layer.lifted = style == .lifted
            if layer.content != c.content || paletteChanged || !same { layer.set(c.content, palette: palette) }
            layer.pickerOpen = m.pickerField == c.field
            let w = ChipLayer.width(c.content)
            let f = CGRect(x: x, y: (TK.M.row - TK.M.chip) / 2, width: w, height: TK.M.chip)
            layer.frame = f
            chipFrames.append((c.field, f))
            x += w + TK.M.chipSpacing
        }
        // `.chips` keeps its 8pt margin even when empty.
        right -= chipsWidth + TK.M.chipsGap
        if let w = m.whereText {
            whereLabel.isHidden = false
            whereLabel.set(w, font: TK.Font.small, color: palette.ink3)
            let ww = TextLayer.width(w, font: TK.Font.small)
            whereLabel.place(x: right - ww, lineTop: (TK.M.row - 16) / 2, lineHeight: 16, width: ww + 2)
            right -= ww + 8
        } else {
            whereLabel.isHidden = true
        }

        // The title: flex 1, nudged up 0.5. With notes, their hint follows the text 6 later and stays whole: the title
        // shrinks first. Its last 24pt fade out only when it's cut off (css:166–168, md:67–77).
        // A heading's copy has no checkbox: its name starts at the checkbox's edge, semibold (css:480–481).
        let titleX = m.heading ? TK.M.rowPadLeft : TK.M.rowPadLeft + TK.M.check + TK.M.titleGap
        let slot = max(0, right - titleX)
        let color = (m.done || m.untitled) ? palette.ink3 : m.trashed ? palette.ink2 : palette.ink
        let text = m.untitled ? "New Task" : m.title
        title.set(text, font: m.heading ? HeadingRowView.font : TK.Font.body,
                  color: same ? (title.foregroundColor.flatMap(NSColor.init(cgColor:)) ?? color) : color)
        let hintW = layoutHint(m, palette)
        let room = hintW > 0 ? max(0, slot - hintW - 6) : slot
        let clipped = title.textWidth > room + 0.5
        let titleW = clipped ? room : min(room, ceil(title.textWidth) + 1)
        title.place(x: titleX, lineTop: (TK.M.row - 16) / 2 - 0.5, lineHeight: 16, width: titleW)
        titleFrame = CGRect(x: titleX, y: (TK.M.row - 16) / 2 - 0.5, width: slot, height: 16)
        titleMask.update(width: titleW, height: title.bounds.height, fade: clipped ? TK.M.titleFade : 0)
        title.isHidden = m.renaming
        let hintX = titleX + (clipped ? room : min(room, title.textWidth)) + 6
        hintGlyph.position = CGPoint(x: hintX + (m.notes.total > 0 ? 0 : 1.5) + 5.5, y: TK.M.row / 2)
        hintCount.place(x: hintX + 15, lineTop: (TK.M.row - 14) / 2, lineHeight: 14, width: hintCount.textWidth + 2)
        hintGlyph.isHidden = hintW == 0 || m.renaming
        hintCount.isHidden = m.notes.total == 0 || hintW == 0 || m.renaming
        // The strike is instant; the color takes 200 ms (css:169–171).
        strike.isHidden = !m.done || m.renaming
        strike.backgroundColor = palette.inkQ.cgColor
        let baseline = (TK.M.row - 16) / 2 - 0.5 + (16 - (TK.Font.body.ascender - TK.Font.body.descender)) / 2 + TK.Font.body.ascender
        strike.frame = CGRect(x: titleX, y: (baseline - 4.0).rounded(), width: min(title.textWidth, titleW), height: 1)
        CATransaction.commit()
        if anim && old?.done != m.done {
            title.animate("foregroundColor", to: color.cgColor, TK.CA.colorT)
        } else {
            title.setInstant { title.foregroundColor = color.cgColor }
        }

        updateOpen(animated: anim)
        if old?.dragSource != m.dragSource {
            // A dragged row leaves its place at once and fades back in after the drop (150 ms, §21).
            if m.dragSource || !anim {
                layer?.setInstant { layer?.opacity = m.dragSource ? 0 : 1 }
            } else {
                layer?.animate("opacity", to: 1, TK.CA.fadeOutT)
            }
        }
        let notesLabel = !m.notes.hasNotes ? nil : m.notes.total > 0 ? "\(m.notes.checked) of \(m.notes.total) checked" : "Has notes"
        setAccessibilityLabel(([text, notesLabel].compactMap { $0 } + m.chips.map(\.content.text) + [m.whereText].compactMap { $0 }).joined(separator: ", "))
        setAccessibilitySelected(m.selected)
    }

    // MARK: Hover and press

    /// The part under a point in the row's own coordinates.
    func part(at p: CGPoint) -> Part {
        guard let m = model else { return .body }
        if style == .row, m.openAllowed, open.frame.insetBy(dx: 0, dy: 0).contains(p) { return .open }
        if m.trashed { return .body }
        for (field, f) in chipFrames where f.contains(p) { return .chip(field) }
        // The checkbox's hit area is 30×30 around it (css:192); a new task's box ignores the pointer.
        let c = check.position
        if !m.draft, abs(p.x - c.x) <= TK.M.checkHit / 2, abs(p.y - c.y) <= TK.M.checkHit / 2 { return .check }
        return .body
    }

    func chipFrame(_ field: Overlays.Picker.Field) -> CGRect? { chipFrames.first { $0.0 == field }?.1 }

    /// The row's hover (the › fades in) and the hovered control.
    func setHover(row: Bool, part: Part?) {
        if rowHovered != row {
            rowHovered = row
            updateOpen(animated: true)
        }
        let p = row ? part : nil
        guard p != hoveredPart else { return }
        hoveredPart = p
        check.hovered = p == .check
        open.hovered = p == .open
        for (i, c) in chipLayers.enumerated() where i < chipFrames.count {
            c.hovered = p == .chip(chipFrames[i].0)
        }
    }

    func setPressed(_ part: Part?) {
        check.setPressedIfChanged(part == .check)
        open.pressed = part == .open
        for (i, c) in chipLayers.enumerated() where i < chipFrames.count {
            c.pressed = part == .chip(chipFrames[i].0)
        }
    }

    nonisolated(unsafe) static let hintFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)   // .ncount 500 11/14

    /// Sets the hint's glyph, count and colors, and returns its width (0 without notes): the glyph alone in a 14pt
    /// box (`ink-quaternary`), or the box glyph, 4, and "2/5" in `ink-tertiary`, `ink-quaternary` once all are checked
    /// or on a done row (md:74–77).
    private func layoutHint(_ m: RowModel, _ p: TK.Palette) -> CGFloat {
        guard m.notes.hasNotes, !m.untitled || !m.draft else { return 0 }
        if m.notes.total > 0 {
            let quiet = m.done || m.notes.checked == m.notes.total
            let c = quiet ? p.inkQ : p.ink3
            if hintGlyph.glyph != .checklist { hintGlyph.set(.checklist, size: 11) }
            hintGlyph.color = c
            let text = "\(m.notes.checked)/\(m.notes.total)"
            hintCount.set(text, font: Self.hintFont, color: c)
            return 11 + 4 + TextLayer.width(text, font: Self.hintFont)
        }
        if hintGlyph.glyph != .notes { hintGlyph.set(.notes, size: 11) }
        hintGlyph.color = p.inkQ
        return 14
    }

    private func updateOpen(animated: Bool) {
        let show = rowHovered && (model?.openAllowed ?? false) && style == .row
        open.isHidden = !(model?.openAllowed ?? false)
        open.reveal(show, animated: animated)
    }

    /// The caret index for a point (a double-click on the title puts the caret there).
    func caretIndex(at p: CGPoint) -> Int? {
        guard let m = model, titleFrame.contains(p) else { return nil }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: m.title, attributes: [.font: TK.Font.body]))
        let i = CTLineGetStringIndexForPosition(line, CGPoint(x: p.x - titleFrame.minX, y: 0))
        return i == kCFNotFound ? nil : i
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .row }

    // MARK: Accessibility: the checkbox and the › as their own elements (§18.15)

    /// Set by the list: what the checkbox and the › do when VoiceOver presses them.
    var onCheck: (() -> Void)?
    var onOpen: (() -> Void)?
    private lazy var checkElement = PressElement(role: .checkBox, parent: self)
    private lazy var openElement = PressElement(role: .button, parent: self)

    override func accessibilityChildren() -> [Any]? {
        guard let m = model, style == .row else { return [] }
        let title = m.untitled ? "New Task" : m.title
        checkElement.setAccessibilityLabel((m.done ? "Mark not done: " : "Complete: ") + title)
        checkElement.setAccessibilityValue(m.done ? 1 : 0)
        checkElement.setAccessibilityFrameInParentSpace(CGRect(x: check.frame.minX, y: bounds.height - check.frame.maxY, width: check.frame.width, height: check.frame.height))
        checkElement.onPress = onCheck
        var children: [Any] = m.draft ? [] : [checkElement]
        if m.openAllowed {
            openElement.setAccessibilityLabel("Show details")
            openElement.setAccessibilityFrameInParentSpace(CGRect(x: open.frame.minX, y: bounds.height - open.frame.maxY, width: open.frame.width, height: open.frame.height))
            openElement.onPress = onOpen
            children.append(openElement)
        }
        return children
    }
}

/// An accessibility element that VoiceOver can press.
final class PressElement: NSAccessibilityElement {
    var onPress: (() -> Void)?

    init(role: NSAccessibility.Role, parent: NSView) {
        super.init()
        setAccessibilityRole(role)
        setAccessibilityParent(parent)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return onPress != nil
    }
}

extension CheckLayer {
    func setPressedIfChanged(_ pressed: Bool) {
        let key = "tk.pressed"
        let was = value(forKey: key) as? Bool ?? false
        guard was != pressed else { return }
        setValue(pressed, forKey: key)
        setPressed(pressed)
    }
}

// MARK: - Today's group labels (css:131–139, 233–237)

/// A list's name as a group label in a 32pt slot; its + (New Task in School) is revealed on hover. Today's
/// "Completed" label has no button.
final class GroupLabelView: NSView {
    private let label = TextLayer()
    /// A day's date after its name (§22): 400 `ink-quiet`, 6 after the name.
    private let sub = TextLayer()
    private var palette = TK.Palette.dark
    private var quiet = false
    private var drop = false
    let plus = IconButtonLayer(.plus, size: 22, glyphSize: 12)
    private(set) var key: EntityID = ""
    private(set) var hasPlus = true
    private var hovered = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(label)
        layer?.addSublayer(sub)
        layer?.addSublayer(plus)
        label.actions = TaskRowView.noActions
        sub.actions = TaskRowView.noActions
        plus.reveal(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    func configure(key: EntityID, name: String, plus hasPlus: Bool, palette: TK.Palette, width: CGFloat,
                   sub subText: String? = nil, quiet: Bool = false) {
        self.key = key
        self.hasPlus = hasPlus
        self.palette = palette
        self.quiet = quiet
        let room = max(0, width - 12 - (hasPlus ? 32 : 0))
        layer?.setInstant {
            let colors = labelColors
            label.set(name, font: TK.Font.label, color: colors.name)
            // The name takes at most 70% when a date follows it (css:417).
            let nameW = subText == nil ? room : min(TextLayer.width(name, font: TK.Font.label), room * 0.7)
            // 1pt of room past the text, so the clip never takes a glyph's overhang.
            label.place(x: 12, lineTop: 10, lineHeight: 14, width: nameW + 1)
            label.masksToBounds = true
            if let subText, !subText.isEmpty {
                sub.isHidden = false
                sub.set(subText, font: Self.subFont, color: colors.sub)
                sub.place(x: 12 + nameW + 6, lineTop: 10, lineHeight: 14, width: max(0, room - nameW - 6))
                sub.masksToBounds = true
            } else {
                sub.isHidden = true
            }
            plus.isHidden = !hasPlus
            plus.setPalette(palette)
            plus.position = CGPoint(x: width - 5 - 11, y: 6 + 11)
        }
    }

    func plusContains(_ p: CGPoint) -> Bool { hasPlus && plus.frame.contains(p) }

    nonisolated(unsafe) static let subFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    #if DEBUG
    var debugLit: Bool { drop }
    #endif

    /// The name `ink-tertiary` (an empty day's `ink-quiet`), the date `ink-quiet`; both `accent-text` on the day a drag
    /// in Upcoming would land on.
    private var labelColors: (name: NSColor, sub: NSColor) {
        if drop { return (palette.accentText, palette.accentText) }
        return (quiet ? palette.inkQ : palette.ink3, palette.inkQ)
    }

    /// The drop day lights in on `hover-in`, out on `hover-out` (css:421–422).
    func setDrop(_ on: Bool, animated: Bool) {
        guard on != drop else { return }
        drop = on
        let c = labelColors
        if animated && !TK.CA.reduce {
            let t = on ? TK.CA.hoverInT : TK.CA.hoverOutT
            label.animate("foregroundColor", to: c.name.cgColor, t)
            sub.animate("foregroundColor", to: c.sub.cgColor, t)
        } else {
            layer?.setInstant {
                label.foregroundColor = c.name.cgColor
                sub.foregroundColor = c.sub.cgColor
            }
        }
    }

    func setHover(_ on: Bool, overPlus: Bool) {
        if on != hovered {
            hovered = on
            plus.reveal(on)
        }
        plus.hovered = on && overPlus
    }
}

// MARK: - The "› Completed 23" row (css:226–231)

final class CompletedRowView: NSView {
    private let chevron = GlyphLayer(.chevronRight, size: 12)
    private let label = TextLayer()
    private let count = TextLayer()
    private var palette = TK.Palette.dark
    private var hovered = false
    private(set) var open = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.cornerRadius = TK.M.rowRadius
        for l in [chevron, label, count] as [CALayer] {
            l.actions = TaskRowView.noActions
            layer?.addSublayer(l)
        }
        setAccessibilityRole(.button)
        setAccessibilityLabel("Completed tasks")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    /// Returns the row's width (it's only as wide as its content, §21).
    @discardableResult
    func configure(count n: Int, open: Bool, palette: TK.Palette, animated: Bool) -> CGFloat {
        self.palette = palette
        let color = hovered ? palette.ink : palette.ink2
        let countText = "\(n)"
        layer?.setInstant {
            chevron.color = color
            chevron.position = CGPoint(x: 12 + 6, y: TK.M.row / 2)
            label.set("Completed", font: TK.Font.bodyMedium, color: color)
            let lw = TextLayer.width("Completed", font: TK.Font.bodyMedium)
            label.place(x: 12 + 12 + 6, lineTop: 7, lineHeight: 16, width: lw + 2)
            count.set(countText, font: TK.Font.count, color: palette.ink3)
            count.place(x: 30 + lw + 6, lineTop: 7, lineHeight: 16, width: TextLayer.width(countText, font: TK.Font.count) + 2)
        }
        if open != self.open {
            self.open = open
            let angle = open ? CGFloat.pi / 2 : 0
            if animated {
                chevron.animate("transform.rotation.z", to: angle, TK.CA.chevronT)
            } else {
                chevron.setInstant { chevron.setValue(angle, forKeyPath: "transform.rotation.z") }
            }
        }
        setAccessibilityValue(open ? "Expanded" : "Collapsed")
        return 30 + TextLayer.width("Completed", font: TK.Font.bodyMedium) + 6 + TextLayer.width(countText, font: TK.Font.count) + 10
    }

    func setHover(_ on: Bool) {
        guard on != hovered else { return }
        hovered = on
        let color = on ? palette.ink : palette.ink2
        let t = on ? TK.CA.hoverInT : TK.CA.hoverOutT
        chevron.animate("strokeColor", to: color.cgColor, t)
        label.animate("foregroundColor", to: color.cgColor, t)
    }
}

// MARK: - Empty states (css:298–303, §13)

final class EmptyStateView: NSView {
    private let glyph = GlyphLayer(.sun, size: 22)
    private let title = TextLayer()
    private let text = CATextLayer()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(glyph)
        layer?.addSublayer(title)
        layer?.addSublayer(text)
        title.alignmentMode = .center
        text.isWrapped = true
        text.alignmentMode = .center
        for l in [glyph, title, text] as [CALayer] { l.actions = TaskRowView.noActions }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    func configure(_ kind: TaskLayout.Empty, palette: TK.Palette, width: CGFloat) {
        let (e1, e2): (String, String) = switch kind {
        case .list: ("No tasks", "Double-click anywhere here or press ⌘N to add one.")
        case .today: ("Nothing for today", "Tasks you plan for today, or that are due, show up here.")
        case .allDone: ("All done for today", "")
        case .upcoming: ("Nothing upcoming", "Tasks with a date after today show up here, on the day they reach Today.")
        case .undated: ("Every task has a date", "Open tasks with no When and no Deadline show up here, by list.")
        case .completed: ("Nothing completed yet", "Tasks you check off show up here, newest first.")
        case .trash: ("Trash is empty", "Deleted tasks wait here until you put them back.")
        }
        var y: CGFloat = 0
        layer?.setInstant {
            switch kind {
            case .today:
                glyph.isHidden = false
                glyph.set(.sun, size: 22)
                glyph.color = palette.inkQ
            case .allDone:
                glyph.isHidden = false
                glyph.set(.checkCircle, size: 22)
                glyph.color = palette.accent
            case .list:
                glyph.isHidden = true
            case .upcoming, .undated, .completed, .trash:
                glyph.isHidden = false
                let g: Glyph = kind == .upcoming ? .calendar : kind == .undated ? .layers : kind == .completed ? .checkCircle : .trash
                glyph.set(g, size: 22)
                glyph.color = palette.inkQ
            }
            if !glyph.isHidden {
                glyph.frame = CGRect(x: (width - 22) / 2, y: 0, width: 22, height: 22)
                y = 22 + 4 + 6
            }
        }
        let tw = min(280, max(0, width - 48))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.minimumLineHeight = 16
        para.maximumLineHeight = 16
        let body = NSAttributedString(string: e2, attributes: [.font: TK.Font.small, .foregroundColor: palette.ink3, .paragraphStyle: para])
        let h = ceil(body.boundingRect(with: CGSize(width: tw, height: 200), options: [.usesLineFragmentOrigin]).height)
        layer?.setInstant {
            title.set(e1, font: TK.Font.bodyMedium, color: palette.ink2)
            title.place(x: 24, lineTop: y, lineHeight: 16, width: max(0, width - 48))
            text.string = body
            text.isHidden = e2.isEmpty
            text.frame = CGRect(x: (width - tw) / 2, y: y + 16 + 6 - 0.5, width: tw, height: h + 2)
        }
        y += 16 + 6
        frame.size = CGSize(width: width, height: y + h)
    }
}

// MARK: - The archived list's banner (css:287–289, §12, §21)

final class BannerView: NSView {
    private let bg = CALayer()
    private let icon = GlyphLayer(.archive, size: 14)
    private let text = CATextLayer()
    private let button = CALayer()
    private let buttonLabel = TextLayer()
    private var palette = TK.Palette.dark
    private var hovered = false
    private var pressed = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        bg.cornerRadius = 8
        button.cornerRadius = 12
        layer?.addSublayer(bg)
        layer?.addSublayer(icon)
        layer?.addSublayer(button)
        button.addSublayer(buttonLabel)
        text.isWrapped = true
        layer?.addSublayer(text)
        for l in [bg, icon, button, buttonLabel, text] as [CALayer] { l.actions = TaskRowView.noActions }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    var buttonFrame: CGRect { button.frame }

    /// Lays the banner out in `width`; returns its height.
    @discardableResult
    func configure(archivedOn: String, palette: TK.Palette, width: CGFloat) -> CGFloat {
        self.palette = palette
        let bw = 12 + TextLayer.width("Unarchive", font: TK.Font.body) + 12
        let textX: CGFloat = 12 + 14 + 10
        let textW = max(0, width - textX - 10 - bw - 10)
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = 16
        para.maximumLineHeight = 16
        let s = NSMutableAttributedString(string: "Archived \(archivedOn)", attributes: [.font: TK.Font.body, .foregroundColor: palette.ink, .paragraphStyle: para])
        s.append(NSAttributedString(string: " · Not in Today or Move to. Everything still edits.", attributes: [.font: TK.Font.small, .foregroundColor: palette.ink2, .paragraphStyle: para]))
        let th = ceil(s.boundingRect(with: CGSize(width: textW, height: 400), options: [.usesLineFragmentOrigin]).height)
        let h = max(24, th) + 18
        layer?.setInstant {
            text.string = s
            text.frame = CGRect(x: textX, y: (h - th) / 2, width: textW, height: th + 2)
            bg.frame = CGRect(x: 0, y: 0, width: width, height: h)
            bg.backgroundColor = palette.fillControl.cgColor
            icon.color = palette.ink2
            icon.position = CGPoint(x: 12 + 7, y: h / 2)
            button.frame = CGRect(x: width - 10 - bw, y: (h - 24) / 2, width: bw, height: 24)
            buttonLabel.set("Unarchive", font: TK.Font.body, color: palette.accentText)
            buttonLabel.place(x: 12, lineTop: 4, lineHeight: 16, width: bw)
            restyle()
        }
        return h
    }

    func setButtonState(hovered: Bool, pressed: Bool) {
        guard hovered != self.hovered || pressed != self.pressed else { return }
        let wasPressed = self.pressed
        self.hovered = hovered
        self.pressed = pressed
        if pressed || !wasPressed && !hovered && !self.hovered {
            layer?.setInstant(restyle)
        } else {
            let b = pressed ? TK.Palette.pressBrightness : hovered ? palette.buttonHoverBrightness : 1
            button.animate("backgroundColor", to: palette.accentTint.brightness(b).cgColor, TK.CA.iconT)
            buttonLabel.animate("foregroundColor", to: palette.accentText.brightness(b).cgColor, TK.CA.iconT)
        }
    }

    private func restyle() {
        let b = pressed ? TK.Palette.pressBrightness : hovered ? palette.buttonHoverBrightness : 1
        button.backgroundColor = palette.accentTint.brightness(b).cgColor
        buttonLabel.foregroundColor = palette.accentText.brightness(b).cgColor
    }
}
