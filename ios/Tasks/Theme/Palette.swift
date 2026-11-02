// Tasks · themes. A port of design/THEMES.md (themes.js): each theme is base, ink and accent per appearance, with
// optional ground, list colours, danger, attention and a high-contrast flag. Every other token is a straight sRGB mix,
// derived once per (theme, appearance), then checked against the contrast floors. Default pins Rex's measured values.

import SwiftUI

// MARK: - Colour math

struct RGB: Hashable, Sendable {
    var r: Double, g: Double, b: Double, a: Double = 1   // 0…255 channels, alpha 0…1

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF); g = Double((hex >> 8) & 0xFF); b = Double(hex & 0xFF)
    }
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    static let black = RGB(0x000000)
    static let white = RGB(0xFFFFFF)

    /// t of the way from self to other, rounded to whole levels as the prototype's hex() does.
    func mix(_ other: RGB, _ t: Double) -> RGB {
        func ch(_ x: Double, _ y: Double) -> Double { (min(255, max(0, x + (y - x) * t))).rounded() }
        return RGB(r: ch(r, other.r), g: ch(g, other.g), b: ch(b, other.b))
    }
    func alpha(_ a: Double) -> RGB { RGB(r: r, g: g, b: b, a: a) }

    var luminance: Double {
        func f(_ v: Double) -> Double { let v = v / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }
    func contrast(_ o: RGB) -> Double {
        let x = luminance, y = o.luminance
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
}

// MARK: - Themes

enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum InterfaceStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, glass
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ListHue: String, CaseIterable, Sendable, Hashable {
    case ink, blue, magenta, green, cyan, yellow, red
    static let slots: [ListHue] = [.blue, .magenta, .green, .cyan, .yellow, .red]
}

struct ThemeSide: Sendable {
    var base: RGB, ink: RGB, accent: RGB
    var ground: RGB? = nil
    var danger: RGB? = nil
    var attention: RGB? = nil
    var lists: [ListHue: RGB] = [:]
    var highContrast = false
    var pins: [String: RGB] = [:]
}

struct TasksTheme: Identifiable, Sendable {
    let id: String
    let name: String
    let mood: String
    let dark: ThemeSide
    let light: ThemeSide

    static let rexLists: [Bool: [ListHue: RGB]] = [
        true: [.blue: RGB(0x58A6FF), .magenta: RGB(0xBC8CFF), .green: RGB(0x3FB950), .cyan: RGB(0x39C5CF), .yellow: RGB(0xD29922), .red: RGB(0xFF7B72)],
        false: [.blue: RGB(0x0969DA), .magenta: RGB(0x8250DF), .green: RGB(0x116329), .cyan: RGB(0x1B7C83), .yellow: RGB(0x9A6700), .red: RGB(0xCF222E)],
    ]

    static let rexPinsDark: [String: RGB] = [
        "ground": RGB(0x181818), "base": RGB(0x1C1C1C), "dim": RGB(0x181818), "popover": RGB(0x262626), "lift": RGB(0x2C2C2C),
        "line-pane": RGB(0x323334), "line-pane-dim": RGB(0x282929), "line-sep": RGB(0x363738), "line-field": RGB(0x696B6E),
        "ink-2": RGB(0xA8ADB1), "ink-3": RGB(0x7F8386), "ink-q": RGB(0x6D7072), "sel": RGB(0x333333), "sel-dim": RGB(0x292929),
        "fill-control": RGB(0x2D2E2E), "fill-track": RGB(0x303132), "fill-thumb": RGB(0x4A4C4D), "fill-strong": RGB(0x444444),
        "edge-outer": RGB(0x5E5E5E), "edge-inner": RGB(0x535353),
        "hover": RGB.white.alpha(0.07), "press": RGB.white.alpha(0.12),
        "accent-text": RGB(0x5799F6), "accent-tint": RGB(0x1E2938), "danger-tint": RGB(0x3C2928), "attn-tint": RGB(0x352E1D),
        "tile-fill": RGB(0x444444), "tile-ring": RGB.white.alpha(0.10), "lift-chip": RGB(0x3A3A3A),
        "mark-trail": RGB(0x6D7072), "mark-rings": RGB(0xA8ADB1),
    ]
    static let rexPinsLight: [String: RGB] = [
        "ground": RGB(0xF5F5F5), "base": RGB(0xFFFFFF), "dim": RGB(0xFAFAFA), "popover": RGB(0xFFFFFF), "lift": RGB(0xFFFFFF),
        "line-pane": RGB(0xD4D5D6), "line-pane-dim": RGB(0xEBEBEC), "line-sep": RGB(0xE7E8E8), "line-field": RGB(0x848689),
        "ink-2": RGB(0x626568), "ink-3": RGB(0x6C6F72), "ink-q": RGB(0x888A8D), "sel": RGB(0xE6E6E8), "sel-dim": RGB(0xEFEFF0),
        "fill-control": RGB(0xEDEDEE), "fill-track": RGB(0xE9E9EA), "fill-thumb": RGB(0xFFFFFF), "fill-strong": RGB(0xE0E0E1),
        "edge-outer": RGB(0xCFCFD0), "edge-inner": RGB(0xD6D6D7), "accent-tint": RGB(0xE6F0FB), "danger-tint": RGB(0xFBEBEC), "attn-tint": RGB(0xFAF7F2),
        "tile-fill": RGB(0xE3E3E4), "lift-chip": RGB(0xE9E9EA), "mark-trail": RGB(0xA9ACAF), "mark-rings": RGB(0x626568),
    ]

    static let all: [TasksTheme] = [
        TasksTheme(id: "default", name: "Default", mood: "Graphite and white, a blue accent",
                   dark: ThemeSide(base: RGB(0x1C1C1C), ink: RGB(0xE6EDF3), accent: RGB(0x2F81F7), ground: RGB(0x181818), pins: rexPinsDark),
                   light: ThemeSide(base: RGB(0xFFFFFF), ink: RGB(0x1F2328), accent: RGB(0x0969DA), ground: RGB(0xF5F5F5), pins: rexPinsLight)),
        TasksTheme(id: "paper", name: "Paper", mood: "Warm paper and brown ink, a rust accent",
                   dark: ThemeSide(base: RGB(0x1F1C18), ink: RGB(0xEAE3D8), accent: RGB(0xE0905F), ground: RGB(0x1A1714),
                                   lists: [.blue: RGB(0x8FB3D9), .magenta: RGB(0xD49AC4), .green: RGB(0xA8C07A), .cyan: RGB(0x7FC1B8), .yellow: RGB(0xDDB25C), .red: RGB(0xEE8A74)]),
                   light: ThemeSide(base: RGB(0xFBF8F2), ink: RGB(0x2A2621), accent: RGB(0xA44E2A), ground: RGB(0xF1ECE2),
                                    lists: [.blue: RGB(0x2F5F8A), .magenta: RGB(0x8A4B7A), .green: RGB(0x4F6B2A), .cyan: RGB(0x2E6E6A), .yellow: RGB(0x8A6512), .red: RGB(0xB0362A)])),
        TasksTheme(id: "contrast", name: "Contrast", mood: "Black and white, brighter quiet ink, stronger lines",
                   dark: ThemeSide(base: RGB(0x0A0A0A), ink: RGB(0xFFFFFF), accent: RGB(0x4AA8FF), ground: RGB(0x000000), highContrast: true),
                   light: ThemeSide(base: RGB(0xFFFFFF), ink: RGB(0x000000), accent: RGB(0x0047B3), ground: RGB(0xEDEDED), highContrast: true)),
        TasksTheme(id: "dusk", name: "Dusk", mood: "Muted slate, soft ink, a periwinkle accent",
                   dark: ThemeSide(base: RGB(0x23232A), ink: RGB(0xD9DAE2), accent: RGB(0x9AA7E0), ground: RGB(0x1D1D23),
                                   lists: [.blue: RGB(0x8FA8D8), .magenta: RGB(0xB9A0D6), .green: RGB(0x9DC0A0), .cyan: RGB(0x8CC3C8), .yellow: RGB(0xD2BA84), .red: RGB(0xDE9A94)]),
                   light: ThemeSide(base: RGB(0xF6F6F4), ink: RGB(0x34353C), accent: RGB(0x55639D), ground: RGB(0xECECE8),
                                    lists: [.blue: RGB(0x4A6596), .magenta: RGB(0x76598F), .green: RGB(0x4C7352), .cyan: RGB(0x3D7478), .yellow: RGB(0x7F6629), .red: RGB(0x9E4D47)])),
        TasksTheme(id: "harbor", name: "Harbor", mood: "Cool blue-grey surfaces, a clear sky accent",
                   dark: ThemeSide(base: RGB(0x15202B), ink: RGB(0xDCE7F2), accent: RGB(0x4CB2EC), ground: RGB(0x101922)),
                   light: ThemeSide(base: RGB(0xF7FAFD), ink: RGB(0x18232F), accent: RGB(0x0E6FB5), ground: RGB(0xE9EFF6))),
        TasksTheme(id: "iris", name: "Iris", mood: "The default surfaces with one vivid violet accent",
                   dark: ThemeSide(base: RGB(0x1C1C1C), ink: RGB(0xE6EDF3), accent: RGB(0x9B6BFF), ground: RGB(0x181818)),
                   light: ThemeSide(base: RGB(0xFFFFFF), ink: RGB(0x1F2328), accent: RGB(0x7A3FF2), ground: RGB(0xF5F5F5))),
        TasksTheme(id: "moss", name: "Moss", mood: "Green-grey surfaces, a leaf accent",
                   dark: ThemeSide(base: RGB(0x1B1F1C), ink: RGB(0xDEE6DD), accent: RGB(0x62C08A), ground: RGB(0x161A17)),
                   light: ThemeSide(base: RGB(0xFAFBF8), ink: RGB(0x212822), accent: RGB(0x2B7A4B), ground: RGB(0xEDF1EA))),
    ]

    static func byID(_ id: String) -> TasksTheme { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Derivation

private enum Rule {
    case mix(String, String, Double, Kind)   // from token → to token (or a literal), t
    case literalMix(String, RGB, Double, Kind)
    case alpha(String, Double)
    case same(String)
    enum Kind { case plain, ink, line }
}

private let darkRules: [(String, Rule)] = [
    ("ground", .literalMix("base", .black, 0.14, .plain)), ("dim", .same("ground")),
    ("popover", .mix("base", "ink", 0.05, .plain)), ("lift", .mix("base", "ink", 0.078, .plain)),
    ("line-pane", .mix("base", "ink", 0.107, .line)), ("line-pane-dim", .mix("base", "ink", 0.058, .line)),
    ("line-sep", .mix("base", "ink", 0.127, .line)), ("line-field", .mix("base", "ink", 0.375, .line)),
    ("ink-2", .mix("ink", "base", 0.307, .ink)), ("ink-3", .mix("ink", "base", 0.51, .ink)), ("ink-q", .mix("ink", "base", 0.6, .ink)),
    ("sel", .mix("base", "ink", 0.114, .plain)), ("sel-dim", .mix("base", "ink", 0.064, .plain)),
    ("fill-control", .mix("base", "ink", 0.084, .plain)), ("fill-track", .mix("base", "ink", 0.099, .plain)),
    ("fill-thumb", .mix("base", "ink", 0.225, .plain)), ("fill-strong", .mix("base", "ink", 0.198, .plain)),
    ("edge-outer", .mix("base", "ink", 0.327, .line)), ("edge-inner", .mix("base", "ink", 0.272, .line)),
    ("hover", .alpha("ink", 0.07)), ("press", .alpha("ink", 0.12)),
    ("accent-text", .mix("accent", "ink", 0.22, .plain)), ("accent-tint", .mix("base", "accent", 0.13, .plain)), ("text-sel", .alpha("accent", 0.45)),
    ("danger-tint", .mix("base", "danger", 0.141, .plain)), ("attn-tint", .mix("base", "attention", 0.137, .plain)),
    ("tile-fill", .same("fill-strong")), ("tile-ring", .alpha("ink", 0.1)), ("lift-chip", .mix("base", "ink", 0.147, .plain)),
    ("mark-trail", .same("ink-q")), ("mark-rings", .same("ink-2")),
]

private let lightRules: [(String, Rule)] = [
    ("ground", .mix("base", "ink", 0.045, .plain)), ("dim", .mix("base", "ground", 0.5, .plain)),
    ("popover", .same("base")), ("lift", .same("base")),
    ("line-pane", .mix("base", "ink", 0.192, .line)), ("line-pane-dim", .mix("base", "ink", 0.089, .line)),
    ("line-sep", .mix("base", "ink", 0.107, .line)), ("line-field", .mix("base", "ink", 0.549, .line)),
    ("ink-2", .mix("ink", "base", 0.3, .ink)), ("ink-3", .mix("ink", "base", 0.344, .ink)), ("ink-q", .mix("ink", "base", 0.47, .ink)),
    ("sel", .mix("base", "ink", 0.112, .plain)), ("sel-dim", .mix("base", "ink", 0.071, .plain)),
    ("fill-control", .mix("base", "ink", 0.08, .plain)), ("fill-track", .mix("base", "ink", 0.098, .plain)),
    ("fill-thumb", .same("base")), ("fill-strong", .mix("base", "ink", 0.138, .plain)),
    ("edge-outer", .mix("base", "ink", 0.214, .line)), ("edge-inner", .mix("base", "ink", 0.183, .line)),
    ("hover", .alpha("ink", 0.06)), ("press", .alpha("ink", 0.11)),
    ("accent-text", .same("accent")), ("accent-tint", .mix("base", "accent", 0.1, .plain)), ("text-sel", .alpha("accent", 0.25)),
    ("danger-tint", .mix("base", "danger", 0.09, .plain)), ("attn-tint", .mix("base", "attention", 0.05, .plain)),
    ("tile-fill", .mix("base", "ink", 0.125, .plain)), ("tile-ring", .alpha("ink", 0.1)), ("lift-chip", .same("fill-track")),
    ("mark-trail", .mix("ink", "base", 0.616, .plain)), ("mark-rings", .same("ink-2")),
]

private struct Floor { let t: String; let on: [String]; let min: Double; let reject: Bool }
private let floors: [Floor] = [
    Floor(t: "ink", on: ["base", "ground", "sel", "popover"], min: 7, reject: true),
    Floor(t: "accent", on: ["base"], min: 3, reject: true),
    Floor(t: "ink-2", on: ["base", "ground", "sel", "fill-control"], min: 4.5, reject: false),
    Floor(t: "ink-3", on: ["base", "ground"], min: 4.5, reject: false),
    Floor(t: "ink-q", on: ["base", "ground"], min: 3, reject: false),
    Floor(t: "line-field", on: ["base"], min: 3, reject: false),
    Floor(t: "accent-text", on: ["base", "accent-tint"], min: 4.5, reject: false),
    Floor(t: "danger", on: ["danger-tint", "base"], min: 4.5, reject: false),
    Floor(t: "attention", on: ["attn-tint", "base"], min: 4.5, reject: false),
    Floor(t: "on-accent", on: ["accent"], min: 3, reject: false),
    Floor(t: "list", on: ["tile-fill"], min: 3, reject: false),
]

/// Every colour the app draws, derived from one theme and appearance.
struct Palette: Sendable {
    let themeID: String
    let isDark: Bool
    let raw: [String: RGB]
    let passesFloors: Bool

    // Surfaces
    let ground, base, dim, popover, lift: Color
    // Lines
    let linePane, linePaneDim, lineSep, lineField: Color
    // Ink
    let ink, ink2, ink3, inkQ: Color
    // Fills
    let sel, selDim, fillControl, fillTrack, fillThumb, fillStrong, edgeOuter, edgeInner, hover, press: Color
    // Accent and state
    let accent, accentText, accentTint, onAccent, textSel: Color
    let danger, dangerTint, attn, attnTint: Color
    // Tiles and the mark
    let tileFill, tileRing, liftChip, markTrail, markRings, markBar, markHead: Color
    private let lists: [ListHue: Color]

    func list(_ hue: ListHue) -> Color { lists[hue] ?? ink }

    init(theme: TasksTheme, dark: Bool) {
        let side = dark ? theme.dark : theme.light
        let rules = dark ? darkRules : lightRules
        let high = side.highContrast
        var listRGB = TasksTheme.rexLists[dark]!
        for (k, v) in side.lists { listRGB[k] = v }

        var v: [String: RGB] = ["base": side.base, "ink": side.ink, "accent": side.accent]
        v["danger"] = side.danger ?? listRGB[.red]!
        v["attention"] = side.attention ?? listRGB[.yellow]!
        var pinned = Set<String>()
        var input = Set(["base", "ink", "accent"])
        if let g = side.ground { v["ground"] = g; input.insert("ground") }

        for (k, rule) in rules {
            if k == "ground" && side.ground != nil { continue }
            var val: RGB
            switch rule {
            case let .mix(a, b, t0, kind):
                var t = t0
                if high && kind == .ink { t *= 0.5 }
                if high && kind == .line { t = min(0.9, t * 1.6) }
                val = v[a]!.mix(v[b]!, t)
            case let .literalMix(a, lit, t0, kind):
                var t = t0
                if high && kind == .ink { t *= 0.5 }
                if high && kind == .line { t = min(0.9, t * 1.6) }
                val = v[a]!.mix(lit, t)
            case let .alpha(a, t): val = v[a]!.alpha(t)
            case let .same(a): val = v[a]!
            }
            if let p = side.pins[k] { val = p; pinned.insert(k) }
            v[k] = val
        }
        // On the accent: white when it reads (3:1, macOS's own convention), else the darkest ink there is.
        v["on-accent"] = RGB.white.contrast(v["accent"]!) >= 3 ? .white : (dark ? v["base"]! : v["ink"]!)
        v["mark-bar"] = v["ink"]; v["mark-head"] = v["accent"]

        var ok = true
        for f in floors {
            let targets: [String]
            if f.t == "list" {
                for s in ListHue.slots where v["list-" + s.rawValue] == nil { v["list-" + s.rawValue] = listRGB[s] }
                targets = ListHue.slots.map { "list-" + $0.rawValue }
            } else { targets = [f.t] }
            for k in targets {
                for on in f.on {
                    guard let c = v[k], let bg = v[on] else { continue }
                    let isPinned = pinned.contains(k)
                    let floorMin = isPinned ? f.min - 0.05 : f.min
                    if c.contrast(bg) >= floorMin { continue }
                    if f.reject || isPinned || input.contains(k) && f.reject { ok = false; continue }
                    var n = c, steps = 0
                    while n.contrast(bg) < f.min && steps < 50 { n = n.mix(dark ? .white : .black, 0.02); steps += 1 }
                    v[k] = n
                }
            }
        }
        v["list-ink"] = v["ink"]

        themeID = theme.id; isDark = dark; raw = v; passesFloors = ok
        func c(_ k: String) -> Color { (v[k] ?? .white).color }
        ground = c("ground"); base = c("base"); dim = c("dim"); popover = c("popover"); lift = c("lift")
        linePane = c("line-pane"); linePaneDim = c("line-pane-dim"); lineSep = c("line-sep"); lineField = c("line-field")
        ink = c("ink"); ink2 = c("ink-2"); ink3 = c("ink-3"); inkQ = c("ink-q")
        sel = c("sel"); selDim = c("sel-dim"); fillControl = c("fill-control"); fillTrack = c("fill-track")
        fillThumb = c("fill-thumb"); fillStrong = c("fill-strong"); edgeOuter = c("edge-outer"); edgeInner = c("edge-inner")
        hover = c("hover"); press = c("press")
        accent = c("accent"); accentText = c("accent-text"); accentTint = c("accent-tint"); onAccent = c("on-accent"); textSel = c("text-sel")
        danger = c("danger"); dangerTint = c("danger-tint"); attn = c("attention"); attnTint = c("attn-tint")
        tileFill = c("tile-fill"); tileRing = c("tile-ring"); liftChip = c("lift-chip")
        markTrail = c("mark-trail"); markRings = c("mark-rings"); markBar = c("mark-bar"); markHead = c("mark-head")
        var l: [ListHue: Color] = [.ink: c("ink")]
        for s in ListHue.slots { l[s] = c("list-" + s.rawValue) }
        lists = l
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Palette] = [:]
    static func make(_ themeID: String, dark: Bool) -> Palette {
        let key = themeID + (dark ? ":d" : ":l")
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let p = cache[key] { return p }
        let p = Palette(theme: TasksTheme.byID(themeID), dark: dark)
        cache[key] = p
        return p
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make("default", dark: true)
}
private struct InterfaceStyleKey: EnvironmentKey {
    static let defaultValue: InterfaceStyle = .classic
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var interfaceStyle: InterfaceStyle {
        get { self[InterfaceStyleKey.self] }
        set { self[InterfaceStyleKey.self] = newValue }
    }
}
