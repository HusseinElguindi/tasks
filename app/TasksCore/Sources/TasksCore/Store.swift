import Foundation
import Observation

/// What the sidebar footer and Settings show about sync.
public enum SyncState: Equatable, Sendable {
    /// No server configured.
    case off
    case idle(lastSynced: Date?)
    case syncing
    /// Server or network trouble; retrying with backoff (1 s doubling, capped at 1 min).
    case retrying(at: Date, reason: String)
    /// 401. Stopped until the token changes or ⌘R.
    case checkToken
    /// `bad_request`, 404, 405: a bug or a wrong URL. Stopped until the settings change or ⌘R.
    case failed(String)
}

/// "Restoring sync · 1,500 of 12,000": recovery-queue ops confirmed so far, of the total (spec §5).
public struct RecoveryProgress: Equatable, Sendable {
    public var confirmed: Int
    public var total: Int
}

public struct StoreClock: Sendable {
    public var now: @Sendable () -> Date
    public var calendar: Calendar

    public init(now: @escaping @Sendable () -> Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    public static let system = StoreClock(now: { Date() }, calendar: .autoupdatingCurrent)
}

/// Who is making changes, and the change they belong to (spec §5 `actor`, `batch`).
public struct Attribution: Hashable, Sendable {
    public var actor: String
    public var batch: String

    public init(actor: String, batch: String) {
        self.actor = actor
        self.batch = batch
    }
}

/// The app's single source of truth on the main actor: confirmed state, cursor, base, pending ops and the
/// projection, plus the sync loop (spec §5, §8). Views read the projection's models and buckets and call the
/// actions in `Store+Actions.swift`; they never touch persistence or the network.
@MainActor
@Observable
public final class Store {
    @ObservationIgnored public let projection: Projection
    @ObservationIgnored let persistence: Persistence
    @ObservationIgnored let transport: SyncTransport
    @ObservationIgnored let clock: StoreClock

    /// Server URL and token. Changing them clears a stopped state and syncs.
    public var config: SyncConfig? {
        didSet {
            guard config != oldValue else { return }
            requestSync(force: true)
        }
    }

    public private(set) var syncState: SyncState = .off
    public private(set) var recovery: RecoveryProgress?
    /// How many changes wait to go out (`projection.pending`, which isn't observed): the sync indicator's "3 changes
    /// waiting" (INTERACTIONS-v2 §26).
    public private(set) var pendingCount = 0
    /// A non-blocking notice, e.g. "A change couldn't be saved."
    public var notice: String?

    /// Stamped on every op `perform` queues. The app leaves it nil; the CLI sets one per command.
    @ObservationIgnored public var attribution: Attribution?

    /// The next seq this Mac doesn't have, and the hash of entry `cursor − 1`.
    @ObservationIgnored public private(set) var cursor: Int
    @ObservationIgnored public private(set) var base: String?

    static let maxOpsPerRequest = 500
    static let maxBytesPerRequest = 900_000

    @ObservationIgnored private var batchLimit = Store.maxOpsPerRequest
    @ObservationIgnored private var backoff: Duration = .seconds(1)
    @ObservationIgnored private var retryAt: Date?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var mismatchesInARow = 0
    /// Op ids the server acknowledged with a 200 but that haven't come back in a page yet; not resent. Cleared
    /// when a page reaches the head: anything still pending then was lost (a restored server) and goes out again.
    @ObservationIgnored private var inServerLog: Set<String> = []
    @ObservationIgnored private var recoveryIDs: Set<String> = []
    @ObservationIgnored private var currentSync: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false
    @ObservationIgnored private var trigger: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

    public init(loaded: LoadedState, persistence: Persistence, transport: SyncTransport, clock: StoreClock = .system) {
        self.persistence = persistence
        self.transport = transport
        self.clock = clock
        cursor = loaded.cursor
        base = loaded.hash
        projection = Projection(confirmed: loaded.confirmed, pending: loaded.pending,
                                day: Day(containing: clock.now(), calendar: clock.calendar))
        if loaded.recovering {
            recoveryIDs = Set(loaded.pending.map(\.op.id))
            recovery = RecoveryProgress(confirmed: 0, total: recoveryIDs.count)
        }
        if case .fullReplay = loaded.source { writeSnapshot() }
        seedInboxIfMissing()
        countPending()
    }

    private func countPending() {
        let n = projection.pending.count
        if n != pendingCount { pendingCount = n }
    }

    /// Loads the data directory off the main thread, then builds the projection.
    public static func open(directory: URL, transport: SyncTransport = HTTPSyncTransport(),
                            clock: StoreClock = .system) async -> Store {
        let persistence = Persistence(directory: directory)
        let loaded = await persistence.load()
        return Store(loaded: loaded, persistence: persistence, transport: transport, clock: clock)
    }

    var nowMs: Int { Int((clock.now().timeIntervalSince1970 * 1000).rounded()) }

    /// Client-generated op and entity ids: lowercase UUID strings, compared as strings, never round-tripped
    /// through `UUID` (the server treats ids as case-sensitive).
    public func newID() -> String { UUID().uuidString.lowercased() }

    // MARK: - Local ops

    /// Applies ops optimistically, queues them for sync, and registers their inverse with the undo manager
    /// (undo is a new op, like `git revert`; spec §6).
    @discardableResult
    public func perform(_ ops: [Op], undoManager: UndoManager? = nil, actionName: String? = nil) -> Bool {
        guard !ops.isEmpty else { return false }
        var ops = ops
        if let a = attribution {
            for i in ops.indices {
                ops[i].actor = a.actor
                ops[i].batch = a.batch
            }
        }
        // Inverses against the state before the batch; undo applies them in reverse order.
        var tasks: [EntityID: TaskItem?] = [:]
        var lists: [EntityID: TaskList?] = [:]
        var inverses: [Op] = []
        for op in ops {
            if op.type.isTask {
                var before = tasks[op.target] ?? projection.task(op.target)
                if let inverse = Inverse.of(op, beforeTask: before, id: "", at: 0) { inverses.append(inverse) }
                Reducer.apply(op, to: &before)
                tasks[op.target] = before
            } else if op.type.isList {
                var before = lists[op.target] ?? projection.list(op.target)
                if let inverse = Inverse.of(op, beforeList: before, id: "", at: 0) { inverses.append(inverse) }
                Reducer.apply(op, to: &before)
                lists[op.target] = before
            }
        }
        let pending = ops.map(PendingOp.init)
        projection.perform(pending)
        countPending()
        for p in pending { persistence.appendPending(p.json) }
        if let undoManager, !inverses.isEmpty {
            let templates = Array(inverses.reversed())
            let manager = UnsafeSendable(undoManager)
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    _ = store.perform(templates.map(store.stamp), undoManager: manager.value, actionName: actionName)
                }
            }
            if let actionName { undoManager.setActionName(actionName) }
        }
        requestSync(after: .seconds(1))
        return true
    }

    /// A fresh id and timestamp for an op template.
    func stamp(_ template: Op) -> Op {
        Op(id: newID(), at: nowMs, type: template.type, target: template.target, set: template.set)
    }

    private func seedInboxIfMissing() {
        if let seed = Seed.inboxIfMissing(listExists: { projection.list($0) != nil }, now: nowMs) {
            perform([seed])
        }
    }

    /// Recomputes Today when the day or time zone changes, and when the app becomes active (spec §2).
    public func refreshDay() {
        projection.setDay(Day(containing: clock.now(), calendar: clock.calendar))
    }

    // MARK: - Snapshot

    public func writeSnapshot() {
        persistence.writeSnapshot(state: projection.confirmed, cursor: cursor, hash: base)
    }

    private func scheduleSnapshot() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.writeSnapshot()
        }
    }

    /// Resign active / quit: write the snapshot now and wait for queued writes.
    public func persistNow() {
        snapshotTask?.cancel()
        writeSnapshot()
        persistence.flush()
    }

    // MARK: - Sync triggers (spec §5): launch, activation, every 30 s, ~1 s after a local change, ⌘R

    /// Schedules a sync. Automatic triggers respect a stopped state and the current backoff; `force` (⌘R, new
    /// settings, app activation) clears both.
    public func requestSync(after delay: Duration = .zero, force: Bool = false) {
        if force {
            stopped = false
            retryAt = nil
            backoff = .seconds(1)
        }
        guard !stopped, config != nil else {
            if config == nil { syncState = .off }
            return
        }
        var wait = delay
        if let retryAt {
            wait = max(wait, .milliseconds(Int(retryAt.timeIntervalSince(clock.now()) * 1000)))
        }
        trigger?.cancel()
        trigger = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Cancels a scheduled sync (a debounce or a backoff timer). Tests drive `sync()` directly.
    public func cancelScheduledSync() {
        trigger?.cancel()
        trigger = nil
    }

    /// Runs requests until up to date, stopped or backing off. A call during a sync asks for one more pass and
    /// returns when that pass is done.
    public func sync() async {
        if let running = currentSync {
            syncAgain = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                syncAgain = false
                await runSync()
            } while syncAgain && !stopped && retryAt == nil
        }
        currentSync = task
        await task.value
        currentSync = nil
    }

    private func runSync() async {
        guard let config else {
            syncState = .off
            return
        }
        retryAt = nil
        syncState = .syncing
        batchLimit = Self.maxOpsPerRequest
        while true {
            let chunk = nextChunk()
            let body = SyncRequest.body(from: cursor, base: base, opJSON: chunk.map(\.json))
            let outcome = await transport.send(body, config: config)
            guard config == self.config else { return } // settings changed mid-request; that triggered a new sync
            switch outcome {
            case .page(let page):
                backoff = .seconds(1)
                for p in chunk { inServerLog.insert(p.op.id) }
                guard apply(page) else {
                    // A page that doesn't start at our cursor: the logs diverged. Never guess; recover.
                    await recoverFrom409()
                    continue
                }
                mismatchesInARow = 0
                if !page.more { inServerLog.removeAll() }
                if page.more || hasUnsent { continue }
                finishRecoveryIfDone()
                syncState = .idle(lastSynced: clock.now())
                return
            case .invalidOp(let error):
                guard let i = error.index, chunk.indices.contains(i) else {
                    stop(.failed(error.message ?? "The server rejected a change."))
                    return
                }
                reject(chunk[i], error)
            case .tooLarge:
                guard chunk.count > 1 else {
                    stop(.failed("A change is too large to sync."))
                    return
                }
                batchLimit = max(1, chunk.count / 2)
            case .logMismatch:
                mismatchesInARow += 1
                guard mismatchesInARow <= 3 else {
                    stop(.failed("The server's log keeps changing."))
                    return
                }
                await recoverFrom409()
            case .badToken:
                stop(.checkToken)
                return
            case .badRequest(let message), .misconfigured(let message):
                stop(.failed(message))
                return
            case .transient(let reason):
                let wait = backoff
                backoff = min(backoff * 2, .seconds(60))
                let at = clock.now().addingTimeInterval(Double(wait.components.seconds) + Double(wait.components.attoseconds) / 1e18)
                retryAt = at
                syncState = .retrying(at: at, reason: reason)
                requestSync()
                return
            }
        }
    }

    private func stop(_ state: SyncState) {
        stopped = true
        syncState = state
    }

    private var hasUnsent: Bool { projection.pending.contains { !inServerLog.contains($0.op.id) } }

    /// The next request's ops: oldest first, at most 500 ops and ~900 KB, each as its verbatim JSON.
    private func nextChunk() -> [PendingOp] {
        var chunk: [PendingOp] = []
        var bytes = 0
        for p in projection.pending where !inServerLog.contains(p.op.id) {
            if chunk.count >= batchLimit || (!chunk.isEmpty && bytes + p.json.count > Self.maxBytesPerRequest) { break }
            chunk.append(p)
            bytes += p.json.count + 1
        }
        return chunk
    }

    /// Appends the page to the log, applies it to confirmed state and drops our confirmed ops from pending
    /// (only ids that actually came back). Returns false if the page doesn't continue our log.
    private func apply(_ page: SyncPage) -> Bool {
        guard let first = page.entries.first, let last = page.entries.last else { return !page.more }
        guard first.seq == cursor, last.seq == cursor + page.entries.count - 1 else { return false }
        let pendingBefore = projection.pending.count
        projection.confirm(page.entries, touchingAll: recovery != nil)
        countPending()
        cursor = last.seq + 1
        base = last.hash
        persistence.appendLog(page.rawEntries, nextCursor: cursor)
        if projection.pending.count != pendingBefore {
            persistence.rewritePending(projection.pending.map(\.json))
        }
        if var r = recovery {
            for e in page.entries where recoveryIDs.remove(e.op.id) != nil { r.confirmed += 1 }
            recovery = r
        }
        scheduleSnapshot()
        return true
    }

    /// `invalid_op`: move the op to rejected.jsonl, rebuild its entity, tell the user, retry without it.
    private func reject(_ p: PendingOp, _ error: ErrorBody) {
        projection.reject(opID: p.op.id)
        countPending()
        persistence.appendRejected(p.json, error: error, at: nowMs)
        persistence.rewritePending(projection.pending.map(\.json))
        if recoveryIDs.remove(p.op.id) != nil { recovery?.total -= 1 }
        notice = "A change couldn't be saved."
    }

    /// `409` (spec §5 "Recovering from a 409"): never discard an op. Every known op (log + pending) becomes
    /// pending, the snapshot goes, the log is moved aside, and the next request starts from 0.
    private func recoverFrom409() async {
        snapshotTask?.cancel()
        let before = projection.pending
        let queue = await persistence.beginRecovery(pending: before, now: nowMs)
        // Edits made while the files were being rewritten queue behind the recovery queue.
        var seen = Set(queue.map(\.op.id))
        let later = projection.pending.dropFirst(before.count).filter { seen.insert($0.op.id).inserted }
        projection.recover(pending: queue + later)
        countPending()
        cursor = 0
        base = nil
        inServerLog = []
        batchLimit = Self.maxOpsPerRequest
        recoveryIDs = Set(projection.pending.map(\.op.id))
        recovery = RecoveryProgress(confirmed: 0, total: recoveryIDs.count)
    }

    /// Backups are deleted once a sync ends with `more: false` and nothing pending.
    private func finishRecoveryIfDone() {
        guard recovery != nil, projection.pending.isEmpty else { return }
        persistence.deleteBackups()
        recovery = nil
        recoveryIDs = []
    }
}

/// Carries a non-Sendable reference into an undo handler, which UndoManager always calls on the main thread.
struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
