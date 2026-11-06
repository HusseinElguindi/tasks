import Foundation
import notify

/// The CLI's nudge to the app (spec §5 "Realtime"): after a command has pushed ops, the CLI posts a Darwin
/// notification and the app syncs at once instead of at its next 30 s tick. It carries no data; the changes still
/// come through `/v1/sync`.
public enum SyncNudge {
    /// Release builds of the app and the CLI.
    public static let base = "com.elguindi.Tasks.changed"

    /// The name for a server. Release builds use `base`. Debug builds (the scratch "Tasks Dev" app, a `swift build`
    /// CLI) add `.dev.` and a hash of the server's origin, so a test run against a `wrangler dev` reaches only the Debug
    /// apps on that same server and never the installed app. The server is what the two share: the CLI's replica and
    /// the app's data folder are different directories.
    public static func name(server: URL?) -> String {
        #if DEBUG
        name(server: server, debug: true)
        #else
        name(server: server, debug: false)
        #endif
    }

    public static func name(server: URL?, debug: Bool) -> String {
        guard debug else { return base }
        return base + ".dev." + hash(origin(server))
    }

    /// `scheme://host:port`, lowercased, the port spelled out: the same server however its URL is written.
    static func origin(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return "none" }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    /// FNV-1a 32 over the UTF-8 bytes, as 8 hex digits: stable across processes (unlike `hashValue`).
    static func hash(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 {
            h ^= UInt32(b)
            h = h &* 16_777_619
        }
        return String(format: "%08x", h)
    }

    /// Posts the nudge for `server` (the CLI, after a push succeeded).
    public static func post(server: URL?) {
        notify_post(name(server: server))
    }

    /// When to sync after nudges: `quiet` after the last one, but no later than `cap` after the first of a burst, so a
    /// burst of CLI commands is one sync and a long one still syncs now and then. Pure, so it's tested without timers.
    public struct Debounce: Sendable {
        public var quiet: Double
        public var cap: Double
        private var burstStart: Double?

        public init(quiet: Double = 0.5, cap: Double = 5) {
            self.quiet = quiet
            self.cap = cap
        }

        /// A nudge at `now`: the time the sync should run (the caller reschedules its one timer to it).
        public mutating func nudge(at now: Double) -> Double {
            let start = burstStart ?? now
            burstStart = start
            return min(now + quiet, start + cap)
        }

        /// The timer fired and the sync was asked for: the next nudge starts a new burst.
        public mutating func fired() { burstStart = nil }
    }
}

/// The widget's nudge to the app (design/WIDGETS.md §2.1): after a widget's intent appended to `WidgetInbox`, it posts
/// this Darwin notification and a running app drains the inbox at once. It carries no data. Debug builds add `.dev`, as
/// their files live in `WidgetFolder`'s `Tasks Dev`, so the scratch app never drains for the installed one's widget.
public enum WidgetNudge {
    /// Release builds of the app and its widgets.
    public static let base = "com.elguindi.Tasks.widget"

    /// The name for this build: `base`, or `base + ".dev"` when TasksCore is built with `DEBUG`.
    public static var name: String {
        #if DEBUG
        name(debug: true)
        #else
        name(debug: false)
        #endif
    }

    public static func name(debug: Bool) -> String { debug ? base + ".dev" : base }

    /// Posts the nudge (the widget's intent, after its append).
    public static func post() {
        notify_post(name)
    }
}
