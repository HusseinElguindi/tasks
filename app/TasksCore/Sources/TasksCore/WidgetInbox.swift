import Foundation

/// The widget's outbox and the app's inbox (design/WIDGETS.md §3.3): `widget-inbox.jsonl` next to the feed, one `Op`
/// per line in TasksCore's canonical JSON (`Op.jsonData`). A widget's intent appends the op it built and posts
/// `WidgetNudge`; the app reads the ops, performs them through `Store.perform` (which keeps each op's id and `at`), and
/// then removes exactly the lines it performed.
///
/// Every access takes an exclusive `flock` on a sibling lock file, `widget-inbox.jsonl.lock`, so appends from the
/// widget's process and the app's read and rewrite never interleave. The lock is on a separate file because the
/// rewrite replaces the inbox by rename: a lock on the inbox itself would stay on the old inode. Each call opens its
/// own descriptors and holds the lock only for one read or write (no lock is held across a suspension, which iOS
/// punishes in a shared container).
public struct WidgetInbox: Sendable {
    public static let fileName = "widget-inbox.jsonl"
    /// Who the widget's ops are from (`Op.actor`).
    public static let actor = "widget"

    public let url: URL
    var lockURL: URL { url.appendingPathExtension("lock") }

    public init(url: URL) { self.url = url }

    /// The inbox in `folder` (from `WidgetFolder`).
    public init(folder: URL) { self.init(url: folder.appendingPathComponent(Self.fileName)) }

    /// What a `read` saw: the ops, oldest first, to perform and then pass to `removeDrained`.
    public struct Drain: Hashable, Sendable {
        public var ops: [Op]
        public var isEmpty: Bool { ops.isEmpty }
    }

    public enum InboxError: Error { case lock(Int32), open(Int32), write(Int32) }

    // MARK: - The widget

    /// The op behind a widget's check box (§2.1): sets `completedAt` to `now` or clears it, an explicit state rather
    /// than a flip, so two quick taps settle on the second's. A fresh lowercase UUID id, `actor: "widget"`, and a
    /// batch id of its own (pass one to group several).
    public static func setCompleted(_ task: EntityID, _ completed: Bool, now: Date = Date(), id: String? = nil,
                                    batch: String? = nil) -> Op {
        let at = Int((now.timeIntervalSince1970 * 1000).rounded())
        return Op(id: id ?? UUID().uuidString.lowercased(), at: at, type: .taskUpdate, target: task,
                  set: Patch(completedAt: .some(completed ? at : nil)), actor: actor,
                  batch: batch ?? UUID().uuidString.lowercased())
    }

    /// Appends ops, one line each, under the lock. Creates the folder and the file if needed.
    public func append(_ ops: [Op]) throws {
        guard !ops.isEmpty else { return }
        var data = Data()
        for op in ops {
            data.append(op.jsonData)
            data.append(UInt8(ascii: "\n"))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try locked {
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
            guard fd >= 0 else { throw InboxError.open(errno) }
            defer { close(fd) }
            try data.withUnsafeBytes { buf in
                var off = 0
                while off < buf.count {
                    let n = write(fd, buf.baseAddress! + off, buf.count - off)
                    if n < 0 {
                        if errno == EINTR { continue }
                        throw InboxError.write(errno)
                    }
                    off += n
                }
            }
        }
    }

    public func append(_ op: Op) throws { try append([op]) }

    // MARK: - The app

    /// The ops waiting, oldest first, under the lock. Lines that don't decode are skipped. Empty if there's no inbox.
    /// The widget's provider reads it too, for the overlay.
    public func read() -> Drain {
        guard FileManager.default.fileExists(atPath: url.path) else { return Drain(ops: []) }
        let data = (try? locked { try? Data(contentsOf: url) }) ?? nil
        return Drain(ops: Self.ops(in: data ?? Data()))
    }

    /// After the drained ops were performed: rewrites the inbox without them, under the lock, keeping every line
    /// appended since the `read` (and any other op not in `drain`). Lines are matched by op id, which is unique per tap.
    /// Removes the file when nothing is left.
    public func removeDrained(_ drain: Drain) throws {
        guard !drain.isEmpty else { return }
        let gone = Set(drain.ops.map(\.id))
        try locked {
            guard let data = try? Data(contentsOf: url) else { return }
            var keep = Data()
            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                guard let op = try? JSONDecoder().decode(Op.self, from: Data(line)), !gone.contains(op.id) else { continue }
                keep.append(contentsOf: line)
                keep.append(UInt8(ascii: "\n"))
            }
            if keep.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else {
                try keep.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: -

    static func ops(in data: Data) -> [Op] {
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(Op.self, from: Data($0))
        }
    }

    /// Runs `body` holding an exclusive `flock` on the lock file (blocking until it's free).
    func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw InboxError.open(errno) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { throw InboxError.lock(errno) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
