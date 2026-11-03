import AppKit
import CryptoKit
import XCTest
// The theme's values and the tile's finish move into the TasksTheme package (step 5). Before the move they're compiled
// into this bundle; after it they come from the package. This file is the same before and after.
#if canImport(TasksTheme)
import TasksTheme
#endif

/// The gate for moving the theme out of the app: every token of Rex in both appearances, every colour the Mac's
/// palettes store (their private tile and list colours too), the brightness factors, and the lit tile's pixels, against
/// ThemeGolden.json. The JSON was recorded on the code before the move and doesn't change after it, so a pass shows the
/// move changed nothing, bit for bit. `TEST_RUNNER_THEME_GOLDEN_RECORD=1` rewrites it (and fails, so a recording is
/// never taken for a pass). The pixels compare only on the macOS build they were recorded on, since CoreGraphics may
/// draw differently on another; the values are arithmetic and compare everywhere.
final class ThemeGoldenTests: XCTestCase {
    private struct Golden: Codable {
        var os: String
        var values: [String: String]
        var pixels: [String: String]
    }

    private static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ThemeGolden.json")
    private static var os: String { ProcessInfo.processInfo.operatingSystemVersionString }

    /// The recorded golden, after writing the current one first when recording.
    private func recorded() throws -> Golden {
        if ProcessInfo.processInfo.environment["THEME_GOLDEN_RECORD"] == "1" {
            let now = Golden(os: Self.os, values: Self.values(), pixels: Self.pixels())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try (encoder.encode(now) + Data("\n".utf8)).write(to: Self.file)
            XCTFail("Recorded \(Self.file.lastPathComponent); run again without THEME_GOLDEN_RECORD")
        }
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.file))
    }

    private func assertSame(_ now: [String: String], _ then: [String: String]) {
        XCTAssertFalse(then.isEmpty)
        for key in Set(now.keys).union(then.keys).sorted() {
            XCTAssertEqual(now[key], then[key], key)
        }
    }

    func testTheThemesValuesAreTheRecordedOnes() throws {
        let now = Self.values()
        XCTAssertFalse(now.values.contains { $0.hasPrefix("unhandled") }, "a palette field this test doesn't read")
        assertSame(now, try recorded().values)
    }

    func testTheTilesPixelsAreTheRecordedOnes() throws {
        let golden = try recorded()
        guard golden.os == Self.os else {
            throw XCTSkip("The tiles' pixels were recorded on \(golden.os); this is \(Self.os)")
        }
        assertSame(Self.pixels(), golden.pixels)
    }

    // MARK: Values

    private static func values() -> [String: String] {
        var out: [String: String] = ["tokens.count": "\(TK.Token.allCases.count)"]
        for dark in [true, false] {
            let v = TK.Theme.rex.tokens(dark: dark)
            for t in TK.Token.allCases { out["tokens.\(dark ? "dark" : "light").\(t)"] = rgba(v[t.rawValue]) }
        }
        let palettes: [(String, TK.Palette)] = [("dark", .dark), ("light", .light),
                                                ("dark.quieter", TK.Palette.dark.quieter),
                                                ("light.quieter", TK.Palette.light.quieter)]
        for (name, p) in palettes {
            // Every stored property, by reflection, so the private ones count and a new one can't be missed.
            for child in Mirror(reflecting: p).children {
                let key = "palette.\(name).\(child.label ?? "?")"
                switch child.value {
                case let c as NSColor:
                    out[key] = color(c)
                case let cs as [NSColor]:
                    out[key + ".count"] = "\(cs.count)"
                    for (i, c) in cs.enumerated() { out["\(key)[\(i)]"] = color(c) }
                case let vs as [TK.RGBA]:
                    out[key + ".count"] = "\(vs.count)"
                    for (i, c) in vs.enumerated() { out["\(key)[\(i)]"] = rgba(c) }
                case let b as Bool:
                    out[key] = "\(b)"
                default:
                    out[key] = "unhandled \(type(of: child.value))"
                }
            }
            out["palette.\(name).chipHoverBrightness"] = number(p.chipHoverBrightness)
            out["palette.\(name).buttonHoverBrightness"] = number(p.buttonHoverBrightness)
        }
        out["palette.pressBrightness"] = number(TK.Palette.pressBrightness)
        return out
    }

    /// A Double as Swift prints it (the shortest that reads back the same) and its bits.
    private static func number(_ x: Double) -> String { "\(x) " + String(format: "%016llx", x.bitPattern) }

    private static func rgba(_ c: TK.RGBA) -> String { [c.r, c.g, c.b, c.a].map(number).joined(separator: ", ") }

    /// An NSColor's colour space and components, so the rule that keeps white and black in AppKit's gray space is
    /// checked too.
    private static func color(_ c: NSColor) -> String {
        guard c.type == .componentBased else { return "type \(c.type.rawValue)" }
        let space = c.colorSpace
        var components = [CGFloat](repeating: 0, count: c.numberOfComponents)
        c.getComponents(&components)
        let name = space.cgColorSpace?.name.map { $0 as String } ?? "unnamed"
        return "\(name) model \(space.colorSpaceModel.rawValue): " + components.map { number($0) }.joined(separator: ", ")
    }

    // MARK: Pixels

    /// Each tile hue, Today's and the brand mark's head, with each appearance's halo, at the Mac's sizes (TileLayer's
    /// regular 20×16 r4 and small 16×13 r3.5; the sidebar's 18pt mark's head, round, no specular), at 1× and 2×.
    private static func pixels() -> [String: String] {
        var out: [String: String] = [:]
        let slots = ["blue", "magenta", "green", "cyan", "yellow", "red", "ink"]
        let shapes: [(name: String, size: CGSize, radius: CGFloat)] = [("regular", CGSize(width: 20, height: 16), 4),
                                                                       ("small", CGSize(width: 16, height: 13), 3.5)]
        // SidebarHeader: the 18pt mark over BrandMark's 724-wide viewBox, its head a circle of radius 100.
        let k: CGFloat = 18 / 724, r = 100 * k
        for (side, p) in [("dark", TK.Palette.dark), ("light", TK.Palette.light)] {
            let hues = slots.enumerated().map { ("tile.\($1)", p.tile(slot: $0)) } + [("tile.today", p.tileToday)]
            for scale: CGFloat in [1, 2] {
                for (hue, color) in hues {
                    for s in shapes {
                        out["\(side).\(hue).\(s.name)@\(Int(scale))x"] =
                            describe(TileArt.image(hue: color, halo: p.tileHalo, size: s.size, radius: s.radius, scale: scale))
                    }
                }
                out["\(side).markHead@\(Int(scale))x"] =
                    describe(TileArt.image(hue: p.markHead, halo: p.tileHalo, size: CGSize(width: 2 * r, height: 2 * r),
                                           radius: r, scale: scale, specular: false))
            }
        }
        return out
    }

    /// The image's geometry and a SHA-256 of its pixels (each row's pixels, not the row's padding).
    private static func describe(_ image: CGImage?) -> String {
        guard let image, let data = image.dataProvider?.data as Data? else { return "no image" }
        let row = image.width * image.bitsPerPixel / 8
        var hash = SHA256()
        for y in 0..<image.height {
            let start = y * image.bytesPerRow
            hash.update(data: data[start..<start + row])
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(image.width)x\(image.height) \(image.bitsPerPixel)bpp info \(image.bitmapInfo.rawValue) sha256 \(digest)"
    }
}
