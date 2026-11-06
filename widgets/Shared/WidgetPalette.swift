import SwiftUI
import TasksTheme

/// The colours a widget draws with: the app's one theme, Rex with the Ember accent (TasksTheme), for the system's
/// appearance (WIDGETS.md Q6). Only the tokens the widgets use, by the Mac's names.
struct WidgetPalette: Sendable {
    let isDark: Bool
    let base, ink, inkSecondary, inkTertiary, fillControl: Color
    let accent, onAccent, plan, danger, dangerTint, attention, attentionTint: Color
    let tileHalo: RGBA
    private let tiles: [RGBA]

    init(theme: Theme = .rex, dark: Bool) {
        let v = theme.tokens(dark: dark)
        func c(_ t: Token) -> Color { v[t.rawValue].swiftUI }
        isDark = dark
        base = c(.base); ink = c(.ink); inkSecondary = c(.inkSecondary); inkTertiary = c(.inkTertiary)
        fillControl = c(.fillControl)
        accent = c(.accent); onAccent = c(.onAccent); plan = c(.plan)
        danger = c(.danger); dangerTint = c(.dangerTint); attention = c(.attention); attentionTint = c(.attentionTint)
        tileHalo = v[Token.tileHalo.rawValue]
        tiles = [Token.tileBlue, .tileMagenta, .tileGreen, .tileCyan, .tileYellow, .tileRed, .tileInk].map { v[$0.rawValue] }
    }

    static let dark = WidgetPalette(dark: true)
    static let light = WidgetPalette(dark: false)
    static func of(_ scheme: ColorScheme) -> WidgetPalette { scheme == .dark ? .dark : .light }

    /// A list's tile hue, from its slot.
    func tile(slot: Int) -> RGBA { tiles[((slot % 7) + 7) % 7] }

    /// The ring's colour for a cue.
    func ring(_ cue: TodaySnapshot.Cue) -> Color {
        switch cue {
        case .late: danger
        case .due: attention
        case .planned: plan
        case .none: inkTertiary
        }
    }
}

extension RGBA {
    /// As the app's `color`: pure white and black stay the system's own.
    var swiftUI: Color {
        if r == g, g == b, r == 1 || r == 0 { return (r == 1 ? Color.white : .black).opacity(a) }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
