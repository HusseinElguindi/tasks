import Foundation
import Security
import TasksCore

/// An error a command reports. `kind` is also the error's type in code mode (§6 of docs/SDK-PLAN.md).
struct CLIError: Error, Equatable {
    enum Kind: String, Sendable {
        case usage = "Usage"
        case notFound = "NotFound"
        case ambiguous = "Ambiguous"
        case invalid = "Invalid"
        case noActiveList = "NoActiveList"
        case limit = "Limit"
        case sync = "Sync"
        case busy = "Busy"
        case config = "Config"
    }

    var kind: Kind
    var message: String
    var field: String? = nil
    var candidates: [String] = []

    var exitCode: Int32 { kind == .usage ? 2 : 1 }

    static func usage(_ m: String) -> CLIError { CLIError(kind: .usage, message: m) }
    static func invalid(_ m: String, field: String? = nil) -> CLIError { CLIError(kind: .invalid, message: m, field: field) }
}

/// Everything a command reads from outside: the environment, files, the clock, the network and the terminal.
/// Tests build one with a fake server and a fixed clock.
struct Environment: @unchecked Sendable {
    var vars: [String: String]
    var home: URL
    var transport: SyncTransport
    var clock: StoreClock
    var stdinIsTTY: Bool
    var readStdin: () -> String
    var out: (String) -> Void
    var err: (String) -> Void
    /// The app's Keychain item (§8). Only consulted when a person is at the terminal.
    var keychainToken: () -> String?
    /// Sleeps between sync retries; tests skip it.
    var sleep: (Double) async -> Void

    static func live() -> Environment {
        Environment(
            vars: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser,
            transport: HTTPSyncTransport(),
            clock: .system,
            stdinIsTTY: isatty(STDIN_FILENO) == 1,
            readStdin: { String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) },
            out: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
            err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
            keychainToken: Keychain.appToken,
            sleep: { try? await Task.sleep(for: .seconds($0)) }
        )
    }

    subscript(_ name: String) -> String? {
        guard let v = vars[name], !v.isEmpty else { return nil }
        return v
    }

    var nowMs: Int { Int((clock.now().timeIntervalSince1970 * 1000).rounded()) }

    /// `~/.tasks-sync.env` (or `TASKS_ENV_FILE`): `KEY=value` lines.
    var envFile: URL {
        self["TASKS_ENV_FILE"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? home.appendingPathComponent(".tasks-sync.env")
    }

    func envFileValues() -> [String: String] {
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line.removeFirst(7) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    /// "~/.tasks-sync.env" for messages.
    func pretty(_ url: URL) -> String {
        let path = url.path
        return path.hasPrefix(home.path + "/") ? "~" + path.dropFirst(home.path.count) : path
    }
}

/// The app's sync token in the login Keychain (`AppModel.swift`): service `com.elguindi.Tasks.sync`.
enum Keychain {
    static func appToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.elguindi.Tasks.sync",
                                    kSecAttrAccount as String: "API_TOKEN", kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Where and how to sync: the server URL, the token and where it came from (never the token in messages).
struct Server {
    var config: SyncConfig
    var tokenSource: String

    /// URL: `--server`, else `TASKS_URL`, else a `TASKS_URL=` line in `~/.tasks-sync.env`; there is no default.
    /// Token: `TASKS_TOKEN`, else `API_TOKEN` in that file, else the app's Keychain item, which is only read
    /// when a person is at the terminal, because macOS may show a dialog an agent can't answer.
    static func resolve(_ env: Environment, override: String?) throws -> Server {
        let file = env.envFileValues()
        guard let raw = override ?? env["TASKS_URL"] ?? file["TASKS_URL"] else {
            throw CLIError(kind: .config, message: "No server. Set TASKS_URL, or add a TASKS_URL=https://… line to \(env.pretty(env.envFile)).")
        }
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme == "https" || url.scheme == "http",
              url.host != nil else {
            throw CLIError(kind: .config, message: "TASKS_URL isn't an http(s) URL.")
        }
        #if DEBUG
        // Like the app's Debug builds: only a local wrangler dev, unless told otherwise.
        guard isLocal(url) || env["TASKS_ALLOW_REMOTE"] == "1" else {
            throw CLIError(kind: .config, message: "This is a debug build of tasks: it only talks to localhost (set TASKS_ALLOW_REMOTE=1 to override).")
        }
        #endif
        if let t = env["TASKS_TOKEN"] { return Server(config: SyncConfig(url: url, token: t), tokenSource: "TASKS_TOKEN") }
        if let t = file["API_TOKEN"], !t.isEmpty {
            return Server(config: SyncConfig(url: url, token: t), tokenSource: env.pretty(env.envFile))
        }
        if env.stdinIsTTY, let t = env.keychainToken(), !t.isEmpty {
            return Server(config: SyncConfig(url: url, token: t), tokenSource: "the Tasks app's Keychain item")
        }
        throw CLIError(kind: .config, message: "No token. Set TASKS_TOKEN, or add API_TOKEN=… to \(env.pretty(env.envFile)). (The app's Keychain item is only read when you run tasks yourself in a terminal.)")
    }

    static func isLocal(_ url: URL) -> Bool { ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") }

    /// One replica per server (§2): `~/Library/Application Support/Tasks CLI/<host>[:<port>]/`, or under
    /// `TASKS_DATA_DIR`. Never the app's `Tasks` or `Tasks Dev`.
    func directory(_ env: Environment) -> URL {
        let base = env["TASKS_DATA_DIR"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? env.home.appendingPathComponent("Library/Application Support/Tasks CLI", isDirectory: true)
        let url = config.url
        let name = (url.host ?? "server") + (url.port.map { ":\($0)" } ?? "")
        return base.appendingPathComponent(name, isDirectory: true)
    }
}

/// An exclusive `flock` on `<dir>/lock`. The kernel drops it when the process exits, so there's no stale lock.
final class DirectoryLock {
    private let fd: Int32

    init(_ dir: URL, wait: Double = 15) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fd = open(dir.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CLIError(kind: .busy, message: "Can't open the lock in \(dir.path).") }
        let deadline = Date().addingTimeInterval(wait)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, Date() < deadline else {
                close(fd)
                throw CLIError(kind: .busy, message: "Another tasks command is still running on this replica.")
            }
            usleep(50_000)
        }
    }

    deinit { close(fd) }
}

/// The CLI's replica: its own data directory, the app's `Store` on it, and the sync loop around a command
/// (docs/SDK-PLAN.md §2).
@MainActor
final class Session {
    let env: Environment
    let server: Server
    let directory: URL
    let persistence: Persistence
    let store: Store
    let actor: String
    private let lock: DirectoryLock

    init(env: Environment, server: Server, actor: String) async throws {
        self.env = env
        self.server = server
        self.actor = actor
        directory = server.directory(env)
        lock = try DirectoryLock(directory)
        persistence = Persistence(directory: directory)
        let loaded = await persistence.load()
        store = Store(loaded: loaded, persistence: persistence, transport: env.transport, clock: env.clock)
        store.config = server.config
        store.cancelScheduledSync()
    }

    var retries: Int { env["TASKS_RETRIES"].flatMap(Int.init) ?? 3 }

    /// Syncs until up to date. Returns true when nothing of ours is left unconfirmed, false when the server
    /// couldn't be reached (the ops stay queued: exit 75). Throws when sync stopped (401, 404, invalid op…).
    func sync() async throws -> Bool {
        store.notice = nil
        var tries = 0
        while true {
            await store.sync()
            store.cancelScheduledSync()
            if case .retrying(let at, _) = store.syncState, tries < retries {
                tries += 1
                await env.sleep(min(max(0, at.timeIntervalSince(env.clock.now())), 8))
                continue
            }
            break
        }
        if store.notice != nil {
            store.notice = nil
            throw CLIError(kind: .sync, message: "The server rejected a change (it's in \(directory.appendingPathComponent("rejected.jsonl").path)). This is a bug in tasks.")
        }
        switch store.syncState {
        case .idle: return store.projection.pending.isEmpty
        case .retrying(_, let reason):
            env.err("tasks: can't reach the server (\(reason)); working offline.")
            return false
        case .checkToken:
            throw CLIError(kind: .sync, message: "The server rejected the token (from \(server.tokenSource)).")
        case .failed(let message):
            throw CLIError(kind: .sync, message: "Sync stopped: \(message)")
        case .off, .syncing:
            return false
        }
    }

    /// Writes a change: the ops go through the real `Store` with this command's actor and batch, into
    /// `pending.jsonl` before anything is sent, then out (§2 "One command's life").
    func commit(_ ops: [Op], batch: String, push: Bool = true) async throws -> Bool {
        store.attribution = Attribution(actor: actor, batch: batch)
        store.perform(ops)
        store.attribution = nil
        store.cancelScheduledSync()
        store.persistNow()
        guard push else { return false }
        let synced = try await sync()
        store.persistNow()
        return synced
    }

    /// A second `Store` on the same state, with scratch files and no server: every write is built on one, so a
    /// dry run, a code-mode run and a failed command write nothing (§4 "Forks").
    func fork() -> (Store, URL) {
        let loaded = LoadedState(confirmed: store.projection.confirmed, cursor: store.cursor, hash: store.base,
                                 pending: store.projection.pending, source: .empty, recovering: false)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-cli-fork-\(UUID().uuidString)")
        let fork = Store(loaded: loaded, persistence: Persistence(directory: dir), transport: OfflineTransport(),
                         clock: env.clock)
        return (fork, dir)
    }

    /// The default actor: `--actor`, `TASKS_ACTOR`, `agent:claude-code` under Claude Code, else `cli` (§4).
    static func actor(_ env: Environment, override: String?) throws -> String {
        let a = override ?? env["TASKS_ACTOR"] ?? (env["CLAUDECODE"] == "1" ? "agent:claude-code" : "cli")
        guard (1...64).contains(a.utf16.count) else { throw CLIError.invalid("The actor must be 1 to 64 characters.", field: "actor") }
        return a
    }
}

/// A fork never syncs (it has no config); this is only there to satisfy `Store`.
struct OfflineTransport: SyncTransport {
    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome { .transient("offline") }
}
