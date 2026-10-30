import XCTest
@testable import TasksCore

/// The wire format of spec §5, using the worked examples' test vectors.
final class WireTests: XCTestCase {
    func testDecodeSpecOps() throws {
        let a = op(Spec.opAJSON)
        XCTAssertEqual(a.type, .listCreate)
        XCTAssertEqual(a.at, 1_761_811_200_000)
        XCTAssertEqual(a.set, Patch(order: "a0", name: "Inbox"))
        let b = op(Spec.opBJSON)
        XCTAssertEqual(b.type, .taskCreate)
        XCTAssertEqual(b.set, Patch(list: Spec.inbox, order: "a0", title: "Buy milk", when: .some(date("2026-10-30"))))

        var s = AppState()
        s.apply(a)
        s.apply(b)
        XCTAssertEqual(s.lists[Spec.inbox]?.name, "Inbox")
        XCTAssertEqual(s.tasks["9f8e7d6c-5b4a-4321-8fed-cba987654321"]?.title, "Buy milk")
    }

    /// Encoding keeps explicit nulls distinct from absent keys, and round-trips.
    func testOpEncodingRoundTrip() throws {
        let o = Op(id: "i", at: 1, type: .taskUpdate, target: "t",
                   set: Patch(title: "x", when: .some(nil), completedAt: .some(5), deleted: false))
        let json = String(decoding: o.jsonData, as: UTF8.self)
        XCTAssertEqual(json, #"{"id":"i","at":1,"type":"task.update","target":"t","set":{"title":"x","when":null,"completedAt":5,"deleted":false}}"#)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: Data(json.utf8)), o)
        XCTAssertEqual(try JSONDecoder().decode(Op.self, from: JSONEncoder().encode(o)), o)
        // The spec's test-vector ops print exactly as the spec writes them.
        XCTAssertEqual(String(decoding: op(Spec.opAJSON).jsonData, as: UTF8.self), Spec.opAJSON)
        XCTAssertEqual(String(decoding: op(Spec.opBJSON).jsonData, as: UTF8.self), Spec.opBJSON)
    }

    func testJSONEscaping() throws {
        let tricky = "q\"uote\\ back\nline\ttab \u{01} é 🎉 </script>"
        let o = Op(id: "i", at: 0, type: .taskUpdate, target: "t", set: Patch(title: tricky, notes: ""))
        let decoded = try JSONDecoder().decode(Op.self, from: o.jsonData)
        XCTAssertEqual(decoded.set.title, tricky)
        XCTAssertEqual(decoded, o)
        XCTAssertFalse(o.jsonData.contains(0x0A), "one op per JSONL line")
    }

    func testRequestBody() throws {
        let opData = [Data(Spec.opAJSON.utf8), Data(Spec.opBJSON.utf8)]
        let body = SyncRequest.body(from: 0, base: nil, opJSON: opData)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"from":0,"base":null,"ops":["# + Spec.opAJSON + "," + Spec.opBJSON + "]}")
        let decoded = try JSONDecoder().decode(SyncRequest.self, from: body)
        XCTAssertEqual(decoded, SyncRequest(from: 0, base: nil, ops: [op(Spec.opAJSON), op(Spec.opBJSON)]))
        let pull = SyncRequest.body(from: 2, base: Spec.hash1, opJSON: [])
        XCTAssertEqual(String(decoding: pull, as: UTF8.self), #"{"from":2,"base":"\#(Spec.hash1)","ops":[]}"#)
        XCTAssertEqual(try JSONDecoder().decode(SyncRequest.self, from: pull), SyncRequest(from: 2, base: Spec.hash1, ops: []))
    }

    /// Worked example 1: the 200 response to the first push.
    func testPushResponseAndVerbatimEntries() throws {
        let e0 = #"{"seq":0,"received":1761811261234,"hash":"\#(Spec.hash0)","op":\#(Spec.opAJSON)}"#
        let e1 = #"{"seq":1,"received":1761811261234,"hash":"\#(Spec.hash1)","op":\#(Spec.opBJSON)}"#
        let body = #"{"entries":[\#(e0),\#(e1)],"head":2,"more":false}"#
        let page = try SyncPage.decode(Data(body.utf8))
        XCTAssertEqual(page.head, 2)
        XCTAssertFalse(page.more)
        XCTAssertEqual(page.entries.map(\.seq), [0, 1])
        XCTAssertEqual(page.entries.last?.hash, Spec.hash1)
        XCTAssertEqual(page.entries.map(\.op), [op(Spec.opAJSON), op(Spec.opBJSON)])
        XCTAssertEqual(page.rawEntries.map { String(decoding: $0, as: UTF8.self) }, [e0, e1])
    }

    /// Entries are kept verbatim: unknown keys survive, and pretty-printed bodies become single lines.
    func testVerbatimSlicesWithUnknownKeysAndWhitespace() throws {
        let body = """
        {
          "head": 1, "note": {"nested": ["]", "}", "\\"q\\""]},
          "entries": [
            { "seq": 0, "received": 5, "hash": "h", "op": {"id":"o","at":1,"type":"task.zap","target":"t","set":{"future":[1, 2]}}, "extra": "a b" }
          ],
          "more": false
        }
        """
        let page = try SyncPage.decode(Data(body.utf8))
        XCTAssertEqual(page.entries.first?.op.type, .unknown("task.zap"))
        XCTAssertEqual(String(decoding: page.rawEntries[0], as: UTF8.self),
                       #"{"seq":0,"received":5,"hash":"h","op":{"id":"o","at":1,"type":"task.zap","target":"t","set":{"future":[1,2]}},"extra":"a b"}"#)
    }

    func testEmptyPageAndMalformedBodies() throws {
        let page = try SyncPage.decode(Data(#"{"entries":[],"head":7,"more":false}"#.utf8))
        XCTAssertTrue(page.entries.isEmpty)
        XCTAssertEqual(page.head, 7)
        XCTAssertThrowsError(try SyncPage.decode(Data("<html>502 Bad Gateway</html>".utf8)))
        XCTAssertThrowsError(try SyncPage.decode(Data(#"{"entries":[{"seq":0}"#.utf8)))
    }

    /// An entry whose op this client can't read still advances the cursor and carries its hash.
    func testUnreadableOpStillOccupiesItsSeq() throws {
        let page = try SyncPage.decode(Data(#"{"entries":[{"seq":4,"received":1,"hash":"h4","op":{"weird":true}}],"head":5,"more":false}"#.utf8))
        XCTAssertEqual(page.entries.first?.seq, 4)
        XCTAssertEqual(page.entries.first?.hash, "h4")
        var s = AppState()
        XCTAssertNil(s.apply(page.entries[0].op))
    }

    func testErrorBodies() throws {
        let invalid = try JSONDecoder().decode(ErrorBody.self, from: Data(#"{"error":"invalid_op","message":"ops[1].set.order must match ^[0-9A-Za-z]{1,128}$","index":1,"field":"set.order"}"#.utf8))
        XCTAssertEqual(invalid, ErrorBody(error: "invalid_op", message: "ops[1].set.order must match ^[0-9A-Za-z]{1,128}$", index: 1, field: "set.order"))
        let token = try JSONDecoder().decode(ErrorBody.self, from: Data(#"{"error":"bad_token","message":"Missing or invalid bearer token."}"#.utf8))
        XCTAssertEqual(token.error, "bad_token")
        XCTAssertNil(token.index)
    }
}
