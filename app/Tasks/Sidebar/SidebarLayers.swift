import AppKit
import QuartzCore

// The sidebar's layers (css:107–140, 240–243). Geometry is y down, in points; every layer's top-left is its position
// (anchor point zero), so the rows can spring on `position.y`.

// MARK: - A row (Today, a list, an archived list)

/// The 209×30 capsule (`.sbi.srow`), its tile, title and count, in each state of the §12 table.
final class SidebarRowLayer: CALayer {
    private let edgeInner = CALayer()
    private let edgeOuter = CALayer()
    private let ring = CALayer()
    let tile = TileLayer()
    let title = TextLayer()
    private let fade = FadeMask()
    let count = TextLayer()
    private(set) var row: SidebarModel.Row?
    private(set) var hovered = false
    private var palette = TK.Palette.dark
    /// The capsule's width, from the sidebar's (`SB.rowWidth(sidebar:)`).
    var rowWidth: CGFloat = SB.rowWidth(sidebar: TK.M.sidebar) {
        didSet { if rowWidth != oldValue { placeAcross() } }
    }

    nonisolated(unsafe) static let hintFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)   // .ct.hint

    override init() {
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: rowWidth, height: SB.rowHeight)
        cornerRadius = SB.radius
        // Inset box-shadows (css:109, 115, 119): the 1pt inner edge, the 0.5pt outer edge on top of it, or the accent ring.
        for l in [edgeInner, edgeOuter, ring] {
            l.frame = bounds
            l.cornerRadius = SB.radius
            addSublayer(l)
        }
        edgeInner.borderWidth = 1
        edgeOuter.borderWidth = 0.5
        addSublayer(tile)
        addSublayer(title)
        addSublayer(count)
        title.mask = fade
        count.alignmentMode = .right
        // A text layer redraws its contents at commit time, outside the sidebar's no-actions transaction, and the
        // default `contents` action crossfaded it over 250 ms: a list's count stayed blue after a drag moved on to the
        // next list (v2 feedback 7). The count's color changes at once (css:113–117).
        count.actions = TaskRowView.noActions
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// Applies a row's state. `animated` runs the title's color change on `hoverIn` / `hoverOut` (fills, edges and the
    /// count change at once, as in css:107–118); off for list switches, themes and the first frame.
    func update(_ r: SidebarModel.Row, palette p: TK.Palette, hovered h: Bool, animated: Bool) {
        let first = row == nil
        row = r
        hovered = h
        palette = p

        let tileColor = r.monogram == nil ? p.ansiYellow : p.listColor(slot: r.slot)
        tile.set(monogram: r.monogram, color: tileColor, palette: p)
        tile.position = CGPoint(x: SB.tileX + tile.bounds.width / 2, y: SB.rowHeight / 2)

        let bg: NSColor? = r.drop ? p.accentTint : r.editing ? p.fillControl : r.current ? p.fillStrong : nil
        backgroundColor = bg?.cgColor
        let edges = r.current && !r.drop && !r.editing
        edgeInner.isHidden = !edges
        edgeOuter.isHidden = !edges
        edgeInner.borderColor = p.edgeInner.cgColor
        edgeOuter.borderColor = p.edgeOuter.cgColor
        ring.borderWidth = r.drop ? 2 : r.editing ? 1.5 : 0
        ring.borderColor = p.accent.cgColor

        title.isHidden = r.editing
        let tc = titleColor
        title.set(r.name, font: TK.Font.body, color: first || !animated ? tc : NSColor(cgColor: title.foregroundColor ?? tc.cgColor) ?? tc)
        if animated && !first { setTitleColor(tc) }

        let cc: NSColor = r.drop ? p.accentText : r.hint ? p.ink2 : r.current ? p.ink2 : p.ink3
        count.set(r.count, font: r.hint ? Self.hintFont : TK.Font.count, color: cc)
        placeAcross()
    }

    /// What depends on the capsule's width: its box and edges, the title's width and fade, the count's box (right-
    /// aligned, ending 8 short of the capsule's right edge, on the row's centered 16pt line).
    private func placeAcross() {
        bounds = CGRect(x: 0, y: 0, width: rowWidth, height: SB.rowHeight)
        for l in [edgeInner, edgeOuter, ring] { l.frame = bounds }
        let titleWidth = rowWidth - SB.titleX
        title.place(x: SB.titleX, lineTop: SB.titleLineTop, lineHeight: 16, width: titleWidth)
        fade.update(width: titleWidth, height: title.bounds.height, fade: SB.titleFade, end: SB.titleFadeEnd)
        let countWidth: CGFloat = 80
        count.place(x: rowWidth - SB.countRight - countWidth, lineTop: (SB.rowHeight - 16) / 2, lineHeight: 16, width: countWidth)
    }

    /// The pointer arrived or left: the title goes to `ink` on `hoverIn`, back on `hoverOut`.
    func setHovered(_ h: Bool) {
        guard h != hovered else { return }
        hovered = h
        guard row != nil else { return }
        setTitleColor(titleColor)
    }

    /// css:107–117: rest `ink-secondary`, hovered or current `ink`; archived `ink-tertiary` (`ink` hovered or current);
    /// a drop target `accent-text`; being renamed `ink`.
    private var titleColor: NSColor {
        guard let r = row else { return palette.ink2 }
        let p = palette
        if r.editing { return p.ink }
        if r.drop { return p.accentText }
        if hovered || r.current { return p.ink }
        return r.archived ? p.ink3 : p.ink2
    }

    private func setTitleColor(_ c: NSColor) {
        let cg = c.cgColor
        if let cur = title.foregroundColor, cur == cg { return }
        title.animate("foregroundColor", to: cg, hovered ? TK.CA.hoverInT : TK.CA.hoverOutT)
    }
}

// MARK: - A group label ("Lists" with its +, "Archive" with its chevron)

/// `.glabel` (css:131–139): a 32pt slot, 11/14 semibold `ink-tertiary` 12 in and 10 down; its button (`.gbtn`) is
/// revealed while the label is hovered (`hoverIn` / `hoverOut`), and for the Archive chevron while the group is open.
final class SidebarLabelLayer: CALayer {
    let text = TextLayer()
    let button: IconButtonLayer
    private(set) var titleText = ""
    private var chevronOpen = false
    var rowWidth: CGFloat = SB.rowWidth(sidebar: TK.M.sidebar) {
        didSet {
            guard rowWidth != oldValue else { return }
            bounds.size.width = rowWidth
            button.position = SB.buttonFrame(rowWidth: rowWidth).origin
            text.place(x: SB.labelTextX, lineTop: SB.labelTextTop, lineHeight: 14, width: rowWidth - SB.labelTextX)
        }
    }

    init(title: String, glyph: Glyph) {
        button = IconButtonLayer(glyph, size: SB.buttonSize, glyphSize: 12, radius: 6)
        titleText = title
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: rowWidth, height: SB.labelHeight)
        addSublayer(text)
        addSublayer(button)
        button.anchorPoint = .zero
        button.position = SB.buttonFrame(rowWidth: rowWidth).origin
        button.reveal(false, animated: false)
    }

    override init(layer: Any) {
        button = IconButtonLayer(.plus, size: SB.buttonSize)
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPalette(_ p: TK.Palette) {
        text.set(titleText, font: TK.Font.label, color: p.ink3)
        text.place(x: SB.labelTextX, lineTop: SB.labelTextTop, lineHeight: 14, width: rowWidth - SB.labelTextX)
        text.masksToBounds = true
        button.setPalette(p)
    }

    /// The chevron turns 90° in 200 ms ease-out (css:138–139).
    func setChevron(open: Bool, animated: Bool) {
        guard open != chevronOpen else { return }
        chevronOpen = open
        let angle: CGFloat = open ? .pi / 2 : 0
        if animated {
            button.glyph.animate("transform.rotation.z", to: angle, TK.CA.chevronT)
        } else {
            button.glyph.setInstant { button.glyph.setValue(angle, forKeyPath: "transform.rotation.z") }
        }
    }
}

// MARK: - The lifted copy of a dragged list (css:240–243, dc:2016–2021)

/// `.lifted.cap`: the capsule in `fill-strong` with `shadow-lift` (a 0.5pt ring plus `0 8 24`), its tile, and the
/// name in `ink` fading over its last 24pt. It lives in the window's drag overlay, at window points.
final class SidebarLiftLayer: CALayer {
    private let ring = CALayer()
    private let tile = TileLayer()
    private let label = TextLayer()
    private let fade = FadeMask()

    init(name text: String, monogram: String, slot: Int, rowWidth: CGFloat, palette p: TK.Palette) {
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: rowWidth, height: SB.rowHeight)
        cornerRadius = SB.radius
        backgroundColor = p.fillStrong.cgColor
        shadowColor = p.liftShadow.cgColor
        shadowOpacity = 1
        shadowOffset = CGSize(width: 0, height: 8)
        shadowRadius = 12
        shadowPath = CGPath(roundedRect: bounds, cornerWidth: SB.radius, cornerHeight: SB.radius, transform: nil)
        // The ring is outside the box (a 0.5pt spread, not inset).
        ring.frame = bounds.insetBy(dx: -0.5, dy: -0.5)
        ring.cornerRadius = SB.radius + 0.5
        ring.borderWidth = 0.5
        ring.borderColor = p.liftRing.cgColor
        addSublayer(ring)
        tile.set(monogram: monogram, color: p.listColor(slot: slot), palette: p)
        tile.position = CGPoint(x: SB.tileX + tile.bounds.width / 2, y: SB.rowHeight / 2)
        addSublayer(tile)
        // `.tt`: 7 after the tile to the 10pt right padding, on the row's own text line (the row's 0.5 nudge too, so the
        // copy's name lies exactly on the row's as it fades out over it after a drop, v2 feedback 5).
        let width = rowWidth - SB.titleX - 10
        label.set(text, font: TK.Font.body, color: p.ink)
        label.place(x: SB.titleX, lineTop: SB.titleLineTop, lineHeight: 16, width: width)
        fade.update(width: width, height: label.bounds.height, fade: 24)
        label.mask = fade
        addSublayer(label)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
}
