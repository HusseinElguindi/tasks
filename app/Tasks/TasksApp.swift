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
            .environment(\.paneInterfaceStyle, model.interfaceStyle)
            .tint(colors.accent)
            .preferredColorScheme(model.theme == .system ? nil : (dark ? .dark : .light))
    }
}

struct TasksCommands: Commands {
    @FocusedValue(\.windowState) private var window
    @FocusedValue(\.store) private var store

    private var actions: WindowActions? {
        guard let window, let store else { return nil }
        return WindowActions(store: store, window: window)
    }

    private var hasTarget: Bool { !(actions?.targetIDs.isEmpty ?? true) }

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
            Button("Complete") { actions?.toggleComplete() }
                .keyboardShortcut("k")
                .disabled(!hasTarget)
            Button(window?.detailTaskID == nil ? "Show Details" : "Hide Details") { actions?.toggleDetail() }
                .keyboardShortcut("d")
                .disabled(actions == nil)
            Button("Move to…") { window?.movePickerPresented = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!hasTarget)
            Menu("When") {
                Button("Today") { actions?.setWhen(store?.projection.day.date) }.keyboardShortcut("t")
                Button("Tomorrow") { actions?.setWhen(store?.projection.day.date.adding(days: 1)) }
                Button("Next Week") { actions?.setWhen(store.map { DateText.nextWeek(from: $0.projection.day.date) }) }
                Divider()
                Button("No Date") { actions?.setWhen(nil) }
            }
            .disabled(!hasTarget)
            Divider()
            Button("Delete") { actions?.delete() }
                .keyboardShortcut(.delete)
                .disabled(!hasTarget)
        }
        CommandGroup(after: .sidebar) {
            Button("Sync Now") { store?.requestSync(force: true) }
                .keyboardShortcut("r")
                .disabled(store == nil)
            Divider()
        }
    }
}
