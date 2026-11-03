import Foundation

// One set of semantic colour tokens (design/THEMES.md §1, §2.1–2.5, §6; v2 feedback 17; design/COLOR.md). A theme
// gives a few colours and every other token comes from them by a fixed rule, so a later theme only has to supply its
// base colours. There's one theme: Rex's surfaces, which it pins to their measured values, with COLOR.md's Ember accent
// and lit tiles (A + B + D). The picker, theme files and sample themes are tabled.
//
// Shared by the Mac and iOS apps: values only, in sRGB. Each app builds its own colour type from them (the Mac's
// `RGBA.ns` in app/Tasks/Theme/Theme.swift, iOS's `RGBA.color` in ios/Tasks/Theme/Theme.swift).

/// An sRGB colour with alpha: what themes and their rules work in, and what palettes compare.
public struct RGBA: Hashable, Sendable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(_ hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let black = RGBA(r: 0, g: 0, b: 0)

    /// `a → b t`: t of the way from this colour to `o`, straight in sRGB.
    public func mix(_ o: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    /// `x at t`.
    public func alpha(_ t: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: t) }

    /// THEMES.md §2.5's fix: 2% steps toward white (dark) or black (light) until `passes`, at most 50 (`themes.js`
    /// `nudge`).
    public func raised(dark: Bool, until passes: (RGBA) -> Bool) -> RGBA {
        var c = self, n = 0
        while !passes(c), n < 50 {
            c = c.mix(dark ? .white : .black, 0.02)
            n += 1
        }
        return c
    }

    /// WCAG 2's contrast ratio, on the opaque colours.
    public func contrast(_ o: RGBA) -> Double {
        func lum(_ c: RGBA) -> Double {
            func f(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
        }
        let x = lum(self), y = lum(o)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// Every colour token (THEMES.md §1.1), grouped as there.
public enum Token: Int, CaseIterable, Sendable {
    // Inputs (§2.1): what a theme gives. The list slots, danger and attention have Rex's ANSI colours by default.
    case base, ink, accent, ground
    case listBlue, listMagenta, listGreen, listCyan, listYellow, listRed, listInk
    case danger, attention
    // B's tile hues (COLOR.md §2), the same in both appearances: the seven list slots' (the views share theirs:
    // Upcoming magenta, Undated cyan, Completed green, Trash ink) and Today's, which is the theme's accent.
    case tileBlue, tileMagenta, tileGreen, tileCyan, tileYellow, tileRed, tileInk, tileToday
    // Surfaces
    case dim, popover, lift, card
    // Lines and edges
    case linePane, linePaneDim, lineSeparator, lineField, edgeOuter, edgeInner
    // Ink
    case inkSecondary, inkTertiary, inkQuiet
    // Fills
    case fillRowSelected, fillRowSelectedDim, fillControl, fillTrack, fillStrong, hover, press
    // Accent, focus and state
    case accentText, accentTint, onAccent, focus, textSelection, dangerTint, attentionTint
    /// The When ring, planned for today (COLOR.md §1): its own token, so it stays cool under a warm accent.
    case plan
    /// D's spark (COLOR.md §4): the completing ring and rays, the box's first frame, the all-done sun.
    case spark
    // Tiles, drag and the brand mark. `tileHalo` is the lit tile's one per-appearance value (COLOR.md §2).
    case tileHalo, liftChip, markHead, markBar, markRings, markTrail
    // Shadows: a 0.5pt ring of ink, then a blur whose darkness is fixed per appearance
    case shadowPopoverRing, shadowPopover, shadowLiftRing, shadowLift
}

/// A theme (THEMES.md §2.1): one accent, the tile hues, and per appearance two colours and a few optional ones.
/// `pins` fixes any derived token, for a calibrated theme like Rex.
public struct Theme: Sendable {
    public struct Side: Sendable {
        public var base, ink: RGBA
        /// This appearance's own accent; nil derives it from the theme's (`Theme.accent(dark:)`).
        public var accent: RGBA?
        public var ground: RGBA?
        /// The six list hues: blue, magenta, green, cyan, yellow, red. A list's slot comes from its id.
        public var lists: [RGBA]
        public var danger, attention: RGBA?
        public var pins: [Token: RGBA] = [:]

        public init(base: RGBA, ink: RGBA, accent: RGBA? = nil, ground: RGBA? = nil, lists: [RGBA], danger: RGBA? = nil,
                    attention: RGBA? = nil, pins: [Token: RGBA] = [:]) {
            self.base = base
            self.ink = ink
            self.accent = accent
            self.ground = ground
            self.lists = lists
            self.danger = danger
            self.attention = attention
            self.pins = pins
        }
    }

    public let id: String
    /// The accent (COLOR.md §1, §6): the one value to change for another accent. Every token that shows it is
    /// derived from it: each appearance's `accent` (`accent(dark:)`), `accent-text`, `accent-tint`, `on-accent`,
    /// `focus`, `text-selection`, `spark`, `mark-head` and Today's tile, so the checked box, the highlighted day
    /// and menu item, links and rings follow.
    public var accent: RGBA
    /// B's tile hues by list slot, the same in both appearances (COLOR.md §2): blue, magenta, green, cyan, yellow,
    /// red, ink. Each holds white 4.5:1 at the lightest lit point under a letter; the finish over them is fixed
    /// (`TileArt`), so any hue takes it.
    public var tiles: [RGBA]
    public var dark, light: Side

    public init(id: String, accent: RGBA, tiles: [RGBA], dark: Side, light: Side) {
        self.id = id
        self.accent = accent
        self.tiles = tiles
        self.dark = dark
        self.light = light
    }
}

// MARK: - Derivation (THEMES.md §2.4)

extension Theme {
    /// How a token is made from the ones before it. The amounts are Rex's own: each solves its measured value from
    /// Rex's base, ink and accent, so Rex's three colours alone land within a few levels of the pins.
    enum Rule: Sendable {
        /// `a → b t`
        case mix(Token, Token, Double)
        /// `a → a fixed colour t` (dark's ground: base toward black)
        case toward(Token, RGBA, Double)
        /// `a at t`
        case alpha(Token, Double)
        /// `= a`
        case same(Token)
        /// Fixed per appearance (the dark shadows' blur)
        case fixed(RGBA)
        /// White when it holds 3:1 on the accent (macOS's own white-on-accent), else the darkest ink there is
        case onAccent
    }

    /// Light's tint of the accent (`accent-tint`'s rule), which light's accent has to read on (`accent(dark:)`).
    static let lightAccentTint = 0.1

    /// The rules, by appearance, in the order they're derived: each reads only tokens set before it. Inputs have none.
    static func rules(dark: Bool) -> [(Token, Rule)] {
        dark ? [
            (.ground, .toward(.base, .black, 0.14)), (.dim, .same(.ground)),
            (.popover, .mix(.base, .ink, 0.05)), (.lift, .mix(.base, .ink, 0.078)), (.card, .mix(.base, .ink, 0.015)),
            (.linePane, .mix(.base, .ink, 0.107)), (.linePaneDim, .mix(.base, .ink, 0.058)),
            (.lineSeparator, .mix(.base, .ink, 0.127)), (.lineField, .mix(.base, .ink, 0.375)),
            (.edgeOuter, .mix(.base, .ink, 0.327)), (.edgeInner, .mix(.base, .ink, 0.272)),
            (.inkSecondary, .mix(.ink, .base, 0.307)), (.inkTertiary, .mix(.ink, .base, 0.51)), (.inkQuiet, .mix(.ink, .base, 0.6)),
            (.fillRowSelected, .mix(.base, .ink, 0.114)), (.fillRowSelectedDim, .mix(.base, .ink, 0.064)),
            (.fillControl, .mix(.base, .ink, 0.084)), (.fillTrack, .mix(.base, .ink, 0.099)), (.fillStrong, .mix(.base, .ink, 0.198)),
            (.hover, .alpha(.ink, 0.07)), (.press, .alpha(.ink, 0.12)),
            (.accentTint, .mix(.base, .accent, 0.13)), (.accentText, .mix(.accent, .ink, 0.22)), (.onAccent, .onAccent),
            (.focus, .same(.accent)), (.textSelection, .alpha(.accent, 0.42)), (.plan, .same(.accentText)), (.spark, .same(.accentText)),
            (.dangerTint, .mix(.base, .danger, 0.141)), (.attentionTint, .mix(.base, .attention, 0.137)),
            (.tileHalo, .fixed(RGBA.black.alpha(0.35))),
            (.liftChip, .mix(.base, .ink, 0.147)),
            (.markHead, .same(.accent)), (.markBar, .same(.ink)), (.markRings, .same(.inkSecondary)), (.markTrail, .same(.inkQuiet)),
            (.shadowPopoverRing, .alpha(.ink, 0.14)), (.shadowPopover, .fixed(RGBA.black.alpha(0.5))),
            (.shadowLiftRing, .alpha(.ink, 0.14)), (.shadowLift, .fixed(RGBA.black.alpha(0.5))),
        ] : [
            (.ground, .mix(.base, .ink, 0.045)), (.dim, .mix(.base, .ground, 0.5)),
            (.popover, .same(.base)), (.lift, .same(.base)), (.card, .same(.base)),
            (.linePane, .mix(.base, .ink, 0.192)), (.linePaneDim, .mix(.base, .ink, 0.089)),
            (.lineSeparator, .mix(.base, .ink, 0.107)), (.lineField, .mix(.base, .ink, 0.549)),
            (.edgeOuter, .mix(.base, .ink, 0.214)), (.edgeInner, .mix(.base, .ink, 0.183)),
            (.inkSecondary, .mix(.ink, .base, 0.3)), (.inkTertiary, .mix(.ink, .base, 0.344)), (.inkQuiet, .mix(.ink, .base, 0.47)),
            (.fillRowSelected, .mix(.base, .ink, 0.112)), (.fillRowSelectedDim, .mix(.base, .ink, 0.071)),
            (.fillControl, .mix(.base, .ink, 0.08)), (.fillTrack, .mix(.base, .ink, 0.098)), (.fillStrong, .mix(.base, .ink, 0.138)),
            (.hover, .alpha(.ink, 0.06)), (.press, .alpha(.ink, 0.11)),
            (.accentTint, .mix(.base, .accent, lightAccentTint)), (.accentText, .same(.accent)), (.onAccent, .onAccent),
            (.focus, .same(.accent)), (.textSelection, .alpha(.accent, 0.22)), (.plan, .same(.accentText)), (.spark, .same(.accentText)),
            (.dangerTint, .mix(.base, .danger, 0.09)), (.attentionTint, .mix(.base, .attention, 0.05)),
            (.tileHalo, .fixed(RGBA.black.alpha(0.18))),
            (.liftChip, .same(.fillTrack)),
            (.markHead, .same(.accent)), (.markBar, .same(.ink)), (.markRings, .same(.inkSecondary)), (.markTrail, .mix(.ink, .base, 0.616)),
            (.shadowPopoverRing, .alpha(.ink, 0.16)), (.shadowPopover, .alpha(.ink, 0.16)),
            (.shadowLiftRing, .alpha(.ink, 0.14)), (.shadowLift, .alpha(.ink, 0.18)),
        ]
    }

    /// The floors the derivation holds (§2.5; so far the one a theme's accent can break): a derived token under its
    /// floor on any of `on` is raised until it passes. A pinned token isn't raised. Each `on` is derived before it.
    static let floors: [(token: Token, on: [Token], min: Double)] = [(.accentText, [.base, .accentTint], 4.5)]

    /// A side's accent: its own, else the theme's. Light's `accent-text` is its accent (§1.1), so light raises the
    /// theme's by §2.5's steps until it holds `accent-text`'s floor, 4.5:1, on base and on its own tint, as Rex's
    /// light blue does: #E6683D becomes #B1502F. Dark's is the theme's as it is.
    public func accent(dark: Bool) -> RGBA {
        let s = dark ? self.dark : light
        if let a = s.accent { return a }
        if dark { return accent }
        return accent.raised(dark: false) { $0.contrast(s.base) >= 4.5 && $0.contrast(s.base.mix($0, Self.lightAccentTint)) >= 4.5 }
    }

    /// Every token's value for one appearance, indexed by `Token.rawValue`. Pins win over rules; a rule reads the
    /// pinned value of a token before it, as `themes.js` does.
    public func tokens(dark: Bool) -> [RGBA] {
        let s = dark ? self.dark : light
        var v = [RGBA?](repeating: nil, count: Token.allCases.count)
        func set(_ t: Token, _ c: RGBA) { v[t.rawValue] = c }
        func get(_ t: Token) -> RGBA { v[t.rawValue]! }
        set(.base, s.base)
        set(.ink, s.ink)
        set(.accent, accent(dark: dark))
        if let g = s.ground { set(.ground, g) }
        let slots: [Token] = [.listBlue, .listMagenta, .listGreen, .listCyan, .listYellow, .listRed]
        for (t, c) in zip(slots, s.lists) { set(t, c) }
        set(.listInk, s.ink)
        set(.danger, s.danger ?? s.lists[5])
        set(.attention, s.attention ?? s.lists[4])
        let tileSlots: [Token] = [.tileBlue, .tileMagenta, .tileGreen, .tileCyan, .tileYellow, .tileRed, .tileInk]
        for (t, c) in zip(tileSlots, tiles) { set(t, c) }
        // Today's tile is the accent as given, in both appearances: tiles don't change with the appearance.
        set(.tileToday, accent)
        for (t, rule) in Self.rules(dark: dark) where v[t.rawValue] == nil {
            if let pin = s.pins[t] { set(t, pin); continue }
            var c: RGBA
            switch rule {
            case .mix(let a, let b, let x): c = get(a).mix(get(b), x)
            case .toward(let a, let to, let x): c = get(a).mix(to, x)
            case .alpha(let a, let x): c = get(a).alpha(x)
            case .same(let a): c = get(a)
            case .fixed(let f): c = f
            case .onAccent: c = RGBA.white.contrast(get(.accent)) >= 3 ? .white : get(dark ? .base : .ink)
            }
            if let f = Self.floors.first(where: { $0.token == t }) {
                c = c.raised(dark: dark) { x in f.on.allSatisfy { x.contrast(get($0)) >= f.min } }
            }
            set(t, c)
        }
        return v.map { $0! }
    }
}

// MARK: - Rex, the one theme

extension Theme {
    /// Rex (design/REX-REFERENCE.md): graphite and white, with COLOR.md's Ember accent (A) and lit tiles (B). It pins
    /// every grey measured from Rex (`tasks-v2.css:46–78`, `themes.js` `REX_PINS`) and the brand mark's light trail,
    /// so the surfaces don't change; the ones its rules give exactly, like light `hover`, aren't pinned. Nothing that
    /// shows the accent is pinned, so changing `accent` changes all of it (THEMES.md §6 says how). `plan` is pinned to
    /// Rex's blue: under a warm accent the When ring stays cool.
    public static let rex = Theme(
        id: "rex",
        // The source tile's fill (docs/feedback/reference-tile.svg).
        accent: .init(0xE6683D),
        tiles: [0x285FCA, 0x6B4FB8, 0x227040, 0x146E77, 0x825C15, 0xAD3B5C, 0x5A6068].map(RGBA.init),
        dark: Side(
            base: .init(0x1C1C1C), ink: .init(0xE6EDF3), ground: .init(0x181818),
            lists: [0x58A6FF, 0xBC8CFF, 0x3FB950, 0x39C5CF, 0xD29922, 0xFF7B72].map(RGBA.init),
            pins: [
                .dim: .init(0x181818), .popover: .init(0x262626), .lift: .init(0x2C2C2C),
                .linePane: .init(0x323334), .linePaneDim: .init(0x282929), .lineSeparator: .init(0x363738),
                .lineField: .init(0x696B6E), .edgeOuter: .init(0x5E5E5E), .edgeInner: .init(0x535353),
                .inkSecondary: .init(0xA8ADB1), .inkTertiary: .init(0x7F8386), .inkQuiet: .init(0x6D7072),
                .fillRowSelected: .init(0x333333), .fillRowSelectedDim: .init(0x292929),
                .fillControl: .init(0x2D2E2E), .fillTrack: .init(0x303132), .fillStrong: .init(0x444444),
                // Rex's hover, press and hairlines are white, not its ink, at these amounts.
                .hover: RGBA.white.alpha(0.07), .press: RGBA.white.alpha(0.12),
                .plan: .init(0x5799F6),
                .dangerTint: .init(0x3C2928), .attentionTint: .init(0x352E1D),
                .liftChip: .init(0x3A3A3A),
                .shadowPopoverRing: RGBA.white.alpha(0.14), .shadowLiftRing: RGBA.white.alpha(0.14),
            ]),
        light: Side(
            base: .init(0xFFFFFF), ink: .init(0x1F2328), ground: .init(0xF5F5F5),
            lists: [0x0969DA, 0x8250DF, 0x116329, 0x1B7C83, 0x9A6700, 0xCF222E].map(RGBA.init),
            pins: [
                .dim: .init(0xFAFAFA),
                .linePane: .init(0xD4D5D6), .linePaneDim: .init(0xEBEBEC), .lineSeparator: .init(0xE7E8E8),
                .lineField: .init(0x848689), .edgeOuter: .init(0xCFCFD0), .edgeInner: .init(0xD6D6D7),
                .inkSecondary: .init(0x626568), .inkTertiary: .init(0x6C6F72), .inkQuiet: .init(0x888A8D),
                .fillRowSelected: .init(0xE6E6E8), .fillRowSelectedDim: .init(0xEFEFF0),
                .fillControl: .init(0xEDEDEE), .fillTrack: .init(0xE9E9EA), .fillStrong: .init(0xE0E0E1),
                .plan: .init(0x0969DA), .dangerTint: .init(0xFBEBEC), .attentionTint: .init(0xFAF7F2),
                .markTrail: .init(0xA9ACAF),
            ]))
}
