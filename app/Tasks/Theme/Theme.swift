import AppKit
import TasksTheme

/// The theme (design/THEMES.md, design/COLOR.md) lives in the TasksTheme package, shared with iOS: its tokens, Rex
/// and the lit tile's finish, as sRGB values (app/TasksCore/Sources/TasksTheme). This is the Mac's side of it: the
/// `TK.` names the app has always used, and the values as AppKit colours.
extension TK {
    typealias RGBA = TasksTheme.RGBA
    typealias Token = TasksTheme.Token
    typealias Theme = TasksTheme.Theme
}

extension TasksTheme.RGBA {
    /// Pure white and black stay AppKit's own (a gray colour space), as these tokens always were: sRGB white at
    /// 10% composites a level apart from it on the dark tiles.
    var ns: NSColor {
        if r == g, g == b, r == 1 || r == 0 { return (r == 1 ? NSColor.white : .black).withAlphaComponent(a) }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// An `NSColor`'s sRGB components (black if it has none).
    init(ns c: NSColor) {
        let s = c.usingColorSpace(.sRGB)
        self.init(r: Double(s?.redComponent ?? 0), g: Double(s?.greenComponent ?? 0), b: Double(s?.blueComponent ?? 0),
                  a: Double(s?.alphaComponent ?? 1))
    }
}

extension TileArt {
    /// The tile at `scale` from the palette's colours, `outset` larger than `size` on every side: place it at the
    /// tile's frame inset by −`outset`.
    static func image(hue: NSColor, halo: NSColor, size: CGSize, radius: CGFloat, scale: CGFloat,
                      specular: Bool = true) -> CGImage? {
        image(hue: RGBA(ns: hue), halo: RGBA(ns: halo), size: size, radius: radius, scale: scale, specular: specular)
    }
}

#if DEBUG
extension TasksTheme.Theme {
    /// Rex from its base, ink, accent and ground alone, every rule applied: for checking the rules against the pins
    /// (`-debugThemeCheck`) and that a palette change within one appearance redraws everything (`-debugTheme derived`).
    static var rexDerived: Theme {
        var d = rex.dark, l = rex.light
        d.pins = [:]
        l.pins = [:]
        return Theme(id: "rex-derived", accent: rex.accent, tiles: rex.tiles, dark: d, light: l)
    }
}
#endif
