import AppKit
import SwiftUI

/// SwiftUI's `List` is an NSTableView on macOS. Pane draws its own selection (fill-selected at radius-row), so this
/// turns off the table's highlight and background once the row is in the table.
struct PaneTableStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var v: NSView? = superview
            while let view = v, !(view is NSTableView) { v = view.superview }
            guard let table = v as? NSTableView else { return }
            if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
            if table.backgroundColor != .clear { table.backgroundColor = .clear }
            if table.gridStyleMask != [] { table.gridStyleMask = [] }
            table.enclosingScrollView?.drawsBackground = false
        }
    }
}

/// Lets the window be dragged by its empty background (the hidden title bar's area included).
struct WindowConfigurator: NSViewRepresentable {
    var ground: NSColor

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.backgroundColor = ground
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

#if DEBUG
/// Debug aid: `-snapshotTo /path.png` renders the key window to a PNG once data is on screen, then
/// `-snapshotQuit YES` quits. Used to check the UI against the design boards without screen-recording access.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshotTo") else { return }
        let delay = defaults.double(forKey: "snapshotDelay") > 0 ? defaults.double(forKey: "snapshotDelay") : 1.5
        if let size = defaults.string(forKey: "debugWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: size[0], height: size[1])), display: true)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView else { return }
            let bounds = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            view.cacheDisplay(in: bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            if defaults.bool(forKey: "snapshotQuit") { NSApp.terminate(nil) }
        }
    }
}
#endif
