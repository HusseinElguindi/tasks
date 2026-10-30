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

/// Applies the Pane theme: Dark or Light by the system appearance unless the user picked one in Settings.
struct ThemedRoot<Content: View>: View {
    let model: AppModel
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = model.theme == .dark || (model.theme == .system && scheme == .dark)
        let colors = PaneColors(dark ? .dark : .light)
        content
            .environment(\.pane, colors)
            .environment(\.tk, dark ? TK.Palette.dark : TK.Palette.light)
            .environment(\.paneInterfaceStyle, model.interfaceStyle)
            .tint(colors.accent)
            .paneRespectsReduceMotion()
            .preferredColorScheme(model.theme == .system ? nil : (dark ? .dark : .light))
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
        CommandMenu("Task") {
            Button(window?.detailOpen == true ? "Hide Details" : "Show Details") { actions?.toggleDetail() }
                .keyboardShortcut("d")
                .disabled(actions == nil || pickerOpen)
            Divider()
            Button(completeTitle) { run { $0.toggleComplete() } }
                .keyboardShortcut("k")
                .disabled(!hasTarget)
            Button("When…") { run { $0.openPicker(.when) } }
                .keyboardShortcut("s")
                .disabled(!hasTarget)
            Button("When: Today") { run { $0.setDate(nil, .when, $0.today) } }
                .keyboardShortcut("t")
                .disabled(!hasTarget)
            Button("Deadline…") { run { $0.openPicker(.deadline) } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!hasTarget)
            Button("Move to…") { run { $0.popMoveMenu() } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!hasTarget)
            Divider()
            Button("Move Up") { run { $0.moveUpDown(-1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(actions == nil || typing)
            Button("Move Down") { run { $0.moveUpDown(1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(actions == nil || typing)
            Divider()
            Button(window?.focus == .sidebar ? "Archive List" : "Delete") { run { $0.deleteOrArchive() } }
                .keyboardShortcut(.delete)
                .disabled(actions == nil || typing || (window?.focus != .sidebar && !hasTarget))
        }
        CommandGroup(before: .sidebar) {
            Button("Today") { actions?.goNumber(1) }
                .keyboardShortcut("1")
                .disabled(actions == nil || pickerOpen)
            ForEach(Array(listNames.enumerated()), id: \.offset) { i, name in
                Button(name) { actions?.goNumber(i + 2) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 2)")))
                    .disabled(pickerOpen)
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

    /// The first eight active lists, for ⌘2–⌘9.
    private var listNames: [String] {
        guard let a = actions else { return [] }
        return a.p.activeLists.ids.prefix(8).map(a.listName)
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
