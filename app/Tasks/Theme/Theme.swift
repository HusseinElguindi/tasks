import AppKit

/// One set of semantic colour tokens (design/THEMES.md §1, §2.1–2.4, §6; v2 feedback 17). A theme gives a few colours
/// per appearance and every other token comes from them by a fixed rule, so a later theme only has to supply its base
/// colours. There's one theme, Rex, which pins its measured values, so it draws exactly as before. The picker, theme
/// files and sample themes are tabled.
extension TK {
    /// An sRGB colour with alpha: what themes and their rules work in, and what palettes compare.
    struct RGBA: Hashable, Sendable {
        var r, g, b, a: Double

        init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        init(_ hex: UInt32) {
            self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
        }

        static let white = RGBA(r: 1, g: 1, b: 1)
        static let black = RGBA(r: 0, g: 0, b: 0)

        /// `a → b t`: t of the way from this colour to `o`, straight in sRGB.
        func mix(_ o: RGBA, _ t: Double) -> RGBA {
            RGBA(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
        }

        /// `x at t`.
        func alpha(_ t: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: t) }

        /// WCAG 2's contrast ratio, on the opaque colours.
        func contrast(_ o: RGBA) -> Double {
            func lum(_ c: RGBA) -> Double {
                func f(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
                return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
            }
            let x = lum(self), y = lum(o)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }

        /// Pure white and black stay AppKit's own (a gray colour space), as these tokens always were: sRGB white at
        /// 10% composites a level apart from it on the dark tiles.
        var ns: NSColor {
            if r == g, g == b, r == 1 || r == 0 { return (r == 1 ? NSColor.white : .black).withAlphaComponent(a) }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
    }

    /// Every colour token (THEMES.md §1.1), grouped as there.
    enum Token: Int, CaseIterable, Sendable {
        // Inputs (§2.1): what a theme gives. The list slots, danger and attention have Rex's ANSI colours by default.
        case base, ink, accent, ground
        case listBlue, listMagenta, listGreen, listCyan, listYellow, listRed, listInk
        case danger, attention
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
        // Tiles, drag and the brand mark
        case tileFill, tileRing, liftChip, markHead, markBar, markRings, markTrail
        // Shadows: a 0.5pt ring of ink, then a blur whose darkness is fixed per appearance
        case shadowPopoverRing, shadowPopover, shadowLiftRing, shadowLift
    }

    /// A theme (THEMES.md §2.1): per appearance, three colours and a few optional ones. `pins` fixes any derived token,
    /// for a calibrated theme like Rex.
    struct Theme: Sendable {
        struct Side: Sendable {
            var base, ink, accent: RGBA
            var ground: RGBA?
            /// The six list hues: blue, magenta, green, cyan, yellow, red. A list's slot comes from its id.
            var lists: [RGBA]
            var danger, attention: RGBA?
            var pins: [Token: RGBA] = [:]
        }

        let id: String
        let dark, light: Side
    }
}

// MARK: - Derivation (THEMES.md §2.4)

extension TK.Theme {
    /// How a token is made from the ones before it. The amounts are Rex's own: each solves its measured value from
    /// Rex's base, ink and accent, so Rex's three colours alone land within a few levels of the pins.
    enum Rule: Sendable {
        /// `a → b t`
        case mix(TK.Token, TK.Token, Double)
        /// `a → a fixed colour t` (dark's ground: base toward black)
        case toward(TK.Token, TK.RGBA, Double)
        /// `a at t`
        case alpha(TK.Token, Double)
        /// `= a`
        case same(TK.Token)
        /// Fixed per appearance (the dark shadows' blur)
        case fixed(TK.RGBA)
        /// White when it holds 3:1 on the accent (macOS's own white-on-accent), else the darkest ink there is
        case onAccent
    }

    /// The rules, by appearance, in the order they're derived: each reads only tokens set before it. Inputs have none.
    static func rules(dark: Bool) -> [(TK.Token, Rule)] {
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
            (.accentText, .mix(.accent, .ink, 0.22)), (.accentTint, .mix(.base, .accent, 0.13)), (.onAccent, .onAccent),
            (.focus, .same(.accent)), (.textSelection, .alpha(.accent, 0.45)),
            (.dangerTint, .mix(.base, .danger, 0.141)), (.attentionTint, .mix(.base, .attention, 0.137)),
            (.tileFill, .same(.fillStrong)), (.tileRing, .alpha(.ink, 0.1)), (.liftChip, .mix(.base, .ink, 0.147)),
            (.markHead, .same(.accent)), (.markBar, .same(.ink)), (.markRings, .same(.inkSecondary)), (.markTrail, .same(.inkQuiet)),
            (.shadowPopoverRing, .alpha(.ink, 0.14)), (.shadowPopover, .fixed(TK.RGBA.black.alpha(0.5))),
            (.shadowLiftRing, .alpha(.ink, 0.14)), (.shadowLift, .fixed(TK.RGBA.black.alpha(0.5))),
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
            (.accentText, .same(.accent)), (.accentTint, .mix(.base, .accent, 0.1)), (.onAccent, .onAccent),
            (.focus, .same(.accent)), (.textSelection, .alpha(.accent, 0.25)),
            (.dangerTint, .mix(.base, .danger, 0.09)), (.attentionTint, .mix(.base, .attention, 0.05)),
            (.tileFill, .mix(.base, .ink, 0.125)), (.tileRing, .alpha(.ink, 0.1)), (.liftChip, .same(.fillTrack)),
            (.markHead, .same(.accent)), (.markBar, .same(.ink)), (.markRings, .same(.inkSecondary)), (.markTrail, .mix(.ink, .base, 0.616)),
            (.shadowPopoverRing, .alpha(.ink, 0.16)), (.shadowPopover, .alpha(.ink, 0.16)),
            (.shadowLiftRing, .alpha(.ink, 0.14)), (.shadowLift, .alpha(.ink, 0.18)),
        ]
    }

    /// Every token's value for one appearance, indexed by `Token.rawValue`. Pins win over rules; a rule reads the
    /// pinned value of a token before it, as `themes.js` does.
    func tokens(dark: Bool) -> [TK.RGBA] {
        let s = dark ? self.dark : light
        var v = [TK.RGBA?](repeating: nil, count: TK.Token.allCases.count)
        func set(_ t: TK.Token, _ c: TK.RGBA) { v[t.rawValue] = c }
        func get(_ t: TK.Token) -> TK.RGBA { v[t.rawValue]! }
        set(.base, s.base)
        set(.ink, s.ink)
        set(.accent, s.accent)
        if let g = s.ground { set(.ground, g) }
        let slots: [TK.Token] = [.listBlue, .listMagenta, .listGreen, .listCyan, .listYellow, .listRed]
        for (t, c) in zip(slots, s.lists) { set(t, c) }
        set(.listInk, s.ink)
        set(.danger, s.danger ?? s.lists[5])
        set(.attention, s.attention ?? s.lists[4])
        for (t, rule) in Self.rules(dark: dark) where v[t.rawValue] == nil {
            if let pin = s.pins[t] { set(t, pin); continue }
            switch rule {
            case .mix(let a, let b, let x): set(t, get(a).mix(get(b), x))
            case .toward(let a, let c, let x): set(t, get(a).mix(c, x))
            case .alpha(let a, let x): set(t, get(a).alpha(x))
            case .same(let a): set(t, get(a))
            case .fixed(let c): set(t, c)
            case .onAccent: set(t, TK.RGBA.white.contrast(get(.accent)) >= 3 ? .white : get(dark ? .base : .ink))
            }
        }
        return v.map { $0! }
    }
}

// MARK: - Rex, the one theme

extension TK.Theme {
    /// Rex (design/REX-REFERENCE.md): graphite and white with a blue accent. It pins every value measured from Rex
    /// (`tasks-v2.css:46–78`, `themes.js` `REX_PINS`) and the brand mark's light trail, so nothing changes; the
    /// ones its rules give exactly, like light `hover`, aren't pinned.
    static let rex = TK.Theme(
        id: "rex",
        dark: Side(
            base: .init(0x1C1C1C), ink: .init(0xE6EDF3), accent: .init(0x2F81F7), ground: .init(0x181818),
            lists: [0x58A6FF, 0xBC8CFF, 0x3FB950, 0x39C5CF, 0xD29922, 0xFF7B72].map(TK.RGBA.init),
            pins: [
                .dim: .init(0x181818), .popover: .init(0x262626), .lift: .init(0x2C2C2C),
                .linePane: .init(0x323334), .linePaneDim: .init(0x282929), .lineSeparator: .init(0x363738),
                .lineField: .init(0x696B6E), .edgeOuter: .init(0x5E5E5E), .edgeInner: .init(0x535353),
                .inkSecondary: .init(0xA8ADB1), .inkTertiary: .init(0x7F8386), .inkQuiet: .init(0x6D7072),
                .fillRowSelected: .init(0x333333), .fillRowSelectedDim: .init(0x292929),
                .fillControl: .init(0x2D2E2E), .fillTrack: .init(0x303132), .fillStrong: .init(0x444444),
                // Rex's hover, press and hairlines are white, not its ink, at these amounts.
                .hover: TK.RGBA.white.alpha(0.07), .press: TK.RGBA.white.alpha(0.12),
                .accentText: .init(0x5799F6), .accentTint: .init(0x1E2938),
                .dangerTint: .init(0x3C2928), .attentionTint: .init(0x352E1D),
                .tileFill: .init(0x444444), .tileRing: TK.RGBA.white.alpha(0.1), .liftChip: .init(0x3A3A3A),
                .shadowPopoverRing: TK.RGBA.white.alpha(0.14), .shadowLiftRing: TK.RGBA.white.alpha(0.14),
            ]),
        light: Side(
            base: .init(0xFFFFFF), ink: .init(0x1F2328), accent: .init(0x0969DA), ground: .init(0xF5F5F5),
            lists: [0x0969DA, 0x8250DF, 0x116329, 0x1B7C83, 0x9A6700, 0xCF222E].map(TK.RGBA.init),
            pins: [
                .dim: .init(0xFAFAFA),
                .linePane: .init(0xD4D5D6), .linePaneDim: .init(0xEBEBEC), .lineSeparator: .init(0xE7E8E8),
                .lineField: .init(0x848689), .edgeOuter: .init(0xCFCFD0), .edgeInner: .init(0xD6D6D7),
                .inkSecondary: .init(0x626568), .inkTertiary: .init(0x6C6F72), .inkQuiet: .init(0x888A8D),
                .fillRowSelected: .init(0xE6E6E8), .fillRowSelectedDim: .init(0xEFEFF0),
                .fillControl: .init(0xEDEDEE), .fillTrack: .init(0xE9E9EA), .fillStrong: .init(0xE0E0E1),
                .accentTint: .init(0xE6F0FB), .dangerTint: .init(0xFBEBEC), .attentionTint: .init(0xFAF7F2),
                .tileFill: .init(0xE3E3E4), .markTrail: .init(0xA9ACAF),
            ]))
}

#if DEBUG
extension TK.Theme {
    /// Rex from its base, ink, accent and ground alone, every rule applied: for checking the rules against the pins
    /// (`-debugThemeCheck`) and that a palette change within one appearance redraws everything (`-debugTheme derived`).
    static var rexDerived: TK.Theme {
        var d = rex.dark, l = rex.light
        d.pins = [:]
        l.pins = [:]
        return TK.Theme(id: "rex-derived", dark: d, light: l)
    }
}
#endif
