import Foundation
import TasksCore

/// core-fold.json and inverse.json, plus the op texts op-json.json reuses.
@MainActor
enum CoreFold {
    struct Case {
        var name: String
        var entries: [String]
        var pending: [String]
        var when: When
    }

    struct Output {
        var fold: J
        var foldCount: Int
        var inverse: J
        var inverseCount: Int
        /// Every distinct op text in the logs and pending queues, in first-seen order.
        var opTexts: [String]
    }

    static func build() throws -> Output {
        var cases = try fixtureCases()
        cases += handmadeCases()
        cases += randomCases()

        var json: [J] = []
        var opTexts: [String] = []
        var seenTexts: Set<String> = []
        func note(_ text: String) {
            if seenTexts.insert(text).inserted { opTexts.append(text) }
        }
        for c in cases {
            json.append(try fold(c))
            for e in c.entries {
                if let raw = try? JSONSlices.member(named: "op", in: Data(e.utf8)) {
                    note(String(decoding: raw, as: UTF8.self))
                }
            }
            for p in c.pending { note(p) }
        }
        let inverse = inverseCases(cases)
        return Output(fold: .obj(["cases": .arr(json)]), foldCount: json.count, inverse: .obj(["cases": .arr(inverse)]),
                      inverseCount: inverse.count, opTexts: opTexts)
    }

    // MARK: - Folding one case

    static func decodeEntries(_ lines: [String]) throws -> [LogEntry] {
        try lines.map { try JSONDecoder().decode(LogEntry.self, from: Data($0.utf8)) }
    }

    static func fold(_ c: Case) throws -> J {
        let entries = try decodeEntries(c.entries)
        for (a, b) in zip(entries, entries.dropFirst()) where b.seq != a.seq + 1 {
            warnings.append("\(c.name): entries not contiguous at \(a.seq)")
        }
        let confirmed = AppState.replay(entries.map(\.op))
        let pending = c.pending.compactMap { PendingOp(json: Data($0.utf8)) }
        let day = c.when.day
        let p = Projection(confirmed: confirmed, pending: pending, day: day)

        // Consistency checks on the Swift side: visible state is the plain fold of log + pending, and an
        // incrementally built projection shows the same views as one built from scratch.
        let all = AppState.replay(entries.map(\.op) + pending.map(\.op))
        for id in p.allTaskIDs where p.task(id) != all.tasks[id] { warnings.append("\(c.name): visible task \(id) != replay") }
        for id in p.allListIDs where p.list(id) != all.lists[id] { warnings.append("\(c.name): visible list \(id) != replay") }
        let listIDs = knownLists(p, confirmed: confirmed)
        let v = views(p, listIDs: listIDs)
        let incremental = Projection(confirmed: confirmed, pending: [], day: day)
        incremental.perform(pending)
        if JSONOut.compact(views(incremental, listIDs: listIDs)) != JSONOut.compact(v) {
            warnings.append("\(c.name): incremental projection's views differ from a rebuild")
        }

        var tasks: [String: J] = [:]
        for (id, t) in confirmed.tasks { tasks[id] = encode(t) }
        var lists: [String: J] = [:]
        for (id, l) in confirmed.lists { lists[id] = encode(l) }
        var visibleTasks: [String: J] = [:]
        for id in p.allTaskIDs { visibleTasks[id] = encode(p.task(id)!) }
        var visibleLists: [String: J] = [:]
        for id in p.allListIDs { visibleLists[id] = encode(p.list(id)!) }

        return .obj([
            "name": .str(c.name),
            "entries": .ids(c.entries),
            "pending": .ids(c.pending),
            "now": .int(c.when.now),
            "timeZone": .str(c.when.zone),
            "expect": .obj([
                "tasks": .obj(tasks), "lists": .obj(lists),
                "visibleTasks": .obj(visibleTasks), "visibleLists": .obj(visibleLists),
                "views": v,
            ]),
        ])
    }

    /// Every list id there is a view for: lists that exist (live and deleted) and lists tasks point at.
    static func knownLists(_ p: Projection, confirmed: AppState) -> [String] {
        var ids = p.allListIDs
        for id in p.allTaskIDs { if let t = p.task(id) { ids.insert(t.list) } }
        for t in confirmed.tasks.values { ids.insert(t.list) }
        return ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    static func views(_ p: Projection, listIDs: [String]) -> J {
        var lists: [String: J] = [:]
        for id in listIDs {
            lists[id] = .obj([
                "open": .ids(p.openTasks(in: id).ids),
                "headings": .ids(p.headings(in: id).ids),
                "openCount": .int(p.openTaskCount(in: id)),
                "completed": .ids(p.completedTasks(in: id).ids),
                "today": .ids(p.todayTasks(in: id).ids),
                "orderedIncludingCompleted": .ids(p.orderedTasksIncludingCompleted(in: id).map(\.id)),
            ])
        }
        var sections: [String: J] = [:]
        var headingOf: [String: J] = [:]
        for id in p.allTaskIDs.sorted() {
            guard let t = p.task(id), !t.deleted else { continue }
            headingOf[id] = .s(p.heading(of: id))
            if t.isHeading { sections[id] = .ids(p.section(of: id)) }
        }
        return .obj([
            "day": encode(p.day),
            "activeLists": .ids(p.activeLists.ids),
            "deletedLists": .ids(p.deletedLists.ids),
            // A task in a deleted list counts as deleted (INTERACTIONS-v2 §28).
            "liveTasks": .ids(p.allTaskIDs.filter { p.isLive(task: $0) }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }),
            "todayDone": .ids(p.todayDone.ids),
            "lists": .obj(lists),
            "sections": .obj(sections),
            "headingOf": .obj(headingOf),
        ])
    }

    // MARK: - The cases

    /// Each 200 response's entries in fixtures/sync, verbatim, plus the whole 2,345-entry log.
    static func fixtureCases() throws -> [Case] {
        let dir = repoRoot.appendingPathComponent("fixtures/sync")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") && $0.first?.isNumber == true }
            .sorted()
        let when = When(label: "fixtures", now: localMs(2026, 10, 30, 12, 0, offset: -240), zone: "America/Toronto")
        var out: [Case] = []
        for f in files {
            let data = try Data(contentsOf: dir.appendingPathComponent(f))
            let response = try JSONSlices.member(named: "response", in: data)
            guard let body = try? JSONSlices.member(named: "body", in: response),
                  let raw = try? JSONSlices.arrayElements(named: "entries", in: body), !raw.isEmpty else { continue }
            out.append(Case(name: "fixture/" + f, entries: raw.map { String(decoding: $0, as: UTF8.self) }, pending: [],
                            when: when))
        }
        let log = try String(contentsOf: dir.appendingPathComponent("log-2345.jsonl"), encoding: .utf8)
        out.append(Case(name: "fixture/log-2345.jsonl", entries: log.split(separator: "\n").map(String.init), pending: [],
                        when: when))
        return out
    }

    /// Small logs aimed at one rule each.
    static func handmadeCases() -> [Case] {
        let toronto = foldTimes.first { $0.label == "toronto-dst-end-1200" }!
        let d = toronto.day
        let today = d.date.string
        let yesterday = CalendarDate(dayNumber: d.date.dayNumber - 1)!.string
        let tomorrow = CalendarDate(dayNumber: d.date.dayNumber + 1)!.string
        var seq = 0
        func e(_ op: String) -> String {
            defer { seq += 1 }
            return #"{"seq":\#(seq),"received":1761811261234,"hash":"\#(String(repeating: "ab", count: 32))","op":\#(op)}"#
        }
        func lines(_ ops: [String]) -> [String] {
            seq = 0
            return ops.map(e)
        }
        var n = 0
        func op(_ type: String, _ target: String, _ set: String, at: Int? = nil) -> String {
            n += 1
            return #"{"id":"h-\#(n)","at":\#(at ?? (1_761_811_200_000 + n * 1000)),"type":"\#(type)","target":"\#(target)","set":\#(set)}"#
        }
        var out: [Case] = []

        // Headings, sections and counts: completed tasks keep their place under their heading.
        out.append(Case(name: "handmade/headings-and-sections", entries: lines([
            op("list.create", "L", #"{"name":"L","order":"a0"}"#),
            op("task.create", "t0", #"{"list":"L","order":"a0","title":"before any heading"}"#),
            op("task.create", "h1", #"{"list":"L","order":"a1","title":"H1","kind":"heading","when":"\#(yesterday)"}"#),
            op("task.create", "t1", #"{"list":"L","order":"a2","title":"under h1","when":"\#(today)"}"#),
            op("task.create", "t2", #"{"list":"L","order":"a3","title":"done under h1","when":"\#(today)","completedAt":\#(d.start + 1000)}"#),
            op("task.create", "h2", #"{"list":"L","order":"a4","title":"H2","kind":"heading"}"#),
            op("task.update", "h2", #"{"completedAt":\#(d.start + 5)}"#),
            op("task.create", "t3", #"{"list":"L","order":"a5","title":"under h2"}"#),
            op("task.create", "h3", #"{"list":"L","order":"a6","kind":"heading"}"#),
            op("task.update", "h3", #"{"deleted":true}"#),
            op("task.create", "t4", #"{"list":"L","order":"a7","title":"under deleted h3"}"#),
            op("task.create", "h4", #"{"list":"L","order":"a5","kind":"heading","title":"tied with t3"}"#),
        ]), pending: [], when: toronto))

        // Today and todayDone across midnight, deleted and missing lists.
        out.append(Case(name: "handmade/today-boundaries", entries: lines([
            op("list.create", "A", #"{"name":"active","order":"a0"}"#),
            op("list.create", "R", #"{"name":"archived","order":"a1"}"#),
            op("list.update", "R", #"{"archivedAt":\#(d.start - 10)}"#),
            op("task.create", "w-today", #"{"list":"A","order":"a0","when":"\#(today)"}"#),
            op("task.create", "w-tomorrow", #"{"list":"A","order":"a1","when":"\#(tomorrow)"}"#),
            op("task.create", "d-today", #"{"list":"A","order":"a2","deadline":"\#(today)","when":"\#(tomorrow)"}"#),
            op("task.create", "c-start", #"{"list":"A","order":"a3","when":"\#(today)","completedAt":\#(d.start)}"#),
            op("task.create", "c-end-1", #"{"list":"A","order":"a4","when":"\#(yesterday)","completedAt":\#(d.end - 1)}"#),
            op("task.create", "c-end", #"{"list":"A","order":"a5","when":"\#(today)","completedAt":\#(d.end)}"#),
            op("task.create", "c-before", #"{"list":"A","order":"a6","when":"\#(today)","completedAt":\#(d.start - 1)}"#),
            op("task.create", "c-nodate", #"{"list":"A","order":"a7","completedAt":\#(d.start + 60000)}"#),
            op("task.create", "c-future-when", #"{"list":"A","order":"a8","when":"\#(tomorrow)","completedAt":\#(d.start + 60000)}"#),
            op("task.create", "r-open", #"{"list":"R","order":"a0","when":"\#(today)"}"#),
            op("task.create", "r-done", #"{"list":"R","order":"a1","when":"\#(today)","completedAt":\#(d.start + 7)}"#),
            op("task.create", "g-open", #"{"list":"ghost","order":"a0","when":"\#(today)"}"#),
            op("task.create", "g-done", #"{"list":"ghost","order":"a1","when":"\#(today)","completedAt":\#(d.start + 9)}"#),
            op("task.create", "tie-b", #"{"list":"A","order":"b0","when":"\#(today)","completedAt":\#(d.start + 100)}"#),
            op("task.create", "tie-a", #"{"list":"A","order":"b1","when":"\#(today)","completedAt":\#(d.start + 100)}"#),
        ]), pending: [
            // Restore R and delete A while pending: todayDone moves with them.
            op("list.update", "R", #"{"archivedAt":null}"#),
            op("list.update", "A", #"{"archivedAt":\#(d.start + 1)}"#),
            op("list.update", "A", #"{"archivedAt":null}"#),
            op("task.update", "c-before", #"{"completedAt":\#(d.start + 2)}"#),
        ], when: toronto))

        // Delete List (INTERACTIONS-v2 §28): a task deleted before its list stays deleted when the list is restored;
        // while the list is deleted none of its tasks is live; one task put back in another list stays there.
        out.append(Case(name: "handmade/deleted-list", entries: lines([
            op("list.create", "S", #"{"name":"School","order":"a0"}"#),
            op("list.create", "I", #"{"name":"Inbox","order":"a1"}"#),
            op("task.create", "s-open", #"{"list":"S","order":"a0","when":"\#(today)"}"#),
            op("task.create", "s-done", #"{"list":"S","order":"a1","when":"\#(today)","completedAt":\#(d.start + 3)}"#),
            op("task.create", "s-old", #"{"list":"S","order":"a2"}"#),
            op("task.update", "s-old", #"{"deleted":true}"#),
            op("task.create", "s-out", #"{"list":"S","order":"a3"}"#),
            op("list.update", "S", #"{"archivedAt":\#(d.start + 5)}"#),
            op("task.update", "s-out", #"{"list":"I","order":"a0"}"#),
        ]), pending: [
            op("list.update", "S", #"{"archivedAt":null}"#),
            op("list.update", "S", #"{"archivedAt":\#(d.start + 9)}"#),
        ], when: toronto))

        // Ties broken by id as UTF-8 bytes: in UTF-16 order "😀" sorts before "～", in UTF-8 after.
        out.append(Case(name: "handmade/utf8-id-ties", entries: lines([
            op("list.create", "L", #"{"name":"L","order":"a0"}"#),
            op("list.create", "～", #"{"name":"fullwidth","order":"a0"}"#),
            op("list.create", "😀", #"{"name":"emoji","order":"a0"}"#),
            op("list.create", "é", #"{"name":"e acute","order":"a0"}"#),
            op("list.create", "Z", #"{"name":"Z","order":"a0"}"#),
            op("task.create", "😀", #"{"list":"L","order":"a0"}"#),
            op("task.create", "～", #"{"list":"L","order":"a0"}"#),
            op("task.create", "\u{FFFD}", #"{"list":"L","order":"a0"}"#),
            op("task.create", "a", #"{"list":"L","order":"a0"}"#),
            op("task.create", "B", #"{"list":"L","order":"a0"}"#),
            op("task.create", "o1", #"{"list":"L","order":"😀"}"#),
            op("task.create", "o2", #"{"list":"L","order":"～"}"#),
            op("task.create", "o3", #"{"list":"L","order":""}"#),
            op("task.create", "o4", #"{"list":"L","order":"a0́"}"#),
            op("task.create", "c1", #"{"list":"L","order":"a0","completedAt":5}"#),
            op("task.create", "c0", #"{"list":"L","order":"a0","completedAt":5}"#),
        ]), pending: [], when: toronto))

        // Ids that are Object.prototype names, and one id used for both a task and a list.
        out.append(Case(name: "handmade/prototype-ids", entries: lines([
            op("list.create", "__proto__", #"{"name":"proto","order":"a0"}"#),
            op("list.create", "constructor", #"{"name":"ctor","order":"a1"}"#),
            op("task.create", "__proto__", #"{"list":"constructor","order":"a0","title":"t","when":"\#(today)"}"#),
            op("task.create", "toString", #"{"list":"__proto__","order":"a0","kind":"heading"}"#),
            op("task.create", "hasOwnProperty", #"{"list":"__proto__","order":"a1"}"#),
            op("task.create", "constructor", #"{"list":"valueOf","order":"a1"}"#),
        ]), pending: [op("task.update", "__proto__", #"{"title":"renamed"}"#)], when: toronto))

        // Pending ops: creates, edits of confirmed entities, creates on confirmed ids (ignored), unreadable lines.
        out.append(Case(name: "handmade/pending-overlay", entries: lines([
            op("list.create", "L", #"{"name":"L","order":"a0"}"#),
            op("task.create", "t1", #"{"list":"L","order":"a0","title":"confirmed"}"#),
        ]), pending: [
            op("task.create", "t1", #"{"list":"X","order":"a9","title":"create on a confirmed id"}"#),
            op("task.update", "t1", #"{"title":"edited","list":"M","order":"a1"}"#),
            op("list.create", "M", #"{"name":"pending list","order":"a1"}"#),
            op("task.create", "t2", #"{"list":"M","order":"a0","when":"\#(today)"}"#),
            op("task.update", "t2", #"{"completedAt":\#(d.start + 3)}"#),
            op("task.update", "nope", #"{"title":"unknown id"}"#),
            op("task.zap", "t1", #"{"title":"unknown type"}"#),
            #"{"at":1,"type":"task.update","target":"t1","set":{"title":"no id: dropped"}}"#,
            #"{"id":"x","at":1,"type":"task.update","set":{"title":"no target: dropped"}}"#,
            #"{"id":"h-pend-1","at":"soon","type":"task.update","target":"t1","set":{"notes":"at as a string"},"extra":1}"#,
        ], when: toronto))

        // An empty log, and pending ops alone.
        out.append(Case(name: "handmade/empty", entries: [], pending: [], when: toronto))
        out.append(Case(name: "handmade/pending-only", entries: [], pending: [
            op("list.create", "L", #"{"name":"L","order":"a0"}"#),
            op("task.create", "t", #"{"list":"L","order":"a0","deadline":"\#(yesterday)"}"#),
        ], when: toronto))
        return out
    }

    static let randomCaseCount = 72

    static func randomCases() -> [Case] {
        var out: [Case] = []
        let toronto = foldTimes.filter { $0.zone == "America/Toronto" }
        let others = foldTimes.filter { $0.zone != "America/Toronto" }
        for i in 0..<randomCaseCount {
            var pick = Rng(UInt64(1000 + i))
            let when = i % 3 == 2 ? others[(i / 3) % others.count] : toronto[i % toronto.count]
            var g = LogGen(seed: UInt64(5_000 + i), when: when, weirdIDs: i % 7 == 3)
            let size = [5, 12, 30, 60, 120, 200, 300][pick.int(7)]
            let malformedRate = i % 4 == 0 ? 0.15 : 0.05
            var entries: [String] = []
            for seq in 0..<size {
                let op = g.next(malformedRate: malformedRate)
                entries.append(g.entry(seq: seq, op: op))
            }
            var pending: [String] = []
            if i % 3 == 1 || i % 7 == 3 {
                let count = pick.int(in: 1...40)
                for _ in 0..<count {
                    if g.rng.chance(0.04) {
                        pending.append(#"{"at":1,"type":"task.update","target":"\#(g.existingTask())","set":{"title":"dropped"}}"#)
                        continue
                    }
                    pending.append(g.next(malformedRate: malformedRate))
                }
            }
            out.append(Case(name: "random/\(i)-\(when.label)-\(size)", entries: entries, pending: pending, when: when))
        }
        return out
    }

    // MARK: - inverse.json

    /// Inverse.of for ops of the random logs, against the confirmed entity just before each op.
    static func inverseCases(_ cases: [Case]) -> [J] {
        var out: [J] = []
        var n = 0
        for c in cases where c.name.hasPrefix("random/") || c.name.hasPrefix("handmade/") {
            guard let entries = try? decodeEntries(c.entries) else { continue }
            var state = AppState()
            let ops = entries.map(\.op) + c.pending.compactMap { decodeOp($0) }
            for (k, op) in ops.enumerated() {
                defer { state.apply(op) }
                // Every op of the small cases, every third of the large ones.
                guard ops.count <= 40 || k % 3 == 0 else { continue }
                n += 1
                let id = "inv-\(n)"
                let at = op.at + 1000
                // The op's own kind; an unknown type is tried as both. Now and then the other kind, which is nil.
                var kinds: [String] = op.type.isTask ? ["task"] : op.type.isList ? ["list"] : ["task", "list"]
                if n % 11 == 0 { kinds.append(op.type.isTask ? "list" : "task") }
                for kind in kinds {
                    let before: J
                    let result: Op?
                    if kind == "task" {
                        let b = state.tasks[op.target]
                        before = b.map(encode) ?? .null
                        result = Inverse.of(op, beforeTask: b, id: id, at: at)
                    } else {
                        let b = state.lists[op.target]
                        before = b.map(encode) ?? .null
                        result = Inverse.of(op, beforeList: b, id: id, at: at)
                    }
                    out.append(.obj([
                        "op": .str(canonical(op)), "before": before, "kind": .str(kind), "id": .str(id), "at": .int(at),
                        "expect": .s(result.map(canonical)),
                    ]))
                }
            }
        }
        return out
    }
}
