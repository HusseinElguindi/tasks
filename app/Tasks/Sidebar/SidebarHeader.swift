import AppKit
import QuartzCore

// The sidebar's brand header (v2 feedback 12): the bare 04 · Log mark and "Tasks", above Today. The logo canvas's
// "Sidebar header" board (design/logo/Sheet.dc.html, around line 168).

/// The bare 04 · Log mark as vectors, from the shapes in `design/logo/final/gen.py` (`mark()`), in its 724-unit
/// viewBox (150 150 724 724), y down. Four layers, back to front: the trail (spine and the two short bars), the rings,
/// the head's bar, and the head with its check cut out. `small` is the cut the icon uses below 60px: the rings become
/// dots and every stroke thickens; at 18pt it's the one that reads (the full cut's rings and check are hairlines).
enum BrandMark {
    enum Part: CaseIterable { case trail, rings, bar, head }

    static let viewBox = CGRect(x: 150, y: 150, width: 724, height: 724)

    static func paths(small: Bool) -> [(Part, CGPath)] {
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        func capsule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
            CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        }
        func union(_ ps: [CGPath]) -> CGPath {
            let m = CGMutablePath()
            ps.forEach { m.addPath($0) }
            return m
        }
        /// The check, a round-capped, round-joined stroke of width `2 × half` (gen.py `check`).
        func check(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ half: CGFloat) -> CGPath {
            let line = CGMutablePath()
            line.addLines(between: [CGPoint(x: cx - 26 * s, y: cy + 2 * s), CGPoint(x: cx - 8 * s, y: cy + 20 * s),
                                    CGPoint(x: cx + 26 * s, y: cy - 18 * s)])
            return line.copy(strokingWithWidth: 2 * half, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        let cx: CGFloat, headY: CGFloat, r1: CGFloat, r2: CGFloat, barX: CGFloat
        let head, rings, bar, trail: CGPath
        if small {
            (cx, headY, r1, r2, barX) = (322, 336, 556, 732, 462)
            head = circle(cx, headY, 100).subtracting(check(cx, headY, 1.75, 15))
            rings = union([circle(cx, r1, 56), circle(cx, r2, 56)])
            bar = capsule(barX, headY - 40, 340, 80)
            trail = union([CGPath(rect: CGRect(x: cx - 18, y: headY + 100, width: 36, height: r1 - 56 - headY - 100), transform: nil),
                           CGPath(rect: CGRect(x: cx - 18, y: r1 + 56, width: 36, height: r2 - 56 - r1 - 56), transform: nil),
                           capsule(barX, r1 - 32, 280, 64), capsule(barX, r2 - 32, 220, 64)])
        } else {
            (cx, headY, r1, r2, barX) = (324, 314, 541, 739, 454)
            head = circle(cx, headY, 84).subtracting(check(cx, headY, 1.45, 11))
            rings = union([circle(cx, r1, 55).subtracting(circle(cx, r1, 33)), circle(cx, r2, 55).subtracting(circle(cx, r2, 33))])
            bar = capsule(barX, headY - 24, 330, 48)
            trail = union([CGPath(rect: CGRect(x: cx - 11, y: headY + 84, width: 22, height: r1 - 55 - headY - 84), transform: nil),
                           CGPath(rect: CGRect(x: cx - 11, y: r1 + 55, width: 22, height: r2 - 55 - r1 - 55), transform: nil),
                           capsule(barX, r1 - 18, 260, 36), capsule(barX, r2 - 18, 200, 36)])
        }
        return [(.trail, trail), (.rings, rings), (.bar, bar), (.head, head)]
    }

    /// The mark's colors: the icon's dark layers (gen.py `COLORS['dark']`), and on the light sidebar the light variant
    /// the final mark was designed with (commit 5568418), since the icon itself is dark only.
    static func color(_ part: Part, dark: Bool) -> NSColor {
        switch part {
        case .trail: TK.hex(dark ? 0x6D7072 : 0xA9ACAF)
        case .rings: TK.hex(dark ? 0xA8ADB1 : 0x626568)
        case .bar: TK.hex(dark ? 0xE6EDF3 : 0x1F2328)
        case .head: TK.hex(dark ? 0x2F81F7 : 0x0969DA)
        }
    }
}

/// The header row: 34 tall at the top of the sidebar's content, inset 10 like the rows; the mark at 18pt 10 in, then
/// "Tasks" 8 after it in 13pt semibold `ink`. A label, not a control: no hover, no press, and it scrolls and collapses
/// with the sidebar.
final class SidebarHeaderLayer: CALayer {
    static let markSize: CGFloat = 18
    static let markX: CGFloat = 10
    static let gap: CGFloat = 8

    private let mark = CALayer()
    private var shapes: [BrandMark.Part: CAShapeLayer] = [:]
    let title = TextLayer()
    private var dark: Bool?

    override init() {
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: SB.rowWidth(sidebar: TK.M.sidebar), height: SB.headerHeight)
        actions = TaskRowView.noActions
        let s = Self.markSize
        mark.anchorPoint = .zero
        mark.frame = CGRect(x: Self.markX, y: (SB.headerHeight - s) / 2, width: s, height: s)
        mark.actions = TaskRowView.noActions
        let v = BrandMark.viewBox
        var t = CGAffineTransform(scaleX: s / v.width, y: s / v.height).translatedBy(x: -v.minX, y: -v.minY)
        for (part, path) in BrandMark.paths(small: true) {
            let l = CAShapeLayer()
            l.path = path.copy(using: &t)
            l.actions = TaskRowView.noActions
            mark.addSublayer(l)
            shapes[part] = l
        }
        addSublayer(mark)
        addSublayer(title)
        title.actions = TaskRowView.noActions
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setPalette(_ p: TK.Palette) {
        guard dark != p.isDark else { return }
        dark = p.isDark
        for (part, l) in shapes { l.fillColor = BrandMark.color(part, dark: p.isDark).cgColor }
        let x = Self.markX + Self.markSize + Self.gap
        title.set("Tasks", font: TK.Font.brand, color: p.ink)
        title.place(x: x, lineTop: (SB.headerHeight - 16) / 2, lineHeight: 16, width: bounds.width - x)
    }
}
