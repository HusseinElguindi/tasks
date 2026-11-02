import AppKit
import SwiftUI
import TasksCore

/// Settings (⌘,): the sync server and token (Keychain), appearance, how tasks are edited, and the data folder.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tk) private var tk
    @State private var token = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            PaneSection("Sync") {
                PaneRow("Server URL", description: "The Worker's address. Sync starts once both are set.") {
                    TextField("https://tasks.example.workers.dev", text: $model.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                PaneRowDivider()
                PaneRow("Token", description: model.hasToken ? "Saved in the Keychain." : "The API_TOKEN secret, pasted once.") {
                    SecureField(model.hasToken ? "••••••••" : "Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(saveToken)
                    Button("Save", action: saveToken)
                        .buttonStyle(.pane(.tinted))
                        .disabled(token.isEmpty)
                }
                PaneRowDivider()
                PaneRow("Status", description: status) {
                    Button("Sync Now") { model.store?.requestSync(force: true) }
                        .buttonStyle(.pane())
                        .disabled(model.store == nil)
                }
            }
            PaneSection("Appearance") {
                PaneRow("Theme") {
                    Picker("Theme", selection: $model.theme) {
                        Text("System").tag(AppModel.ThemeChoice.system)
                        Text("Dark").tag(AppModel.ThemeChoice.dark)
                        Text("Light").tag(AppModel.ThemeChoice.light)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                PaneRowDivider()
                PaneRow("Interface style", description: "Classic panes are opaque; Glass is translucent.") {
                    Picker("Interface style", selection: $model.interfaceStyle) {
                        Text("Classic").tag(PaneInterfaceStyle.classic)
                        Text("Glass").tag(PaneInterfaceStyle.glass)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                PaneRowDivider()
                // The user, 2026-11-01 (INTERACTIONS-v2 §4 Pane focus): the focused pane's fill and edge.
                PaneRow("Highlight focused pane", description: highlightDescription) {
                    Picker("Highlight focused pane", selection: $model.paneHighlight) {
                        Text("Always").tag(AppModel.PaneHighlight.always)
                        Text("Two panes").tag(AppModel.PaneHighlight.twoPanes)
                        Text("Never").tag(AppModel.PaneHighlight.never)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            PaneSection("Behavior") {
                // v2 feedback 8 (INTERACTIONS-v2 §7): the › button, ⌘N and the sidebar's list renames are the same in both.
                PaneRow("Edit tasks", description: model.taskEditing == .detail
                        ? "Double-click or Return opens a task in the detail pane."
                        : "Double-click or Return renames a task in its row.") {
                    Picker("Edit tasks", selection: $model.taskEditing) {
                        Text("Open in detail pane").tag(AppModel.TaskEditing.detail)
                        Text("Rename in the list").tag(AppModel.TaskEditing.inline)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            PaneSection("Data") {
                PaneRow("Folder", description: model.dataDirectory.path) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.dataDirectory])
                    }
                    .buttonStyle(.pane())
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .background(tk.ground.swiftUI)
    }

    private var highlightDescription: String {
        switch model.paneHighlight {
        case .always: "Even when it's the only pane."
        case .twoPanes: "Only while the detail pane is open."
        case .never: "Neutral; the header shows focus."
        }
    }

    private func saveToken() {
        guard !token.isEmpty else { return }
        model.setToken(token)
        token = ""
    }

    private var status: String {
        guard let store = model.store else { return "Loading…" }
        if let r = store.recovery { return "Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())" }
        switch store.syncState {
        case .off: return "Off. Set the server URL and token."
        case .syncing: return "Syncing…"
        case .idle(let at): return at.map { "Up to date, \($0.formatted(date: .omitted, time: .shortened))." } ?? "Up to date."
        case .retrying(let at, let reason): return "Can't reach the server (\(reason)). Retrying \(at.formatted(.relative(presentation: .named)))."
        case .checkToken: return "The server rejected the token. Check it and save again."
        case .failed(let message): return "Sync stopped: \(message)"
        }
    }
}
