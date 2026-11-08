import Foundation

/// The poke socket's rules (design/PUSH-SYNC.md §3), pure so they're tested without sockets or timers
/// (`SocketPolicyTests`): when to reconnect after the socket closes, and how often the periodic sync still runs
/// alongside it. `SyncSocket` follows them.
///
/// - **Reconnecting:** 1 s after the first drop, doubling to a 5 min cap, each wait ±20% so that a deploy, which closes
///   every socket at once, doesn't bring every client back at the same moment. A connection that lasted a minute
///   resets the backoff. A wake from sleep or a network change resets it too (`reset`).
/// - **401** on the upgrade stops the socket until the token changes, as `Store`'s "Check sync token" does.
/// - **An old server** (404, 405 or 426 on the upgrade: no `/v1/events` yet) is tried again once an hour; the periodic
///   sync keeps today's pace meanwhile, so deploying the server and the apps can happen in any order.
/// - **Liveness:** a protocol ping every 30 s; no pong within 10 s counts as a drop.
/// - **The periodic sync** is a safety net while the socket is up (a lost poke, a half-open socket): every 5 min with a
///   window or in front, every 10 min with no window. While it's down, today's 30 s and 60 s.
public struct SocketPolicy: Sendable, Equatable {
    public static let firstDelay: Double = 1
    public static let maxDelay: Double = 300
    public static let jitter: Double = 0.2
    /// A connection that lasted this long resets the backoff.
    public static let stableAfter: Double = 60
    /// How long to wait before trying an old server's `/v1/events` again.
    public static let oldServerRetry: Double = 3600
    public static let pingInterval: Double = 30
    public static let pongDeadline: Double = 10

    /// Why the socket closed, from the upgrade's status or the connection.
    public enum Close: Sendable, Equatable {
        /// 401: the token was refused.
        case badToken
        /// 404, 405 or 426: the server has no `/v1/events`.
        case oldServer
        /// Anything else: a network error, a 5xx, a missed pong, the server going away (a deploy).
        case dropped

        /// The upgrade's HTTP status (nil: none, the connection failed or dropped).
        public init(status: Int?) {
            switch status {
            case 401: self = .badToken
            case 404, 405, 426: self = .oldServer
            default: self = .dropped
            }
        }
    }

    public enum Next: Sendable, Equatable {
        /// Connect again after this many seconds.
        case retry(after: Double)
        /// Don't, until the token changes.
        case stop
    }

    /// Drops since the last reset or stable connection.
    public private(set) var failures = 0
    /// When the current connection opened (its first message); nil when not connected.
    public private(set) var openedAt: Double?

    public init() {}

    /// The socket is connected (the server's first message arrived) at `now`.
    public mutating func opened(at now: Double) {
        openedAt = now
    }

    /// The socket closed (or never opened) at `now`. `random` is uniform in 0..<1, for the jitter.
    public mutating func closed(_ why: Close, at now: Double, random: Double) -> Next {
        if let openedAt, now - openedAt >= Self.stableAfter { failures = 0 }
        openedAt = nil
        switch why {
        case .badToken:
            return .stop
        case .oldServer:
            return .retry(after: Self.jittered(Self.oldServerRetry, random: random))
        case .dropped:
            let base = min(Self.firstDelay * pow(2, Double(min(failures, 30))), Self.maxDelay)
            failures += 1
            return .retry(after: Self.jittered(base, random: random))
        }
    }

    /// Back to the first delay: a wake, a network change, new settings, coming to the front.
    public mutating func reset() {
        failures = 0
        openedAt = nil
    }

    /// `delay` ±20%: `random` 0 gives −20%, 0.5 the delay itself, just under 1 just under +20%.
    public static func jittered(_ delay: Double, random: Double) -> Double {
        delay * (1 + jitter * (2 * min(max(random, 0), 1) - 1))
    }

    // MARK: The periodic sync

    /// Where the app is, for how often it syncs on its own and whether it holds the socket.
    public enum Presence: Sendable, Equatable {
        /// A window visible (the Mac), or in front (the iPhone).
        case front
        /// The Mac with no window visible and Settings ▸ Sync with no window open on.
        case windowless
        /// Nothing syncs periodically: the Mac with no window and that setting off, the iPhone in the background.
        case away
    }

    /// Whether to hold the socket: whenever the app syncs periodically at all.
    public static func holds(_ presence: Presence) -> Bool { presence != .away }

    /// How often the periodic sync runs, or nil for never.
    public static func pollInterval(_ presence: Presence, socketConnected: Bool) -> Double? {
        switch presence {
        case .front: socketConnected ? 300 : 30
        case .windowless: socketConnected ? 600 : 60
        case .away: nil
        }
    }

    /// Whether a periodic tick at `now` syncs. `lastPoll`: when a tick last synced (nil: none yet). A second's slack,
    /// since ticks drift a little: with a 30 s tick and a 30 s interval every tick syncs, with 60 s every other one.
    public static func pollDue(_ presence: Presence, socketConnected: Bool, now: Double, lastPoll: Double?) -> Bool {
        guard let interval = pollInterval(presence, socketConnected: socketConnected) else { return false }
        guard let lastPoll else { return true }
        return now - lastPoll >= interval - 1
    }
}
