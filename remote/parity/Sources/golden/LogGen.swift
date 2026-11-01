import Foundation
import TasksCore

/// One fold case's time: the instant and the zone its Day is built in.
struct When {
    var label: String
    var now: Int
    var zone: String
    var day: Day { dayOf(now: now, zone: zone) }
}

/// The instants random logs are folded at: America/Toronto mostly, with both 2026 DST days, plus three other zones.
let foldTimes: [When] = {
    let edt = -240, est = -300
    var t: [When] = [
        When(label: "toronto-dst-end-0000", now: localMs(2026, 11, 1, 0, 0, offset: edt), zone: "America/Toronto"),
        When(label: "toronto-dst-end-0130a", now: localMs(2026, 11, 1, 1, 30, offset: edt), zone: "America/Toronto"),
        When(label: "toronto-dst-end-0130b", now: localMs(2026, 11, 1, 1, 30, offset: est), zone: "America/Toronto"),
        When(label: "toronto-dst-end-1200", now: localMs(2026, 11, 1, 12, 0, offset: est), zone: "America/Toronto"),
        When(label: "toronto-dst-end-2359", now: localMs(2026, 11, 1, 23, 59, offset: est, s: 59, ms: 999), zone: "America/Toronto"),
        When(label: "toronto-dst-start-0000", now: localMs(2026, 3, 8, 0, 0, offset: est), zone: "America/Toronto"),
        When(label: "toronto-dst-start-0159", now: localMs(2026, 3, 8, 1, 59, offset: est, s: 59, ms: 999), zone: "America/Toronto"),
        When(label: "toronto-dst-start-0300", now: localMs(2026, 3, 8, 3, 0, offset: edt), zone: "America/Toronto"),
        When(label: "toronto-dst-start-1200", now: localMs(2026, 3, 8, 12, 0, offset: edt), zone: "America/Toronto"),
        When(label: "toronto-dst-start-2359", now: localMs(2026, 3, 8, 23, 59, offset: edt, s: 59, ms: 999), zone: "America/Toronto"),
        When(label: "toronto-oct30-noon", now: localMs(2026, 10, 30, 12, 0, offset: edt), zone: "America/Toronto"),
        When(label: "toronto-nye-2359", now: localMs(2026, 12, 31, 23, 59, offset: est, s: 59, ms: 999), zone: "America/Toronto"),
        When(label: "toronto-ny-0000", now: localMs(2027, 1, 1, 0, 0, offset: est), zone: "America/Toronto"),
        When(label: "toronto-leap-0900", now: localMs(2028, 2, 29, 9, 0, offset: est), zone: "America/Toronto"),
        When(label: "london-bst-start", now: utcMs(2026, 3, 29, 11, 0), zone: "Europe/London"),
        When(label: "london-bst-end-0130", now: utcMs(2026, 10, 25, 0, 30), zone: "Europe/London"),
        When(label: "london-nov1-2359", now: utcMs(2026, 11, 1, 23, 59, 59, 999), zone: "Europe/London"),
        When(label: "kolkata-midnight", now: localMs(2026, 11, 1, 0, 0, offset: 330), zone: "Asia/Kolkata"),
        When(label: "kolkata-noon", now: localMs(2026, 11, 1, 12, 0, offset: 330), zone: "Asia/Kolkata"),
        When(label: "lordhowe-dst-end", now: localMs(2026, 4, 5, 12, 0, offset: 630), zone: "Australia/Lord_Howe"),
        When(label: "lordhowe-dst-start", now: localMs(2026, 10, 4, 0, 0, offset: 630), zone: "Australia/Lord_Howe"),
        When(label: "lordhowe-nov1", now: localMs(2026, 11, 1, 12, 0, offset: 660), zone: "Australia/Lord_Howe"),
    ]
    t.sort { $0.label < $1.label }
    return t
}()

/// Writes random but plausible logs as raw text: mostly canonical op JSON (what the server stores), with a share
/// of lines the lenient decoders must cope with.
struct LogGen {
    var rng: Rng
    let when: When
    let today: CalendarDate
    let day: Day
    var at: Int
    /// The fold of everything written so far (confirmed, then visible once pending ops start).
    var state = AppState()
    var taskIDs: [String] = []
    var listIDs: [String] = []
    /// Lists tasks refer to that are never created.
    var ghostLists: [String] = []
    let weirdIDs: Bool
    var lastOrders: [String] = ["a0"]

    init(seed: UInt64, when: When, weirdIDs: Bool) {
        rng = Rng(seed)
        self.when = when
        day = when.day
        today = day.date
        at = when.now - 20 * 86_400_000
        self.weirdIDs = weirdIDs
        ghostLists = [rng.uuid()]
    }

    // MARK: Values

    mutating func tick() -> Int {
        at += rng.int(in: 1...90_000)
        return at
    }

    mutating func newID(list: Bool) -> String {
        if weirdIDs, rng.chance(0.3) {
            let odd = ["é-\(rng.int(100))", "😀\(rng.int(100))", "～\(rng.int(100))", "\u{FF61}x\(rng.int(9))",
                       "Z\(rng.int(100))", "a\(rng.int(100))", "__proto__", "constructor", "toString", "0\(rng.int(9))",
                       "\(rng.int(100))", "id with space", "q\"uote", "ﬃ\(rng.int(9))"]
            return rng.pick(odd)
        }
        if weirdIDs, rng.chance(0.15), let other = (list ? taskIDs : listIDs).last { return other } // same id, other kind
        switch rng.int(10) {
        case 0: return rng.uuid().uppercased()
        case 1: return (list ? "L" : "t") + String(rng.int(1000))
        default: return rng.uuid()
        }
    }

    mutating func orderKey() -> String {
        switch rng.int(12) {
        case 0...3:
            return rng.pick(["a0", "a1", "a2", "a0V", "Zz", "b00", "a1", "a5", "aV", "a0", "Zzz", "a0G"])
        case 4...8:
            let a = rng.pick(lastOrders)
            let b = (try? FractionalIndex.keyBetween(a, nil)) ?? "a0"
            let key = rng.chance(0.5) ? b : ((try? FractionalIndex.keyBetween(a, b)) ?? b)
            lastOrders.append(key)
            if lastOrders.count > 8 { lastOrders.removeFirst() }
            return key
        case 9:
            return rng.pick(lastOrders)
        case 10:
            return rng.pick(["A0", "a", "0", "z", "a00", "a0a", "a0A", "A", "Zz0"])
        default:
            return weirdIDs ? rng.pick(["é", "😀", "～", "a0\u{301}", "", "~"]) : rng.pick(["a0", "a3"])
        }
    }

    mutating func title() -> String {
        rng.pick(["Buy milk", "", "Lab report", "Call mom", "naïve café", "emoji 🎉 party", "quote \" and \\ backslash",
                  "tab\tand\nnewline", "nul\u{0}byte", "e\u{301} combining", "RTL שלום", "line\u{2028}sep", " padded ",
                  "</script>", "\u{1F}unit sep", "\u{7F}del", "a/b", String(repeating: "long ", count: 40),
                  "Heading: Errands", "x"])
    }

    mutating func notes() -> String {
        rng.pick(["", "**bold** notes", "- [ ] item\n- [x] done", "line1\nline2", "# H1\n\ntext", "😀"])
    }

    mutating func relDate() -> CalendarDate {
        let k = rng.pick([-400, -30, -3, -2, -1, 0, 0, 0, 1, 1, 2, 3, 7, 30, 400])
        return CalendarDate(dayNumber: today.dayNumber + k) ?? today
    }

    mutating func completedAt() -> Int {
        let len = day.end - day.start
        switch rng.int(12) {
        case 0: return day.start
        case 1: return day.end - 1
        case 2: return day.end
        case 3: return day.start - 1
        case 4: return when.now
        case 5: return day.start - rng.int(in: 1...86_400_000)
        case 6: return day.end + rng.int(in: 0...86_400_000)
        case 7: return rng.chance(0.5) ? 0 : day.start - 400 * 86_400_000
        default: return day.start + rng.int(len)
        }
    }

    mutating func archivedAt() -> Int {
        rng.pick([when.now - rng.int(in: 1...90_000_000), when.now, 1, 0, at])
    }

    // MARK: Ops

    mutating func existingTask() -> String {
        if taskIDs.isEmpty || rng.chance(0.04) { return newID(list: false) }
        return rng.pick(taskIDs)
    }

    mutating func existingList() -> String {
        if listIDs.isEmpty || rng.chance(0.04) { return newID(list: true) }
        return rng.pick(listIDs)
    }

    mutating func listForTask() -> String {
        if rng.chance(0.08) { return rng.pick(ghostLists) }
        return existingList()
    }

    mutating func envelope(_ type: OpType, _ target: String, _ set: Patch) -> Op {
        var op = Op(id: rng.uuid(), at: tick(), type: type, target: target, set: set)
        if rng.chance(0.05) { op.actor = rng.pick(["agent:claude-code", "agent:claude-ai", "user", "é😀"]) }
        if rng.chance(0.05) { op.batch = rng.uuid() }
        return op
    }

    mutating func taskPatch() -> Patch {
        var p = Patch()
        repeat {
            switch rng.int(11) {
            case 0: p.title = title()
            case 1: p.notes = notes()
            case 2: p.when = rng.chance(0.25) ? .some(nil) : .some(relDate())
            case 3: p.deadline = rng.chance(0.25) ? .some(nil) : .some(relDate())
            case 4, 5: p.completedAt = rng.chance(0.2) ? .some(nil) : .some(completedAt())
            case 6: p.deleted = rng.chance(0.7)
            case 7, 8:
                p.list = listForTask()
                p.order = orderKey()
            case 9: p.order = orderKey()
            default: p.list = listForTask()
            }
        } while rng.chance(0.35)
        return p
    }

    mutating func listPatch() -> Patch {
        var p = Patch()
        repeat {
            switch rng.int(5) {
            case 0: p.name = rng.pick(["Inbox", "School", "Home", "", "Ünïcode 😀"])
            case 1: p.order = orderKey()
            case 2: p.notes = notes()
            default: p.archivedAt = rng.chance(0.35) ? .some(nil) : .some(archivedAt())
            }
        } while rng.chance(0.3)
        return p
    }

    /// A well-formed op, as canonical text.
    mutating func wellFormed() -> String {
        let r = rng.int(100)
        let op: Op
        switch r {
        case 0..<9:
            let id = rng.chance(0.06) && !listIDs.isEmpty ? rng.pick(listIDs) : newID(list: true)
            var p = Patch(order: orderKey(), name: rng.pick(["Inbox", "School", "Home", "Errands", "", "😀"]))
            if rng.chance(0.2) { p.notes = notes() }
            op = envelope(.listCreate, id, p)
        case 9..<17:
            op = envelope(.listUpdate, existingList(), listPatch())
        case 17..<38:
            let id = rng.chance(0.04) && !taskIDs.isEmpty ? rng.pick(taskIDs) : newID(list: false)
            var p = Patch(list: listForTask(), order: orderKey())
            if rng.chance(0.85) { p.title = title() }
            if rng.chance(0.2) { p.notes = notes() }
            if rng.chance(0.35) { p.when = .some(relDate()) }
            if rng.chance(0.25) { p.deadline = .some(relDate()) }
            if rng.chance(0.08) { p.completedAt = .some(completedAt()) }
            if rng.chance(0.03) { p.when = .some(nil) }
            if rng.chance(0.12) { p.kind = Patch.heading } else if rng.chance(0.02) { p.kind = "other" }
            op = envelope(.taskCreate, id, p)
        default:
            op = envelope(.taskUpdate, existingTask(), taskPatch())
        }
        return canonical(op)
    }

    /// An op text the server wouldn't write today but a client must read: wrong types, unknown keys and types,
    /// odd envelopes, unreadable ops.
    mutating func malformed() -> String {
        func q(_ s: String) -> String { JSONOut.quote(s) }
        func obj(_ pairs: [(String, String)]) -> String {
            "{" + pairs.map { q($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
        }
        let id = q(rng.uuid())
        let atText = String(tick())
        func env(_ type: String, _ target: String, _ set: String) -> [(String, String)] {
            [("id", id), ("at", atText), ("type", q(type)), ("target", q(target)), ("set", set)]
        }
        switch rng.int(12) {
        case 0, 1, 2:
            // Wrong-typed and unknown keys on an update, one value per key.
            let choices: [(String, String)] = [
                ("title", "5"), ("title", "null"), ("title", "[\"x\"]"), ("title", q(title())),
                ("notes", q("kept")), ("notes", "{}"), ("color", q("red")), ("priority", "3"), ("tags", "[\"a\",1]"),
                ("when", q("2026-02-30")), ("when", "20261101"), ("when", q("2026-11-01T00:00")), ("when", "null"),
                ("when", q(relDate().string)), ("deadline", q(relDate().string)), ("deadline", q("")),
                ("completedAt", q("soon")), ("completedAt", "-5"), ("completedAt", "1.5"),
                ("completedAt", "\(completedAt()).0"), ("completedAt", "null"), ("completedAt", String(completedAt())),
                ("deleted", "1"), ("deleted", q("true")), ("deleted", "null"), ("deleted", "true"), ("deleted", "false"),
                ("list", "null"), ("list", "7"), ("order", "7"), ("order", q(orderKey())),
                ("kind", q("heading")), ("kind", "5"), ("name", q("list name")), ("archivedAt", "5"),
                ("archivedAt", "null"),
            ]
            var used: Set<String> = []
            var set: [(String, String)] = []
            for _ in 0..<rng.int(in: 1...5) {
                let c = rng.pick(choices)
                if used.insert(c.0).inserted { set.append(c) }
            }
            return obj(env("task.update", existingTask(), obj(set)))
        case 3:
            // The same for a list.
            let choices: [(String, String)] = [
                ("name", "5"), ("name", q("Renamed")), ("name", "null"), ("order", "[]"), ("notes", q("n")),
                ("archivedAt", "-1"), ("archivedAt", q("1")), ("archivedAt", String(archivedAt())), ("archivedAt", "null"),
                ("archivedAt", "2.5"), ("title", q("not a list key")), ("deleted", "true"), ("completedAt", "5"),
                ("emoji", q("🎉")),
            ]
            var used: Set<String> = []
            var set: [(String, String)] = []
            for _ in 0..<rng.int(in: 1...4) {
                let c = rng.pick(choices)
                if used.insert(c.0).inserted { set.append(c) }
            }
            return obj(env("list.update", existingList(), obj(set)))
        case 4:
            // Creates with missing or wrong-typed required keys, or keys a create ignores.
            let t = newID(list: false)
            let l = listForTask()
            let sets = [
                obj([("list", q(l))]),
                obj([("order", q("a0")), ("title", q("no list"))]),
                obj([("list", q(l)), ("order", "7")]),
                obj([("list", "null"), ("order", q("a0"))]),
                obj([("list", q(l)), ("order", q(orderKey())), ("deleted", "true"), ("title", q("born deleted?"))]),
                obj([("list", q(l)), ("order", q(orderKey())), ("kind", "5"), ("title", q("kind 5"))]),
                obj([("list", q(l)), ("order", q(orderKey())), ("kind", q("Heading")), ("title", q("kind case"))]),
                obj([("list", q(l)), ("order", q(orderKey())), ("kind", q("heading")), ("completedAt", String(completedAt())),
                     ("when", q(relDate().string)), ("deadline", q(relDate().string)), ("title", q("dated heading"))]),
                obj([("list", q(l)), ("order", q(orderKey())), ("title", "null"), ("notes", "5"), ("when", "null")]),
            ]
            return obj(env("task.create", t, rng.pick(sets)))
        case 5:
            let lid = newID(list: true)
            let sets = [
                obj([("name", q("no order"))]),
                obj([("order", q("a0"))]),
                obj([("name", q("Archived?")), ("order", q(orderKey())), ("archivedAt", "7")]),
                obj([("name", "5"), ("order", q("a0"))]),
                obj([("name", q("ok")), ("order", q(orderKey())), ("notes", "[]"), ("x", "null")]),
            ]
            return obj(env("list.create", lid, rng.pick(sets)))
        case 6:
            // Unknown op types, aimed at real entities.
            let type = rng.pick(["task.archive", "list.delete", "", "Task.create", "task.create.v2", "comment.add", "task"])
            let target = rng.chance(0.5) ? existingTask() : existingList()
            return obj(env(type, target, obj([("title", q("ignored")), ("list", q(existingList())), ("order", q("a0")),
                                              ("name", q("ignored"))])))
        case 7:
            // Envelope oddities: `at` and `set` of the wrong type or missing, extra keys, keys in another order.
            let target = q(existingTask())
            let set = obj([("title", q(title()))])
            let variants: [[(String, String)]] = [
                [("id", id), ("at", q("123")), ("type", q("task.update")), ("target", target), ("set", set)],
                [("id", id), ("type", q("task.update")), ("target", target), ("set", set)],
                [("id", id), ("at", "-5"), ("type", q("task.update")), ("target", target), ("set", set)],
                [("id", id), ("at", atText + ".0"), ("type", q("task.update")), ("target", target), ("set", set)],
                [("id", id), ("at", "1.5"), ("type", q("task.update")), ("target", target), ("set", set)],
                [("id", id), ("at", atText), ("type", q("task.update")), ("target", target)],
                [("id", id), ("at", atText), ("type", q("task.update")), ("target", target), ("set", "null")],
                [("id", id), ("at", atText), ("type", q("task.update")), ("target", target), ("set", "[]")],
                [("id", id), ("at", atText), ("type", "5"), ("target", target), ("set", set)],
                [("set", set), ("target", target), ("type", q("task.update")), ("at", atText), ("id", id), ("v", "2")],
                [("id", id), ("at", atText), ("type", q("task.update")), ("target", target), ("set", set),
                 ("actor", "7"), ("batch", "null"), ("meta", obj([("k", "[1,{}]")]))],
                [("id", id), ("at", atText), ("type", q("task.update")), ("target", target), ("set", set),
                 ("actor", q("")), ("batch", q(""))],
            ]
            return obj(rng.pick(variants))
        case 8:
            // Undecodable as an Op: the entry still holds its seq, the reducer skips it.
            let target = q(existingTask())
            let set = obj([("title", q("never applied"))])
            return rng.pick([
                obj([("at", atText), ("type", q("task.update")), ("target", target), ("set", set)]),
                obj([("id", "5"), ("at", atText), ("type", q("task.update")), ("target", target), ("set", set)]),
                obj([("id", id), ("at", atText), ("type", q("task.update")), ("set", set)]),
                obj([("id", id), ("at", atText), ("type", q("task.update")), ("target", "null"), ("set", set)]),
                "null", "\"op\"", "[]", "{}", "42",
            ])
        case 9:
            // Keys of the other entity type, and `kind` on an update.
            if rng.chance(0.5) {
                return obj(env("task.update", existingTask(), obj([("name", q("list name")), ("archivedAt", "5"),
                                                                  ("kind", q(rng.pick(["heading", "task"])))])))
            }
            return obj(env("list.update", existingList(), obj([("title", q("task title")), ("deleted", "true"),
                                                               ("completedAt", "5"), ("list", q("x"))])))
        case 10:
            // Escaped key names and values decode like plain ones.
            return obj(env("task.update", existingTask(), obj([("t\\u0069tle", q("escaped key")),
                                                              ("notes", "\"\\u00e9\\ud83c\\udf89\\/\\b\\f\"")])))
                .replacingOccurrences(of: "\"t\\\\u0069tle\"", with: "\"t\\u0069tle\"")
        default:
            // An update with a key present twice is avoided (JSON.parse and JSONDecoder disagree); this is a
            // plain create with whitespace inside the op.
            return "{ \"id\" : \(id) , \"at\" : \(atText), \"type\":\"task.create\", \"target\": \(q(newID(list: false))), "
                + "\"set\": { \"list\": \(q(listForTask())), \"order\": \(q(orderKey())), \"title\": \(q(title())) } }"
        }
    }

    /// One op text, applied to `state` and remembered.
    mutating func next(malformedRate: Double) -> String {
        let text = rng.chance(malformedRate) ? malformed() : wellFormed()
        record(text)
        return text
    }

    mutating func record(_ text: String) {
        guard let op = decodeOp(text) else { return }
        if op.type == .taskCreate, !taskIDs.contains(op.target) { taskIDs.append(op.target) }
        if op.type == .listCreate, !listIDs.contains(op.target) { listIDs.append(op.target) }
        state.apply(op)
    }

    /// A log line around `op`, mostly as the server writes it.
    mutating func entry(seq: Int, op: String) -> String {
        let received = "1761811261234"
        let hash = JSONOut.quote(rng.hash())
        switch rng.int(40) {
        case 0: return #"{"op":\#(op),"seq":\#(seq),"hash":\#(hash),"received":\#(received)}"#
        case 1: return #"{"seq":\#(seq),"hash":\#(hash),"op":\#(op),"extra":"a b","sig":null}"#
        case 2: return #"{"seq":\#(seq),"received":"later","hash":\#(hash),"op":\#(op)}"#
        case 3: return #"{ "seq": \#(seq), "received": \#(received), "hash": \#(hash), "op": \#(op) }"#
        default: return #"{"seq":\#(seq),"received":\#(received),"hash":\#(hash),"op":\#(op)}"#
        }
    }
}
