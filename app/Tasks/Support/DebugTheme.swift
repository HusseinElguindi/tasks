#if DEBUG
import Foundation

/// Debug aid: `-debugThemeCheck /path.txt` writes, per appearance, how far each token Rex pins lies from what its rule
/// (THEMES.md §2.4) gives from Rex's base, ink and accent alone, in levels of 255. THEMES.md expects 1–4; dark's
/// hover, press and shadow rings show 25, the gap between white, which Rex draws them in, and its ink. (The accent
/// family isn't pinned since COLOR.md's accent, so it isn't listed.)
@MainActor
enum DebugThemeCheck {
    static func runIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "debugThemeCheck") else { return }
        var out = ""
        for dark in [true, false] {
            let pinned = TK.Theme.rex.tokens(dark: dark), derived = TK.Theme.rexDerived.tokens(dark: dark)
            let side = dark ? TK.Theme.rex.dark : TK.Theme.rex.light
            out += dark ? "dark\n" : "light\n"
            for t in TK.Token.allCases where side.pins[t] != nil {
                let p = pinned[t.rawValue], d = derived[t.rawValue]
                let levels = [p.r - d.r, p.g - d.g, p.b - d.b, p.a - d.a].map { abs($0) * 255 }.max() ?? 0
                out += "  \(t) \(String(format: "%.1f", levels))\n"
            }
        }
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
