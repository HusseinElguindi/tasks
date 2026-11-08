import Foundation
import notify
import TasksCore

/// The CLI's nudge (feedback item 14, spec §5 "Realtime") and the server's pokes (design/PUSH-SYNC.md): after a
/// command pushed ops, `tasks` posts a Darwin notification; after any device pushed, the server's `/v1/events` socket
/// (`SyncSocket`, held by `AppModel`) says the new head. Both go through one debounce (`SyncPokes`: 0.5 s after the
/// last, at most 5 s after the first), so a CLI command heard both ways, or a burst of them, is one sync. A poke at a
/// head the store already has (its own push, mostly) syncs nothing. Nothing shows on screen; the changes come through
/// `/v1/sync`.
///
/// Release listens for "com.elguindi.Tasks.changed"; Debug ("Tasks Dev") for its server's own name, so a scratch run
/// never pokes the installed app (`SyncNudge.name`).
@MainActor
final class SyncNudgeListener {
    private weak var store: Store?
    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private(set) var name: String?
    private let pokes: SyncPokes

    init(store: Store) {
        self.store = store
        pokes = SyncPokes(store: store)
        pokes.log = { [weak self] in self?.log($0) }
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
        log("nudge")
        pokes.nudge()
    }

    /// The socket's `{"head":N}`.
    func poked(head: Int) {
        log("poke head=\(head)")
        pokes.poke(head: head)
    }

    // MARK: Debug: `-debugNudgeLog <file>` appends each nudge and poke, the socket's states, each request and each
    // sync, with times.

    #if DEBUG
    private static let logURL: URL? = UserDefaults.standard.string(forKey: "debugNudgeLog").map { URL(fileURLWithPath: $0) }

    func log(_ s: String) {
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
    func log(_ s: String) {}
    #endif
}
