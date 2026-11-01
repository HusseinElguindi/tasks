import AppKit

/// B's lit tile (design/COLOR.md §2 "The finish"; color.css `.f-tiles :is(.tile, .vg)`): the reference tile's recipe
/// (docs/feedback/reference-tile.svg), scaled from 58.5×45.5 to our tiles. A tile is its hue plus fixed layers, so any
/// hue (any list colour, any theme's) takes the same finish; only the halo's darkness depends on the appearance
/// (`tile-halo`). Bottom to top: the halo, the fill, the light, the specular strip and the inner ring. Each hairline
/// is one device pixel: 0.5pt at 2×, or 1pt at half the alpha at 1×, so it keeps the same amount of light or dark.
/// Drawn once per hue, size and scale into a cached image, which every tile shows: the sidebar's, the headers', the
/// detail pane's, the menus', the dragged list's, and (round, no specular) the brand mark's head.
enum TileArt {
    // MARK: The light

    /// Radial from the top middle, its radii these fractions of the tile's width and height.
    static let lightRadii = CGSize(width: 1.4, height: 1.1)
    /// White 0.216 × (1 − s(d / 0.58)) out to 0.58 of the way, then black 0.072 × s((d − 0.58) / 0.42) to the rim.
    static let lightWhite = 0.216, lightBlack = 0.072, lightTurn = 0.58
    /// Where the prototype puts its stops (color.css), the source's own.
    static let lightLocations: [Double] = [0, 0.0725, 0.145, 0.2175, 0.29, 0.3625, 0.435, 0.5075, 0.58,
                                           0.65, 0.72, 0.79, 0.86, 0.93, 1]

    /// Smootherstep, 6u⁵ − 15u⁴ + 10u³: the source's easing.
    static func smootherstep(_ u: Double) -> Double {
        let u = min(max(u, 0), 1)
        return u * u * u * (u * (u * 6 - 15) + 10)
    }

    /// The light `d` of the way to the rim: white at that alpha when positive, black when negative.
    static func light(_ d: Double) -> Double {
        d <= lightTurn
            ? lightWhite * (1 - smootherstep(d / lightTurn))
            : -lightBlack * smootherstep((d - lightTurn) / (1 - lightTurn))
    }

    /// What a white glyph sits on at `p` (top-left origin, points) in a tile of `size`: the hue under the light. The
    /// tiles' floor is checked here, at the lightest point under the glyph (COLOR.md §6).
    static func lit(_ hue: TK.RGBA, at p: CGPoint, in size: CGSize) -> TK.RGBA {
        let dx = (p.x - size.width / 2) / (lightRadii.width * size.width), dy = p.y / (lightRadii.height * size.height)
        let a = light(min(1, (dx * dx + dy * dy).squareRoot()))
        return a >= 0 ? hue.mix(.white, a) : hue.mix(.black, -a)
    }

    // MARK: The hairlines

    /// The specular strip along the top edge, white, in sixteenths from the left to the middle; mirrored after it.
    static let specularHalf: [Double] = [0, 0.003, 0.058, 0.111, 0.157, 0.196, 0.226, 0.244, 0.25]
    /// The inner ring, white, just inside the edge.
    static let ringWhite = 0.07

    /// One device pixel, at least 0.5pt, and the factor on a 0.5pt hairline's alpha that keeps its amount.
    static func hairline(scale: CGFloat) -> (width: CGFloat, alpha: CGFloat) {
        let w = max(0.5, 1 / max(scale, 1))
        return (w, 0.5 / w)
    }

    // MARK: Drawing

    /// Draws the tile into `ctx`, its top-left at the origin and y down, with the halo outside `size`.
    static func draw(_ ctx: CGContext, size: CGSize, radius: CGFloat, hue: TK.RGBA, halo: TK.RGBA, scale: CGFloat,
                     specular: Bool = true) {
        let (hair, k) = hairline(scale: scale)
        let rect = CGRect(origin: .zero, size: size)
        func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
            let c = max(0, min(radius, r.width / 2, r.height / 2))
            return CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil)
        }
        let shape = rounded(rect, radius)
        func cg(_ c: TK.RGBA, alpha: Double? = nil) -> CGColor {
            CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha ?? c.a)
        }

        // The halo: a ring one hairline wide, just outside the edge.
        ctx.saveGState()
        ctx.addPath(rounded(rect.insetBy(dx: -hair, dy: -hair), radius + hair))
        ctx.addPath(shape)
        ctx.setFillColor(cg(halo, alpha: halo.a * k))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        // The fill.
        ctx.setFillColor(cg(hue))
        ctx.fill(rect)
        // The light: a circle's gradient, scaled into the ellipse.
        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: 0)
        ctx.scaleBy(x: lightRadii.width * size.width, y: lightRadii.height * size.height)
        ctx.drawRadialGradient(lightGradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                               options: .drawsAfterEndLocation)
        ctx.restoreGState()
        // The specular strip, one hairline tall along the top.
        if specular {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: hair))
            ctx.drawLinearGradient(specularGradient(k), start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            ctx.restoreGState()
        }
        // The inner ring, one hairline wide, just inside the edge.
        ctx.addPath(shape)
        ctx.addPath(rounded(rect.insetBy(dx: hair, dy: hair), radius - hair))
        ctx.setFillColor(cg(.white, alpha: ringWhite * k))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    nonisolated(unsafe) private static let lightGradient: CGGradient = {
        var colors: [CGColor] = [], locations: [CGFloat] = []
        for d in lightLocations {
            let a = light(d)
            if d == lightTurn {
                // The turn: white fades out, then black fades in, as the source's stops do.
                colors += [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)]
                locations += [d, d]
            } else {
                let v: CGFloat = a >= 0 ? 1 : 0
                colors.append(CGColor(srgbRed: v, green: v, blue: v, alpha: abs(a)))
                locations.append(d)
            }
        }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }()

    private static func specularGradient(_ k: CGFloat) -> CGGradient {
        let alphas = specularHalf + specularHalf.dropLast().reversed()
        let colors = alphas.map { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: $0 * k) }
        let locations = alphas.indices.map { CGFloat($0) / CGFloat(alphas.count - 1) }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }

    // MARK: The cached image

    /// How far the image reaches past the tile on each side, for the halo (1pt covers it at any scale).
    static let outset: CGFloat = 1

    private struct Key: Hashable {
        let hue, halo: TK.RGBA
        let size: CGSize
        let radius, scale: CGFloat
        let specular: Bool

        func hash(into h: inout Hasher) {
            h.combine(hue); h.combine(halo); h.combine(size.width); h.combine(size.height)
            h.combine(radius); h.combine(scale); h.combine(specular)
        }
    }

    @MainActor private static var cache: [Key: CGImage] = [:]

    /// The tile at `scale`, `outset` larger than `size` on every side: place it at the tile's frame inset by
    /// −`outset`.
    @MainActor
    static func image(hue: NSColor, halo: NSColor, size: CGSize, radius: CGFloat, scale: CGFloat,
                      specular: Bool = true) -> CGImage? {
        let key = Key(hue: TK.RGBA(ns: hue), halo: TK.RGBA(ns: halo), size: size, radius: radius, scale: max(1, scale),
                      specular: specular)
        if let img = cache[key] { return img }
        let full = CGSize(width: size.width + 2 * outset, height: size.height + 2 * outset)
        let w = Int((full.width * key.scale).rounded(.up)), h = Int((full.height * key.scale).rounded(.up))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y down, in points, with the tile's top-left at (outset, outset).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: key.scale, y: -key.scale)
        ctx.translateBy(x: outset, y: outset)
        draw(ctx, size: size, radius: radius, hue: key.hue, halo: key.halo, scale: key.scale, specular: specular)
        guard let img = ctx.makeImage() else { return nil }
        if cache.count > 256 { cache.removeAll() }
        cache[key] = img
        return img
    }
}

extension TK.RGBA {
    /// An `NSColor`'s sRGB components (black if it has none).
    init(ns c: NSColor) {
        let s = c.usingColorSpace(.sRGB)
        self.init(r: Double(s?.redComponent ?? 0), g: Double(s?.greenComponent ?? 0), b: Double(s?.blueComponent ?? 0),
                  a: Double(s?.alphaComponent ?? 1))
    }
}
