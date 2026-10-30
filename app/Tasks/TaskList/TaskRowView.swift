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
        layer.addSublayer(strike)
        layer.addSublayer(whereLabel)
        layer.addSublayer(open)
        open.setInstant { open.opacity = 0 }
        open.reveal(false, animated: false)
        for l in [selection, ring, check, title, strike, whereLabel, open] as [CALayer] { l.actions = Self.noActions }
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

        // The title: flex 1, nudged up 0.5, its last 24pt fading out (css:166–168).
        let titleX = TK.M.rowPadLeft + TK.M.check + TK.M.titleGap
        let titleW = max(0, right - titleX)
        let color = (m.done || m.untitled) ? palette.ink3 : palette.ink
        let text = m.untitled ? "New Task" : m.title
        title.set(text, font: TK.Font.body, color: same ? (title.foregroundColor.flatMap(NSColor.init(cgColor:)) ?? color) : color)
        title.place(x: titleX, lineTop: (TK.M.row - 16) / 2 - 0.5, lineHeight: 16, width: titleW)
        titleFrame = CGRect(x: titleX, y: (TK.M.row - 16) / 2 - 0.5, width: titleW, height: 16)
        titleMask.update(width: titleW, height: title.bounds.height, fade: TK.M.titleFade)
        title.isHidden = m.renaming
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
        setAccessibilityLabel(([text] + m.chips.map(\.content.text) + [m.whereText].compactMap { $0 }).joined(separator: ", "))
        setAccessibilitySelected(m.selected)
    }

    // MARK: Hover and press

    /// The part under a point in the row's own coordinates.
    func part(at p: CGPoint) -> Part {
        guard let m = model else { return .body }
        if style == .row, m.openAllowed, open.frame.insetBy(dx: 0, dy: 0).contains(p) { return .open }
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
        layer?.addSublayer(plus)
        label.actions = TaskRowView.noActions
        plus.reveal(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    func configure(key: EntityID, name: String, plus hasPlus: Bool, palette: TK.Palette, width: CGFloat) {
        self.key = key
        self.hasPlus = hasPlus
        layer?.setInstant {
            label.set(name, font: TK.Font.label, color: palette.ink3)
            label.place(x: 12, lineTop: 10, lineHeight: 14, width: max(0, width - 12 - (hasPlus ? 32 : 0)))
            plus.isHidden = !hasPlus
            plus.setPalette(palette)
            plus.position = CGPoint(x: width - 5 - 11, y: 6 + 11)
        }
    }

    func plusContains(_ p: CGPoint) -> Bool { hasPlus && plus.frame.contains(p) }

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

// MARK: - The ghost row in the landing slot (css:218–223)

final class GhostRowView: NSView {
    private let ring = CAShapeLayer()
    private let label = TextLayer()
    private(set) var shown = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let s = TK.M.check
        ring.path = CGPath(ellipseIn: CGRect(x: 0.75, y: 0.75, width: s - 1.5, height: s - 1.5), transform: nil)
        ring.lineWidth = 1.5
        ring.fillColor = nil
        ring.opacity = 0.8
        ring.frame = CGRect(x: TK.M.rowPadLeft, y: (TK.M.row - s) / 2, width: s, height: s)
        layer?.addSublayer(ring)
        layer?.addSublayer(label)
        layer?.opacity = 0
        for l in [ring, label] as [CALayer] { l.actions = TaskRowView.noActions }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    func configure(palette: TK.Palette) {
        layer?.setInstant {
            ring.strokeColor = palette.inkQ.cgColor
            label.set("New Task", font: TK.Font.body, color: palette.ink3)
            label.place(x: TK.M.rowPadLeft + TK.M.check + TK.M.titleGap, lineTop: 7, lineHeight: 16, width: 120)
        }
    }

    func show(_ on: Bool, animated: Bool = true) {
        guard on != shown else { return }
        shown = on
        if animated {
            layer?.animate("opacity", to: on ? 1 : 0, on ? TK.CA.hoverInT : TK.CA.hoverOutT)
        } else {
            layer?.setInstant { layer?.opacity = on ? 1 : 0 }
        }
    }
}

// MARK: - Empty states (css:298–303, §13)

final class EmptyStateView: NSView {
    private let glyph = GlyphLayer(.sun, size: 22)
    private let title = NSTextField(labelWithString: "")
    private let text = NSTextField(wrappingLabelWithString: "")

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(glyph)
        for f in [title, text] {
            f.alignment = .center
            f.isSelectable = false
            addSubview(f)
        }
        title.font = TK.Font.bodyMedium
        text.font = TK.Font.small
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ kind: TaskLayout.Empty, palette: TK.Palette, width: CGFloat) {
        let (e1, e2): (String, String) = switch kind {
        case .list: ("No tasks", "Click anywhere here or press ⌘N to add one.")
        case .today: ("Nothing for today", "Tasks you plan for today, or that are due, show up here.")
        case .allDone: ("All done for today", "")
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
            }
            if !glyph.isHidden {
                glyph.frame = CGRect(x: (width - 22) / 2, y: 0, width: 22, height: 22)
                y = 22 + 4 + 6
            }
        }
        title.stringValue = e1
        title.textColor = palette.ink2
        title.sizeToFit()
        title.frame = CGRect(x: 24, y: y - 0.5, width: max(0, width - 48), height: 16)
        y += 16 + 6
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.minimumLineHeight = 16
        para.maximumLineHeight = 16
        text.attributedStringValue = NSAttributedString(string: e2, attributes: [.font: TK.Font.small, .foregroundColor: palette.ink3, .paragraphStyle: para])
        text.isHidden = e2.isEmpty
        let tw = min(280, max(0, width - 48))
        let h = text.attributedStringValue.boundingRect(with: CGSize(width: tw, height: 200), options: [.usesLineFragmentOrigin]).height
        text.frame = CGRect(x: (width - tw) / 2 - 2, y: y, width: tw + 4, height: ceil(h) + 2)
        frame.size = CGSize(width: width, height: y + h)
    }
}

// MARK: - The archived list's banner (css:287–289, §12, §21)

final class BannerView: NSView {
    private let bg = CALayer()
    private let icon = GlyphLayer(.archive, size: 14)
    private let text = NSTextField(wrappingLabelWithString: "")
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
        text.isSelectable = false
        addSubview(text)
        for l in [bg, icon, button, buttonLabel] as [CALayer] { l.actions = TaskRowView.noActions }
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
        text.attributedStringValue = s
        let th = ceil(s.boundingRect(with: CGSize(width: textW, height: 400), options: [.usesLineFragmentOrigin]).height)
        let h = max(24, th) + 18
        text.frame = CGRect(x: textX - 2, y: (h - th) / 2, width: textW + 4, height: th + 1)
        layer?.setInstant {
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
