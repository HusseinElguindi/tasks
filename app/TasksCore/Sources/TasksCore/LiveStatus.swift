import Foundation

/// Settings ▸ Sync ▸ Live updates and the sync indicators' live cloud (design/SYNC-STATUS.md): what the poke socket
/// (`SyncSocket`) is doing, in a dot, a word and a line, on the Mac and the iPhone. Pure, so it's tested without
/// sockets or timers (`LiveStatusTests`).
///
/// Push being down never loses data (the periodic sync goes back to every 30 s, or every minute on a windowless Mac),
/// so nothing here is an error except a refused token.
public struct LiveStatus: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The server's first message arrived.
        case live
        /// The first try, after a wake, a network change or coming to the front.
        case connecting
        /// A drop (or a failed try): waiting out the backoff until then.
        case reconnecting(at: Date)
        /// No network path.
        case offline
        /// An old server (no `/v1/events`): tried again at then, hourly.
        case notAvailable(retryAt: Date)
        /// 401 on the upgrade, until the token changes.
        case rejected
        /// Not held: the Mac with no window and Sync with no window open off; the iPhone in the background.
        case off
    }

    /// The dot before the word: 7pt on the Mac, 8pt on the iPhone.
    public enum Dot: Sendable, Equatable {
        /// Filled, `list-green`: the only green in the app's chrome.
        case live
        /// A 1.5pt ring in `ink-tertiary`.
        case ring
        /// A 1.5pt ring in `ink-quiet`.
        case quietRing
        /// Filled, `ink-quiet`.
        case quiet
        /// Filled, `attention`; the word is in `attention` too.
        case attention
    }

    public enum Device: Sendable, Equatable {
        /// `syncWithoutWindow`: Settings ▸ Sync with no window open.
        case mac(syncWithoutWindow: Bool)
        case iPhone
    }

    /// What the socket says at a moment (`SyncSocket.liveInput`).
    public struct Input: Sendable, Equatable {
        public var state: SyncSocket.State
        public var offline: Bool
        public var droppedAt: Date?
        public var lastChangeAt: Date?

        public init(state: SyncSocket.State, offline: Bool = false, droppedAt: Date? = nil, lastChangeAt: Date? = nil) {
            self.state = state
            self.offline = offline
            self.droppedAt = droppedAt
            self.lastChangeAt = lastChangeAt
        }
    }

    public var kind: Kind
    public var dot: Dot
    /// On the right of the row: "Live", "Reconnecting in 8 s".
    public var word: String
    /// Under the title.
    public var detail: String
    /// VoiceOver's value for the row (its label is "Live updates"): the word and the detail, with units in words.
    public var spoken: String

    /// The row's title, on both devices.
    public static let title = "Live updates"

    /// `pace`: how often the periodic sync runs while the socket is down (`pace(for:)`): 30 s with a window or in
    /// front, 60 on a windowless Mac.
    public init(_ input: Input, device: Device, pace: Double, now: Date, calendar: Calendar = .current) {
        let kind = Self.kind(input)
        self.kind = kind
        let mac: Bool
        let withoutWindow: Bool
        switch device {
        case .mac(let on): mac = true; withoutWindow = on
        case .iPhone: mac = false; withoutWindow = false
        }
        func checking(_ spoken: Bool) -> String { "Checking " + Self.pace(pace, spoken: spoken) }
        var word: String, spokenWord: String
        var detail: (Bool) -> String
        switch kind {
        case .live:
            dot = .live
            word = "Live"; spokenWord = word
            detail = { spoken in
                if mac, !withoutWindow {
                    return "Changes from your other devices arrive within seconds, until you close the last window."
                }
                var d = "Changes from your other devices arrive within seconds" + (mac ? "." : " while Tasks is open.")
                if let last = input.lastChangeAt {
                    d += " Last one " + Self.ago(last, now: now, spoken: spoken, calendar: calendar) + "."
                }
                return d
            }
        case .connecting:
            dot = .ring
            word = "Connecting…"; spokenWord = "Connecting"
            detail = { checking($0) + " until it connects." }
        case .reconnecting(let at):
            dot = .ring
            let lost = input.droppedAt.map { "Lost the connection " + Self.at($0, now: now, calendar: calendar) + "." }
                ?? "Couldn't connect."
            if mac {
                word = "Reconnecting in " + Self.countdown(to: at, now: now, spoken: false)
                spokenWord = "Reconnecting in " + Self.countdown(to: at, now: now, spoken: true)
                detail = { lost + " " + checking($0) + " meanwhile." }
            } else {
                // The iPhone's word has less room: the countdown goes in the detail.
                word = "Reconnecting"; spokenWord = word
                detail = { spoken in
                    lost + " Trying again in " + Self.countdown(to: at, now: now, spoken: spoken) + "; "
                        + checking(spoken).lowercased() + " meanwhile."
                }
            }
        case .offline:
            dot = .quiet
            word = "Offline"; spokenWord = word
            detail = { _ in "No network. Reconnects as soon as it's back." }
        case .notAvailable(let at):
            dot = .quiet
            word = "Not available"; spokenWord = word
            detail = { spoken in
                "This server doesn't have them yet. " + checking(spoken) + "; trying again "
                    + Self.at(at, now: now, calendar: calendar) + "."
            }
        case .rejected:
            dot = .attention
            word = mac ? "Token rejected" : "Rejected"; spokenWord = "Token rejected"
            detail = { _ in "The server didn't accept the token. Save it again above." }
        case .off:
            dot = .quietRing
            word = "Off"; spokenWord = word
            detail = { _ in
                mac ? "Only while a window is open. Turn on Sync with no window open to keep them."
                    : "Only while Tasks is open. In the background, Background refresh takes over."
            }
        }
        self.word = word
        self.detail = detail(false)
        spoken = spokenWord + ". " + detail(true)
    }

    /// The state the row shows. No network wins over connecting and waiting, since those can't succeed then.
    public static func kind(_ input: Input) -> Kind {
        switch input.state {
        case .connected: .live
        case .stopped: .rejected
        case .off: .off
        case .connecting: input.offline ? .offline : .connecting
        case .waiting(let until, let why):
            input.offline ? .offline : why == .oldServer ? .notAvailable(retryAt: until) : .reconnecting(at: until)
        }
    }

    /// How often the periodic sync runs while the socket is down: 30 s with a window or in front, 60 s on a windowless
    /// Mac (`SocketPolicy.pollInterval`).
    public static func pace(for presence: SocketPolicy.Presence) -> Double {
        SocketPolicy.pollInterval(presence, socketConnected: false) ?? SocketPolicy.pollInterval(.front, socketConnected: false)!
    }

    // MARK: The indicators

    /// The second line of the Mac's Synced tooltip (§26 option C), with `live` from `LiveGlyph`: "Live", or how often
    /// it checks instead.
    public static func tipLine(live: Bool, pace: Double, spoken: Bool = false) -> String {
        live ? "Live" : "Checking " + Self.pace(pace, spoken: spoken)
    }

    /// The bolt cloud while live, the plain cloud while not (the Mac's hovered Synced cloud, the iPhone's sync line).
    public static func symbol(live: Bool) -> String { live ? "bolt.horizontal.icloud" : "icloud" }

    // MARK: Words

    /// "every 30 s", "every minute", "every 5 min"; spoken: "every 30 seconds".
    public static func pace(_ seconds: Double, spoken: Bool = false) -> String {
        let s = max(1, Int(seconds.rounded()))
        if s == 60 { return "every minute" }
        if s % 60 == 0 { return "every \(s / 60)" + (spoken ? " minutes" : " min") }
        return "every \(s)" + (spoken ? " seconds" : " s")
    }

    /// "8 s" under a minute, then "4 min", rounded up, at least 1; spoken: "8 seconds", "1 minute".
    public static func countdown(to d: Date, now: Date, spoken: Bool = false) -> String {
        let s = max(1, Int(d.timeIntervalSince(now).rounded(.up)))
        if s < 60 { return spoken ? (s == 1 ? "1 second" : "\(s) seconds") : "\(s) s" }
        let m = Int((Double(s) / 60).rounded(.up))
        return spoken ? (m == 1 ? "1 minute" : "\(m) minutes") : "\(m) min"
    }

    /// "at 9:38 AM" today, "yesterday at 9:38 AM", "tomorrow at 12:20 AM", else "on Nov 7 at 9:38 AM".
    public static func at(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = "at " + d.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(d, inSameDayAs: now) { return time }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "yesterday " + time }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) { return "tomorrow " + time }
        return "on " + d.formatted(.dateTime.month(.abbreviated).day()) + " " + time
    }

    /// "just now" under a minute, "N min ago" under an hour, then "at 9:41", then "yesterday at 9:41", then "Nov 7 at
    /// 9:41" (the Mac's §26 tooltip and the iPhone's sync line say times this way).
    public static func ago(_ d: Date, now: Date, spoken: Bool = false, calendar: Calendar = .current) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { let m = Int(s / 60); return spoken ? (m == 1 ? "1 minute ago" : "\(m) minutes ago") : "\(m) min ago" }
        let time = d.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(d, inSameDayAs: now) { return "at " + time }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "yesterday at " + time }
        return d.formatted(.dateTime.month(.abbreviated).day()) + " at " + time
    }
}

/// The live cloud's 5 s rule (design/SYNC-STATUS.md §3): the bolt shows once the socket is connected, the plain cloud
/// only once it has been down for 5 s, so a reconnect (a wake, a network change, coming to the front) doesn't flip it.
/// Until then it keeps what it showed; at first, the plain cloud.
public struct LiveGlyph: Sendable, Equatable {
    public static let downAfter: Double = 5

    /// Show the bolt cloud.
    public private(set) var live = false
    private var downSince: Double?

    public init() {}

    /// The socket is connected or not at `now` (any clock in seconds). Returns when to call again, as the 5 s run out,
    /// or nil.
    @discardableResult
    public mutating func update(connected: Bool, now: Double) -> Double? {
        if connected {
            live = true
            downSince = nil
            return nil
        }
        guard live else { return nil }
        let since = downSince ?? now
        downSince = since
        if now - since >= Self.downAfter {
            live = false
            downSince = nil
            return nil
        }
        return since + Self.downAfter
    }
}

extension SyncSocket {
    /// What `LiveStatus` reads, as of now.
    public var liveInput: LiveStatus.Input {
        LiveStatus.Input(state: state, offline: offline, droppedAt: droppedAt, lastChangeAt: lastChangeAt)
    }
}
