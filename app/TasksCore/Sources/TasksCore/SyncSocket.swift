import Foundation
import Network
import Observation

/// The poke socket (design/PUSH-SYNC.md): one WebSocket to the server's `GET /v1/events`, which says `{"head":N}` when
/// it connects and after every append. It carries no data; the app hands each head to `SyncPokes`, which syncs through
/// `/v1/sync` if the store is behind. `SocketPolicy` has the rules for reconnecting; this class runs them.
///
/// The app calls `update(config:hold:)` whenever the settings or its presence may have changed (repeating it costs
/// nothing), `suspend()` before the Mac sleeps and `reconnectNow()` after it wakes. A network change (`NWPathMonitor`)
/// reconnects at once on its own.
///
/// The Mac holds it while it syncs periodically at all, with a window or without (`SocketPolicy.holds`); the iPhone
/// only in front, as iOS suspends the app soon after it leaves.
///
/// It's observable for Settings ▸ Sync ▸ Live updates and the sync indicators (design/SYNC-STATUS.md, `LiveStatus`):
/// its state, why it's waiting, whether there's a network, and when the connection opened, dropped and last heard a
/// change.
@MainActor
@Observable
public final class SyncSocket {
    public enum State: Sendable, Equatable {
        /// No config, not held, or suspended.
        case off
        case connecting
        /// The server's first message arrived.
        case connected
        /// Waiting until then before connecting again, and why: a drop's backoff (`.dropped`) or an old server's
        /// hourly retry (`.oldServer`). A `Date`, so a countdown stays live.
        case waiting(until: Date, why: SocketPolicy.Close)
        /// 401: until the token changes.
        case stopped
    }

    public private(set) var state: State = .off {
        didSet { if state != oldValue { onState?(state) } }
    }

    public var isConnected: Bool { state == .connected }

    /// No network path (`NWPathMonitor` unsatisfied). False until the monitor says otherwise, and without one.
    public private(set) var offline = false
    /// When the current connection opened (its first message); nil while not connected.
    public private(set) var connectedAt: Date?
    /// When an open connection last dropped; nil once new settings, holding again or a sleep start over.
    public private(set) var droppedAt: Date?
    /// When a poke last moved the head: "the last time the server's data changed", heard live (your own edits too).
    /// Not the first message on connecting, which only says where the head is.
    public private(set) var lastChangeAt: Date?

    /// Each `{"head":N}` the server sends, the first one right after connecting.
    @ObservationIgnored public var onHead: ((Int) -> Void)?
    /// Each state change (the Mac's `-debugNudgeLog`).
    @ObservationIgnored public var onState: ((State) -> Void)?

    @ObservationIgnored private var config: SyncConfig?
    @ObservationIgnored private var hold = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var policy = SocketPolicy()
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    /// Bumped by every connect and teardown, so callbacks from an old task are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var receiver: Task<Void, Never>?
    @ObservationIgnored private var pinger: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    /// The head the current connection last said (nil before its first message).
    @ObservationIgnored private var lastHead: Int?
    private let session: URLSession
    private let uptime: @Sendable () -> Double
    private let random: @Sendable () -> Double
    private let clock: @Sendable () -> Date
    private let pingInterval: Double
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var path: PathSummary?

    /// `watchNetwork`: reconnect at once when the network comes back or changes (off in tests). `pingInterval`: shorter
    /// in tests. `clock`: the wall clock, for the published times.
    public init(session: URLSession? = nil, watchNetwork: Bool = true, pingInterval: Double = SocketPolicy.pingInterval,
                uptime: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        if let session {
            self.session = session
        } else {
            let c = URLSessionConfiguration.ephemeral
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            c.timeoutIntervalForRequest = 30
            c.waitsForConnectivity = false
            self.session = URLSession(configuration: c)
        }
        self.uptime = uptime
        self.random = random
        self.clock = clock
        self.pingInterval = pingInterval
        if watchNetwork { startMonitor() }
    }

    deinit {
        monitor?.cancel()
    }

    // MARK: What the app calls

    /// Holds the socket to `config` while `hold` is true; closes it otherwise. New settings (a new token after a 401)
    /// start again from the first delay, and so does `hold` turning on (the iPhone coming to the front).
    public func update(config: SyncConfig?, hold: Bool) {
        let changed = config != self.config
        let resumed = hold && !self.hold
        self.config = config
        self.hold = hold
        if changed {
            teardown()
            policy.reset()
            state = .off
            droppedAt = nil
            lastChangeAt = nil
        } else if resumed {
            policy.reset()
            droppedAt = nil
        }
        guard config != nil, hold, !suspended else {
            teardown()
            state = .off
            connectedAt = nil
            return
        }
        if state == .off { connect() }
    }

    /// Closes the socket until `reconnectNow` (the Mac going to sleep: a socket that lived through it is usually dead
    /// without knowing it).
    public func suspend() {
        suspended = true
        teardown()
        state = .off
        connectedAt = nil
        droppedAt = nil
    }

    /// Connects again now, skipping the backoff: after a wake, or a network change. A 401 stays stopped.
    public func reconnectNow() {
        suspended = false
        guard config != nil, hold, state != .stopped else { return }
        teardown()
        policy.reset()
        connect()
    }

    /// Sync Now (⌘R, pull to refresh): a wait, a drop's backoff or an old server's hour, is skipped and it connects
    /// now. A live connection, one being made, a refused token and a socket that isn't held are left alone.
    public func retryNow() {
        guard case .waiting = state, config != nil, hold, !suspended else { return }
        connect()
    }

    // MARK: The connection

    private func connect() {
        guard let config else { return }
        teardown()
        generation += 1
        let gen = generation
        var request = URLRequest(url: config.eventsURL)
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let t = session.webSocketTask(with: request)
        task = t
        lastHead = nil
        connectedAt = nil
        state = .connecting
        t.resume()
        receiver = Task { [weak self] in
            while true {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await t.receive()
                } catch {
                    let status = (t.response as? HTTPURLResponse)?.statusCode
                    self?.closed(gen, SocketPolicy.Close(status: status == 101 ? nil : status))
                    return
                }
                guard let self, gen == self.generation else { return }
                self.received(message)
            }
        }
    }

    private func received(_ message: URLSessionWebSocketTask.Message) {
        let data: Data? = switch message {
        case .string(let s): Data(s.utf8)
        case .data(let d): d
        @unknown default: nil
        }
        guard let data, let head = (try? JSONDecoder().decode(Poke.self, from: data))?.head else { return }
        if state != .connected {
            connectedAt = clock()
            state = .connected
            policy.opened(at: uptime())
            startPinging()
        } else if let lastHead, head != lastHead {
            lastChangeAt = clock()
        }
        lastHead = head
        onHead?(head)
    }

    private struct Poke: Decodable {
        var head: Int
    }

    private func closed(_ gen: Int, _ why: SocketPolicy.Close) {
        guard gen == generation else { return }
        teardown()
        if state == .connected { droppedAt = clock() }
        connectedAt = nil
        switch policy.closed(why, at: uptime(), random: random()) {
        case .stop:
            state = .stopped
        case .retry(let after):
            state = .waiting(until: clock().addingTimeInterval(after), why: why)
            let next = generation
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(after))
                guard !Task.isCancelled, let self, next == self.generation else { return }
                self.connect()
            }
        }
    }

    /// Pongs received on this connection (tests).
    @ObservationIgnored public private(set) var pongs = 0

    /// A protocol ping every 30 s; no pong within 10 s is a drop. The server's runtime answers without waking the DO.
    private func startPinging() {
        guard let t = task else { return }
        let gen = generation
        let interval = pingInterval
        pongs = 0
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                let ok = await Self.ping(t, deadline: SocketPolicy.pongDeadline)
                guard !Task.isCancelled, let self, gen == self.generation else { return }
                guard ok else {
                    self.closed(gen, .dropped)
                    return
                }
                self.pongs += 1
            }
        }
    }

    private nonisolated static func ping(_ t: URLSessionWebSocketTask, deadline: Double) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let once = Once(c)
            t.sendPing { error in once.resume(error == nil) }
            DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { once.resume(false) }
        }
    }

    /// Cancels the task and every timer. Bumps the generation so their callbacks do nothing.
    private func teardown() {
        generation += 1
        receiver?.cancel()
        receiver = nil
        pinger?.cancel()
        pinger = nil
        retry?.cancel()
        retry = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: The network

    private struct PathSummary: Equatable {
        var satisfied: Bool
        var interfaces: [String]
    }

    private func startMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] p in
            let summary = PathSummary(satisfied: p.status == .satisfied, interfaces: p.availableInterfaces.map(\.name))
            Task { @MainActor [weak self] in self?.pathChanged(summary) }
        }
        m.start(queue: DispatchQueue(label: "com.elguindi.Tasks.SyncSocket.path"))
        monitor = m
    }

    /// The network came back, or moved (Wi-Fi to Ethernet): the old connection is likely dead; connect now.
    private func pathChanged(_ new: PathSummary) {
        let old = path
        path = new
        if offline == new.satisfied { offline = !new.satisfied }
        guard let old, new.satisfied, new != old else { return }
        reconnectNow()
    }
}

extension SyncConfig {
    /// `GET {url}/v1/events` as a WebSocket URL (http → ws, https → wss).
    public var eventsURL: URL {
        var c = URLComponents(url: url.appendingPathComponent("v1").appendingPathComponent("events"),
                              resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme?.lowercased() == "http" ? "ws" : "wss"
        return c.url!
    }
}

/// Resumes a continuation once, whichever of the pong and the deadline comes first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ c: CheckedContinuation<Bool, Never>) { continuation = c }

    func resume(_ value: Bool) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

/// Turns the server's pokes and the CLI's nudges into syncs (design/PUSH-SYNC.md §3), through one debounce
/// (`SyncNudge.Debounce`: 0.5 s after the last, at most 5 s after the first), so a burst of CLI commands, heard by
/// both the nudge and the socket, is one sync. When it fires it waits for any sync in flight, then syncs unless the
/// store's cursor is already at the poked head (the writer's own poke, mostly). A nudge carries no head, so it always
/// syncs. A head below the cursor means the server lost entries (a restore); that syncs too, and the 409 recovers.
@MainActor
public final class SyncPokes {
    private weak var store: Store?
    private var debounce: SyncNudge.Debounce
    private var timer: Task<Void, Never>?
    private var head: Int?
    private var always = false
    private let uptime: @Sendable () -> Double
    /// "sync requested" or "up to date" each time it fires (the Mac's `-debugNudgeLog`).
    public var log: ((String) -> Void)?

    public init(store: Store, debounce: SyncNudge.Debounce = SyncNudge.Debounce(),
                uptime: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.debounce = debounce
        self.uptime = uptime
    }

    /// The CLI's Darwin nudge: sync, whatever the cursor.
    public func nudge() {
        always = true
        schedule()
    }

    /// The server's head, from the socket.
    public func poke(head n: Int) {
        head = max(head ?? n, n)
        schedule()
    }

    private func schedule() {
        let now = uptime()
        let at = debounce.nudge(at: now)
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, at - now)))
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
    }

    /// The debounce ran out. Internal so tests can run it without waiting.
    func fire() async {
        timer = nil
        debounce.fired()
        let target = always ? nil : head
        head = nil
        always = false
        guard let store else { return }
        log?(await store.syncIfBehind(head: target) ? "sync requested" : "up to date")
    }
}
