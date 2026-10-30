import AppKit
import SwiftUI

// STUB: the real overlay follows.
final class DragOverlayView: FlippedLayerView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct DragOverlayRepresentable: NSViewRepresentable {
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> DragOverlayView {
        let v = DragOverlayView(frame: .zero)
        window.dragOverlay = v
        return v
    }

    func updateNSView(_ nsView: DragOverlayView, context: Context) {}
}
