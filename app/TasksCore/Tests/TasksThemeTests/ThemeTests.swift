import CoreGraphics
import TasksTheme
import XCTest

/// The theme's derivation (design/THEMES.md §2.4–2.5) with COLOR.md's accent and tiles, and the lit tile's light
/// (moved from app/TasksTests/ThemeTests.swift with the theme; the Mac's palette keeps its own tests there).
final class ThemeTests: XCTestCase {
    private let rex = Theme.rex

    private func hex(_ c: RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    private func value(_ t: Theme, _ token: Token, dark: Bool) -> RGBA { t.tokens(dark: dark)[token.rawValue] }

    /// The tokens that show the accent: all derived from `Theme.accent`, none pinned (COLOR.md §6).
    private let accentTokens: [Token] = [.accent, .accentText, .accentTint, .focus, .textSelection, .spark, .markHead,
                                         .tileToday]

    func testTheAccentsValues() {
        let expected: [(Token, String, String)] = [
            (.accent, "#E6683D", "#B1502F"), (.accentText, "#E68565", "#B1502F"), (.accentTint, "#362620", "#F7EDEA"),
            (.focus, "#E6683D", "#B1502F"), (.spark, "#E68565", "#B1502F"), (.markHead, "#E6683D", "#B1502F"),
            (.tileToday, "#E6683D", "#E6683D"), (.onAccent, "#FFFFFF", "#FFFFFF"), (.plan, "#5799F6", "#0969DA"),
        ]
        for (token, dark, light) in expected {
            XCTAssertEqual(hex(value(rex, token, dark: true)), dark, "\(token) dark")
            XCTAssertEqual(hex(value(rex, token, dark: false)), light, "\(token) light")
        }
        XCTAssertEqual(value(rex, .textSelection, dark: true).a, 0.42, accuracy: 1e-9)
        XCTAssertEqual(value(rex, .textSelection, dark: false).a, 0.22, accuracy: 1e-9)
    }

    func testNothingThatShowsTheAccentIsPinned() {
        for side in [rex.dark, rex.light] {
            XCTAssertNil(side.accent)
            for t in accentTokens { XCTAssertNil(side.pins[t], "\(t) is pinned") }
        }
    }

    /// Changing the one source accent changes every token derived from it, in both appearances, and nothing else.
    func testChangingTheAccentChangesEveryDerivedToken() {
        for other: UInt32 in [0x2F81F7, 0x8E44AD, 0x2EA043, 0xD29922] {
            var t = rex
            t.accent = RGBA(other)
            for dark in [true, false] {
                let before = rex.tokens(dark: dark), after = t.tokens(dark: dark)
                for token in Token.allCases {
                    let b = before[token.rawValue], a = after[token.rawValue]
                    if accentTokens.contains(token) {
                        XCTAssertNotEqual(a, b, "\(token) didn't follow \(hex(t.accent)) (dark: \(dark))")
                    } else if token != .onAccent {
                        XCTAssertEqual(a, b, "\(token) changed with the accent (dark: \(dark))")
                    }
                }
            }
        }
        // on-accent follows as well: white until white is under 3:1 on the accent, then the darkest ink.
        var yellow = rex
        yellow.accent = RGBA(0xF5D90A)
        XCTAssertNotEqual(value(yellow, .onAccent, dark: true), value(rex, .onAccent, dark: true))
    }

    /// A side may still give its own accent, which wins over the theme's.
    func testASidesOwnAccentWins() {
        var t = rex
        t.light.accent = RGBA(0x0969DA)
        XCTAssertEqual(hex(value(t, .accent, dark: false)), "#0969DA")
        XCTAssertEqual(hex(value(t, .accent, dark: true)), "#E6683D")
    }

    /// `accent-text` holds 4.5:1 on base and on `accent-tint` for any accent (§2.5's raise), and light's accent, which
    /// is its text, does too; white or ink holds 3:1 on the accent.
    func testTheAccentsFloorsHoldForAnyAccent() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            var t = rex
            t.accent = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng), b: .random(in: 0...1, using: &rng))
            for dark in [true, false] {
                let v = t.tokens(dark: dark)
                func get(_ k: Token) -> RGBA { v[k.rawValue] }
                XCTAssertGreaterThanOrEqual(get(.accentText).contrast(get(.base)), 4.5, "\(hex(t.accent)) dark: \(dark)")
                XCTAssertGreaterThanOrEqual(get(.accentText).contrast(get(.accentTint)), 4.5, "\(hex(t.accent)) dark: \(dark)")
                XCTAssertEqual(get(.spark), get(.accentText))
                if RGBA.white.contrast(get(.accent)) >= 3 { XCTAssertEqual(get(.onAccent), .white) }
            }
        }
    }

    /// B's tiles: white holds 4.5:1 at a letter's cap top (4.5pt down the middle of a 20×16 tile, the lightest point
    /// under it), and Today's sun 3:1 through the middle (COLOR.md §2). The hues are given, not derived, so they're
    /// checked as THEMES §2.5 checks a pin, 0.05 under the floor (blue is 4.496 on the continuous light; the spec's
    /// table rounds it to 4.50).
    func testTileHuesHoldWhiteUnderTheLight() {
        let size = CGSize(width: 20, height: 16)
        for hue in rex.tiles {
            let under = TileArt.lit(hue, at: CGPoint(x: 10, y: 4.5), in: size)
            XCTAssertGreaterThanOrEqual(RGBA.white.contrast(under), 4.45, hex(hue))
        }
        let today = TileArt.lit(rex.accent, at: CGPoint(x: 10, y: 8), in: size)
        XCTAssertGreaterThanOrEqual(RGBA.white.contrast(today), 3.2)
    }

    /// The light's rule gives the spec's stops (COLOR.md §2).
    func testTheLightsStops() {
        let spec: [Double] = [0.216, 0.213, 0.194, 0.157, 0.108, 0.059, 0.022, 0.003, 0,
                              -0.003, -0.015, -0.036, -0.057, -0.069, -0.072]
        for (d, a) in zip(TileArt.lightLocations, spec) {
            XCTAssertEqual(TileArt.light(d), a, accuracy: 0.0011, "at \(d)")
        }
    }

    /// The finish draws on any platform: an image `outset` larger than the tile all round, at the scale asked, the
    /// same image for the same tile from the cache.
    func testTheTileImageIsOutsetAndCached() throws {
        let hue = rex.tiles[0], halo = RGBA.black.alpha(0.35)
        let img = try XCTUnwrap(TileArt.image(hue: hue, halo: halo, size: CGSize(width: 20, height: 16), radius: 4, scale: 2))
        XCTAssertEqual(img.width, Int((20 + 2 * TileArt.outset) * 2))
        XCTAssertEqual(img.height, Int((16 + 2 * TileArt.outset) * 2))
        XCTAssertTrue(img === TileArt.image(hue: hue, halo: halo, size: CGSize(width: 20, height: 16), radius: 4, scale: 2))
    }
}
