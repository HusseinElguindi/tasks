import AppKit
import Observation
import ServiceManagement
import SwiftUI
import TasksCore

/// App-wide state: the store (loaded off the main thread at launch), sync settings, appearance, and the sync
/// triggers that don't belong to a view (spec §5: launch, activation, every 30 s; §2: day changes).
@MainActor
@Observable
final class AppModel {
    enum ThemeChoice: String, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
    }

    /// Settings ▸ Edit tasks (v2 feedback 8, INTERACTIONS-v2 §7): what double-click and Return do to a task. Lists in the
    /// sidebar rename in place either way.
    enum TaskEditing: String, CaseIterable, Identifiable {
        /// Open it in the detail pane with the caret in its title (the default).
        case detail
        /// Rename its title in place in the row.
        case inline
        var id: String { rawValue }

        /// The saved choice, read where a gesture needs it (the window's actions have no model). A `-taskEditing inline`
        /// launch argument overrides it without saving (UserDefaults' argument domain).
        static var current: TaskEditing { TaskEditing(rawValue: UserDefaults.standard.string(forKey: Keys.taskEditing) ?? "") ?? .detail }
    }

    /// Settings ▸ Highlight focused pane (the user, 2026-11-01; INTERACTIONS-v2 §4 Pane focus): when the focused pane
    /// shows its active fill and edge. Per Mac, never synced. A `-paneHighlight never` launch argument overrides it
    /// without saving (UserDefaults' argument domain).
    enum PaneHighlight: String, CaseIterable, Identifiable {
        /// Even when it's the only pane (the default).
        case always
        /// Only while both panes are open (v2 feedback 3).
        case twoPanes
        /// Neutral fill and edge everywhere; the header and the selected rows still show which pane has the keys.
        case never
        var id: String { rawValue }

        static var current: PaneHighlight { PaneHighlight(rawValue: UserDefaults.standard.string(forKey: Keys.paneHighlight) ?? "") ?? .always }
    }

    private(set) var store: Store?
    let dataDirectory: URL

    /// The Worker's base URL, e.g. https://tasks.<account>.workers.dev. A `-serverURL` launch argument overrides it
    /// without saving (UserDefaults' argument domain).
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
            applyConfig()
        }
    }

    private(set) var hasToken: Bool

    var theme: ThemeChoice {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
            updatePalette()
        }
    }

    /// Whether the system appearance is dark, for Theme ▸ System: the app's effective appearance, watched. Reading
    /// SwiftUI's `colorScheme` instead kept the last explicit choice after switching back to System (v2 feedback 9).
    private(set) var systemDark = AppModel.isDark(NSApplication.shared.effectiveAppearance) {
        didSet { updatePalette() }
    }

    /// Dark or Light, after resolving System.
    var dark: Bool { theme == .dark || (theme == .system && systemDark) }

    /// Every colour token for the theme (Rex, the only one) in the current appearance (v2 feedback 17). Built when
    /// the appearance changes, never per frame; `ThemedRoot` hands it to every view.
    private(set) var palette = TK.Palette.dark

    private func updatePalette() {
        var p = dark ? TK.Palette.dark : TK.Palette.light
        #if DEBUG
        if debugDerivedTheme { p = TK.Palette(theme: .rexDerived, dark: dark) }
        #endif
        if p != palette { palette = p }
    }

    #if DEBUG
    /// Debug: `-debugTheme derived`, or the script's `palette:derived|rex`, draws Rex from its base colours alone.
    var debugDerivedTheme = UserDefaults.standard.string(forKey: "debugTheme") == "derived" {
        didSet { updatePalette() }
    }
    #endif

    var interfaceStyle: PaneInterfaceStyle {
        didSet { UserDefaults.standard.set(interfaceStyle == .glass ? "glass" : "classic", forKey: Keys.interfaceStyle) }
    }

    var paneHighlight: PaneHighlight {
        didSet { UserDefaults.standard.set(paneHighlight.rawValue, forKey: Keys.paneHighlight) }
    }

    /// Settings ▸ Sync with no window open (the user, 2026-11-06: "allow me to disable 1 in the settings"; on by
    /// default): keep syncing every minute while the app runs with no window on screen, so the widgets keep up with
    /// other devices (`SyncSchedule`). Off: the periodic sync runs only while a window is open, as before.
    var syncWithoutWindow: Bool {
        didSet { UserDefaults.standard.set(syncWithoutWindow, forKey: Keys.syncWithoutWindow) }
    }

    /// Settings ▸ Open at login: whether the app is registered to open at login (`SMAppService.mainApp`). macOS keeps
    /// it, not the app; read again when Settings opens, since System Settings ▸ Login Items can change it.
    private(set) var loginItem: SMAppService.Status = SMAppService.mainApp.status
    /// Why the last change to Open at login failed, shown under the switch.
    private(set) var loginItemError: String?

    var taskEditing: TaskEditing {
        didSet { UserDefaults.standard.set(taskEditing.rawValue, forKey: Keys.taskEditing) }
    }

    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    /// The CLI's nudge: sync at once after `tasks` pushed (feedback item 14).
    @ObservationIgnored private var nudges: SyncNudgeListener?
    /// Writes the widgets' feed into the group container (Widgets/WidgetFeedWriter.swift).
    @ObservationIgnored private(set) var widgetFeed: WidgetFeedWriter?

    enum Keys {
        static let serverURL = "serverURL"
        static let theme = "theme"
        static let interfaceStyle = "interfaceStyle"
        static let taskEditing = "taskEditing"
        static let paneHighlight = "paneHighlight"
        static let syncWithoutWindow = "syncWithoutWindow"
        /// Testing only: data directory and token from launch arguments (spec §10 end-to-end check).
        static let dataDirectory = "dataDirectory"
        static let syncToken = "syncToken"
    }

    init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: Keys.dataDirectory), !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            #if DEBUG
            let folder = "Tasks Dev" // never the real app's data
            #else
            let folder = "Tasks"
            #endif
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(folder, isDirectory: true)
        }
        serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        theme = ThemeChoice(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        interfaceStyle = defaults.string(forKey: Keys.interfaceStyle) == "glass" ? .glass : .classic
        taskEditing = TaskEditing.current
        paneHighlight = PaneHighlight.current
        // On unless turned off (a `-syncWithoutWindow NO` launch argument is a string, which `bool(forKey:)` reads).
        syncWithoutWindow = defaults.object(forKey: Keys.syncWithoutWindow) == nil || defaults.bool(forKey: Keys.syncWithoutWindow)
        hasToken = defaults.string(forKey: Keys.syncToken) != nil || Keychain.token() != nil
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] app, _ in
            MainActor.assumeIsolated {
                let dark = AppModel.isDark(app.effectiveAppearance)
                if self?.systemDark != dark { self?.systemDark = dark }
            }
        }
        updatePalette()
        Task { await load() }
    }

    private static func isDark(_ a: NSAppearance) -> Bool { a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    private func load() async {
        #if DEBUG
        // Debug builds sync through a transport the sync indicator's debug steps can slow down or fail (DebugSync).
        let store = await Store.open(directory: dataDirectory, transport: DebugSync.Transport())
        #else
        let store = await Store.open(directory: dataDirectory)
        #endif
        self.store = store
        nudges = SyncNudgeListener(store: store)
        applyConfig()
        startTriggers(store)
        widgetFeed = WidgetFeedWriter(store: store, windowVisible: { AppModel.hasVisibleWindow })
        widgetFeed?.start()
    }

    // MARK: Sync settings

    var syncConfig: SyncConfig? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host != nil,
              let token = UserDefaults.standard.string(forKey: Keys.syncToken) ?? Keychain.token(), !token.isEmpty else {
            return nil
        }
        #if DEBUG
        // Development builds only ever talk to a local `wrangler dev`, unless explicitly told otherwise.
        guard ["127.0.0.1", "localhost"].contains(url.host ?? "") || UserDefaults.standard.bool(forKey: "allowRemoteServer") else {
            return nil
        }
        #endif
        return SyncConfig(url: url, token: token)
    }

    func setToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { Keychain.deleteToken() } else { Keychain.setToken(t) }
        hasToken = !t.isEmpty
        applyConfig()
    }

    private func applyConfig() {
        let config = syncConfig
        store?.config = config
        nudges?.listen(server: config?.url)
    }

    // MARK: Open at login

    /// Registers or unregisters the app as a login item. macOS may ask the user to allow it in System Settings ▸
    /// General ▸ Login Items (`.requiresApproval`).
    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItem = SMAppService.mainApp.status
    }

    func refreshLoginItem() {
        let s = SMAppService.mainApp.status
        if s != loginItem { loginItem = s }
    }

    // MARK: Triggers

    /// One of the main windows is on screen (not closed, hidden with the app, or minimized).
    static var hasVisibleWindow: Bool { NSApp.windows.contains { $0.isVisible && $0.canBecomeMain } }

    private func startTriggers(_ store: Store) {
        store.requestSync(force: true) // launch
        // Every 30 s while a window is open; every 60 s with none unless Settings turns it off (spec §5, SyncSchedule).
        periodic = Task { [weak self, weak store] in
            var lastTick: TimeInterval?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SyncSchedule.tick))
                guard let self, let store else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if SyncSchedule.tickSyncs(windowVisible: Self.hasVisibleWindow, syncWithoutWindow: self.syncWithoutWindow,
                                          now: now, lastTick: lastTick) {
                    lastTick = now
                    store.requestSync()
                }
            }
        }
        let center = NotificationCenter.default
        let refreshDay: @Sendable (Notification) -> Void = { [weak store] _ in
            MainActor.assumeIsolated { store?.refreshDay() }
        }
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                store?.refreshDay()
                store?.requestSync(force: true)
                // A feed write held back while no window was open goes out now.
                self?.widgetFeed?.flush()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                store?.persistNow()
                // Leaving the app may uncover the desktop: what the feed writer is batching goes out now.
                self?.widgetFeed?.flush()
            }
        })
        // The window hidden, closed or minimized: the desktop's widgets show, so a write held for the 20 s gap goes now
        // (SyncSchedule). Any window's close or minimize does it; flushing with nothing waiting does nothing.
        let flushFeed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetFeed?.flush() }
        }
        observers.append(center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main, using: flushFeed))
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main, using: flushFeed))
        observers.append(center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main, using: flushFeed))
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                guard let store else { return }
                // What's being typed first: quitting never ends an edit by itself (docs/MAC-EDIT-DURABILITY.md).
                WindowActions.endAllEdits(store: store)
                store.persistNow()
                self?.widgetFeed?.flush()
            }
        })
    }
}

/// The sync token lives in the login Keychain (spec §7), never in defaults or files.
enum Keychain {
    /// "com.elguindi.Tasks.sync" for the app; Debug builds (com.elguindi.Tasks.dev) get their own item.
    private static let service = (Bundle.main.bundleIdentifier ?? "com.elguindi.Tasks") + ".sync"
    private static let account = "API_TOKEN"

    static func token() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String) {
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let data = Data(token.utf8)
        if SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Tasks sync token"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func deleteToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
