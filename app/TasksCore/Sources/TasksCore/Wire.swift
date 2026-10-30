import Foundation

/// A log entry as the server sends it, and as `log.jsonl` stores it (verbatim, one per line).
public struct LogEntry: Hashable, Sendable {
    public var seq: Int
    public var received: Int
    /// SHA-256(prev hash + "\n" + op text), hex. The client never computes it, only echoes it as `base`.
    public var hash: String
    public var op: Op

    public init(seq: Int, received: Int, hash: String, op: Op) {
        self.seq = seq
        self.received = received
        self.hash = hash
        self.op = op
    }
}

extension LogEntry: Codable {
    enum Key: String, CodingKey { case seq, received, hash, op }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        seq = try c.decode(Int.self, forKey: .seq)
        received = (try? c.decode(Int.self, forKey: .received)) ?? 0
        hash = try c.decode(String.self, forKey: .hash)
        // An op this client can't read still occupies its seq and hash; the reducer just ignores it (rule 6).
        op = (try? c.decode(Op.self, forKey: .op))
            ?? Op(id: "", at: 0, type: .unknown(""), target: "", set: Patch())
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(seq, forKey: .seq)
        try c.encode(received, forKey: .received)
        try c.encode(hash, forKey: .hash)
        try c.encode(op, forKey: .op)
    }
}

/// `POST /v1/sync` request body (spec §5). Pushing and pulling are the same call.
public struct SyncRequest: Hashable, Sendable, Codable {
    /// The client's cursor: the next seq it doesn't have.
    public var from: Int
    /// Hash of entry `from − 1`; null if and only if `from == 0`.
    public var base: String?
    public var ops: [Op]

    public init(from: Int, base: String?, ops: [Op]) {
        self.from = from
        self.base = base
        self.ops = ops
    }

    enum Key: String, CodingKey { case from, base, ops }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(from, forKey: .from)
        if let base { try c.encode(base, forKey: .base) } else { try c.encodeNil(forKey: .base) }
        try c.encode(ops, forKey: .ops)
    }

    /// The body built from already-encoded op JSON, so pending ops are serialized once (when queued).
    public static func body(from: Int, base: String?, opJSON: [Data]) -> Data {
        var body = Data()
        body.reserveCapacity(64 + opJSON.reduce(0) { $0 + $1.count + 1 })
        body.append(contentsOf: Array(#"{"from":\#(from),"base":"#.utf8))
        if let base { body.append(contentsOf: Array("\"\(base)\"".utf8)) } else { body.append(contentsOf: Array("null".utf8)) }
        body.append(contentsOf: Array(#","ops":["#.utf8))
        for (i, op) in opJSON.enumerated() {
            if i > 0 { body.append(UInt8(ascii: ",")) }
            body.append(op)
        }
        body.append(contentsOf: Array("]}".utf8))
        return body
    }
}

/// `200` response body.
public struct SyncResponse: Hashable, Sendable, Codable {
    /// `[from, from+1000) ∩ [from, head)`, in seq order.
    public var entries: [LogEntry]
    public var head: Int
    /// True when the 1,000-entry page limit cut the response short.
    public var more: Bool

    public init(entries: [LogEntry], head: Int, more: Bool) {
        self.entries = entries
        self.head = head
        self.more = more
    }
}

/// Every non-200 response has this body.
public struct ErrorBody: Hashable, Sendable, Codable {
    public var error: String
    public var message: String?
    /// Only on `invalid_op`.
    public var index: Int?
    public var field: String?

    public init(error: String, message: String? = nil, index: Int? = nil, field: String? = nil) {
        self.error = error
        self.message = message
        self.index = index
        self.field = field
    }
}

/// A sync page as the client consumes it: each entry decoded, plus its exact bytes for `log.jsonl`.
public struct SyncPage: Sendable {
    public var entries: [LogEntry]
    /// The verbatim JSON of each entry, one per entry, without newlines.
    public var rawEntries: [Data]
    public var head: Int
    public var more: Bool

    public init(entries: [LogEntry], rawEntries: [Data], head: Int, more: Bool) {
        self.entries = entries
        self.rawEntries = rawEntries
        self.head = head
        self.more = more
    }

    /// Decodes a 200 body. Runs off the main actor (spec §9).
    public static func decode(_ data: Data) throws -> SyncPage {
        let decoder = JSONDecoder()
        let response = try decoder.decode(SyncResponse.self, from: data)
        let raw = try JSONSlices.arrayElements(named: "entries", in: data)
        guard raw.count == response.entries.count else { throw JSONSlices.Failure.malformed }
        return SyncPage(entries: response.entries, rawEntries: raw, head: response.head, more: response.more)
    }
}

/// Finds the exact bytes of each element of a top-level array member, so log entries are stored verbatim
/// (unknown keys and all) rather than re-encoded. A tiny JSON tokenizer; it only skips values.
public enum JSONSlices {
    public enum Failure: Error { case malformed, missing }

    public static func arrayElements(named name: String, in data: Data) throws -> [Data] {
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> [Data] in
            var s = Scanner(bytes: buf.bindMemory(to: UInt8.self))
            s.skipSpace()
            try s.expect(UInt8(ascii: "{"))
            let wanted = Array(name.utf8)
            s.skipSpace()
            if s.peek == UInt8(ascii: "}") { throw Failure.missing }
            while true {
                s.skipSpace()
                let key = try s.string()
                s.skipSpace()
                try s.expect(UInt8(ascii: ":"))
                s.skipSpace()
                if key.elementsEqual(wanted) {
                    return try s.arrayElements()
                }
                try s.skipValue()
                s.skipSpace()
                if s.peek == UInt8(ascii: ",") { s.i += 1; continue }
                throw Failure.missing
            }
        }
    }

    @inline(__always)
    static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 }

    struct Scanner {
        let bytes: UnsafeBufferPointer<UInt8>
        var i = 0

        var peek: UInt8? { i < bytes.count ? bytes[i] : nil }

        mutating func skipSpace() {
            while i < bytes.count, isSpace(bytes[i]) { i += 1 }
        }

        mutating func expect(_ c: UInt8) throws {
            guard peek == c else { throw Failure.malformed }
            i += 1
        }

        /// The raw bytes between the quotes (escapes left as-is; keys we look for have none).
        mutating func string() throws -> UnsafeBufferPointer<UInt8> {
            try expect(UInt8(ascii: "\""))
            let start = i
            while i < bytes.count {
                switch bytes[i] {
                case UInt8(ascii: "\\"): i += 2
                case UInt8(ascii: "\""):
                    let s = UnsafeBufferPointer(rebasing: bytes[start..<i])
                    i += 1
                    return s
                default: i += 1
                }
            }
            throw Failure.malformed
        }

        mutating func skipValue() throws {
            guard let c = peek else { throw Failure.malformed }
            switch c {
            case UInt8(ascii: "\""): _ = try string()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while i < bytes.count {
                    switch bytes[i] {
                    case UInt8(ascii: "\""): _ = try string(); continue
                    case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                    case UInt8(ascii: "}"), UInt8(ascii: "]"):
                        depth -= 1
                        if depth == 0 { i += 1; return }
                    default: break
                    }
                    i += 1
                }
                throw Failure.malformed
            default:
                // Number, true, false, null.
                while i < bytes.count, bytes[i] != UInt8(ascii: ","), bytes[i] != UInt8(ascii: "}"), bytes[i] != UInt8(ascii: "]"), !isSpace(bytes[i]) {
                    i += 1
                }
            }
        }

        mutating func arrayElements() throws -> [Data] {
            try expect(UInt8(ascii: "["))
            var out: [Data] = []
            skipSpace()
            if peek == UInt8(ascii: "]") { i += 1; return out }
            while true {
                skipSpace()
                let start = i
                try skipValue()
                out.append(Self.minified(UnsafeBufferPointer(rebasing: bytes[start..<i])))
                skipSpace()
                guard let c = peek else { throw Failure.malformed }
                i += 1
                if c == UInt8(ascii: "]") { return out }
                guard c == UInt8(ascii: ",") else { throw Failure.malformed }
            }
        }

        /// The element's bytes, with any whitespace outside strings removed so it fits on one JSONL line.
        static func minified(_ b: UnsafeBufferPointer<UInt8>) -> Data {
            guard b.contains(where: isSpace) else { return Data(b) }
            var out = Data(capacity: b.count)
            var inString = false
            var k = 0
            while k < b.count {
                let c = b[k]
                if inString {
                    out.append(c)
                    if c == UInt8(ascii: "\\"), k + 1 < b.count { out.append(b[k + 1]); k += 2; continue }
                    if c == UInt8(ascii: "\"") { inString = false }
                } else if c == UInt8(ascii: "\"") {
                    inString = true
                    out.append(c)
                } else if !isSpace(c) {
                    out.append(c)
                }
                k += 1
            }
            return out
        }
    }
}
