import AppKit
import QuartzCore
import TasksTheme

// The sidebar's brand header (v2 feedback 12): the app's mark and "Tasks", above Today.
//
// The user, 2026-11-08: "let's go with lit body (2a), but when the logo shows in the app, it's a list mark." So inside
// the app the mark is a list mark: the lit tile every list wears (`TileLayer`, `TileArt`) in the accent, with the
// check in white, the same 20×16 as the rows' tiles and on their column. The app icon is the same tile filling its
// whole body (design/logo/final, 02a Lit body; design/logo/round2 has the canvas).

/// The app's mark as a list mark: the tile's hue and glyph. The hue is Today's tile's, the accent as given: tiles don't
/// change with the appearance, where `mark-head` is light's raised accent and would sit darker than every tile under it.
enum ListMark {
    static let glyph = Glyph.check

    static func hue(_ p: TK.Palette) -> NSColor { p.tileToday }

    /// The mark as an image `width` wide (20×16 in proportion, radius 4 of 20), centred in a square, for places that
    /// take an `NSImage` (the About panel). Drawn by `TileArt` with the check as `TileLayer` draws a glyph: white, 12
    /// of 20 wide.
    static func image(width: CGFloat, palette p: TK.Palette) -> NSImage {
        let k = width / TileLayer.dimensions(.regular).width
        let d = CGSize(width: width, height: TileLayer.dimensions(.regular).height * k)
        let radius = TileLayer.radius(.regular) * k, glyphSize = TileLayer.glyphSize(.regular) * k
        let halo = TK.RGBA(ns: p.tileHalo), fill = TK.RGBA(ns: hue(p))
        return NSImage(size: CGSize(width: width, height: width), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = abs(ctx.userSpaceToDeviceSpaceTransform.a)
            let origin = CGPoint(x: 0, y: (width - d.height) / 2)
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            TileArt.draw(ctx, size: d, radius: radius, hue: fill, halo: halo, scale: scale > 0 ? scale : 2)
            ctx.translateBy(x: (d.width - glyphSize) / 2, y: (d.height - glyphSize) / 2)
            ctx.addPath(glyph.path(size: glyphSize))
            ctx.setStrokeColor(TileLayer.ink.cgColor)
            ctx.setLineWidth(glyph.lineWidth(size: glyphSize))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()
            return true
        }
    }
}

/// The header row: 34 tall at the top of the sidebar's content. The mark is a 20×16 list mark on the rows' tile column
/// (`SB.tileX`), and "Tasks" in 13pt semibold `ink` starts on their title column (`SB.titleX`). A label, not a
/// control: no hover, no press, and it scrolls and collapses with the sidebar.
final class SidebarHeaderLayer: CALayer {
    private let mark = TileLayer()
    let title = TextLayer()
    private var palette: TK.Palette?

    override init() {
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: SB.rowWidth(sidebar: TK.M.sidebar), height: SB.headerHeight)
        actions = TaskRowView.noActions
        mark.actions = TaskRowView.noActions
        addSublayer(mark)
        addSublayer(title)
        title.actions = TaskRowView.noActions
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setPalette(_ p: TK.Palette) {
        guard p != palette else { return }
        palette = p
        mark.set(monogram: nil, hue: ListMark.hue(p), palette: p, glyph: ListMark.glyph)
        mark.position = CGPoint(x: SB.tileX + mark.bounds.width / 2, y: SB.headerHeight / 2)
        title.set("Tasks", font: TK.Font.brand, color: p.ink)
        title.place(x: SB.titleX, lineTop: (SB.headerHeight - 16) / 2, lineHeight: 16, width: bounds.width - SB.titleX)
    }
}
