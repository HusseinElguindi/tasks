import SwiftUI
import TasksCore

@main
struct TasksApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ThemedRoot(model: model) { RootView() }
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 760)
        .commands { TasksCommands() }

        Settings {
            ThemedRoot(model: model) { SettingsView() }
                .environment(model)
        }
    }
}

/// Applies the Pane theme: Dark or Light by the system appearance unless the user picked one in Settings. The window
/// always gets an explicit scheme, the one the palette is for. Reading SwiftUI's `colorScheme` here kept the last
/// explicit choice after switching back to System while the window followed the system, so they came apart (v2
/// feedback 9).
struct ThemedRoot<Content: View>: View {
    let model: AppModel
    @ViewBuilder var content: Content

    var body: some View {
        let dark = model.dark
        let colors = PaneColors(dark ? .dark : .light)
        content
            .environment(\.pane, colors)
            .environment(\.tk, dark ? TK.Palette.dark : TK.Palette.light)
            .environment(\.paneInterfaceStyle, model.interfaceStyle)
            .tint(colors.accent)
            .paneRespectsReduceMotion()
            .preferredColorScheme(dark ? .dark : .light)
    }
}

/// The menu bar (§17). Commands that need a task are disabled while there's none (an untitled draft isn't one); the
/// ones that work from a task's text fields end the edit first, the way a press elsewhere would.
struct TasksCommands: Commands {
    @FocusedValue(\.windowState) private var window
    @FocusedValue(\.store) private var store

    private var actions: WindowActions? {
        guard let window, let store else { return nil }
        return WindowActions(store: store, window: window)
    }

    /// A task to act on: the selection, or a titled draft (which is written first). While the date popover is open
    /// its field has the keys, and task commands do nothing (as in the prototype).
    private var hasTarget: Bool {
        guard let a = actions, a.overlays.picker == nil else { return false }
        if let d = a.window.draft, a.window.selection == [d.id] { return !a.untitledDraft }
        return !a.targetIDs.isEmpty
    }

    private var pickerOpen: Bool { window?.overlays.picker != nil }

    /// The Trash reads but doesn't edit: only Put Back and Show Details act on its tasks (§22).
    private var inTrash: Bool { window?.route == .trash }

    /// Text is being typed somewhere: ⌘⌫ belongs to the field.
    private var typing: Bool {
        guard let w = window else { return false }
        return w.detailEditing != nil || w.rename != nil || w.overlays.picker != nil
    }

    private func run(_ body: (WindowActions) -> Void) {
        guard let a = actions else { return }
        a.endEdits()
        body(a)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { actions?.newTask() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("New List") { actions?.newList() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        // Bold and Italic while the notes have the caret (design/MARKDOWN.md §6). There's no Add Link: ⌘K completes.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Bold") { NSApp.sendAction(#selector(NotesTextView.notesBold(_:)), to: nil, from: nil) }
                .keyboardShortcut("b")
                .disabled(window?.detailEditing != .notes)
            Button("Italic") { NSApp.sendAction(#selector(NotesTextView.notesItalic(_:)), to: nil, from: nil) }
                .keyboardShortcut("i")
                .disabled(window?.detailEditing != .notes)
        }
        CommandMenu("Task") {
            Button(window?.detailOpen == true ? "Hide Details" : "Show Details") { actions?.toggleDetail() }
                .keyboardShortcut("d")
                .disabled(actions == nil || pickerOpen)
            Divider()
            Button(completeTitle) { run { $0.toggleComplete() } }
                .keyboardShortcut("k")
                .disabled(!hasTarget || inTrash)
            Button("When…") { run { $0.openPicker(.when) } }
                .keyboardShortcut("s")
                .disabled(!hasTarget || inTrash)
            Button("When: Today") { run { $0.setDate(nil, .when, $0.today) } }
                .keyboardShortcut("t")
                .disabled(!hasTarget || inTrash)
            Button("Deadline…") { run { $0.openPicker(.deadline) } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!hasTarget || inTrash)
            Button("Move to…") { run { $0.popMoveMenu() } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!hasTarget || inTrash)
            Divider()
            Button("Move Up") { run { $0.moveUpDown(-1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(actions == nil || typing)
            Button("Move Down") { run { $0.moveUpDown(1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(actions == nil || typing)
            Divider()
            Button(window?.focus == .sidebar ? "Archive List" : window?.route == .trash ? "Put Back" : "Delete") { run { $0.deleteOrArchive() } }
                .keyboardShortcut(.delete)
                .disabled(actions == nil || typing || (window?.focus != .sidebar && !hasTarget))
        }
        CommandGroup(before: .sidebar) {
            // The sidebar's first nine rows, top to bottom: Today, Upcoming, Undated, then the lists (§22).
            ForEach(Array(sidebarNames.enumerated()), id: \.offset) { i, name in
                Button(name) { actions?.goNumber(i + 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    .disabled(actions == nil || pickerOpen)
            }
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Button(window?.sidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") { actions?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(window == nil)
            Button("Sync Now") { store?.requestSync(force: true) }
                .keyboardShortcut("r")
                .disabled(store == nil)
            Divider()
        }
    }

    /// The sidebar's first nine rows, for ⌘1–⌘9.
    private var sidebarNames: [String] {
        guard let a = actions else { return ["Today", "Upcoming", "Undated"] }
        return WindowState.Route.sidebarOrder(a.p).prefix(9).map(a.routeName)
    }

    private var completeTitle: String {
        guard let a = actions else { return "Complete" }
        let ids = a.targetIDs
        let tasks = ids.compactMap(a.p.task)
        if !tasks.isEmpty, tasks.allSatisfy({ $0.completedAt != nil }) { return "Mark as Not Done" }
        return tasks.count > 1 ? "Complete \(tasks.count) Tasks" : "Complete"
    }
}

extension WindowActions {
    /// ⇧⌘M: the Move-to menu under the first selected row.
    func popMoveMenu() {
        let ids = targetIDs
        guard let first = ids.first, let list = window.taskList, let point = list.moveMenuPoint(for: first) else { return }
        Menus.popMoveMenu(ids, at: point, in: list, actions: self)
    }

    /// ⌥⌘↑ ⌥⌘↓: the selected tasks, or the open list when the sidebar has the keys.
    func moveUpDown(_ delta: Int) {
        if window.focus == .sidebar {
            if let id = window.route.listID, p.list(id)?.archivedAt == nil { moveListBy(id, delta) }
        } else {
            moveSelectionBy(delta)
        }
    }

    /// ⌘⌫: delete the selected tasks; with the sidebar focused, archive the open list.
    func deleteOrArchive() {
        if window.focus == .sidebar {
            if let id = window.route.listID { archive(list: id) }
        } else {
            delete()
        }
    }
}
