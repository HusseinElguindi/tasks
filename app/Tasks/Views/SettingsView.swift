import AppKit
import ServiceManagement
import SwiftUI
import TasksCore

/// Settings (⌘,): the sync server and token (Keychain), syncing with no window open, appearance, how tasks are edited,
/// opening at login, and the data folder.
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
                // The user, 2026-11-06 (spec §5 Realtime): keep the widgets current after ⌘W, and a way to turn it off.
                PaneRow("Sync with no window open", description: model.syncWithoutWindow
                        ? "Keeps syncing while Tasks is open, so widgets stay current."
                        : "Only while a window is open, and after a tasks CLI change.") {
                    Toggle("Sync with no window open", isOn: $model.syncWithoutWindow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                PaneRowDivider()
                PaneRow("Status", description: status) {
                    Button("Sync Now") { model.syncNow() }
                        .buttonStyle(.pane())
                        .disabled(model.store == nil)
                }
                // The poke socket (design/SYNC-STATUS.md): hidden until sync is set up.
                if let live = model.liveInput {
                    PaneRowDivider()
                    LiveUpdatesRow(input: live)
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
                PaneRowDivider()
                // The user, 2026-11-06: Tasks running after a restart keeps the widgets current (macOS keeps the setting).
                PaneRow("Open at login", description: loginDescription) {
                    if model.loginItem == .requiresApproval {
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.pane())
                    }
                    Toggle("Open at login", isOn: Binding(
                        get: { model.loginItem == .enabled || model.loginItem == .requiresApproval },
                        set: { model.setOpenAtLogin($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
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
        .onAppear { model.refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginItem()
        }
    }

    private var loginDescription: String {
        if let e = model.loginItemError { return "Couldn't change it: \(e)" }
        switch model.loginItem {
        case .enabled: return "Tasks opens when you log in, so widgets stay current."
        case .requiresApproval: return "Allow Tasks in System Settings ▸ Login Items."
        default: return "Off. Widgets update only while Tasks is open."
        }
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

/// Settings ▸ Sync ▸ Live updates (design/SYNC-STATUS.md §2, A): the title, the detail under it, and a dot and a word on
/// the right. The countdown ticks once a second; nothing else moves. One element for VoiceOver.
struct LiveUpdatesRow: View {
    let input: LiveStatus.Input
    @Environment(AppModel.self) private var model
    @Environment(\.tk) private var tk

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let row = LiveStatus(input, device: .mac(syncWithoutWindow: model.syncWithoutWindow), pace: model.livePace,
                                 now: context.date)
            PaneRow(LiveStatus.title, description: row.detail) {
                HStack(spacing: 6) {
                    LiveDot(dot: row.dot, size: 7)
                    Text(row.word)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle((row.dot == .attention ? tk.attention : tk.inkSecondary).swiftUI)
                        .fixedSize()
                }
            }
            // A long detail (an old server's retry time) wraps rather than truncating inside the timeline.
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LiveStatus.title)
            .accessibilityValue(row.spoken)
        }
    }
}

/// The row's dot: filled `list-green` while live, a 1.5pt ring while trying, filled `ink-quiet` offline or with an old
/// server, `attention` for a refused token, a quiet ring when off.
struct LiveDot: View {
    let dot: LiveStatus.Dot
    let size: CGFloat
    @Environment(\.tk) private var tk

    var body: some View {
        Group {
            switch dot {
            case .live: Circle().fill(tk.list(.green).swiftUI)
            case .ring: Circle().strokeBorder(tk.inkTertiary.swiftUI, lineWidth: 1.5)
            case .quietRing: Circle().strokeBorder(tk.inkQuiet.swiftUI, lineWidth: 1.5)
            case .quiet: Circle().fill(tk.inkQuiet.swiftUI)
            case .attention: Circle().fill(tk.attention.swiftUI)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
