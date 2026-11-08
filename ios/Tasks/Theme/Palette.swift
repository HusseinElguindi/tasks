// The colours the app draws: the Mac's one theme, Rex with the Ember accent (TasksTheme, shared with the Mac), for one
// appearance. The tokens have the Mac's `TK.Palette` names (app/Tasks/Theme/TK.swift), as SwiftUI colours.

import SwiftUI
import TasksTheme

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

/// Every colour token for one appearance, by the Mac's names (THEMES.md §1.1). Built once per appearance and kept.
struct Palette: Sendable {
    let isDark: Bool
    // Surfaces
    let ground, base, dim, popover, lift, card: Color
    // Ink
    let ink, inkSecondary, inkTertiary, inkQuiet: Color
    // Lines and edges
    let linePane, linePaneDim, lineSeparator, lineField, edgeOuter, edgeInner: Color
    // Fills
    let fillRowSelected, fillRowSelectedDim, fillControl, fillTrack, fillStrong, hover, press: Color
    // Accent, focus and state
    let accent, accentText, accentTint, onAccent, focus, textSelection: Color
    /// The When ring, planned for today (COLOR.md §1): Rex's blue under the warm accent.
    let plan: Color
    /// D's spark (COLOR.md §4): = accent-text.
    let spark: Color
    let danger, dangerTint, attention, attentionTint: Color
    // Tiles and drag
    /// The lit tile's halo, just outside its edge (COLOR.md §2). A value, as the tiles' hues are: TileArt draws them.
    let tileHalo: RGBA
    let liftChip: Color
    // Shadows
    let shadowPopoverRing, shadowPopover, shadowLiftRing, shadowLift: Color
    /// B's solid tile hues, the same in both appearances: the seven slots, then Today's (the accent).
    private let tiles: [RGBA]
    /// The seven list slots' colours (Rex's ANSI colours, then ink).
    private let lists: [Color]
    /// Every token's value, by `Token.rawValue`: for what's drawn from values rather than colours (TileArt).
    private let values: [RGBA]

    /// The Mac's slots, in its hand-out order. A list's slot comes from its id (`ListModel.colorSlot`).
    enum ListSlot: Int, CaseIterable, Sendable { case blue, magenta, green, cyan, yellow, red, ink }

    init(theme: Theme, dark: Bool) {
        let v = theme.tokens(dark: dark)
        func c(_ t: Token) -> Color { v[t.rawValue].color }
        isDark = dark
        values = v
        ground = c(.ground); base = c(.base); dim = c(.dim); popover = c(.popover); lift = c(.lift); card = c(.card)
        ink = c(.ink); inkSecondary = c(.inkSecondary); inkTertiary = c(.inkTertiary); inkQuiet = c(.inkQuiet)
        linePane = c(.linePane); linePaneDim = c(.linePaneDim); lineSeparator = c(.lineSeparator); lineField = c(.lineField)
        edgeOuter = c(.edgeOuter); edgeInner = c(.edgeInner)
        fillRowSelected = c(.fillRowSelected); fillRowSelectedDim = c(.fillRowSelectedDim)
        fillControl = c(.fillControl); fillTrack = c(.fillTrack); fillStrong = c(.fillStrong)
        hover = c(.hover); press = c(.press)
        accent = c(.accent); accentText = c(.accentText); accentTint = c(.accentTint); onAccent = c(.onAccent)
        focus = c(.focus); textSelection = c(.textSelection); plan = c(.plan); spark = c(.spark)
        danger = c(.danger); dangerTint = c(.dangerTint); attention = c(.attention); attentionTint = c(.attentionTint)
        tileHalo = v[Token.tileHalo.rawValue]; liftChip = c(.liftChip)
        shadowPopoverRing = c(.shadowPopoverRing); shadowPopover = c(.shadowPopover)
        shadowLiftRing = c(.shadowLiftRing); shadowLift = c(.shadowLift)
        tiles = [Token.tileBlue, .tileMagenta, .tileGreen, .tileCyan, .tileYellow, .tileRed, .tileInk, .tileToday].map { v[$0.rawValue] }
        lists = [c(.listBlue), c(.listMagenta), c(.listGreen), c(.listCyan), c(.listYellow), c(.listRed), c(.listInk)]
    }

    static let dark = Palette(theme: .rex, dark: true)
    static let light = Palette(theme: .rex, dark: false)
    static func make(dark: Bool) -> Palette { dark ? .dark : .light }

    func list(_ slot: ListSlot) -> Color { lists[slot.rawValue] }
    func listColor(slot: Int) -> Color { lists[((slot % 7) + 7) % 7] }
    /// A list's solid tile (B): its slot's hue.
    func tile(slot: Int) -> RGBA { tiles[((slot % 7) + 7) % 7] }
    func tile(_ slot: ListSlot) -> RGBA { tiles[slot.rawValue] }
    /// Today's tile: the theme's accent, in both appearances.
    var tileToday: RGBA { tiles[7] }
    /// A token's value.
    func value(_ t: Token) -> RGBA { values[t.rawValue] }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
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
