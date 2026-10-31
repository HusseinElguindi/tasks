import AppKit
import SwiftUI

extension TK {
    /// Settings ▸ Interface style ▸ Glass (v2 feedback 10).
    enum Glass {
        /// The theme's ground over the backdrop: enough to keep its color and the sidebar's contrast, light enough for
        /// what's behind the window to show.
        static let groundTint: Double = 0.6
        /// Pane fills stay at 84–90% so `ink-secondary` stays legible (design/DIRECTIONS.md, A3).
        static let paneFill: Double = 0.88
    }
}

/// The window's ground in Glass: what's behind the window, blurred (the sidebar material, blending behind the window, in
/// the theme's appearance), under the theme's ground at `TK.Glass.groundTint`. The sidebar and the gutters sit on it,
/// and the panes' fills let a little of it through. It stays translucent while the window isn't key, as the setting
/// says.
struct GlassGround: View {
    @Environment(\.tk) private var tk

    var body: some View {
        BehindWindowMaterial(dark: tk.isDark)
            .overlay(tk.ground.swiftUI.opacity(TK.Glass.groundTint))
    }
}

private struct BehindWindowMaterial: NSViewRepresentable {
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .sidebar   // translucent; `.underWindowBackground` is the barely-there wallpaper tint
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        // The theme's appearance, whatever the window's is.
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

#if DEBUG
/// Debug aid for Glass without the window server (the screen can be locked): `glasssnap:/path.png` renders the window
/// in-process with its behind-window materials hidden and no window background, so the PNG's alpha is how much of the
/// glass each pixel covers (0: the backdrop shows as the material renders it; 1: opaque). /path.txt gets the window's
/// opacity and background and every material view: its blending, material, state, appearance and frame.
@MainActor
enum GlassDebug {
    static func snapshot(_ w: NSWindow, to path: String) {
        guard let frame = w.contentView?.superview else { return }
        var effects: [NSVisualEffectView] = []
        func walk(_ v: NSView) {
            if let e = v as? NSVisualEffectView { effects.append(e) }
            v.subviews.forEach(walk)
        }
        walk(frame)
        var info = "window isOpaque=\(w.isOpaque) backgroundColor=\(w.backgroundColor.description) alpha=\(w.alphaValue)\n"
        for e in effects {
            let r = e.convert(e.bounds, to: nil)
            info += "effect \(type(of: e)) blending=\(e.blendingMode == .behindWindow ? "behindWindow" : "withinWindow") "
                + "material=\(e.material.rawValue) state=\(e.state.rawValue) appearance=\(e.appearance?.name.rawValue ?? "inherited") "
                + "effective=\(e.effectiveAppearance.name.rawValue) frame=\(Int(r.minX)),\(Int(w.frame.height - r.maxY)),\(Int(r.width))x\(Int(r.height)) "
                + "hidden=\(e.isHiddenOrHasHiddenAncestor) alpha=\(e.alphaValue)\n"
        }
        try? info.write(toFile: (path as NSString).deletingPathExtension + ".txt", atomically: true, encoding: .utf8)
        let background = w.backgroundColor
        let hidden = effects.map(\.isHidden)
        w.backgroundColor = .clear
        effects.forEach { $0.isHidden = true }
        let scale = w.backingScaleFactor
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frame.bounds.width * scale),
                                         pixelsHigh: Int(frame.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = frame.bounds.size
        frame.cacheDisplay(in: frame.bounds, to: rep)
        for (e, h) in zip(effects, hidden) { e.isHidden = h }
        w.backgroundColor = background
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
