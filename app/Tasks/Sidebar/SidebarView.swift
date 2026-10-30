import AppKit
import SwiftUI
import TasksCore

// STUB: replaced by the sidebar build.
final class SidebarView: FlippedLayerView {
    func takeKeys() { window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
}

struct SidebarRepresentable: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> SidebarView {
        let v = SidebarView(frame: .zero)
        window.sidebarView = v
        return v
    }

    func updateNSView(_ nsView: SidebarView, context: Context) {}
}
