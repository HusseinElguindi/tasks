import SwiftUI
import TasksCore

/// Settings: the sync server and token (Keychain), System / Light / Dark and Classic or Glass, in Pane's sections and
/// cards. One theme, the Mac's.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var token = ""
    /// The background refresh's last run and count (BackgroundRefresh.swift), read as Settings opens.
    @State private var refresh = RefreshHistory.Summary()
    @FocusState private var field: Field?
    private enum Field { case server, token }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Section("Sync") {
                        VStack(spacing: 0) {
                            stacked("Server URL", "The Worker's address. Sync starts once both are set.") {
                                TextField("https://tasks.example.workers.dev", text: $server)
                                    .font(Typo.body)
                                    .keyboardType(.URL)
                                    .textContentType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .focused($field, equals: .server)
                                    .onSubmit(saveServer)
                                    .padding(.horizontal, 12).frame(height: 38)
                                    .background(p.fillControl, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityLabel("Server URL")
                            }
                            divider
                            stacked("Token", app.hasToken ? "Saved in the Keychain." : "The API_TOKEN secret, pasted once.") {
                                HStack(spacing: 10) {
                                    SecureField(app.hasToken ? "••••••••" : "Token", text: $token)
                                        .font(Typo.body)
                                        .textContentType(.password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .submitLabel(.done)
                                        .focused($field, equals: .token)
                                        .onSubmit(saveToken)
                                        .padding(.horizontal, 12).frame(height: 38)
                                        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .accessibilityLabel("Token")
                                    Button("Save", action: saveToken)
                                        .buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 34))
                                        .disabled(token.isEmpty)
                                }
                            }
                            divider
                            row("Status", app.syncStatus) {
                                Button("Sync Now") { app.requestSyncNow() }
                                    .buttonStyle(CapsuleButtonStyle(kind: .neutral, height: 32))
                                    .disabled(app.store.config == nil)
                            }
                            divider
                            // The poke socket (design/SYNC-STATUS.md): hidden until sync is set up.
                            if let live = app.liveInput {
                                liveRow(live)
                                divider
                            }
                            row("Background refresh", app.isSample ? "Off: this is the sample data." : refresh.text()) { EmptyView() }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("backgroundRefresh")
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Section("Appearance") {
                        VStack(spacing: 0) {
                            stacked("Appearance", "System follows the phone’s Light and Dark.") {
                                Picker("Appearance", selection: $app.appearance) {
                                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            divider
                            stacked("Interface style", "Glass lets a wallpaper show through the window, the bars and the sheets.") {
                                Picker("Interface style", selection: $app.style) {
                                    ForEach(InterfaceStyle.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Section("About") {
                        VStack(spacing: 0) {
                            row("Tasks", "Version \(version)") { EmptyView() }
                            divider
                            row("Lists", "\(lists.count) lists, \(lists.reduce(0) { $0 + app.openCount($1.id) }) open tasks.") { EmptyView() }
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .background(p.ground)
        .onAppear {
            server = app.serverURL
            refresh = BackgroundRefresh.shared.history.summary
        }
        .onChange(of: field) { old, _ in if old == .server { saveServer() } }
        .onDisappear(perform: saveServer)
    }

    private var lists: [ListModel] { app.activeLists }

    private func saveServer() {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if s != app.serverURL { app.serverURL = s }
    }

    /// Into the Keychain, then out of the field: the token is never shown again.
    private func saveToken() {
        guard !token.isEmpty else { return }
        app.setToken(token)
        token = ""
        field = nil
    }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    private var divider: some View {
        Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.horizontal, 10)
    }

    private func row<T: View>(_ title: String, _ description: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body).foregroundStyle(p.ink)
                Text(description).font(Typo.meta).foregroundStyle(p.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    /// Settings ▸ Sync ▸ Live updates (design/SYNC-STATUS.md §2, A): the title and detail, and a dot and a word on the
    /// right. The countdown in the detail ticks once a second; nothing else moves. One element for VoiceOver.
    private func liveRow(_ input: LiveStatus.Input) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let r = LiveStatus(input, device: .iPhone, pace: LiveStatus.pace(for: .front), now: context.date)
            row(LiveStatus.title, r.detail) {
                HStack(spacing: 7) {
                    LiveDot(dot: r.dot)
                    Text(r.word)
                        .font(Typo.body)
                        .foregroundStyle(r.dot == .attention ? p.attention : p.inkSecondary)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LiveStatus.title)
            .accessibilityValue(r.spoken)
            .accessibilityIdentifier("liveUpdates")
        }
    }

    private func stacked<T: View>(_ title: String, _ description: String, @ViewBuilder control: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body).foregroundStyle(p.ink)
                Text(description).font(Typo.meta).foregroundStyle(p.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            control()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    private func Section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.ink).padding(.leading, 4)
            content()
        }
    }
}

/// Live updates' dot, 8pt: filled `list-green` while live, a 1.5pt ring while trying, filled `ink-quiet` offline or
/// with an old server, `attention` for a refused token, a quiet ring when off.
struct LiveDot: View {
    let dot: LiveStatus.Dot
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            switch dot {
            case .live: Circle().fill(p.list(.green))
            case .ring: Circle().strokeBorder(p.inkTertiary, lineWidth: 1.5)
            case .quietRing: Circle().strokeBorder(p.inkQuiet, lineWidth: 1.5)
            case .quiet: Circle().fill(p.inkQuiet)
            case .attention: Circle().fill(p.attention)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
