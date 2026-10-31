import Foundation

/// JSON with ordered object keys. Output prints keys in the order `tasks.d.ts` declares them, and code-mode
/// arguments arrive as this too.
indirect enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([Member])

    struct Member: Equatable, Sendable {
        var key: String
        var value: JSON
    }

    init(_ pairs: KeyValuePairs<String, JSON>) {
        self = .object(pairs.map { Member(key: $0.key, value: $0.value) })
    }

    static func str(_ s: String?) -> JSON { s.map(JSON.string) ?? .null }
    static func num(_ n: Int?) -> JSON { n.map(JSON.int) ?? .null }

    subscript(key: String) -> JSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    var keys: [String] {
        guard case .object(let members) = self else { return [] }
        return members.map(\.key)
    }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    var arrayValue: [JSON]? { if case .array(let a) = self { a } else { nil } }
    var intValue: Int? {
        switch self {
        case .int(let n): n
        case .double(let d) where d == d.rounded() && abs(d) < 9e15: Int(d)
        default: nil
        }
    }
    var isNull: Bool { self == .null }

    // MARK: Writing

    /// Compact JSON, strings escaped the way `JSON.stringify` does.
    var text: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        case .double(let d): out += d.isFinite ? String(d) : "null"
        case .string(let s): Self.quote(s, to: &out)
        case .array(let items):
            out += "["
            for (i, v) in items.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, m) in members.enumerated() {
                if i > 0 { out += "," }
                Self.quote(m.key, to: &out)
                out += ":"
                m.value.write(to: &out)
            }
            out += "}"
        }
    }

    static func quote(_ s: String, to out: inout String) {
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
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }

    // MARK: Reading

    static func parse(_ data: Data) throws -> JSON {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return from(any)
    }

    static func parse(_ text: String) throws -> JSON { try parse(Data(text.utf8)) }

    private static func from(_ any: Any) -> JSON {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 9e15 ? .int(Int(d)) : .double(d)
            }
            return .int(n.intValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map(from))
        case let o as [String: Any]:
            return .object(o.keys.sorted().map { Member(key: $0, value: from(o[$0]!)) })
        default: return .null
        }
    }
}
