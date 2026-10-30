import AppKit
import SwiftUI
import TasksCore

// STUB: the real list follows.
final class TaskListView: FlippedLayerView {
    var layout: TaskLayout?
    func takeKeys() { window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    func scrollToVisible(_ id: EntityID) {}
    func scrollToTop() {}
    func moveMenuPoint(for id: EntityID) -> NSPoint? { nil }
    func anchorRect(for id: EntityID, field: Overlays.Picker.Field) -> CGRect? { nil }
}

struct TaskListRepresentable: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> TaskListView {
        let v = TaskListView(frame: .zero)
        window.taskList = v
        return v
    }

    func updateNSView(_ nsView: TaskListView, context: Context) {}
}
