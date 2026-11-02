import Foundation
import TasksCore

/// The shortest unique prefix of each id, at least 6 characters: how output names tasks and lists, like Git's
/// abbreviated hashes.
struct RefIndex {
    private var lengths: [String: Int] = [:]

    init(_ ids: some Sequence<String>) {
        let sorted = ids.map { Array($0.utf8) }.sorted { $0.lexicographicallyPrecedes($1) }
        for (i, id) in sorted.enumerated() {
            var shared = 0
            if i > 0 { shared = max(shared, Self.common(sorted[i - 1], id)) }
            if i + 1 < sorted.count { shared = max(shared, Self.common(id, sorted[i + 1])) }
            lengths[String(decoding: id, as: UTF8.self)] = min(id.count, max(6, shared + 1))
        }
    }

    func ref(_ id: String) -> String { String(id.prefix(lengths[id] ?? 6)) }

    private static func common(_ a: [UInt8], _ b: [UInt8]) -> Int {
        var n = 0
        while n < a.count, n < b.count, a[n] == b[n] { n += 1 }
        return n
    }
}

/// Resolving refs (docs/SDK-PLAN.md §3): a full id, a unique id prefix of 4+ characters, or for lists a name.
/// Refs fail closed: a missing or ambiguous one is an error listing the candidates, never a guess.
@MainActor
struct Resolver {
    let p: Projection

    /// A live task (not deleted, and its list not deleted, §28); with `includeDeleted`, any task; with
    /// `inDeletedLists`, a live one or one whose list is deleted (what `move --to` takes out, as Put back in).
    func task(_ ref: String, includeDeleted: Bool = false, inDeletedLists: Bool = false) throws -> TaskItem {
        let r = ref.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { throw CLIError(kind: .notFound, message: "An empty task ref.", field: "task") }
        func allowed(_ t: TaskItem) -> Bool {
            includeDeleted || p.isLive(task: t.id) || (inDeletedLists && p.isDeleted(list: t.list))
        }
        if let t = p.task(r) {
            guard allowed(t) else { throw gone(t, ref: r) }
            return t
        }
        let lower = r.lowercased()
        guard lower.count >= 4 else {
            throw CLIError(kind: .notFound, message: "No task \(r). A ref is an id or an id prefix of at least 4 characters.", field: "task")
        }
        let matches = p.allTaskIDs.filter { $0.hasPrefix(lower) }.compactMap(p.task)
        let pool = matches.filter(allowed)
        if pool.count == 1 { return pool[0] }
        if pool.isEmpty {
            if let t = matches.first, matches.count == 1 { throw gone(t, ref: r) }
            throw CLIError(kind: .notFound, message: "No task \(r).", field: "task")
        }
        let refs = RefIndex(p.allTaskIDs)
        let names = pool.sorted { $0.id < $1.id }.map { "\(refs.ref($0.id)) \"\($0.title)\"" }
        throw CLIError(kind: .ambiguous, message: "\(r) matches \(pool.count) tasks: \(names.joined(separator: ", ")).",
                       field: "task", candidates: pool.map(\.id).sorted())
    }

    /// Why a task that exists isn't live: deleted on its own, or in a deleted list (§28).
    private func gone(_ t: TaskItem, ref: String) -> CLIError {
        if let l = p.list(t.list), l.archivedAt != nil {
            return CLIError(kind: .notFound, message: "Task \(ref) (\"\(t.title)\") is in \(l.name), which is deleted; "
                            + Self.deletedListHint(l, task: ref), field: "task")
        }
        return CLIError(kind: .notFound, message: "Task \(ref) (\"\(t.title)\") is deleted; tasks restore \(ref) brings it back.", field: "task")
    }

    /// How a task in a deleted list comes back: with its list, or on its own into another.
    static func deletedListHint(_ l: TaskList, task ref: String) -> String {
        "tasks list restore \(quoted(l.name)) brings it back with its list, or tasks move \(ref) --to LIST puts it in another."
    }

    /// A list name as a shell argument: quoted when it has a space.
    static func quoted(_ name: String) -> String { name.contains(" ") ? "\"\(name)\"" : name }

    func tasks(_ refs: [String], includeDeleted: Bool = false, inDeletedLists: Bool = false) throws -> [TaskItem] {
        var seen = Set<String>()
        return try refs.map { try task($0, includeDeleted: includeDeleted, inDeletedLists: inDeletedLists) }.filter { seen.insert($0.id).inserted }
    }

    /// A list by id, then by name (case-insensitive; live lists first, then deleted ones), then by id prefix.
    func list(_ ref: String) throws -> TaskList {
        let r = ref.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { throw CLIError(kind: .notFound, message: "An empty list ref.", field: "list") }
        if let l = p.list(r) { return l }
        let all = p.allListIDs.compactMap(p.list)
        let named = all.filter { $0.name.compare(r, options: [.caseInsensitive]) == .orderedSame }
        let active = named.filter { $0.archivedAt == nil }
        for group in [active, named] where !group.isEmpty {
            if group.count == 1 { return group[0] }
            throw ambiguous(r, group, by: "name")
        }
        let lower = r.lowercased()
        if lower.count >= 4 {
            let prefixed = all.filter { $0.id.hasPrefix(lower) }
            if prefixed.count == 1 { return prefixed[0] }
            if prefixed.count > 1 { throw ambiguous(r, prefixed, by: "id") }
        }
        let names = active.isEmpty ? p.activeLists.ids.compactMap(p.list).map(\.name) : []
        let hint = names.isEmpty ? "" : " Lists: \(names.joined(separator: ", "))."
        throw CLIError(kind: .notFound, message: "No list \"\(r)\".\(hint)", field: "list")
    }

    private func ambiguous(_ r: String, _ lists: [TaskList], by: String) -> CLIError {
        let refs = RefIndex(p.allListIDs)
        let names = lists.sorted { $0.id < $1.id }.map { "\(refs.ref($0.id)) \"\($0.name)\"\($0.archivedAt != nil ? " (deleted)" : "")" }
        return CLIError(kind: .ambiguous, message: "\"\(r)\" matches \(lists.count) lists: \(names.joined(separator: ", ")). Use an id prefix.",
                        field: "list", candidates: lists.map(\.id).sorted())
    }
}
