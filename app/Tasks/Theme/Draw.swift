import AppKit
import QuartzCore
import SwiftUI

// Drawing primitives for the AppKit lists (task rows, the sidebar, the drag copy), matching the prototype's CSS.
// Every view here is flipped (y down, like the prototype), and every layer's geometry is in points.

// MARK: - Glyphs (the prototype's 16×16 SVG icons, 1.5pt round strokes scaled with the icon, css:40–43)

enum Glyph: CaseIterable {
    case sun, sidebarLeft, split, plus, chevronRight, chevronLeft, calendar, flag, xmark, trash, lines, archive,
         checkCircle, upDown, check

    /// SVG path data in a 16×16 view box, y down.
    private var svg: [String] {
        switch self {
        case .sun: return ["M8 1.9v1.3M8 12.8v1.3M1.9 8h1.3M12.8 8h1.3M3.7 3.7l.9.9M11.4 11.4l.9.9M3.7 12.3l.9-.9M11.4 4.6l.9-.9", "circle 8 8 2.6"]
        case .sidebarLeft: return ["rect 2 3 12 10 2", "M6 3V13"]
        case .split: return ["rect 2 3 12 10 2", "M10 3V13"]
        case .plus: return ["M8 3.5v9M3.5 8h9"]
        case .chevronRight: return ["M6.5 4l4 4-4 4"]
        case .chevronLeft: return ["M9.5 4l-4 4 4 4"]
        case .calendar: return ["rect 2.5 3.5 11 10 2", "M2.5 6.5h11M5.5 2v3M10.5 2v3"]
        case .flag: return ["M4 14V2.5M4 3h7.5L10 5.75 11.5 8.5H4"]
        case .xmark: return ["M4.5 4.5l7 7M11.5 4.5l-7 7"]
        case .trash: return ["M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.5 9h6l.5-9"]
        case .lines: return ["M3 4.5h10M3 8h10M3 11.5h10"]
        case .archive: return ["rect 2 3 12 3.5 1", "M3 6.5v6a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-6M6.5 9.5h3"]
        case .checkCircle: return ["circle 8 8 6.2", "M5.3 8.2l1.9 1.9 3.6-4"]
        case .upDown: return ["M5 6.5L8 3.5l3 3M5 9.5l3 3 3-3"]
        case .check: return ["M3.8 8.4l2.7 2.7 5.7-6.2"]
        }
    }

    /// Stroke width in view-box units (the checkmark is 2.2, css:197).
    var viewBoxStroke: CGFloat { self == .check ? 2.2 : 1.5 }

    /// The path at `size` points square, y down.
    func path(size: CGFloat) -> CGPath {
        let key = "\(self)-\(size)"
        if let cached = Glyph.cache[key] { return cached }
        let s = size / 16
        let path = CGMutablePath()
        let t = CGAffineTransform(scaleX: s, y: s)
        for part in svg {
            let f = part.split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
            if part.hasPrefix("rect") {
                path.addPath(CGPath(roundedRect: CGRect(x: f[0], y: f[1], width: f[2], height: f[3]), cornerWidth: f[4],
                                    cornerHeight: f[4], transform: nil), transform: t)
            } else if part.hasPrefix("circle") {
                path.addEllipse(in: CGRect(x: f[0] - f[2], y: f[1] - f[2], width: 2 * f[2], height: 2 * f[2]), transform: t)
            } else {
                path.addPath(SVGPath.parse(part), transform: t)
            }
        }
        Glyph.cache[key] = path
        return path
    }

    func lineWidth(size: CGFloat) -> CGFloat { viewBoxStroke * size / 16 }

    nonisolated(unsafe) private static var cache: [String: CGPath] = [:]
}

/// A minimal SVG path parser for the commands the prototype's icons use: M m L l H h V v A a, and implicit repeats.
enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
            } else if ch == "-" {
                if !cur.isEmpty && cur.last != "e" { tokens.append(cur); cur = "" }
                cur.append(ch)
            } else if ch == "." && cur.contains(".") {
                tokens.append(cur)
                cur = "."
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var i = 0
        var cmd: Character = "M"
        var p = CGPoint.zero
        var start = CGPoint.zero
        var vertical = false
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter, tokens[i].count == 1 {
                cmd = c
                i += 1
                if cmd == "Z" || cmd == "z" { path.closeSubpath(); p = start; continue }
            }
            switch cmd {
            case "M": p = CGPoint(x: num(), y: num()); path.move(to: p); start = p; cmd = "L"
            case "m": p = CGPoint(x: p.x + num(), y: p.y + num()); path.move(to: p); start = p; cmd = "l"
            case "L": let q = CGPoint(x: num(), y: num()); vertical = q.x == p.x; p = q; path.addLine(to: p)
            case "l": let dx = num(), dy = num(); vertical = dx == 0; p = CGPoint(x: p.x + dx, y: p.y + dy); path.addLine(to: p)
            case "H": p.x = num(); vertical = false; path.addLine(to: p)
            case "h": p.x += num(); vertical = false; path.addLine(to: p)
            case "V": p.y = num(); vertical = true; path.addLine(to: p)
            case "v": p.y += num(); vertical = true; path.addLine(to: p)
            case "a", "A":
                // Only the icons' small quarter-circle corners (a1 1 0 0 0 1 1): approximate with a quadratic curve.
                _ = num(); _ = num(); _ = num(); _ = num(); _ = num()
                var end = CGPoint(x: num(), y: num())
                if cmd == "a" { end = CGPoint(x: p.x + end.x, y: p.y + end.y) }
                // The corner's control point continues the incoming leg.
                let control = vertical ? CGPoint(x: p.x, y: end.y) : CGPoint(x: end.x, y: p.y)
                path.addQuadCurve(to: end, control: control)
                vertical = !vertical
                p = end
            default: i += 1
            }
        }
        return path
    }
}

/// A glyph drawn as a stroked shape layer of `size` points.
final class GlyphLayer: CAShapeLayer {
    private(set) var glyph: Glyph = .plus
    private(set) var size: CGFloat = 14

    convenience init(_ glyph: Glyph, size: CGFloat) {
        self.init()
        fillColor = nil
        lineCap = .round
        lineJoin = .round
        set(glyph, size: size)
    }

    func set(_ glyph: Glyph, size: CGFloat) {
        self.glyph = glyph
        self.size = size
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        path = glyph.path(size: size)
        lineWidth = glyph.lineWidth(size: size)
    }

    var color: NSColor? {
        get { strokeColor.flatMap { NSColor(cgColor: $0) } }
        set { strokeColor = newValue?.cgColor }
    }
}

// MARK: - Text

/// Text in a CATextLayer, placed by its CSS line box: `lineTop` and `lineHeight` as in the prototype, so baselines
/// land where the browser puts them (half-leading above the ascender).
final class TextLayer: CATextLayer {
    private(set) var text = ""
    private(set) var textFont: NSFont = TK.Font.body

    override init() {
        super.init()
        truncationMode = .none
        isWrapped = false
        alignmentMode = .left
        allowsFontSubpixelQuantization = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, font: NSFont, color: NSColor) {
        if self.text != text || textFont != font {
            self.text = text
            textFont = font
            self.font = font
            fontSize = font.pointSize
            string = text
        }
        foregroundColor = color.cgColor
    }

    var textWidth: CGFloat { TextLayer.width(text, font: textFont) }

    /// Positions the layer so the text sits in a CSS line box starting at `lineTop` (y down).
    func place(x: CGFloat, lineTop: CGFloat, lineHeight: CGFloat, width: CGFloat) {
        let top = TextLayer.glyphTop(lineTop: lineTop, lineHeight: lineHeight, font: textFont)
        frame = CGRect(x: x, y: top, width: max(0, width), height: ceil(textFont.ascender - textFont.descender) + 2)
    }

    /// Where CATextLayer's first line must start for the baseline to match CSS's line box.
    static func glyphTop(lineTop: CGFloat, lineHeight: CGFloat, font: NSFont) -> CGFloat {
        let asc = font.ascender, desc = -font.descender
        let baseline = lineTop + (lineHeight - (asc + desc)) / 2 + asc
        // Measured against the prototype in Chrome: CoreText draws half a point lower than this for the same box.
        return baseline - asc - 0.5
    }

    nonisolated(unsafe) private static var widths: [String: CGFloat] = [:]

    static func width(_ s: String, font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(s)"
        if let w = widths[key] { return w }
        let w = ((s as NSString).size(withAttributes: [.font: font]).width * 64).rounded(.up) / 64
        if widths.count > 4000 { widths.removeAll() }
        widths[key] = w
        return w
    }
}

/// A horizontal fade at a layer's right end (the prototype's `mask-image` gradients).
final class FadeMask: CAGradientLayer {
    override init() {
        super.init()
        startPoint = CGPoint(x: 0, y: 0.5)
        endPoint = CGPoint(x: 1, y: 0.5)
        colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// Opaque until `width − fade − end`, transparent from `width − end`.
    func update(width: CGFloat, height: CGFloat, fade: CGFloat, end: CGFloat = 0) {
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard width > 0 else { return }
        let a = max(0, (width - fade - end) / width), b = max(a, (width - end) / width)
        locations = [0, NSNumber(value: Double(a)), NSNumber(value: Double(b))]
    }
}

// MARK: - The list tile (Rex's 5:4 program tile, css:123–127)

final class TileLayer: CALayer {
    enum Size { case regular, small }
    private let letter = TextLayer()
    private let sun = GlyphLayer(.sun, size: 12)
    private let ring = CALayer()
    private(set) var tileSize: Size = .regular

    override init() {
        super.init()
        addSublayer(ring)
        addSublayer(letter)
        addSublayer(sun)
        letter.alignmentMode = .center
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    static func dimensions(_ s: Size) -> CGSize { s == .regular ? CGSize(width: 20, height: 16) : CGSize(width: 16, height: 13) }

    /// `monogram` nil draws Today's sun.
    func set(monogram: String?, color: NSColor, palette: TK.Palette, size: Size = .regular) {
        tileSize = size
        let d = Self.dimensions(size)
        bounds = CGRect(origin: .zero, size: d)
        cornerRadius = size == .regular ? 4 : 3.5
        backgroundColor = palette.tileFill.cgColor
        ring.frame = bounds
        ring.cornerRadius = cornerRadius
        ring.borderWidth = 0.5
        ring.borderColor = palette.tileRing.cgColor
        if let monogram {
            sun.isHidden = true
            letter.isHidden = false
            let font = size == .regular ? TK.Font.tile : TK.Font.tileSmall
            letter.set(monogram, font: font, color: color)
            // `display: grid; place-items: center` with `font: 700 10px/1`: a line box as tall as the font size.
            letter.place(x: 0, lineTop: (d.height - font.pointSize) / 2, lineHeight: font.pointSize, width: d.width)
        } else {
            letter.isHidden = true
            sun.isHidden = false
            sun.color = color
            sun.position = CGPoint(x: d.width / 2, y: d.height / 2)
        }
    }
}

// MARK: - Checkbox (css:190–202)

/// A 16pt ring; checked, an accent fill with a drawn check. `animate` runs the fill, the stroke drawing in and the
/// pop (§8); a recycled row rebinding to another task doesn't.
final class CheckLayer: CALayer {
    private let ring = CAShapeLayer()
    private let fill = CALayer()
    private let mark = GlyphLayer(.check, size: TK.M.checkGlyph)
    private(set) var isOn = false
    private(set) var isPlaceholder = false
    private var palette = TK.Palette.dark
    var hovered = false { didSet { if hovered != oldValue { updateRing(animated: true) } } }

    override init() {
        super.init()
        let s = TK.M.check
        bounds = CGRect(x: 0, y: 0, width: s, height: s)
        fill.frame = bounds
        fill.cornerRadius = s / 2
        ring.frame = bounds
        // A 1.5pt inset ring: stroke a circle inset by half the width.
        let inset = TK.M.checkRing / 2
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        ring.lineWidth = TK.M.checkRing
        ring.fillColor = nil
        mark.position = CGPoint(x: s / 2, y: s / 2)
        mark.strokeEnd = 0
        addSublayer(fill)
        addSublayer(ring)
        addSublayer(mark)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func set(on: Bool, placeholder: Bool = false, palette: TK.Palette, animated: Bool) {
        self.palette = palette
        let changed = on != isOn
        isOn = on
        isPlaceholder = placeholder
        mark.color = palette.onAccent
        opacity = placeholder ? 0.7 : 1
        if animated && changed && !TK.CA.reduce {
            fill.animate("backgroundColor", to: on ? palette.accent.cgColor : NSColor.clear.cgColor, TK.CA.checkFillT)
            if on {
                mark.animate("strokeEnd", to: 1, TK.CA.checkFillT, delay: 0.04)
            } else {
                mark.animate("strokeEnd", to: 0, TK.CA.checkFillT)
            }
            updateRing(animated: true)
            // The box pops from 0.8 on `snappy`, both ways (§8).
            let pop = TK.CA.spring("transform.scale", TK.CA.snappy, from: 0.8, to: 1)
            add(pop, forKey: "pop")
        } else {
            setInstant {
                fill.backgroundColor = on ? palette.accent.cgColor : nil
                mark.strokeEnd = on ? 1 : 0
                updateRing(animated: false)
            }
        }
    }

    private func updateRing(animated: Bool) {
        let color: NSColor
        if isOn { color = palette.accent } else if isPlaceholder { color = palette.inkQ } else { color = hovered ? palette.ink2 : palette.lineField }
        if animated {
            ring.animate("strokeColor", to: color.cgColor, hovered ? TK.CA.hoverInT : TK.CA.hoverOutT)
        } else {
            ring.strokeColor = color.cgColor
        }
    }

    /// Pressed: 0.86 over 80 ms ease-out; released: back on `snappy`.
    func setPressed(_ pressed: Bool) {
        let to: CGFloat = pressed ? 0.86 : 1
        let from = presentation()?.value(forKeyPath: "transform.scale") ?? 1
        setInstant { setValue(to, forKeyPath: "transform.scale") }
        guard !TK.CA.reduce else { return }
        let a: CAAnimation = pressed
            ? TK.CA.basic("transform.scale", TK.CA.pressT, from: from, to: to)
            : TK.CA.spring("transform.scale", TK.CA.snappy, from: from, to: to)
        removeAnimation(forKey: "pop")
        add(a, forKey: "press")
    }
}

// MARK: - Chips (css:205–215)

final class ChipLayer: CALayer {
    enum Tone: Equatable { case neutral, due, late }
    struct Content: Equatable {
        var text: String
        var glyph: Glyph?
        var tone: Tone = .neutral
        var large = false
        var ghost = false
    }

    private let icon = GlyphLayer(.calendar, size: TK.M.chipIcon)
    private let label = TextLayer()
    private(set) var content = Content(text: "")
    private var palette = TK.Palette.dark
    var hovered = false { didSet { if hovered != oldValue { restyle(animated: true) } } }
    var pressed = false { didSet { if pressed != oldValue { restyle(animated: !pressed) } } }
    var pickerOpen = false { didSet { if pickerOpen != oldValue { restyle(animated: true) } } }
    /// The lifted drag copy draws chips on #3A3A3A (dark) or `fill-track` (light), css:246–249.
    var lifted = false

    override init() {
        super.init()
        addSublayer(icon)
        addSublayer(label)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    static func width(_ c: Content) -> CGFloat {
        let font = c.large ? TK.Font.chipLarge : TK.Font.chip
        let pad = c.large ? TK.M.chipLargePad : TK.M.chipPad
        let gap = c.large ? TK.M.chipLargeGap : TK.M.chipGap
        let iconW: CGFloat = c.glyph == nil ? 0 : TK.M.chipIcon + gap
        return pad * 2 + iconW + TextLayer.width(c.text, font: font)
    }

    func set(_ c: Content, palette: TK.Palette) {
        content = c
        self.palette = palette
        let h = c.large ? TK.M.chipLarge : TK.M.chip
        let pad = c.large ? TK.M.chipLargePad : TK.M.chipPad
        let gap = c.large ? TK.M.chipLargeGap : TK.M.chipGap
        let font = c.large ? TK.Font.chipLarge : TK.Font.chip
        bounds = CGRect(x: 0, y: 0, width: Self.width(c), height: h)
        cornerRadius = h / 2
        var x = pad
        if let g = c.glyph {
            icon.isHidden = false
            icon.set(g, size: TK.M.chipIcon)
            icon.position = CGPoint(x: x + TK.M.chipIcon / 2, y: h / 2)
            x += TK.M.chipIcon + gap
        } else {
            icon.isHidden = true
        }
        // `font: 500 11px/14px` (large: 12px with the same 14px line), centered in the capsule.
        label.set(c.text, font: font, color: palette.ink2)
        label.place(x: x, lineTop: (h - 14) / 2, lineHeight: 14, width: TextLayer.width(c.text, font: font) + 2)
        restyle(animated: false)
    }

    private func restyle(animated: Bool) {
        var bg: NSColor
        var fg: NSColor
        switch content.tone {
        case .neutral: bg = palette.fillControl; fg = palette.ink2
        case .due: bg = palette.attnTint; fg = palette.attn
        case .late: bg = palette.dangerTint; fg = palette.danger
        }
        if lifted && content.tone == .neutral { bg = palette.liftChip }
        var ring: NSColor? = nil
        if content.ghost {
            bg = hovered ? palette.hover : .clear
            fg = hovered ? palette.ink2 : palette.ink3
            ring = palette.lineSep
        }
        if pickerOpen {
            bg = palette.accentTint
            fg = palette.accentText
        } else if !content.ghost {
            let b = pressed ? TK.Palette.pressBrightness : hovered ? palette.chipHoverBrightness : 1
            bg = bg.brightness(b)
            fg = fg.brightness(b)
        }
        let apply = {
            self.backgroundColor = bg.cgColor
            self.borderWidth = ring == nil ? 0 : 1
            self.borderColor = ring?.cgColor
            self.icon.strokeColor = fg.cgColor
            self.label.foregroundColor = fg.cgColor
        }
        if animated && !TK.CA.reduce {
            animate("backgroundColor", to: bg.cgColor, TK.CA.iconT)
            icon.animate("strokeColor", to: fg.cgColor, TK.CA.iconT)
            label.animate("foregroundColor", to: fg.cgColor, TK.CA.iconT)
            setInstant {
                borderWidth = ring == nil ? 0 : 1
                borderColor = ring?.cgColor
            }
        } else {
            setInstant(apply)
        }
    }
}

// MARK: - Icon buttons (›, a group label's + and chevron, the date ×; css:135–137, 174–179)

/// A rounded-square button: rest, hover (`hover` fill and a brighter glyph, on `icon`), press (`press` fill at once).
/// `reveal` fades the whole button in and out on `hoverIn` / `hoverOut`.
final class IconButtonLayer: CALayer {
    let glyph: GlyphLayer
    private var palette = TK.Palette.dark
    var restColor: KeyPath<TK.Palette, NSColor> = \.ink3
    var hoverColor: KeyPath<TK.Palette, NSColor> = \.ink2
    var pressColor: KeyPath<TK.Palette, NSColor>? = nil
    var hovered = false { didSet { if hovered != oldValue { restyle(animated: true) } } }
    var pressed = false { didSet { if pressed != oldValue { restyle(animated: !pressed) } } }
    /// Shown (opacity 1) or hidden (0), on `hoverIn` / `hoverOut`.
    private(set) var revealed = true

    init(_ g: Glyph, size: CGFloat, glyphSize: CGFloat = 12, radius: CGFloat = 6) {
        glyph = GlyphLayer(g, size: glyphSize)
        super.init()
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        cornerRadius = radius
        glyph.position = CGPoint(x: size / 2, y: size / 2)
        addSublayer(glyph)
    }

    override init(layer: Any) {
        glyph = GlyphLayer(.plus, size: 12)
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPalette(_ p: TK.Palette) {
        palette = p
        restyle(animated: false)
    }

    func reveal(_ on: Bool, animated: Bool = true) {
        guard on != revealed else { return }
        revealed = on
        if animated {
            animate("opacity", to: on ? 1 : 0, on ? TK.CA.hoverInT : TK.CA.hoverOutT)
        } else {
            setInstant { opacity = on ? 1 : 0 }
        }
    }

    private func restyle(animated: Bool) {
        let bg: NSColor = pressed ? palette.press : hovered ? palette.hover : .clear
        let fg = pressed ? palette[keyPath: pressColor ?? hoverColor] : hovered ? palette[keyPath: hoverColor] : palette[keyPath: restColor]
        if animated && !TK.CA.reduce {
            animate("backgroundColor", to: bg.cgColor, TK.CA.iconT)
            glyph.animate("strokeColor", to: fg.cgColor, TK.CA.iconT)
        } else {
            setInstant {
                backgroundColor = bg.cgColor
                glyph.strokeColor = fg.cgColor
            }
        }
    }
}

// MARK: - SwiftUI glyphs (the same paths, for the SwiftUI panes)

struct GlyphShape: Shape {
    let glyph: Glyph

    func path(in rect: CGRect) -> Path {
        Path(glyph.path(size: min(rect.width, rect.height)))
    }
}

struct GlyphView: View {
    let glyph: Glyph
    var size: CGFloat = 14
    var color: Color

    var body: some View {
        GlyphShape(glyph: glyph)
            .stroke(color, style: StrokeStyle(lineWidth: glyph.lineWidth(size: size), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - Flipped, layer-backed base view

class FlippedLayerView: NSView {
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        func walk(_ l: CALayer) {
            l.contentsScale = scale
            l.sublayers?.forEach(walk)
        }
        if let layer { walk(layer) }
    }
}

extension CALayer {
    /// Sets `contentsScale` on this layer and its sublayers (text layers render blurry without it).
    func setScaleDeep(_ scale: CGFloat) {
        contentsScale = scale
        sublayers?.forEach { $0.setScaleDeep(scale) }
    }
}
