import Foundation
import notify
import TasksCore

/// The CLI's nudge (feedback item 14, spec §5 "Realtime"): after a command pushed ops, `tasks` posts a Darwin
/// notification, and the app runs its normal sync at once instead of at its next 30 s tick. A burst of commands is one
/// sync (`SyncNudge.Debounce`: 0.5 s after the last nudge, at most 5 s after the first); a nudge during a sync asks the
/// store for one more pass after it (`Store.sync`). Nothing shows on screen; the changes come through `/v1/sync`.
///
/// Release listens for "com.elguindi.Tasks.changed"; Debug ("Tasks Dev") for its server's own name, so a scratch run
/// never pokes the installed app (`SyncNudge.name`).
@MainActor
final class SyncNudgeListener {
    private weak var store: Store?
    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private(set) var name: String?
    private var debounce = SyncNudge.Debounce()
    private var pending: DispatchWorkItem?

    init(store: Store) {
        self.store = store
        #if DEBUG
        watch()
        #endif
    }

    /// Listens for `server`'s name; nil (sync off) listens for nothing. Called whenever the sync settings change.
    func listen(server: URL?) {
        let n = server.map { SyncNudge.name(server: $0) }
        guard n != name else { return }
        if token != NOTIFY_TOKEN_INVALID {
            notify_cancel(token)
            token = NOTIFY_TOKEN_INVALID
        }
        name = n
        guard let n else { return }
        notify_register_dispatch(n, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.nudged() }
        }
        log("listening \(n)")
    }

    private func nudged() {
        let now = ProcessInfo.processInfo.systemUptime
        let at = debounce.nudge(at: now)
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, at - now), execute: work)
        log("nudge")
    }

    private func fire() {
        pending = nil
        debounce.fired()
        log("sync requested")
        store?.requestSync()
    }

    // MARK: Debug: `-debugNudgeLog <file>` appends each nudge, each request and each sync, with times.

    #if DEBUG
    private static let logURL: URL? = UserDefaults.standard.string(forKey: "debugNudgeLog").map { URL(fileURLWithPath: $0) }

    private func log(_ s: String) {
        guard let url = Self.logURL else { return }
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, s)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Logs every sync state change and the cursor it ends at: a sync is one "syncing".
    private func watch() {
        guard Self.logURL != nil, let store else { return }
        withObservationTracking {
            _ = store.syncState
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let store = self.store else { return }
                    let state: String = switch store.syncState {
                    case .syncing: "syncing"
                    case .idle: "idle"
                    case .off: "off"
                    case .retrying: "retrying"
                    case .checkToken: "checkToken"
                    case .failed(let m): "failed \(m)"
                    }
                    self.log("state \(state) cursor=\(store.cursor) tasks=\(store.projection.allTaskIDs.count)")
                    self.watch()
                }
            }
        }
    }
    #else
    private func log(_ s: String) {}
    #endif
}
