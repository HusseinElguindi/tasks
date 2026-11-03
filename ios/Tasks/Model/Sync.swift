import Foundation
import Security
import TasksCore

/// The sync token lives in the Keychain (spec §7), never in defaults or files: a generic password, service the bundle
/// id + ".sync", account "API_TOKEN", as the Mac app keeps it (app/Tasks/AppModel.swift `Keychain`).
enum Keychain {
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
            // Readable once the phone has been unlocked after a restart, never copied to another device.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func deleteToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// Sync: TasksCore's Store syncs on its own once it has a `SyncConfig` (about a second after each change, with its
/// backoff and recovery). This sets the config from Settings and triggers it the Mac's way: at launch, on coming to
/// the front, every 30 s while in front, and on pull to refresh (the Mac's ⌘R). No background sync.
extension AppModel {
    /// The Worker the app syncs with unless Settings says otherwise.
    static let defaultServer = "https://tasks.elguindi.workers.dev"

    enum SyncKeys {
        static let serverURL = "serverURL"
        /// Testing only, Debug builds only: a token from the launch arguments (a local `wrangler dev`'s throwaway one).
        static let syncToken = "syncToken"
        static let allowRemoteServer = "allowRemoteServer"
    }

    /// The server and token, if both are set. Debug builds only talk to a local `wrangler dev` (localhost or
    /// 127.0.0.1) unless the `allowRemoteServer` default is set, as the Mac's do; the sample data never syncs.
    var syncConfig: SyncConfig? {
        guard !isSample else { return nil }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host != nil else { return nil }
        #if DEBUG
        let token = UserDefaults.standard.string(forKey: SyncKeys.syncToken) ?? Keychain.token()
        guard ["127.0.0.1", "localhost"].contains(url.host ?? "") || UserDefaults.standard.bool(forKey: SyncKeys.allowRemoteServer) else {
            return nil
        }
        #else
        let token = Keychain.token()
        #endif
        guard let token, !token.isEmpty else { return nil }
        return SyncConfig(url: url, token: token)
    }

    func setToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { Keychain.deleteToken() } else { Keychain.setToken(t) }
        hasToken = !t.isEmpty
        applyConfig()
    }

    /// Hands the Store its config; a change (or the first one) syncs at once.
    func applyConfig() {
        let config = syncConfig
        if store.config != config { store.config = config }
    }

    /// At launch: the config, then a sync every 30 s while the app is in front (spec §5).
    func startSync() {
        applyConfig()
        store.requestSync(force: true)
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                if self.inFront { self.store.requestSync() }
            }
        }
    }

    /// Coming to the front: the day may have changed, and the server may have news.
    func cameToFront() {
        inFront = true
        store.refreshDay()
        store.requestSync(force: true)
    }

    /// Pull to refresh, the Mac's ⌘R: a sync now, clearing a stopped state or a backoff, and wait for it.
    func syncNow() async {
        guard store.config != nil else { return }
        store.requestSync(force: true)
        store.cancelScheduledSync()
        await store.sync()
    }

    // MARK: What it says

    /// A short line for the home screen, nil while sync is off (the Mac's indicator, §26, in words).
    var syncSummary: String? {
        let n = store.pendingCount
        let changes = n == 1 ? "1 change" : "\(n.formatted()) changes"
        if let r = store.recovery { return "Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())" }
        switch store.syncState {
        case .off: return nil
        case .syncing: return n > 0 ? "Syncing · \(changes) waiting" : "Syncing…"
        case .idle(let at):
            if n > 0 { return "\(changes) waiting" }
            return at.map { "Synced " + Self.ago($0, now: Date()) } ?? "Synced"
        case .retrying(_, let reason):
            if let code = Self.httpStatus(reason) { return "The server isn’t answering (\(code))" }
            return n > 0 ? "Can’t reach the server · \(changes) waiting" : "Can’t reach the server"
        case .checkToken: return "The server didn’t accept the token"
        case .failed: return n > 0 ? "Sync stopped · \(changes) waiting" : "Sync stopped"
        }
    }

    /// What VoiceOver says as sync stops or the server refuses the token, once on the way in (the Mac's
    /// `SyncIndicator.announce`, §26); nil in every other state.
    var syncStoppedWords: String? {
        switch store.syncState {
        case .failed(let m): m.isEmpty ? "Sync stopped" : "Sync stopped. " + m
        case .checkToken: "Sync stopped. The server didn’t accept the token"
        default: nil
        }
    }

    /// Settings' status line (the Mac's Settings ▸ Sync ▸ Status).
    var syncStatus: String {
        if let r = store.recovery { return "Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())" }
        let n = store.pendingCount
        let waiting = n == 0 ? "" : n == 1 ? " 1 change waiting." : " \(n.formatted()) changes waiting."
        switch store.syncState {
        case .off:
            if isSample { return "Off: this is the sample data." }
            #if DEBUG
            if syncConfig == nil, hasToken || UserDefaults.standard.string(forKey: SyncKeys.syncToken) != nil {
                return "Off. Debug builds sync only with a local server (localhost)."
            }
            #endif
            return "Off. Set the server URL and token."
        case .syncing: return "Syncing…" + waiting
        case .idle(let at): return (at.map { "Up to date, \($0.formatted(date: .omitted, time: .shortened))." } ?? "Up to date.") + waiting
        case .retrying(let at, let reason):
            let why = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            return "Can't reach the server (\(why)). Retrying \(at.formatted(.relative(presentation: .named)))." + waiting
        case .checkToken: return "The server rejected the token. Check it and save again."
        case .failed(let message): return "Sync stopped: \(message)" + waiting
        }
    }

    /// "just now" under a minute, "N min ago" under an hour, then "at 9:41", then "yesterday at 9:41" (the Mac's).
    static func ago(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDate(d, inSameDayAs: now) { return "at " + time }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) { return "yesterday at " + time }
        return d.formatted(.dateTime.month(.abbreviated).day()) + " at " + time
    }

    /// "HTTP 503" → 503: a server error, not the network.
    private static func httpStatus(_ reason: String) -> Int? {
        guard reason.hasPrefix("HTTP ") else { return nil }
        return Int(reason.dropFirst(5))
    }
}
