import XCTest
@testable import TasksCore

/// The shared wire fixtures in `fixtures/sync/` (written by the server track; see its README), decoded with the
/// client's own types so the client and the server agree on the format.
final class FixtureTests: XCTestCase {
    struct Pair: Decodable {
        struct Setup: Decodable { var log: [Op]?; var logFile: String? }
        struct Request: Decodable { var method: String; var path: String; var headers: [String: String]; var body: SyncRequest? }
        struct Response: Decodable { var status: Int; var headers: [String: String] }
        var name: String
        var setup: Setup
        var request: Request
        var response: Response
    }

    /// One fixture pair, with its request and response bodies kept as the exact JSON bytes (whitespace aside).
    struct Loaded {
        var pair: Pair
        var requestBody: Data?
        var responseBody: Data
    }

    static func loadPairs() throws -> [Loaded] {
        let dir = Fixtures.syncDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent.first?.isNumber == true })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }), !files.isEmpty else {
            throw XCTSkip("No fixtures in \(dir.path) yet (the server track writes them).")
        }
        return try files.map { url in
            let data = try Data(contentsOf: url)
            let pair = try JSONDecoder().decode(Pair.self, from: data)
            let request = try JSONSlices.member(named: "request", in: data)
            let response = try JSONSlices.member(named: "response", in: data)
            return Loaded(pair: pair, requestBody: try? JSONSlices.member(named: "body", in: request),
                          responseBody: try JSONSlices.member(named: "body", in: response))
        }
    }

    static func loadLogFile(_ name: String) throws -> [LogEntry] {
        let text = try String(contentsOf: Fixtures.syncDirectory.appendingPathComponent(name), encoding: .utf8)
        return try text.split(separator: "\n").map { try JSONDecoder().decode(LogEntry.self, from: Data($0.utf8)) }
    }

    func testEveryPairDecodes() throws {
        let pairs = try Self.loadPairs()
        XCTAssertGreaterThanOrEqual(pairs.count, 10)
        for loaded in pairs {
            let p = loaded.pair
            if p.request.method == "POST" && p.response.status != 400 {
                let body = try XCTUnwrap(p.request.body, p.name)
                XCTAssertEqual(body.base == nil, body.from == 0, "\(p.name): base is null iff from = 0")
            }
            if p.response.status == 200 {
                let page = try SyncPage.decode(loaded.responseBody)
                XCTAssertEqual(page.entries.count, page.rawEntries.count)
                if let first = page.entries.first {
                    XCTAssertEqual(first.seq, p.request.body?.from, "\(p.name): the page starts at from")
                    XCTAssertEqual(page.entries.map(\.seq), Array(first.seq..<(first.seq + page.entries.count)), "\(p.name): contiguous")
                }
                XCTAssertTrue(page.entries.allSatisfy { $0.hash.count == 64 }, p.name)
                XCTAssertEqual(page.more, (page.entries.last?.seq ?? -1) + 1 < page.head, "\(p.name): more iff the page stops short of head")
            } else {
                let error = try JSONDecoder().decode(ErrorBody.self, from: loaded.responseBody)
                let expected = [400: ["bad_request", "invalid_op"], 401: ["bad_token"], 404: ["not_found"],
                                405: ["method_not_allowed"], 409: ["log_mismatch"], 413: ["too_large"]][p.response.status]
                XCTAssertTrue(expected?.contains(error.error) == true, "\(p.name): \(p.response.status) \(error.error)")
                if error.error == "invalid_op" {
                    XCTAssertNotNil(error.index)
                    XCTAssertNotNil(error.field)
                }
            }
            for o in p.setup.log ?? [] {
                XCTAssertEqual(try JSONDecoder().decode(Op.self, from: JSONEncoder().encode(o)), o, "\(p.name): op round trip")
            }
        }
    }

    /// Example 1: our own push comes back as the first two log entries, with the spec's hashes.
    func testPushPair() throws {
        let push = try XCTUnwrap(Self.loadPairs().first { $0.pair.name == "01-push" })
        let page = try SyncPage.decode(push.responseBody)
        XCTAssertEqual(page.entries.map(\.op), push.pair.request.body?.ops)
        XCTAssertEqual(page.entries.map(\.hash), [Spec.hash0, Spec.hash1])
        XCTAssertEqual(page.entries.map(\.op), [op(Spec.opAJSON), op(Spec.opBJSON)])
    }

    /// Example 2: three pages tile the 2,345-entry log, and each request's base is the hash of entry from − 1,
    /// exactly what the client's cursor/base bookkeeping produces.
    func testPaginationPairsTileTheLog() throws {
        let log = try Self.loadLogFile("log-2345.jsonl")
        XCTAssertEqual(log.count, 2345)
        XCTAssertEqual(log.map(\.seq), Array(0..<2345))
        let pages = try Self.loadPairs().filter { $0.pair.name.hasPrefix("02") }
        XCTAssertEqual(pages.count, 3)
        var cursor = 0
        var base: String? = nil
        var all: [LogEntry] = []
        for loaded in pages {
            let request = try XCTUnwrap(loaded.pair.request.body)
            XCTAssertEqual(request.from, cursor)
            XCTAssertEqual(request.base, base)
            let page = try SyncPage.decode(loaded.responseBody)
            all += page.entries
            cursor = page.entries.last!.seq + 1
            base = page.entries.last!.hash
            XCTAssertEqual(page.head, 2345)
        }
        XCTAssertEqual(all, log)
        let state = AppState.replay(log.map(\.op))
        XCTAssertEqual(state.lists.count, 1)
        XCTAssertEqual(state.tasks["9f8e7d6c-5b4a-4321-8fed-cba987654321"]?.title, log.last?.op.set.title)
    }

    /// The hash vectors: the stored op text decodes to the spec's opA/opB.
    func testHashVectors() throws {
        struct Vectors: Decodable { var vectors: [Vector] }
        struct Vector: Decodable { var seq: Int; var prev: String; var opText: String; var hash: String }
        let data = try Data(contentsOf: Fixtures.syncDirectory.appendingPathComponent("hash-vectors.json"))
        let v = try JSONDecoder().decode(Vectors.self, from: data).vectors
        XCTAssertEqual(v.map(\.hash), [Spec.hash0, Spec.hash1])
        XCTAssertEqual(v.map(\.prev), ["", Spec.hash0])
        XCTAssertEqual(v.map { op($0.opText) }, [op(Spec.opAJSON), op(Spec.opBJSON)])
    }
}
