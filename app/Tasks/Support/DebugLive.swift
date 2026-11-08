#if DEBUG
import Foundation
import TasksCore

/// Debug aid: `-debugLive live|connecting|reconnecting|offline|unavailable|rejected|off` stands in for the poke
/// socket in Settings ▸ Sync ▸ Live updates and the sync cloud (design/SYNC-STATUS.md), without a server, for
/// screenshots (`-snapshotSettings`). Times are as of each read: the last change 2 min ago, a drop 3 min ago, the
/// reconnect in 8 s, an old server's retry in 58 min.
enum DebugLive {
    static func input(now: Date = Date()) -> LiveStatus.Input? {
        guard let s = UserDefaults.standard.string(forKey: "debugLive") else { return nil }
        switch s {
        case "live": return .init(state: .connected, lastChangeAt: now - 120)
        case "connecting": return .init(state: .connecting)
        case "reconnecting": return .init(state: .waiting(until: now + 7.5, why: .dropped), droppedAt: now - 180)
        case "offline": return .init(state: .waiting(until: now + 30, why: .dropped), offline: true, droppedAt: now - 180)
        case "unavailable": return .init(state: .waiting(until: now + 58 * 60, why: .oldServer))
        case "rejected": return .init(state: .stopped)
        case "off": return .init(state: .off)
        default: return nil
        }
    }
}
#endif
