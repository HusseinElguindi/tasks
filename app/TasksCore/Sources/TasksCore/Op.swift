import Foundation

/// Task and list ids are client-generated strings (UUIDs in practice, 1–64 chars on the wire).
public typealias EntityID = String

public enum OpType: Hashable, Sendable {
    case taskCreate, taskUpdate, listCreate, listUpdate
    /// A type this client doesn't know. The reducer ignores it (spec §5 rule 6).
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "task.create": self = .taskCreate
        case "task.update": self = .taskUpdate
        case "list.create": self = .listCreate
        case "list.update": self = .listUpdate
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .taskCreate: "task.create"
        case .taskUpdate: "task.update"
        case .listCreate: "list.create"
        case .listUpdate: "list.update"
        case .unknown(let raw): raw
        }
    }

    public var isTask: Bool { self == .taskCreate || self == .taskUpdate }
    public var isList: Bool { self == .listCreate || self == .listUpdate }
}

/// The `set` of an op. A present key overwrites the field, `null` clears it, a missing key leaves it alone (spec §5).
///
/// Nullable fields are double optionals: `nil` means the key is absent, `.some(nil)` is an explicit `null`.
/// Decoding is per-key lenient: unknown keys and values of the wrong type are dropped, never fatal (rule 6).
public struct Patch: Hashable, Sendable {
    public var list: EntityID?
    public var order: String?
    public var title: String?
    public var notes: String?
    public var when: CalendarDate??
    public var deadline: CalendarDate??
    public var completedAt: Int??
    public var deleted: Bool?
    public var name: String?
    public var archivedAt: Int??

    public init(list: EntityID? = nil, order: String? = nil, title: String? = nil, notes: String? = nil,
                when: CalendarDate?? = nil, deadline: CalendarDate?? = nil, completedAt: Int?? = nil,
                deleted: Bool? = nil, name: String? = nil, archivedAt: Int?? = nil) {
        self.list = list
        self.order = order
        self.title = title
        self.notes = notes
        self.when = when
        self.deadline = deadline
        self.completedAt = completedAt
        self.deleted = deleted
        self.name = name
        self.archivedAt = archivedAt
    }
}

extension Patch: Codable {
    enum Key: String, CodingKey {
        case list, order, title, notes, when, deadline, completedAt, deleted, name, archivedAt
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Key.self)
        for key in c.allKeys {
            let isNull = (try? c.decodeNil(forKey: key)) ?? false
            switch key {
            case .list: list = try? c.decode(String.self, forKey: key)
            case .order: order = try? c.decode(String.self, forKey: key)
            case .title: title = try? c.decode(String.self, forKey: key)
            case .notes: notes = try? c.decode(String.self, forKey: key)
            case .name: name = try? c.decode(String.self, forKey: key)
            case .deleted: deleted = try? c.decode(Bool.self, forKey: key)
            case .when: when = isNull ? .some(nil) : (try? c.decode(CalendarDate.self, forKey: key)).map { .some($0) }
            case .deadline: deadline = isNull ? .some(nil) : (try? c.decode(CalendarDate.self, forKey: key)).map { .some($0) }
            case .completedAt: completedAt = isNull ? .some(nil) : Self.epochMs(c, key)
            case .archivedAt: archivedAt = isNull ? .some(nil) : Self.epochMs(c, key)
            }
        }
    }

    private static func epochMs(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> Int?? {
        guard let v = try? c.decode(Int.self, forKey: key), v >= 0 else { return nil }
        return .some(v)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        func put<T: Encodable>(_ value: T??, _ key: Key) throws {
            switch value {
            case .none: break
            case .some(.none): try c.encodeNil(forKey: key)
            case .some(.some(let v)): try c.encode(v, forKey: key)
            }
        }
        try c.encodeIfPresent(list, forKey: .list)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(notes, forKey: .notes)
        try put(when, .when)
        try put(deadline, .deadline)
        try put(completedAt, .completedAt)
        try c.encodeIfPresent(deleted, forKey: .deleted)
        try c.encodeIfPresent(name, forKey: .name)
        try put(archivedAt, .archivedAt)
    }
}

/// One change to one entity: an envelope, a type, a target id and a `set` patch (spec §5).
public struct Op: Hashable, Sendable {
    /// Client-generated UUID, the idempotency key.
    public var id: String
    /// Client wall clock in epoch ms. Informational only: createdAt/updatedAt, never conflict resolution.
    public var at: Int
    public var type: OpType
    public var target: EntityID
    public var set: Patch
    /// Optional attribution (spec §5): who wrote the op and the change it belongs to. The reducer never reads
    /// them; the app never sets them, so its ops' JSON is unchanged.
    public var actor: String?
    public var batch: String?

    public init(id: String, at: Int, type: OpType, target: EntityID, set: Patch, actor: String? = nil, batch: String? = nil) {
        self.id = id
        self.at = at
        self.type = type
        self.target = target
        self.set = set
        self.actor = actor
        self.batch = batch
    }
}

extension Op: Codable {
    enum Key: String, CodingKey { case id, at, type, target, set, actor, batch }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: .id)
        at = (try? c.decode(Int.self, forKey: .at)) ?? 0
        type = OpType(rawValue: (try? c.decode(String.self, forKey: .type)) ?? "")
        target = try c.decode(String.self, forKey: .target)
        set = (try? c.decode(Patch.self, forKey: .set)) ?? Patch()
        actor = (try? c.decodeIfPresent(String.self, forKey: .actor)) ?? nil
        batch = (try? c.decodeIfPresent(String.self, forKey: .batch)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(at, forKey: .at)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(target, forKey: .target)
        try c.encode(set, forKey: .set)
        try c.encodeIfPresent(actor, forKey: .actor)
        try c.encodeIfPresent(batch, forKey: .batch)
    }
}

/// A pending op and the exact JSON it is sent as (spec §8 "Pending ops are sent verbatim"). For a local op that's
/// the JSON this client wrote; for an op recovered from the log after a 409 it's the server's text, which may hold
/// keys and types this client can't decode, so it is never re-encoded.
public struct PendingOp: Hashable, Sendable {
    public var op: Op
    public var json: Data

    public init(_ op: Op) {
        self.op = op
        json = op.jsonData
    }

    public init(op: Op, json: Data) {
        self.op = op
        self.json = json
    }

    /// Decodes a verbatim op line; nil if it has no readable id and target.
    public init?(json: Data) {
        guard let op = try? JSONDecoder().decode(Op.self, from: json) else { return nil }
        self.init(op: op, json: json)
    }
}

// MARK: - Canonical JSON

extension Op {
    /// The op as compact JSON with keys in a fixed order (`id, at, type, target, set`, then `actor, batch` when set,
    /// the order the server stores them in). Used for `pending.jsonl` and request bodies; hand-written because JSONEncoder doesn't keep key order.
    public var jsonData: Data {
        var out = Data()
        out.reserveCapacity(160 + (set.title?.utf8.count ?? 0) + (set.notes?.utf8.count ?? 0))
        out.append(contentsOf: #"{"id":"#.utf8)
        JSONText.appendString(id, to: &out)
        out.append(contentsOf: #","at":"#.utf8)
        out.append(contentsOf: String(at).utf8)
        out.append(contentsOf: #","type":"#.utf8)
        JSONText.appendString(type.rawValue, to: &out)
        out.append(contentsOf: #","target":"#.utf8)
        JSONText.appendString(target, to: &out)
        out.append(contentsOf: #","set":{"#.utf8)
        var first = true
        func key(_ k: String) {
            if !first { out.append(UInt8(ascii: ",")) }
            first = false
            out.append(UInt8(ascii: "\""))
            out.append(contentsOf: k.utf8)
            out.append(contentsOf: #"":"#.utf8)
        }
        func string(_ k: String, _ v: String?) {
            guard let v else { return }
            key(k)
            JSONText.appendString(v, to: &out)
        }
        func nullable(_ k: String, _ v: String??) {
            guard let v else { return }
            key(k)
            if let v { JSONText.appendString(v, to: &out) } else { out.append(contentsOf: "null".utf8) }
        }
        func number(_ k: String, _ v: Int??) {
            guard let v else { return }
            key(k)
            out.append(contentsOf: (v.map(String.init) ?? "null").utf8)
        }
        string("name", set.name)
        string("list", set.list)
        string("order", set.order)
        string("title", set.title)
        string("notes", set.notes)
        nullable("when", set.when.map { $0.map(\.string) })
        nullable("deadline", set.deadline.map { $0.map(\.string) })
        number("completedAt", set.completedAt)
        if let d = set.deleted {
            key("deleted")
            out.append(contentsOf: (d ? "true" : "false").utf8)
        }
        number("archivedAt", set.archivedAt)
        out.append(UInt8(ascii: "}"))
        for (k, v) in [("actor", actor), ("batch", batch)] {
            guard let v else { continue }
            out.append(contentsOf: ",\"\(k)\":".utf8)
            JSONText.appendString(v, to: &out)
        }
        out.append(UInt8(ascii: "}"))
        return out
    }
}

enum JSONText {
    /// Appends `s` as a JSON string literal, escaped the way `JSON.stringify` does.
    static func appendString(_ s: String, to out: inout Data) {
        out.append(UInt8(ascii: "\""))
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "\""): out.append(contentsOf: #"\""#.utf8)
            case UInt8(ascii: "\\"): out.append(contentsOf: #"\\"#.utf8)
            case 0x08: out.append(contentsOf: #"\b"#.utf8)
            case 0x0C: out.append(contentsOf: #"\f"#.utf8)
            case 0x0A: out.append(contentsOf: #"\n"#.utf8)
            case 0x0D: out.append(contentsOf: #"\r"#.utf8)
            case 0x09: out.append(contentsOf: #"\t"#.utf8)
            case 0x00..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                out.append(contentsOf: #"\u00"#.utf8)
                out.append(hex[Int(b >> 4)])
                out.append(hex[Int(b & 0xF)])
            default: out.append(b)
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}
