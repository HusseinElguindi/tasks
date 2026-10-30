import AppKit
import Observation
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
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    var interfaceStyle: PaneInterfaceStyle {
        didSet { UserDefaults.standard.set(interfaceStyle == .glass ? "glass" : "classic", forKey: Keys.interfaceStyle) }
    }

    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    enum Keys {
        static let serverURL = "serverURL"
        static let theme = "theme"
        static let interfaceStyle = "interfaceStyle"
        /// Testing only: data directory and token from launch arguments (spec §10 end-to-end check).
        static let dataDirectory = "dataDirectory"
        static let syncToken = "syncToken"
    }

    init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: Keys.dataDirectory), !path.isEmpty {
            dataDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tasks", isDirectory: true)
        }
        serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        theme = ThemeChoice(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        interfaceStyle = defaults.string(forKey: Keys.interfaceStyle) == "glass" ? .glass : .classic
        hasToken = defaults.string(forKey: Keys.syncToken) != nil || Keychain.token() != nil
        Task { await load() }
    }

    private func load() async {
        let store = await Store.open(directory: dataDirectory)
        self.store = store
        applyConfig()
        startTriggers(store)
    }

    // MARK: Sync settings

    var syncConfig: SyncConfig? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host != nil,
              let token = UserDefaults.standard.string(forKey: Keys.syncToken) ?? Keychain.token(), !token.isEmpty else {
            return nil
        }
        return SyncConfig(url: url, token: token)
    }

    func setToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { Keychain.deleteToken() } else { Keychain.setToken(t) }
        hasToken = !t.isEmpty
        applyConfig()
    }

    private func applyConfig() {
        store?.config = syncConfig
    }

    // MARK: Triggers

    private func startTriggers(_ store: Store) {
        store.requestSync(force: true) // launch
        periodic = Task { [weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                // Every 30 s while a window is open (spec §5).
                if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { store?.requestSync() }
            }
        }
        let center = NotificationCenter.default
        let refreshDay: @Sendable (Notification) -> Void = { [weak store] _ in
            MainActor.assumeIsolated { store?.refreshDay() }
        }
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refreshDay))
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated {
                store?.refreshDay()
                store?.requestSync(force: true)
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.persistNow() }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.persistNow() }
        })
    }
}

/// The sync token lives in the login Keychain (spec §7), never in defaults or files.
enum Keychain {
    private static let service = "com.elguindi.Tasks.sync"
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
