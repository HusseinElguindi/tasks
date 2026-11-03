import AppKit
import TasksTheme
import XCTest

/// The Mac's side of the theme: the palette the app draws with follows the theme's accent, and no accent hex lives
/// outside the theme. The theme's own tests (its derivation, the accent and its floors, the tiles' light) moved with it
/// to TasksThemeTests in app/TasksCore. Theme.swift (the AppKit bridge) and TK.swift are compiled into this bundle, so
/// these run without the app.
final class ThemeTests: XCTestCase {
    private let rex = TK.Theme.rex

    private func hex(_ c: TK.RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    private func value(_ t: TK.Theme, _ token: TK.Token, dark: Bool) -> TK.RGBA { t.tokens(dark: dark)[token.rawValue] }

    /// The palette the app draws with follows the accent, in both appearances: the checked box, the highlighted day
    /// and menu item read `accent`, and Today's tile `tileToday`.
    func testThePaletteFollowsTheAccent() {
        for other: UInt32 in [0x2F81F7, 0x8E44AD, 0x2EA043, 0xD29922] {
            var t = rex
            t.accent = TK.RGBA(other)
            for dark in [true, false] {
                let p = TK.Palette(theme: t, dark: dark), q = TK.Palette(theme: rex, dark: dark)
                XCTAssertNotEqual(p, q)
                XCTAssertNotEqual(TK.RGBA(ns: p.accent), TK.RGBA(ns: q.accent))
                XCTAssertNotEqual(TK.RGBA(ns: p.tileToday), TK.RGBA(ns: q.tileToday))
            }
        }
    }

    /// No accent hex outside the theme: every colour that shows the accent comes from `Theme.accent`.
    func testNoAccentHexOutsideTheTheme() throws {
        let tasks = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tasks")
        let hexes = Set([TK.Theme.rex.accent, value(rex, .accent, dark: false), value(rex, .accentText, dark: true),
                         value(rex, .accentTint, dark: true), value(rex, .accentTint, dark: false)]
            .map { hex($0).dropFirst().uppercased() })
        let files = FileManager.default.enumerator(at: tasks, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Theme.swift" }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8).uppercased()
            for h in hexes { XCTAssertFalse(text.contains(h), "\(f.lastPathComponent) has the accent's \(h)") }
        }
    }
}
