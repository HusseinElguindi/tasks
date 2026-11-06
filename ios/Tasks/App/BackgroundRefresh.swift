import BackgroundTasks
import Foundation
import os
import TasksCore

// Background refresh (T42, T43): now and then, while the app is closed, iOS wakes it for about 30 s. It opens the one
// store, syncs once, writes the widgets' feed (which reloads them if it changed), saves, and asks for the next wake.
// iOS decides when (hours apart, never after a swipe-away, in Low Power Mode, or with Background App Refresh off).
// Info.plist only (UIBackgroundModes fetch, BGTaskSchedulerPermittedIdentifiers in project.yml); no entitlement.

/// The one AppModel both the scene and a background launch use, opened once: two Stores on one folder would be a bug.
@MainActor
enum SharedApp {
    private static var opening: Task<AppModel, Never>?

    static func open() async -> AppModel {
        if let opening { return await opening.value }
        let t = Task { @MainActor in await Launch.open() }
        opening = t
        return await t.value
    }
}

/// What the handler needs of a `BGAppRefreshTask`; tests hand it a fake.
protocol RefreshTask: AnyObject {
    /// Called by the system, on a queue of its own, when the time is up.
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: RefreshTask {}

/// What it needs of `BGTaskScheduler`.
protocol RefreshScheduler {
    func submit(_ taskRequest: BGTaskRequest) throws
    func cancel(taskRequestWithIdentifier identifier: String)
}

extension BGTaskScheduler: RefreshScheduler {}

@MainActor
final class BackgroundRefresh {
    static let identifier = "com.elguindi.Tasks.refresh"
    /// The soonest the next one may run. Only a lower bound: iOS picks the time, usually hours later.
    static let interval: TimeInterval = 15 * 60
    static let shared = BackgroundRefresh()
    nonisolated static let logger = Logger(subsystem: "com.elguindi.Tasks", category: "background-refresh")

    let history: RefreshHistory
    private let scheduler: RefreshScheduler
    private let open: @MainActor () async -> AppModel
    /// The server and token, as a foreground sync takes them (`AppModel.syncConfig`); nil means no sync.
    private let config: @MainActor (AppModel) -> SyncConfig?
    private let now: () -> Date

    /// The run in progress, so expiry can end it.
    private struct Running {
        let id: UUID
        let task: RefreshTask
        let start: Date
        var app: AppModel?
        var cursor = 0
    }
    private var running: Running?

    init(scheduler: RefreshScheduler = BGTaskScheduler.shared, history: RefreshHistory = RefreshHistory(),
         open: @escaping @MainActor () async -> AppModel = { await SharedApp.open() },
         config: @escaping @MainActor (AppModel) -> SyncConfig? = { $0.syncConfig },
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.history = history
        self.open = open
        self.config = config
        self.now = now
    }

    /// At launch (TasksApp's init): iOS calls this on the main queue when it wakes the app for a refresh.
    func register() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                let t = UnsafeTask(task)
                Task { @MainActor in await BackgroundRefresh.shared.handle(t.task) }
            }
        }
        if !ok { Self.logger.error("register failed") }
    }

    /// Going to the background, and at the end of each run: the next request (one at a time; a new one replaces
    /// it). None for the sample data or without a server and token, and any waiting one is dropped.
    func schedule(for app: AppModel) {
        guard !app.isSample, config(app) != nil else {
            scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = now().addingTimeInterval(Self.interval)
        do {
            try scheduler.submit(request)
            history.noteSubmit(error: nil)
        } catch {
            // `.unavailable`: Background App Refresh is off for Tasks, or Low Power Mode is on (or the simulator).
            Self.logger.notice("submit failed: \(String(describing: error), privacy: .public)")
            history.noteSubmit(error: (error as? BGTaskScheduler.Error)?.code == .unavailable
                ? "Background App Refresh is off for Tasks (or Low Power Mode is on)" : error.localizedDescription)
        }
    }

    /// The refresh: the shared store, one sync, the feed (and a reload if it changed), a save, the next request.
    /// Expiry ends it at once (`expire`); the sync carries on if the app gets more time, as any sync does.
    func handle(_ task: RefreshTask) async {
        let id = UUID()
        running = Running(id: id, task: task, start: now())
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire(id) }
        }
        let app = await open()
        guard running?.id == id else { return }
        running?.app = app
        guard !app.isSample, let config = config(app) else {
            finish(id, .skipped(app.isSample ? "sample data" : "sync is off"), entries: 0, feed: nil)
            return
        }
        let store = app.store
        store.refreshDay()
        if store.config != config { store.config = config }
        // The config's own trigger (or the scene's launch sync) would run beside this one; this is the one pass.
        store.cancelScheduledSync()
        let before = store.cursor
        running?.cursor = before
        await store.sync()
        guard running?.id == id else { return }
        let entries = max(0, store.cursor - before)
        let wrote = (app.widgetFeed ?? WidgetFeedWriter(store: store, isSample: app.isSample))?.writeNow()
        store.persistNow()
        let outcome: RefreshHistory.Outcome = switch store.syncState {
        case .idle: .ok
        case .off: .error("sync is off")
        case .syncing: .error("still syncing")
        case .retrying(_, let reason): .error("can't reach the server: \(reason)")
        case .checkToken: .error("the server rejected the token")
        case .failed(let m): .error("sync stopped: \(m)")
        }
        finish(id, outcome, entries: entries, feed: wrote)
    }

    /// The system's time is up: save what came, ask for the next one, and end the task now.
    private func expire(_ id: UUID) {
        guard let r = running, r.id == id else { return }
        if let store = r.app?.store {
            store.cancelScheduledSync()
            store.persistNow()
        }
        let entries = r.app.map { max(0, $0.store.cursor - r.cursor) } ?? 0
        finish(id, .expired, entries: entries, feed: nil)
    }

    private func finish(_ id: UUID, _ outcome: RefreshHistory.Outcome, entries: Int, feed: Bool?) {
        guard let r = running, r.id == id else { return }
        running = nil
        let end = now()
        history.record(.init(start: r.start, end: end, outcome: outcome, entries: entries, feed: feed))
        Self.logger.notice("\(outcome.text, privacy: .public), \(entries) entries, \(end.timeIntervalSince(r.start), format: .fixed(precision: 3)) s")
        if let app = r.app { schedule(for: app) }
        r.task.expirationHandler = nil
        r.task.setTaskCompleted(success: outcome.succeeded)
    }

    /// Carries the system's task from its launch handler onto the main actor (both run on the main queue).
    private struct UnsafeTask: @unchecked Sendable {
        let task: BGTask
        init(_ task: BGTask) { self.task = task }
    }
}

/// Each run, in a small rolling log the user can copy off the phone, and the count and last run Settings shows. In the
/// app's own container (`Documents/`), not the App Group (devicectl can't read that) and not UserDefaults:
///   Documents/background-refresh.log    the last 200 runs, one line each
///   Documents/background-refresh.json   the count, since when, the last run, the last submit's refusal
final class RefreshHistory: @unchecked Sendable {
    static let maxLines = 200

    enum Outcome: Codable, Equatable {
        case ok
        case error(String)
        case expired
        case skipped(String)

        var succeeded: Bool {
            switch self {
            case .ok, .skipped: true
            case .error, .expired: false
            }
        }

        var text: String {
            switch self {
            case .ok: "ok"
            case .error(let m): "error: " + m
            case .expired: "expired (iOS's time ran out)"
            case .skipped(let why): "skipped: " + why
            }
        }
    }

    struct Run: Codable, Equatable {
        var start: Date
        var end: Date
        var outcome: Outcome
        var entries: Int
        /// Whether the feed changed (and the widgets reloaded); nil when it wasn't written.
        var feed: Bool?
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    struct Summary: Codable, Equatable {
        var runs = 0
        var since: Date?
        var last: Run?
        /// Why iOS refused the last request, if it did.
        var submitError: String?
    }

    let logURL: URL
    let summaryURL: URL
    private let lock = NSLock()

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        logURL = directory.appendingPathComponent("background-refresh.log")
        summaryURL = directory.appendingPathComponent("background-refresh.json")
    }

    var summary: Summary {
        lock.withLock { readSummary() }
    }

    func record(_ run: Run) {
        lock.withLock {
            var s = readSummary()
            s.runs += 1
            if s.since == nil { s.since = run.start }
            s.last = run
            writeSummary(s)
            appendLine(Self.line(run))
        }
    }

    func noteSubmit(error: String?) {
        lock.withLock {
            var s = readSummary()
            guard s.submitError != error else { return }
            s.submitError = error
            writeSummary(s)
        }
    }

    /// `2026-11-06T04:40:59.870-05:00  end 04:41:00.290  0.420 s  ok  entries 3  feed changed`
    static func line(_ r: Run) -> String {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        full.timeZone = .current
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = .current
        time.dateFormat = "HH:mm:ss.SSS"
        let feed = r.feed.map { $0 ? "feed changed" : "feed unchanged" } ?? "feed not written"
        return [full.string(from: r.start), "end " + time.string(from: r.end), String(format: "%.3f s", r.duration),
                r.outcome.text, "entries \(r.entries)", feed].joined(separator: "  ")
    }

    private func readSummary() -> Summary {
        guard let data = try? Data(contentsOf: summaryURL) else { return Summary() }
        return (try? Self.decoder.decode(Summary.self, from: data)) ?? Summary()
    }

    private func writeSummary(_ s: Summary) {
        try? FileManager.default.createDirectory(at: summaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.encoder.encode(s).write(to: summaryURL, options: .atomic)
    }

    private func appendLine(_ line: String) {
        let old = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        var lines = old.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines.append(line)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension RefreshHistory.Summary {
    /// Settings' line: "Last background refresh: 12 minutes ago (Nov 6, 9:41 AM). 12 runs since Nov 6."
    func text(now: Date = Date()) -> String {
        var parts: [String] = []
        if let last {
            let rel = RelativeDateTimeFormatter()
            rel.dateTimeStyle = .named
            rel.unitsStyle = .full
            let ago = now.timeIntervalSince(last.start) < 60 ? "just now" : rel.localizedString(for: last.start, relativeTo: now)
            let abs = last.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            parts.append("Last background refresh: \(ago) (\(abs)).")
            if last.outcome != .ok { parts.append("It ended \(last.outcome.text).") }
            let since = since.map { " since " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
            parts.append((runs == 1 ? "1 run" : "\(runs) runs") + since + ".")
        } else {
            parts.append("Last background refresh: not yet. iOS runs it now and then while the app is closed.")
        }
        if let submitError { parts.append(submitError + ".") }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
/// Debug only: `-runBackgroundRefresh YES` runs the handler once at launch with a stand-in task, to check the path on
/// the simulator (which can't run background tasks) against a local `wrangler dev`.
final class LaunchArgumentRefreshTask: RefreshTask {
    var expirationHandler: (() -> Void)?
    func setTaskCompleted(success: Bool) {
        BackgroundRefresh.logger.notice("launch-argument refresh completed, success \(success)")
    }
}
#endif
