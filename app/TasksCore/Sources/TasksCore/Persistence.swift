import Foundation

/// Everything launch reads from disk (spec §8).
public struct LoadedState: Sendable {
    public enum Source: Equatable, Sendable {
        case empty
        /// Snapshot plus `tail` log entries after it.
        case snapshot(tail: Int)
        /// No usable snapshot: the whole log was replayed (and a fresh snapshot should be written).
        case fullReplay(reason: String)
    }

    public var confirmed: AppState
    /// The next seq the client doesn't have.
    public var cursor: Int
    /// Hash of entry `cursor − 1` (the request's `base`).
    public var hash: String?
    public var pending: [PendingOp]
    public var source: Source
    /// A `log.jsonl.bak-*` exists: a 409 recovery was under way (spec §5).
    public var recovering: Bool

    public init(confirmed: AppState, cursor: Int, hash: String?, pending: [PendingOp], source: Source, recovering: Bool) {
        self.confirmed = confirmed
        self.cursor = cursor
        self.hash = hash
        self.pending = pending
        self.source = source
        self.recovering = recovering
    }
}

/// The three files in the data directory, and all I/O on them, on one background serial queue (spec §8, §9).
///
/// - `log.jsonl`: confirmed entries exactly as the server sent them. Append-only; the source of truth.
/// - `pending.jsonl`: local ops not yet confirmed. One append per op; rewritten atomically after a sync that leaves
///   some pending, emptied in place after one that confirms them all.
/// - `snapshot.json`: `{schema, cursor, hash, logOffset, state}`, a cache of the reduced state at `cursor`.
/// - `log.jsonl.bak-<ms>`: a log moved aside by a 409 recovery. Never read; deleted when the recovery finishes.
///
/// Callers enqueue work in program order and the queue runs it in that order, which is what makes the write
/// order within a sync (log, then pending, then snapshot) hold.
public final class Persistence: @unchecked Sendable {
    /// Bump whenever `AppState`'s shape or the reducer's semantics change: the next launch replays the log.
    public static let schema = 2

    public let directory: URL
    public var logURL: URL { directory.appendingPathComponent("log.jsonl") }
    public var pendingURL: URL { directory.appendingPathComponent("pending.jsonl") }
    public var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    public var rejectedURL: URL { directory.appendingPathComponent("rejected.jsonl") }

    private let queue = DispatchQueue(label: "tasks.persistence", qos: .utility)
    // Touched only on `queue`:
    private var logHandle: FileHandle?
    private var pendingHandle: FileHandle?
    /// Byte size of log.jsonl and the seq after its last entry, so a snapshot can record `logOffset` for its cursor.
    private var logSize = 0
    private var logCursor = 0
    private var snapshotCursor = -1

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Launch

    /// Loads confirmed state, cursor, hash and pending ops. O(state + tail) from a snapshot; a full replay when
    /// the snapshot is missing, undecodable, from another schema, or fails the offset/seq check.
    public func load() async -> LoadedState {
        await withCheckedContinuation { c in queue.async { c.resume(returning: self.loadOnQueue()) } }
    }

    public func loadSync() -> LoadedState { queue.sync { loadOnQueue() } }

    /// Every confirmed entry in `log.jsonl`, in seq order, for history (the CLI's log and undo). Waits for queued
    /// writes. The app never calls it.
    public func readEntries() -> [LogEntry] {
        queue.sync { parseLog(readLog(from: 0) ?? Data(), firstSeq: 0).entries }
    }

    private func loadOnQueue() -> LoadedState {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = AppState()
        var cursor = 0
        var hash: String? = nil
        var tailIDs: Set<String> = []
        var source = LoadedState.Source.empty

        let logBytes = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        var fromSnapshot = false
        var reason = "no snapshot"
        if let snap = readSnapshot(&reason) {
            if snap.logOffset <= logBytes, let tailData = readLog(from: snap.logOffset) {
                let tail = parseLog(tailData, firstSeq: snap.cursor)
                if tail.ok {
                    state = snap.state.appState
                    cursor = snap.cursor
                    hash = snap.hash
                    for e in tail.entries {
                        state.apply(e.op)
                        tailIDs.insert(e.op.id)
                    }
                    if let last = tail.entries.last {
                        cursor = last.seq + 1
                        hash = last.hash
                    }
                    logSize = snap.logOffset + tail.end
                    truncateLog(to: logSize, of: logBytes)
                    logCursor = cursor
                    snapshotCursor = snap.cursor
                    source = .snapshot(tail: tail.entries.count)
                    fromSnapshot = true
                } else {
                    reason = "first tail entry isn't seq \(snap.cursor)"
                }
            } else {
                reason = "log shorter than the snapshot's offset"
            }
        }
        if !fromSnapshot {
            try? FileManager.default.removeItem(at: snapshotURL)
            snapshotCursor = -1
            let all = parseLog(readLog(from: 0) ?? Data(), firstSeq: 0)
            for e in all.entries {
                state.apply(e.op)
                tailIDs.insert(e.op.id)
            }
            cursor = all.entries.count
            hash = all.entries.last?.hash
            logSize = all.end
            truncateLog(to: logSize, of: logBytes)
            logCursor = cursor
            if logBytes > 0 { source = .fullReplay(reason: reason) }
        }

        // Pending: drop a torn last line, and ops a crash left behind after they were confirmed (they're in the tail).
        // Each op keeps its line verbatim: that's what gets sent.
        var pending: [PendingOp] = []
        var dropped = false
        if let data = try? Data(contentsOf: pendingURL) {
            let lines = Self.lines(data, from: 0)
            for line in lines.lines {
                guard let p = PendingOp(json: line) else { dropped = true; continue }
                if tailIDs.contains(p.op.id) { dropped = true; continue }
                pending.append(p)
            }
            dropped = dropped || lines.end != data.count
        }
        if dropped { rewritePendingOnQueue(pending.map(\.json)) }
        return LoadedState(confirmed: state, cursor: cursor, hash: hash, pending: pending, source: source,
                           recovering: !backups().isEmpty)
    }

    private struct ParsedLog {
        var entries: [LogEntry]
        /// Byte offset just past the last good line.
        var end: Int
        /// The first entry had the expected seq (or there were none).
        var ok: Bool
    }

    /// Parses JSONL log entries, requiring contiguous seqs from `firstSeq`. Stops at the first torn or
    /// out-of-sequence line; everything from there on is dropped (and refetched). Not ok if the very first
    /// complete line doesn't hold `firstSeq`.
    private func parseLog(_ data: Data, firstSeq: Int) -> ParsedLog {
        let lines = Self.lines(data, from: 0)
        var entries: [LogEntry] = []
        entries.reserveCapacity(lines.lines.count)
        var end = 0
        let decoder = JSONDecoder()
        for (i, line) in lines.lines.enumerated() {
            guard let e = try? decoder.decode(LogEntry.self, from: line), e.seq == firstSeq + entries.count else {
                return ParsedLog(entries: entries, end: end, ok: i > 0)
            }
            entries.append(e)
            end = lines.ends[i]
        }
        return ParsedLog(entries: entries, end: end, ok: true)
    }

    private func readLog(from offset: Int) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: logURL) else { return offset == 0 ? Data() : nil }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: UInt64(offset))) != nil else { return nil }
        return (try? h.readToEnd()) ?? Data()
    }

    /// Complete (newline-terminated) lines from `offset`, with the byte offset after each line's newline.
    /// A trailing fragment without a newline is a torn write and isn't returned.
    static func lines(_ data: Data, from offset: Int) -> (lines: [Data], ends: [Int], end: Int) {
        var lines: [Data] = []
        var ends: [Int] = []
        var start = offset
        var end = offset
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            var i = offset
            while i < bytes.count {
                if bytes[i] == 0x0A {
                    if i > start { lines.append(data.subdata(in: start..<i)) ; ends.append(i + 1) }
                    start = i + 1
                    end = i + 1
                }
                i += 1
            }
        }
        return (lines, ends, end)
    }

    private func truncateLog(to size: Int, of current: Int) {
        guard size < current, let h = try? FileHandle(forWritingTo: logURL) else { return }
        try? h.truncate(atOffset: UInt64(size))
        try? h.close()
    }

    // MARK: - Snapshot

    struct SnapshotFile: Codable {
        var schema: Int
        var cursor: Int
        var hash: String?
        var logOffset: Int
        var state: Contents

        struct Contents: Codable {
            var tasks: [TaskItem]
            var lists: [TaskList]

            var appState: AppState {
                var s = AppState()
                s.tasks.reserveCapacity(tasks.count)
                for t in tasks { s.tasks[t.id] = t }
                for l in lists { s.lists[l.id] = l }
                return s
            }
        }
    }

    private func readSnapshot(_ reason: inout String) -> SnapshotFile? {
        guard let data = try? Data(contentsOf: snapshotURL) else { reason = "no snapshot"; return nil }
        guard let snap = try? JSONDecoder().decode(SnapshotFile.self, from: data) else { reason = "snapshot undecodable"; return nil }
        guard snap.schema == Self.schema else { reason = "snapshot schema \(snap.schema), want \(Self.schema)"; return nil }
        return snap
    }

    /// Encodes and writes the snapshot off the main thread, from a value copy of the confirmed state. Skipped if
    /// the cursor hasn't moved, or if the log on disk doesn't end exactly at `cursor`.
    public func writeSnapshot(state: AppState, cursor: Int, hash: String?) {
        queue.async { self.writeSnapshotOnQueue(state: state, cursor: cursor, hash: hash) }
    }

    private func writeSnapshotOnQueue(state: AppState, cursor: Int, hash: String?) {
        guard cursor != snapshotCursor, cursor == logCursor else { return }
        let file = SnapshotFile(schema: Self.schema, cursor: cursor, hash: hash, logOffset: logSize,
                                state: .init(tasks: Array(state.tasks.values), lists: Array(state.lists.values)))
        guard let data = try? JSONEncoder().encode(file) else { return }
        if (try? data.write(to: snapshotURL, options: .atomic)) != nil { snapshotCursor = cursor }
    }

    // MARK: - Appends and rewrites

    /// Appends confirmed entries (verbatim server JSON, one per line). `nextCursor` is the seq after the last one.
    public func appendLog(_ rawEntries: [Data], nextCursor: Int) {
        guard !rawEntries.isEmpty else { return }
        queue.async {
            var chunk = Data()
            chunk.reserveCapacity(rawEntries.reduce(0) { $0 + $1.count + 1 })
            for e in rawEntries {
                chunk.append(e)
                chunk.append(0x0A)
            }
            guard let h = self.handle(&self.logHandle, self.logURL) else { return }
            if (try? h.write(contentsOf: chunk)) != nil {
                self.logSize += chunk.count
                self.logCursor = nextCursor
            }
        }
    }

    public func appendPending(_ op: Data) {
        queue.async {
            guard let h = self.handle(&self.pendingHandle, self.pendingURL) else { return }
            var line = op
            line.append(0x0A)
            try? h.write(contentsOf: line)
        }
    }

    /// Replaces pending.jsonl with the given ops: atomically (temp file, then rename), or with no ops by emptying it
    /// in place.
    public func rewritePending(_ ops: [Data]) {
        queue.async { self.rewritePendingOnQueue(ops) }
    }

    private func rewritePendingOnQueue(_ ops: [Data]) {
        if ops.isEmpty, emptyPendingOnQueue() { return }
        var data = Data()
        for op in ops {
            data.append(op)
            data.append(0x0A)
        }
        try? pendingHandle?.close()
        pendingHandle = nil // the rename replaces the inode; reopen on the next append
        try? data.write(to: pendingURL, options: .atomic)
    }

    /// Every pending op was confirmed: truncate pending.jsonl to 0 bytes in place, and skip it entirely when it's
    /// already empty (the usual case: most syncs confirm the one edit that started them). False if the truncation
    /// failed, and the caller falls back to the atomic rewrite.
    ///
    /// Crash-safe because:
    /// - Truncating to 0 is one change of the file's length. A crash leaves the old file whole or the file empty,
    ///   never part of a line. (A torn last line is dropped at launch anyway.)
    /// - The old file holds only confirmed ops. Each is in log.jsonl, appended earlier on this queue, so if it
    ///   survives a crash launch finds it in the log tail and drops it from pending (`loadOnQueue`).
    /// - No unconfirmed op can be in it: every append and rewrite runs on this serial queue in the order the main
    ///   actor issued them. An op made after the sync's page was applied is appended after this; one made before is
    ///   still in `projection.pending`, so the caller passes it and the atomic rewrite runs instead.
    private func emptyPendingOnQueue() -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: pendingURL.path)[.size] as? Int) ?? 0
        guard size > 0 else { return true } // missing or already empty: nothing to write
        guard let h = handle(&pendingHandle, pendingURL), (try? h.truncate(atOffset: 0)) != nil,
              (try? h.seek(toOffset: 0)) != nil else {
            try? pendingHandle?.close()
            pendingHandle = nil
            return false
        }
        return true
    }

    /// An op the server rejected (`invalid_op`), kept verbatim for debugging.
    public func appendRejected(_ opJSON: Data, error: ErrorBody, at: Int) {
        queue.async {
            var line = Data(#"{"at":\#(at),"error":"#.utf8)
            line.append((try? JSONEncoder().encode(error)) ?? Data("null".utf8))
            line.append(Data(#","op":"#.utf8))
            line.append(opJSON)
            line.append(Data("}\n".utf8))
            var handle: FileHandle? = nil
            if let h = self.handle(&handle, self.rejectedURL) {
                try? h.write(contentsOf: line)
                try? h.close()
            }
        }
    }

    // MARK: - 409 recovery (spec §5 "Recovering from a 409")

    /// The recovery's file steps, in order, so a crash after any of them still ends in a full recovery:
    ///
    /// 1. Build the recovery queue: every op in `log.jsonl` in seq order (its `op` text, verbatim), then `pending`,
    ///    keeping the first occurrence of each op id.
    /// 2. Write it atomically as the new `pending.jsonl`.
    /// 3. Delete `snapshot.json`.
    /// 4. Rename `log.jsonl` to `log.jsonl.bak-<now>`.
    ///
    /// Returns the queue. The caller then resets confirmed state, the cursor and `base`, and syncs from 0.
    public func beginRecovery(pending: [PendingOp], now: Int) async -> [PendingOp] {
        await withCheckedContinuation { c in
            queue.async { c.resume(returning: self.recoverOnQueue(pending: pending, now: now, through: 4)) }
        }
    }

    /// Runs recovery steps 1…`step` and stops, as a crash right after that step would (tests).
    func recoverSync(pending: [PendingOp], now: Int, through step: Int) -> [PendingOp] {
        queue.sync { recoverOnQueue(pending: pending, now: now, through: step) }
    }

    private func recoverOnQueue(pending: [PendingOp], now: Int, through step: Int) -> [PendingOp] {
        // 1.
        var queue: [PendingOp] = []
        var seen: Set<String> = []
        let data = readLog(from: 0) ?? Data()
        for line in Self.lines(data, from: 0).lines {
            guard let text = try? JSONSlices.member(named: "op", in: line), let p = PendingOp(json: text),
                  seen.insert(p.op.id).inserted else { continue }
            queue.append(p)
        }
        for p in pending where seen.insert(p.op.id).inserted { queue.append(p) }
        if step == 1 { return queue }
        // 2.
        rewritePendingOnQueue(queue.map(\.json))
        if step == 2 { return queue }
        // 3.
        try? FileManager.default.removeItem(at: snapshotURL)
        snapshotCursor = -1
        if step == 3 { return queue }
        // 4.
        try? logHandle?.close()
        logHandle = nil
        if FileManager.default.fileExists(atPath: logURL.path) {
            var backup = directory.appendingPathComponent("log.jsonl.bak-\(now)")
            var n = 1
            while FileManager.default.fileExists(atPath: backup.path) {
                backup = directory.appendingPathComponent("log.jsonl.bak-\(now)-\(n)")
                n += 1
            }
            try? FileManager.default.moveItem(at: logURL, to: backup)
        }
        logSize = 0
        logCursor = 0
        return queue
    }

    /// Deletes every `log.jsonl.bak-*` once a recovery has finished (a sync ended with `more: false` and nothing
    /// pending).
    public func deleteBackups() {
        queue.async {
            for url in self.backups() { try? FileManager.default.removeItem(at: url) }
        }
    }

    func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("log.jsonl.bak-") }
    }

    /// Waits for every queued write (quit, tests).
    public func flush() { queue.sync {} }

    private func handle(_ slot: inout FileHandle?, _ url: URL) -> FileHandle? {
        if let h = slot { return h }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? h.seekToEnd()
        slot = h
        return h
    }
}
