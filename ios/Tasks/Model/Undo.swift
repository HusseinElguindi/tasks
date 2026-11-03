import SwiftUI
import TasksCore

// Undo and redo (IX §9; batch 2, item 1; the Mac's `WindowActions.undoable`, `registerRestore` and `restore`,
// WindowActions.swift:55–118). Every change is a named step on the window's one stack, the scene's own `UndoManager`,
// so shake, the three-finger gestures, ⌘Z and ⇧⌘Z, the notice's Undo and the "…" menu's Undo and Redo all reach it.
// Each step also records the screen it was made on and the rows it touched: undoing or redoing it goes back there,
// shows those rows, and says so ("Undo Delete Task").

/// The undo manager isn't Sendable; its handlers run on the main actor (as the Mac's `UnsafeSendableBox`).
private struct UnsafeBox<T>: @unchecked Sendable { let value: T }

extension AppModel {
    /// The scene's undo manager, from `RootView`, before any change can be made. The store's steps register on it, and
    /// the system's undo (shake, the three-finger gestures) asks the responder chain for it.
    func adopt(_ manager: UndoManager?) {
        guard let manager, manager !== undo else { return }
        undo = manager
        undoObservers.forEach(NotificationCenter.default.removeObserver)
        let names: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
                                          .NSUndoManagerDidRedoChange, .NSUndoManagerCheckpoint]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoNames() }
            }
        }
        refreshUndoNames()
    }

    /// The "…" menu's Undo and Redo, each only when there's a step (batch 2 §0, §1).
    func refreshUndoNames() {
        let u = undo.canUndo ? undo.undoActionName : nil
        let r = undo.canRedo ? undo.redoActionName : nil
        if undoName != u { undoName = u }
        if redoName != r { redoName = r }
    }

    /// Runs `body` (store calls that register their own inverse ops) as one step named `name`, plus a step that goes
    /// back to the screen it was made on and shows `ids`, the rows it touched (the Mac's `undoable`).
    @discardableResult
    func undoable(_ name: String, ids: [EntityID] = [], _ body: () -> Bool) -> Bool {
        let um = undo
        let screen = shown
        um.beginUndoGrouping()
        let did = body()
        if did { registerRestore(um, screen: screen, ids: ids, name: name) }
        um.endUndoGrouping()
        if did { um.setActionName(name) }
        return did
    }

    private func registerRestore(_ um: UndoManager, screen: Source?, ids: [EntityID], name: String) {
        let manager = UnsafeBox(value: um)
        um.registerUndo(withTarget: self) { app in
            MainActor.assumeIsolated {
                let um = manager.value
                let verb = um.isUndoing ? "Undo" : "Redo"
                // The counterpart, for redo (or undo again): the screen as it is now.
                app.registerRestore(um, screen: app.shown, ids: ids, name: name)
                // The store's inverse ops run after this in the same group; restore once they have.
                DispatchQueue.main.async { app.restore(screen: screen, ids: ids, notice: "\(verb) \(name)") }
            }
        }
    }

    /// After an undo or a redo, in the brief's order: edits end; the sheet of the task it touched stays, any other
    /// sheet closes; the app goes to the screen where the change was made (Today if that list is gone), at once; its
    /// first touched row scrolls into view, and the touched rows show the selected fill for 0.6 s, then fade; and a
    /// notice says what was undone, with no button, for 1.8 s.
    func restore(screen: Source?, ids: [EntityID], notice text: String) {
        if draft != nil { cancelDraft() }
        listEditor = nil
        showSettings = false
        dateTarget = nil
        if let d = detailTask, !ids.contains(d) { detailTask = nil }
        if let s = selectedTask, !ids.contains(s) { selectedTask = nil }
        if !completing.isEmpty { animate(Motion.layout) { completing.removeAll() } }
        var target = screen
        if case let .list(id)? = target, !projection.isActive(list: id) { target = .today }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if isSplit {
                if let target, selection != target { selection = target }
            } else if path.last != target {
                path = target.map { [$0] } ?? []
            }
        }
        // The rows it touched that are on that screen now (an undone add has none).
        if let target {
            let shown = Set(lines(target).compactMap { if case let .task(t, _, _, _) = $0 { t.id } else { nil } })
            let rows = ids.filter(shown.contains)
            flashed = Set(rows)
            if let first = lines(target).lazy.compactMap({ line -> EntityID? in
                if case let .task(t, _, _, _) = line, rows.contains(t.id) { t.id } else { nil }
            }).first {
                undoReveal = UndoReveal(id: first)
            }
            let token = UUID()
            flashToken = token
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.flashToken == token else { return }
                self.flashed = []
            }
        }
        show(Notice(text: text, undo: nil))
    }

    /// The menu's Undo, the notice's Undo, ⌘Z: what's being typed ends first, as on the Mac (`performUndo`).
    func performUndo() {
        endDraft()
        guard undo.canUndo else { return }
        animate(Motion.layout) { undo.undo() }
    }

    func performRedo() {
        endDraft()
        guard undo.canRedo else { return }
        animate(Motion.layout) { undo.redo() }
    }

    /// A notice's Undo: the stack's undo (the Mac: "The notice's Undo is the same as ⌘Z").
    var undoStep: () -> Void { { [weak self] in self?.performUndo() } }
}

/// The first row an undo or redo touched, to scroll into view on its screen.
struct UndoReveal: Equatable {
    let id: EntityID
    let token = UUID()
}

/// Undo and Redo at the top of a "…" menu, each only when there's a step.
struct UndoItems: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let n = app.undoName {
            Button { app.performUndo() } label: { Label(n.isEmpty ? "Undo" : "Undo \(n)", systemImage: "arrow.uturn.backward") }
        }
        if let n = app.redoName {
            Button { app.performRedo() } label: { Label(n.isEmpty ? "Redo" : "Redo \(n)", systemImage: "arrow.uturn.forward") }
        }
        if app.undoName != nil || app.redoName != nil { Divider() }
    }
}

/// A view's "…" (Today, Upcoming, Undated, Completed, Trash): Undo and Redo for now; Select joins them (batch 2 §0).
/// With nothing in it, it isn't shown.
struct ViewMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        if app.undoName != nil || app.redoName != nil {
            Menu {
                UndoItems()
            } label: {
                Image(systemName: "ellipsis")
            }
            .tint(p.ink)
            .accessibilityLabel("More")
        }
    }
}
