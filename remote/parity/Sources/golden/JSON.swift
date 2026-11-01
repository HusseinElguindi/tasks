import Foundation
import TasksCore

/// A JSON value with explicit nulls. Objects print with their keys sorted (by UTF-8 bytes), so output is stable.
indirect enum J {
    case null
    case bool(Bool)
    case int(Int)
    case str(String)
    case arr([J])
    case obj([String: J])

    static func s(_ v: String?) -> J { v.map(J.str) ?? .null }
    static func i(_ v: Int?) -> J { v.map(J.int) ?? .null }
    static func ids(_ v: [String]) -> J { .arr(v.map(J.str)) }

    var isScalar: Bool {
        switch self {
        case .arr, .obj: false
        default: true
        }
    }
}

enum JSONOut {
    /// Pretty-printed, two-space indent. Objects whose values are all scalars (a task, a case row) stay on one line,
    /// as do short arrays of scalars.
    static func render(_ v: J) -> String {
        var out = ""
        write(v, indent: 0, into: &out)
        out += "\n"
        return out
    }

    static func compact(_ v: J) -> String {
        var out = ""
        inline(v, into: &out)
        return out
    }

    /// A JSON string literal: `"`, `\` and C0 controls escaped, everything else as UTF-8.
    static func quote(_ s: String) -> String {
        var out = ""
        quote(s, into: &out)
        return out
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    private static func sortedKeys(_ o: [String: J]) -> [String] {
        o.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func inline(_ v: J, into out: inout String) {
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .str(let s): quote(s, into: &out)
        case .arr(let a):
            out += "["
            for (i, e) in a.enumerated() {
                if i > 0 { out += "," }
                inline(e, into: &out)
            }
            out += "]"
        case .obj(let o):
            out += "{"
            for (i, k) in sortedKeys(o).enumerated() {
                if i > 0 { out += "," }
                quote(k, into: &out)
                out += ":"
                inline(o[k]!, into: &out)
            }
            out += "}"
        }
    }

    private static func pad(_ n: Int, _ out: inout String) { out += String(repeating: "  ", count: n) }

    private static func write(_ v: J, indent: Int, into out: inout String) {
        switch v {
        case .arr(let a):
            if a.isEmpty { out += "[]"; return }
            if a.allSatisfy(\.isScalar) {
                let s = compact(v)
                if s.utf8.count <= 100 { out += s; return }
            }
            out += "[\n"
            for (i, e) in a.enumerated() {
                pad(indent + 1, &out)
                write(e, indent: indent + 1, into: &out)
                out += i == a.count - 1 ? "\n" : ",\n"
            }
            pad(indent, &out)
            out += "]"
        case .obj(let o):
            if o.isEmpty { out += "{}"; return }
            if o.values.allSatisfy(\.isScalar) { inline(v, into: &out); return }
            out += "{\n"
            let keys = sortedKeys(o)
            for (i, k) in keys.enumerated() {
                pad(indent + 1, &out)
                quote(k, into: &out)
                out += ": "
                write(o[k]!, indent: indent + 1, into: &out)
                out += i == keys.count - 1 ? "\n" : ",\n"
            }
            pad(indent, &out)
            out += "}"
        default:
            inline(v, into: &out)
        }
    }
}

// MARK: - The encodings the TypeScript tests read

func encode(_ t: TaskItem) -> J {
    .obj([
        "id": .str(t.id), "list": .str(t.list), "order": .str(t.order), "title": .str(t.title), "notes": .str(t.notes),
        "isHeading": .bool(t.isHeading), "when": .s(t.when?.string), "deadline": .s(t.deadline?.string),
        "completedAt": .i(t.completedAt), "deleted": .bool(t.deleted), "createdAt": .int(t.createdAt),
        "updatedAt": .int(t.updatedAt),
    ])
}

func encode(_ l: TaskList) -> J {
    .obj([
        "id": .str(l.id), "name": .str(l.name), "order": .str(l.order), "notes": .str(l.notes),
        "archivedAt": .i(l.archivedAt), "createdAt": .int(l.createdAt), "updatedAt": .int(l.updatedAt),
    ])
}

func encode(_ d: Day) -> J {
    .obj(["date": .str(d.date.string), "start": .int(d.start), "end": .int(d.end)])
}

/// The op's canonical text, as `pending.jsonl` and request bodies carry it.
func canonical(_ op: Op) -> String { String(decoding: op.jsonData, as: UTF8.self) }

func decodeOp(_ text: String) -> Op? { try? JSONDecoder().decode(Op.self, from: Data(text.utf8)) }
