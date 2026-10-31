import AppKit
import QuartzCore
import TasksCore

/// What a task row shows. Rows are rebound only when this changes.
struct RowModel: Equatable {
    struct Chip: Equatable {
        var field: Overlays.Picker.Field
        var content: ChipLayer.Content
        /// The full date and how far it is, for the tooltip and VoiceOver: "Deadline: Sat, Nov 14 · 14 days left".
        var tip = ""
    }

    var id: EntityID
    var title: String
    var untitled: Bool
    var done: Bool
    var draft: Bool
    /// The When, after the title and its notes hint, as text (§24 Quiet When).
    var when: Chip?
    /// The Deadline: a capsule at the right, in its tone (§24).
    var deadline: Chip?
    /// What the checkbox's ring says (§24): overdue, due today, planned for today.
    var cue = CheckLayer.Cue()
    /// The notes' hint after the title: a glyph, or the checklist's count (design/MARKDOWN.md §7).
    var notes = NotesSummary()
    /// Today's Completed group: the list's name at the right (css:172).
    var whereText: String?
    /// Kept whole after `whereText` when it's cut: a month row's " · Oct 22" (§22).
    var whereSuffix: String?
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
    private let whereMask = FadeMask()
    private let whereSuffixLabel = TextLayer()
    private let whenChip = ChipLayer()
    private let deadlineChip = ChipLayer()
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
        layer.addSublayer(whereSuffixLabel)
        layer.addSublayer(whenChip)
        layer.addSublayer(deadlineChip)
        whereLabel.mask = whereMask
        layer.addSublayer(open)
        open.setInstant { open.opacity = 0 }
        open.reveal(false, animated: false)
        for l in [selection, ring, check, title, hintGlyph, hintCount, strike, whereLabel, whereSuffixLabel, open, whereMask, titleMask,
                  whenChip, deadlineChip] as [CALayer] {
            l.actions = Self.noActions
        }
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
            selection.backgroundColor = (m.paneFocused ? palette.fillRowSelected : palette.fillRowSelectedDim).cgColor
            selection.frame = CGRect(x: 0, y: 0, width: width, height: TK.M.row + (m.joinBottom ? 2 : 0))
            var corners: CACornerMask = []
            if !m.joinTop { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
            if !m.joinBottom { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
            selection.maskedCorners = corners
        }
        // Renaming: the selected fill plus a 1.5pt inset focus ring (§7).
        ring.isHidden = !m.renaming
        ring.borderColor = palette.focus.cgColor
        ring.frame = CGRect(x: 0, y: 0, width: width, height: TK.M.row)

        // Checkbox at x 10, centered.
        check.position = CGPoint(x: TK.M.rowPadLeft + TK.M.check / 2, y: TK.M.row / 2)
        CATransaction.commit()
        check.set(on: m.done, placeholder: m.draft, cue: m.cue, palette: palette, animated: anim)
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
        // The Deadline at the right, always shown (§24): a date never truncates. `.chips` keeps its 8pt margin even
        // when there's none.
        chipFrames = []
        if let c = m.deadline {
            let w = ChipLayer.width(c.content)
            let f = CGRect(x: right - w, y: (TK.M.row - TK.M.chip) / 2, width: w, height: TK.M.chip)
            bind(deadlineChip, c, frame: f, m: m, paletteChanged: paletteChanged, same: same)
            right -= w
        }
        deadlineChip.isHidden = m.deadline == nil
        right -= TK.M.chipsGap
        // Who gives way when the row is short (v2 feedback 16, §24): the title keeps up to `titleKeep` (all of a
        // shorter one) and its notes hint; the When after them goes rather than cut the title below that, and the
        // Deadline never does; the list name after the title keeps up to `whereKeep` and then truncates with the
        // title's end fade; space beyond the keeps goes to the title first, then to the list name. Nothing is drawn
        // over the leading content or past the row.
        let titleX = m.heading ? TK.M.rowPadLeft : TK.M.rowPadLeft + TK.M.check + TK.M.titleGap
        let color = (m.done || m.untitled) ? palette.inkTertiary : m.trashed ? palette.inkSecondary : palette.ink
        let text = m.untitled ? "New Task" : m.title
        title.set(text, font: m.heading ? HeadingRowView.font : TK.Font.body,
                  color: same ? (title.foregroundColor.flatMap(NSColor.init(cgColor:)) ?? color) : color)
        let hintW = layoutHint(m, palette)
        let hintSpace = hintW > 0 ? hintW + 6 : 0
        let titleNat = ceil(title.textWidth) + 1
        // The When's glyph sits 6 after the hint (or the title); its capsule's 5pt padding reaches back over the gap.
        let whenNat = m.when.map { ChipLayer.width($0.content) + 6 - ChipLayer.quietPad } ?? 0
        let showWhen = whenNat > 0 && right - titleX >= min(titleNat, Self.titleKeep) + hintSpace + whenNat
        let whenSpace = showWhen ? whenNat : 0
        let leadKeep = min(titleNat, Self.titleKeep) + hintSpace + whenSpace
        let leadNat = titleNat + hintSpace + whenSpace
        // The list name (and a month row's date, kept whole), 8 after the title's slot.
        let avail = max(0, right - titleX)
        var whereW: CGFloat = 0
        if let w = m.whereText {
            whereLabel.set(w, font: TK.Font.small, color: palette.inkTertiary)
            let suffix = m.whereSuffix ?? ""
            whereSuffixLabel.set(suffix, font: TK.Font.small, color: palette.inkTertiary)
            let suffixW = suffix.isEmpty ? 0 : TextLayer.width(suffix, font: TK.Font.small)
            let nameNat = TextLayer.width(w, font: TK.Font.small)
            let whereNat = 8 + nameNat + suffixW
            if leadNat + whereNat <= avail {
                whereW = whereNat
            } else {
                let whereKeep = 8 + min(nameNat, Self.whereKeep) + suffixW
                whereW = min(whereNat, max(whereKeep, avail - leadNat), max(0, avail - leadKeep))
                // Less than a few letters of the name reads as noise: then it goes.
                if whereW - 8 - suffixW < min(nameNat, Self.whereMin) { whereW = 0 }
            }
            if whereW > 0 {
                let nameW = whereW - 8 - suffixW
                let cut = nameW < nameNat - 0.5
                let x0 = right - whereW + 8
                whereLabel.place(x: x0, lineTop: (TK.M.row - 16) / 2, lineHeight: 16, width: cut ? nameW : nameNat + 2)
                whereMask.update(width: cut ? nameW : nameNat + 2, height: whereLabel.bounds.height,
                                 fade: cut ? min(TK.M.titleFade, nameW / 2) : 0)
                whereSuffixLabel.place(x: x0 + (cut ? nameW : nameNat), lineTop: (TK.M.row - 16) / 2, lineHeight: 16, width: suffixW + 2)
            }
        }
        whereLabel.isHidden = whereW == 0
        whereSuffixLabel.isHidden = whereW == 0 || (m.whereSuffix ?? "").isEmpty
        right -= whereW

        // The title: flex 1, nudged up 0.5. With notes, their hint follows the text 6 later, then the When 6 after
        // that; both stay whole: the title shrinks first. Its last 24pt fade out only when it's cut off (css:166–168,
        // md:67–77, §24). A heading's copy has no checkbox: its name starts at the checkbox's edge, semibold
        // (css:480–481).
        let slot = max(0, right - titleX)
        let room = max(0, slot - hintSpace - whenSpace)
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
        if showWhen, let c = m.when {
            // The title's end, the hint and its 6, then 6 to the glyph, less the capsule's own padding.
            let x = (hintX - 6) + hintSpace + 6 - ChipLayer.quietPad
            bind(whenChip, c, frame: CGRect(x: x, y: (TK.M.row - TK.M.chip) / 2, width: ChipLayer.width(c.content), height: TK.M.chip),
                 m: m, paletteChanged: paletteChanged, same: same)
        }
        whenChip.isHidden = !showWhen || m.renaming
        // The strike is instant; the color takes 200 ms (css:169–171).
        strike.isHidden = !m.done || m.renaming
        strike.backgroundColor = palette.inkQuiet.cgColor
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
        let whereFull = m.whereText.map { $0 + (m.whereSuffix ?? "") }
        let dates = [m.when, m.deadline].compactMap { $0.map { $0.tip.isEmpty ? $0.content.text : $0.tip } }
        setAccessibilityLabel(([text, notesLabel].compactMap { $0 } + dates + [whereFull].compactMap { $0 }).joined(separator: ", "))
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

    #if DEBUG
    /// Debug (§24): what the row shows of its dates: the When (or "dropped"), the Deadline and its tone, the ring.
    var debugDates: String {
        guard let m = model else { return "-" }
        let when = m.when.map { whenChip.isHidden ? "dropped" : "'\($0.content.text)'" } ?? "-"
        let dl = m.deadline.map { "'\($0.content.text)' \($0.content.tone)" } ?? "-"
        let cue = [m.cue.deadline.map { "\($0)" }, m.cue.planned ? "planned" : nil].compactMap { $0 }.joined(separator: "+")
        return "when=\(when) deadline=\(dl) ring=\(cue.isEmpty ? "-" : cue)\(m.done ? " done" : "")"
    }
    #endif

    /// A date's tooltip (§24), while its chip is shown.
    func chipTip(_ field: Overlays.Picker.Field) -> String? {
        guard chipFrame(field) != nil else { return nil }
        return (field == .when ? model?.when : model?.deadline)?.tip
    }

    /// Shows a date chip in `frame` and records it for hit-testing.
    private func bind(_ layer: ChipLayer, _ c: RowModel.Chip, frame: CGRect, m: RowModel, paletteChanged: Bool, same: Bool) {
        layer.lifted = style == .lifted
        if layer.content != c.content || paletteChanged || !same { layer.set(c.content, palette: palette) }
        layer.pickerOpen = m.pickerField == c.field
        layer.frame = frame
        chipFrames.append((c.field, frame))
    }

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
        whenChip.hovered = p == .chip(.when)
        deadlineChip.hovered = p == .chip(.deadline)
    }

    func setPressed(_ part: Part?) {
        check.setPressedIfChanged(part == .check)
        open.pressed = part == .open
        whenChip.pressed = part == .chip(.when)
        deadlineChip.pressed = part == .chip(.deadline)
    }

    nonisolated(unsafe) static let hintFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)   // .ncount 500 11/14

    /// What the title keeps before chips are dropped or the list name is cut (all of a shorter title), and what the
    /// list name after it keeps before the title gives up more; a list name shorter than `whereMin` after cutting is
    /// left out (v2 feedback 16).
    static let titleKeep: CGFloat = 120
    static let whereKeep: CGFloat = 72
    static let whereMin: CGFloat = 32

    /// Sets the hint's glyph, count and colors, and returns its width (0 without notes): the glyph alone in a 14pt
    /// box (`ink-quaternary`), or the box glyph, 4, and "2/5" in `ink-tertiary`, `ink-quaternary` once all are checked
    /// or on a done row (md:74–77).
    private func layoutHint(_ m: RowModel, _ p: TK.Palette) -> CGFloat {
        guard m.notes.hasNotes, !m.untitled || !m.draft else { return 0 }
        if m.notes.total > 0 {
            let quiet = m.done || m.notes.checked == m.notes.total
            let c = quiet ? p.inkQuiet : p.inkTertiary
            if hintGlyph.glyph != .checklist { hintGlyph.set(.checklist, size: 11) }
            hintGlyph.color = c
            let text = "\(m.notes.checked)/\(m.notes.total)"
            hintCount.set(text, font: Self.hintFont, color: c)
            return 11 + 4 + TextLayer.width(text, font: Self.hintFont)
        }
        if hintGlyph.glyph != .notes { hintGlyph.set(.notes, size: 11) }
        hintGlyph.color = p.inkQuiet
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
    /// A date's button: its tooltip is its label, and pressing it opens its popover (§24).
    var onChip: ((Overlays.Picker.Field) -> Void)?
    private lazy var checkElement = PressElement(role: .checkBox, parent: self)
    private lazy var openElement = PressElement(role: .button, parent: self)
    private lazy var whenElement = PressElement(role: .button, parent: self)
    private lazy var deadlineElement = PressElement(role: .button, parent: self)

    override func accessibilityChildren() -> [Any]? {
        guard let m = model, style == .row else { return [] }
        let title = m.untitled ? "New Task" : m.title
        checkElement.setAccessibilityLabel((m.done ? "Mark not done: " : "Complete: ") + title + (m.done ? "" : m.cue.words))
        checkElement.setAccessibilityValue(m.done ? 1 : 0)
        checkElement.setAccessibilityFrameInParentSpace(CGRect(x: check.frame.minX, y: bounds.height - check.frame.maxY, width: check.frame.width, height: check.frame.height))
        checkElement.onPress = onCheck
        var children: [Any] = m.draft ? [] : [checkElement]
        for (field, element, chip) in [(Overlays.Picker.Field.when, whenElement, m.when), (.deadline, deadlineElement, m.deadline)] {
            guard let chip, let f = chipFrame(field), !m.trashed else { continue }
            element.setAccessibilityLabel(chip.tip)
            element.setAccessibilityFrameInParentSpace(CGRect(x: f.minX, y: bounds.height - f.maxY, width: f.width, height: f.height))
            element.onPress = onChip.map { open in { open(field) } }
            children.append(element)
        }
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
/// "Completed" label folds instead (v2 feedback 15): a 12pt chevron in a 22pt button, revealed on hover and kept while
/// collapsed, the done count 8 after the name when collapsed, and the row's fill when it's selected (Space folds it).
/// The name and a day's date never run under the buttons: cut off, their last 24pt fade out, as a title's do.
final class GroupLabelView: NSView {
    enum Part: Equatable { case body, plus, chevron }

    private let label = TextLayer()
    private let labelMask = FadeMask()
    /// A day's date after its name (§22): 400 `ink-quiet`, 6 after the name.
    private let sub = TextLayer()
    private let subMask = FadeMask()
    private let count = TextLayer()
    private let selection = CALayer()
    private var palette = TK.Palette.dark
    private var quiet = false
    private var drop = false
    let plus = IconButtonLayer(.plus, size: 22, glyphSize: 12)
    /// A 12pt glyph from the first frame in both states: only its rotation changes (as a heading's, §23).
    let chevron = IconButtonLayer(.chevronRight, size: 22, glyphSize: 12)
    private(set) var key: EntityID = ""
    private(set) var hasPlus = true
    private(set) var hasChevron = false
    private(set) var collapsed = false
    private var chevronDown: Bool?
    private var hovered = false
    private var hoveredPart: Part?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        selection.cornerRadius = TK.M.rowRadius
        selection.isHidden = true
        label.mask = labelMask
        sub.mask = subMask
        for l in [selection, label, sub, count, plus, chevron] as [CALayer] {
            l.actions = TaskRowView.noActions
            layer?.addSublayer(l)
        }
        plus.reveal(false, animated: false)
        chevron.reveal(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    /// `chevron`: Today's Completed, which folds (`collapsed` shows `count` after the name). `selected`: its fill.
    func configure(key: EntityID, name: String, plus hasPlus: Bool, palette: TK.Palette, width: CGFloat,
                   sub subText: String? = nil, quiet: Bool = false, chevron hasChevron: Bool = false,
                   collapsed: Bool = false, count n: Int = 0, selected: Bool = false, paneFocused: Bool = true,
                   animated: Bool = false) {
        let paletteChanged = palette != self.palette || self.key.isEmpty
        self.key = key
        self.hasPlus = hasPlus
        self.hasChevron = hasChevron
        self.palette = palette
        self.quiet = quiet
        let isCollapsed = hasChevron && collapsed
        let revealChanged = isCollapsed != self.collapsed
        self.collapsed = isCollapsed
        // The buttons' slot: 22 and 5 from the edge, plus 5 before them; with both, the + 2 before the chevron.
        let buttons: CGFloat = (hasPlus || hasChevron ? 32 : 0) + (hasPlus && hasChevron ? 24 : 0)
        let countText = isCollapsed && n > 0 ? String(n) : ""
        let countW = countText.isEmpty ? 0 : TextLayer.width(countText, font: HeadingRowView.countFont) + 8
        let room = max(0, width - 12 - buttons - countW)
        layer?.setInstant {
            let colors = labelColors
            // Selected (Today's Completed): the row's fill, in the row's 30pt shape (§5).
            selection.isHidden = !selected
            selection.backgroundColor = (paneFocused ? palette.fillRowSelected : palette.fillRowSelectedDim).cgColor
            selection.frame = CGRect(x: 0, y: 1, width: width, height: TK.M.row)
            label.set(name, font: TK.Font.label, color: colors.name)
            let full = TextLayer.width(name, font: TK.Font.label)
            // The name takes at most 70% when a date follows it (css:417).
            let nameRoom = subText == nil ? room : min(full, room * 0.7)
            let nameW = min(nameRoom, ceil(full) + 1)
            // 1pt of room past the text, so the clip never takes a glyph's overhang.
            label.place(x: 12, lineTop: 10, lineHeight: 14, width: nameW + 1)
            labelMask.update(width: nameW + 1, height: label.bounds.height, fade: full > nameRoom + 0.5 ? TK.M.titleFade : 0)
            if let subText, !subText.isEmpty {
                sub.isHidden = false
                sub.set(subText, font: Self.subFont, color: colors.sub)
                let subRoom = max(0, room - nameW - 6)
                let subFull = TextLayer.width(subText, font: Self.subFont)
                let subW = min(subRoom, ceil(subFull) + 1)
                sub.place(x: 12 + nameW + 6, lineTop: 10, lineHeight: 14, width: subW + 1)
                subMask.update(width: subW + 1, height: sub.bounds.height, fade: subFull > subRoom + 0.5 ? TK.M.titleFade : 0)
            } else {
                sub.isHidden = true
            }
            count.isHidden = countText.isEmpty
            count.set(countText, font: HeadingRowView.countFont, color: palette.inkTertiary)
            count.place(x: 12 + nameW + 8, lineTop: 10, lineHeight: 14, width: countW + 2)
            plus.isHidden = !hasPlus
            chevron.isHidden = !hasChevron
            if paletteChanged {
                plus.setPalette(palette)
                chevron.setPalette(palette)
            }
            chevron.position = CGPoint(x: width - 5 - 11, y: 6 + 11)
            plus.position = CGPoint(x: width - 5 - 11 - (hasChevron ? 24 : 0), y: 6 + 11)
        }
        // The chevron points down when open and right when collapsed, turning in 200 ms ease-out.
        if hasChevron {
            let down = !isCollapsed
            if chevronDown != down {
                let angle = down ? CGFloat.pi / 2 : 0
                if chevronDown != nil, animated, !TK.CA.reduce {
                    chevron.glyph.animate("transform.rotation.z", to: angle, TK.CA.chevronT)
                } else {
                    chevron.glyph.setInstant { chevron.glyph.setValue(angle, forKeyPath: "transform.rotation.z") }
                }
                chevronDown = down
            }
            setAccessibilityLabel(name + (isCollapsed ? ", collapsed, \(n)" : ""))
        }
        if revealChanged { updateReveal(animated: animated) }
    }

    func plusContains(_ p: CGPoint) -> Bool { hasPlus && plus.frame.contains(p) }

    /// The part under a point: the buttons first, whatever their fade, so a press there never selects the label.
    func part(at p: CGPoint) -> Part {
        if hasChevron, chevron.frame.contains(p) { return .chevron }
        if hasPlus, plus.frame.contains(p) { return .plus }
        return .body
    }

    nonisolated(unsafe) static let subFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    #if DEBUG
    var debugLit: Bool { drop }
    #endif

    /// The name `ink-tertiary` (an empty day's `ink-quiet`), the date `ink-quiet`; both `accent-text` on the day a drag
    /// in Upcoming would land on.
    private var labelColors: (name: NSColor, sub: NSColor) {
        if drop { return (palette.accentText, palette.accentText) }
        return (quiet ? palette.inkQuiet : palette.inkTertiary, palette.inkQuiet)
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

    func setHover(_ on: Bool, part: Part?) {
        if on != hovered {
            hovered = on
            updateReveal(animated: true)
        }
        let p = on ? part : nil
        guard p != hoveredPart else { return }
        hoveredPart = p
        plus.hovered = p == .plus
        chevron.hovered = p == .chevron
    }

    func setPressed(_ part: Part?) {
        plus.pressed = part == .plus
        chevron.pressed = part == .chevron
    }

    /// Hover fades the buttons in on `hoverIn` and out on `hoverOut`; a collapsed label keeps its chevron.
    private func updateReveal(animated: Bool) {
        plus.reveal(hovered && hasPlus, animated: animated)
        chevron.reveal(hasChevron && (hovered || collapsed), animated: animated)
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
        let color = hovered ? palette.ink : palette.inkSecondary
        let countText = "\(n)"
        layer?.setInstant {
            chevron.color = color
            chevron.position = CGPoint(x: 12 + 6, y: TK.M.row / 2)
            label.set("Completed", font: TK.Font.bodyMedium, color: color)
            let lw = TextLayer.width("Completed", font: TK.Font.bodyMedium)
            label.place(x: 12 + 12 + 6, lineTop: 7, lineHeight: 16, width: lw + 2)
            count.set(countText, font: TK.Font.count, color: palette.inkTertiary)
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
        let color = on ? palette.ink : palette.inkSecondary
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
                glyph.color = palette.inkQuiet
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
                glyph.color = palette.inkQuiet
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
        let body = NSAttributedString(string: e2, attributes: [.font: TK.Font.small, .foregroundColor: palette.inkTertiary, .paragraphStyle: para])
        let h = ceil(body.boundingRect(with: CGSize(width: tw, height: 200), options: [.usesLineFragmentOrigin]).height)
        layer?.setInstant {
            title.set(e1, font: TK.Font.bodyMedium, color: palette.inkSecondary)
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
        s.append(NSAttributedString(string: " · Not in Today or Move to. Everything still edits.", attributes: [.font: TK.Font.small, .foregroundColor: palette.inkSecondary, .paragraphStyle: para]))
        let th = ceil(s.boundingRect(with: CGSize(width: textW, height: 400), options: [.usesLineFragmentOrigin]).height)
        let h = max(24, th) + 18
        layer?.setInstant {
            text.string = s
            text.frame = CGRect(x: textX, y: (h - th) / 2, width: textW, height: th + 2)
            bg.frame = CGRect(x: 0, y: 0, width: width, height: h)
            bg.backgroundColor = palette.fillControl.cgColor
            icon.color = palette.inkSecondary
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
