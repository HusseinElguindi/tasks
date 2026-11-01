import Foundation
import TasksCore

// MARK: - op-json.json

/// Inputs are strict JSON (what `JSON.parse` accepts): JSONDecoder also takes leading zeros, trailing commas and a
/// BOM, and keeps the first of two equal keys where `JSON.parse` keeps the last, but the server, which writes every
/// log line with `JSON.stringify`, never produces those.
enum OpJSONCases {
    static func q(_ s: String) -> String { JSONOut.quote(s) }

    static func op(_ set: String, type: String = "task.update", at: String = "1761811200000", extra: String = "") -> String {
        #"{"id":"op-1","at":\#(at),"type":"\#(type)","target":"t-1","set":\#(set)\#(extra)}"#
    }

    static func handmade() -> [String] {
        var c: [String] = []
        // Escaping: every C0 control, quotes, backslash, slash, DEL, separators, non-BMP, combining marks.
        let tricky = (0..<0x20).map { String(UnicodeScalar(UInt8($0))) }.joined()
        c.append(op("{\"title\":\(q(tricky))}"))
        c.append(op(#"{"title":"\u0000\u0001\u001f\u007f\u0080ÿ  ﻿￾￿"}"#))
        c.append(op(#"{"title":"q\"uote \\ back \/ slash \b\f\n\r\t"}"#))
        c.append(op(#"{"title":"🎉 😀 🎉 é é ﬃ 𝒜 é"}"#))
        c.append(op(#"{"title":"lone \ud800 surrogate"}"#))
        c.append(op(#"{"title":"lone low \udc00"}"#))
        c.append(op(#"{"notes":"pair split \ud83c","title":"ok"}"#))
        c.append(op("{\"title\":\(q("</script> <!-- & ' \u{2028}"))}"))
        c.append(op("{\"notes\":\(q(String(repeating: "x", count: 1000) + "\n" + String(repeating: "é", count: 500)))}"))
        c.append(#"{"id":"q\"id\\","at":5,"type":"task.update","target":"t\n1","set":{}}"#)
        c.append(#"{"id":"😀","at":5,"type":"task.update","target":"\u0000","set":{}}"#)
        // Every Patch key, set, null and of the wrong type, alone and together.
        let values: [String: [String]] = [
            "list": [q("L"), "null", "5", q("")],
            "order": [q("a0"), "null", "[]", q("")],
            "title": [q("T"), "null", "true", q("")],
            "notes": [q("N"), "null", "{}", q("")],
            "kind": [q("heading"), q("task"), "null", "1"],
            "when": [q("2026-11-01"), "null", q("2026-02-30"), q("2026-11-1"), "20261101", q("")],
            "deadline": [q("2024-02-29"), "null", q("2100-02-29"), "false"],
            "completedAt": ["0", "1761811200000", "null", "-1", "1.5", "1.0", "1e3", "-0", q("5"), "9007199254740991",
                            "true", "[]"],
            "deleted": ["true", "false", "null", "1", q("true")],
            "name": [q("Inbox"), "null", "7", q("")],
            "archivedAt": ["0", "5", "null", "-5", "2.5", q("5"), "1E2"],
        ]
        for key in values.keys.sorted() {
            for v in values[key]! {
                c.append(op("{\(q(key)):\(v)}"))
                c.append(op("{\(q(key)):\(v)}", type: key == "name" || key == "archivedAt" ? "list.update" : "task.create"))
            }
        }
        c.append(op(#"{"archivedAt":null,"deleted":false,"name":"n","completedAt":null,"deadline":null,"when":null,"kind":"heading","notes":"","title":"","order":"Zz","list":"L"}"#))
        c.append(op(#"{"list":"L","order":"a0","title":"t","notes":"n","kind":"heading","when":"2026-11-01","deadline":"2026-11-02","completedAt":1,"deleted":true,"name":"x","archivedAt":2}"#, type: "task.create"))
        c.append(op(#"{"color":"red","priority":3,"tags":["a"],"title":"kept","nested":{"title":"no"}}"#))
        c.append(op(#"{"title":"escaped key","notes":"n"}"#))
        c.append(op(#"{"Title":"case matters","TITLE":"no"}"#))
        c.append(op(#"{}"#))
        // The envelope.
        for at in ["0", "-5", "1.0", "1.5", "1e3", "1E+2", "100e-2", "-0", "-0.0", "\"123\"", "null", "true", "[]",
                   "9007199254740991", "1761811200000"] {
            c.append(op(#"{"title":"x"}"#, at: at))
        }
        c.append(#"{"id":"op-1","type":"task.update","target":"t-1","set":{"title":"no at"}}"#)
        c.append(#"{"id":"op-1","at":1,"target":"t-1","set":{"title":"no type"}}"#)
        c.append(#"{"id":"op-1","at":1,"type":5,"target":"t-1","set":{}}"#)
        c.append(#"{"id":"op-1","at":1,"type":null,"target":"t-1","set":{}}"#)
        for type in ["task.create", "task.update", "list.create", "list.update", "task.archive", "", "TASK.UPDATE",
                     "task.update ", "list.delete"] {
            c.append(op(#"{"title":"x","name":"y","list":"L","order":"a0"}"#, type: type))
        }
        c.append(#"{"id":"op-1","at":1,"type":"task.update","target":"t-1"}"#)
        for set in ["null", "[]", "\"x\"", "5", "true", "[{\"title\":\"x\"}]"] { c.append(op(set)) }
        c.append(#"{"id":"op-1","at":1,"type":"task.update","target":"t-1","set":{"title":"x"},"actor":"agent:claude-code","batch":"2c1f9e0a-7b3d-4c5e-8f6a-9b0c1d2e3f4a"}"#)
        c.append(#"{"batch":"b\"1","actor":"a","set":{"title":"x"},"target":"t-1","type":"task.update","at":1,"id":"op-1"}"#)
        c.append(op(#"{"title":"x"}"#, extra: #","actor":7,"batch":null"#))
        c.append(op(#"{"title":"x"}"#, extra: #","actor":"","batch":"""#))
        c.append(op(#"{"title":"x"}"#, extra: #","actor":null,"batch":"b""#))
        c.append(op(#"{"title":"x"}"#, extra: #","actor":["a"],"batch":{"b":1}"#))
        c.append(op(#"{"title":"x"}"#, extra: #","v":2,"meta":{"set":{"title":"no"}},"id2":"x""#))
        c.append(#"  {"id" : "op-1" , "at" : 1 , "type" : "task.update" , "target" : "t-1" , "set" : { "title" : "spaced" } }  "#)
        c.append("{\n\t\"id\": \"op-1\",\n\t\"at\": 1,\n\t\"type\": \"task.update\",\n\t\"target\": \"t-1\",\n\t\"set\": {}\n}")
        // Not decodable as an Op.
        c += [#"{"at":1,"type":"task.update","target":"t-1","set":{}}"#,
              #"{"id":5,"at":1,"type":"task.update","target":"t-1","set":{}}"#,
              #"{"id":null,"at":1,"type":"task.update","target":"t-1","set":{}}"#,
              #"{"id":"op-1","at":1,"type":"task.update","set":{}}"#,
              #"{"id":"op-1","at":1,"type":"task.update","target":["t"],"set":{}}"#,
              #"{"id":"op-1","at":1,"type":"task.update","target":null,"set":{}}"#,
              "{}", "[]", "null", "\"op\"", "5", "true", "[{\"id\":\"op-1\",\"target\":\"t\"}]", "",
              #"{"id":"op-1","at":1,"type":"task.update","target":"t-1","set":{}"#,
              #"not json"#]
        c.append(#"{"id":"","at":1,"type":"task.update","target":"","set":{}}"#)
        return c
    }

    static func build(fromLogs logTexts: [String]) -> (J, Int) {
        var seen: Set<String> = []
        var inputs: [String] = []
        for s in handmade() + logTexts where seen.insert(s).inserted { inputs.append(s) }
        // Keep the handmade ones and a deterministic sample of the rest.
        let handmadeCount = handmade().count
        var cases: [J] = []
        for (i, s) in inputs.enumerated() where i < handmadeCount || i % 3 == 0 {
            cases.append(.obj(["input": .str(s), "canonical": .s(decodeOp(s).map(canonical))]))
        }
        return (.obj(["cases": .arr(cases)]), cases.count)
    }
}
