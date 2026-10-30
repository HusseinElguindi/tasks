import XCTest
@testable import TasksCore

/// Sync against a real server: the Worker running under a local `wrangler dev` (never the deployed one).
///
///     TASKS_LIVE_URL=http://127.0.0.1:8791 TASKS_LIVE_TOKEN=… TASKS_LIVE_DIR=/tmp/live \
///       TASKS_LIVE_PHASE=1 swift test --filter LiveServerTests
///
/// Phase 1 makes two Macs (data directories under TASKS_LIVE_DIR) and converges them. Restart `wrangler dev`
/// with fresh state (a wiped server), then phase 2 reopens both Macs: each gets a 409, re-pushes everything it
/// knows, and a third Mac syncing from 0 must see every op.
@MainActor
final class LiveServerTests: XCTestCase {
    struct Env {
        var config: SyncConfig
        var dir: URL
        var phase: String
    }

    func env() throws -> Env {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["TASKS_LIVE_URL"].flatMap(URL.init(string:)), let token = e["TASKS_LIVE_TOKEN"],
              let dir = e["TASKS_LIVE_DIR"], let phase = e["TASKS_LIVE_PHASE"] else {
            throw XCTSkip("Set TASKS_LIVE_URL, TASKS_LIVE_TOKEN, TASKS_LIVE_DIR and TASKS_LIVE_PHASE to run against wrangler dev.")
        }
        guard ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            throw XCTSkip("Live tests only run against a local wrangler dev, never a deployed server.")
        }
        return Env(config: SyncConfig(url: url, token: token), dir: URL(fileURLWithPath: dir), phase: phase)
    }

    func open(_ env: Env, _ name: String) -> Store {
        let p = Persistence(directory: env.dir.appendingPathComponent(name))
        let store = Store(loaded: p.loadSync(), persistence: p, transport: HTTPSyncTransport())
        store.config = env.config
        store.cancelScheduledSync()
        return store
    }

    func opIDs(_ store: Store) -> Set<String> {
        store.persistence.flush()
        let log = (try? String(contentsOf: store.persistence.logURL, encoding: .utf8)) ?? ""
        return Set(log.split(separator: "\n").compactMap { try? JSONDecoder().decode(LogEntry.self, from: Data($0.utf8)).op.id })
            .union(store.projection.pending.map(\.op.id))
    }

    func testLive() async throws {
        let env = try env()
        let expected = env.dir.appendingPathComponent("expected-op-ids.json")
        if env.phase == "1" {
            try? FileManager.default.removeItem(at: env.dir)
            let a = open(env, "a")
            let b = open(env, "b")
            let school = a.createList(name: "School")
            let lab = a.createTask(title: "Lab report", in: school)!
            a.createTask(title: "Inbox thing")
            await a.sync()
            XCTAssertEqual(a.syncState.withoutDate, .idle(lastSynced: nil))
            await b.sync()
            XCTAssertEqual(b.projection.task(lab)?.title, "Lab report")
            b.setTitle(lab, "Lab report v2")
            b.createTask(title: "From B", notes: "**bold** notes", in: school)
            b.toggleComplete([lab])
            await b.sync()
            await a.sync()
            XCTAssertEqual(a.projection.confirmed, b.projection.confirmed)
            XCTAssertEqual(a.cursor, b.cursor)
            XCTAssertTrue(a.projection.pending.isEmpty && b.projection.pending.isEmpty)
            // A damaged local log against a healthy server: 409, everything deduplicated, nothing appended.
            let head = a.cursor
            a.persistNow()
            var text = try String(contentsOf: a.persistence.logURL, encoding: .utf8)
            text = text.replacingOccurrences(of: a.base!, with: String(repeating: "0", count: 64))
            try text.write(to: a.persistence.logURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: a.persistence.snapshotURL)
            let a2 = open(env, "a")
            await a2.sync()
            XCTAssertEqual(a2.cursor, head)
            XCTAssertNil(a2.recovery)
            XCTAssertEqual(a2.projection.confirmed, b.projection.confirmed)
            a2.persistNow()
            b.persistNow()
            try JSONEncoder().encode(Array(opIDs(a2).union(opIDs(b)))).write(to: expected)
        } else {
            // The server was wiped (fresh wrangler dev state). Both Macs recover it; nothing is lost.
            let ids = Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: expected)))
            let a = open(env, "a")
            let b = open(env, "b")
            a.createTask(title: "Made after the wipe")
            await a.sync()
            XCTAssertNil(a.recovery)
            await b.sync()
            await a.sync()
            let c = open(env, "c-\(UUID().uuidString.prefix(8))")
            await c.sync()
            let onServer = opIDs(c)
            XCTAssertTrue(ids.isSubset(of: onServer), "lost \(ids.subtracting(onServer))")
            XCTAssertEqual(a.projection.confirmed, b.projection.confirmed)
            XCTAssertEqual(c.projection.confirmed, a.projection.confirmed)
            let backups = try FileManager.default.contentsOfDirectory(atPath: a.persistence.directory.path)
                .filter { $0.hasPrefix("log.jsonl.bak-") }
            XCTAssertEqual(backups, [])
        }
    }
}

extension SyncState {
    var withoutDate: SyncState {
        if case .idle = self { return .idle(lastSynced: nil) }
        return self
    }
}
