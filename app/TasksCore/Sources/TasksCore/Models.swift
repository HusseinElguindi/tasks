import Foundation
import Observation

/// One sorted index bucket (spec §9). Views read `ids`; the projection edits it in place, once per change batch.
///
/// Observation is hand-rolled rather than `@Observable` so a batch of inserts and removes mutates the array in
/// place and notifies once.
@MainActor
public final class Bucket: Observable {
    private let registrar = ObservationRegistrar()
    private var storage: [EntityID] = []
    /// Sort keys, parallel to `storage`.
    private(set) var keys: [SortKey] = []

    public init() {}

    public var ids: [EntityID] {
        registrar.access(self, keyPath: \.ids)
        return storage
    }

    public var count: Int { ids.count }

    /// Applies removes then inserts. Small edits use binary search; an edit touching more than ~1/8 of the bucket
    /// re-sorts it once instead.
    func apply(removing removes: [SortKey], inserting inserts: [SortKey]) {
        guard !removes.isEmpty || !inserts.isEmpty else { return }
        registrar.withMutation(of: self, keyPath: \.ids) {
            if removes.count + inserts.count > max(16, keys.count / 8) {
                let gone = Set(removes)
                var next = keys.filter { !gone.contains($0) }
                next.append(contentsOf: inserts)
                next.sort()
                keys = next
                storage = next.map(\.id)
                return
            }
            for key in removes {
                let i = lowerBound(key)
                if i < keys.count, keys[i] == key {
                    keys.remove(at: i)
                    storage.remove(at: i)
                } else if let j = keys.firstIndex(where: { $0.id == key.id }) {
                    assertionFailure("bucket out of sync for \(key.id)")
                    keys.remove(at: j)
                    storage.remove(at: j)
                }
            }
            for key in inserts {
                let i = lowerBound(key)
                keys.insert(key, at: i)
                storage.insert(key.id, at: i)
            }
        }
    }

    /// Replaces the contents with already-sorted keys.
    func replace(with sorted: [SortKey]) {
        registrar.withMutation(of: self, keyPath: \.ids) {
            keys = sorted
            storage = sorted.map(\.id)
        }
    }

    private func lowerBound(_ key: SortKey) -> Int {
        var lo = 0, hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// A position in a bucket: by `order` (manual order) or by a time (`completedAt`, `archivedAt`), ties by id.
struct SortKey: Hashable, Comparable {
    var order: String
    var time: Int
    var id: EntityID

    static func manual(_ order: String, _ id: EntityID) -> SortKey { SortKey(order: order, time: 0, id: id) }
    static func ascending(_ time: Int, _ id: EntityID) -> SortKey { SortKey(order: "", time: time, id: id) }
    static func descending(_ time: Int, _ id: EntityID) -> SortKey { SortKey(order: "", time: -time, id: id) }

    static func < (a: SortKey, b: SortKey) -> Bool {
        if a.time != b.time { return a.time < b.time }
        return orderPrecedes(a.order, a.id, b.order, b.id)
    }
}

/// A task as rows and the detail pane see it. One instance per task id, created lazily and cached; fields are
/// assigned only when they change, so a row redraws only for its own changes (spec §9).
@MainActor
@Observable
public final class TaskModel: Identifiable {
    public let id: EntityID
    public internal(set) var list: EntityID
    public internal(set) var order: String
    public internal(set) var title: String
    public internal(set) var notes: String {
        didSet { notesSummary = NotesSummary(notes) }
    }
    /// What the row shows of the notes (design/MARKDOWN.md §7), worked out once per change of `notes`.
    public private(set) var notesSummary: NotesSummary
    public internal(set) var when: CalendarDate?
    public internal(set) var deadline: CalendarDate?
    public internal(set) var completedAt: Int?
    public internal(set) var deleted: Bool
    public internal(set) var createdAt: Int

    public var isDone: Bool { completedAt != nil }

    init(_ t: TaskItem) {
        id = t.id
        list = t.list
        order = t.order
        title = t.title
        notes = t.notes
        notesSummary = NotesSummary(t.notes)
        when = t.when
        deadline = t.deadline
        completedAt = t.completedAt
        deleted = t.deleted
        createdAt = t.createdAt
    }

    func update(from t: TaskItem) {
        if list != t.list { list = t.list }
        if order != t.order { order = t.order }
        if title != t.title { title = t.title }
        if notes != t.notes { notes = t.notes }
        if when != t.when { when = t.when }
        if deadline != t.deadline { deadline = t.deadline }
        if completedAt != t.completedAt { completedAt = t.completedAt }
        if deleted != t.deleted { deleted = t.deleted }
        if createdAt != t.createdAt { createdAt = t.createdAt }
    }

    func matches(_ t: TaskItem) -> Bool {
        list == t.list && order == t.order && title == t.title && notes == t.notes && when == t.when
            && deadline == t.deadline && completedAt == t.completedAt && deleted == t.deleted && createdAt == t.createdAt
    }
}

@MainActor
@Observable
public final class ListModel: Identifiable {
    public let id: EntityID
    public internal(set) var name: String
    public internal(set) var order: String
    public internal(set) var archivedAt: Int?
    public internal(set) var createdAt: Int

    public var isArchived: Bool { archivedAt != nil }

    /// One of 7 color slots, derived from the id so every Mac agrees with no field (design/DIRECTIONS.md).
    public let colorSlot: Int

    /// The monogram on the list mark: the first letter or digit of the name.
    public var monogram: String { Self.monogram(for: name) }

    /// Nonisolated, so the closure carries no runtime main-actor check: a reviewer's probe build crashed inside that
    /// check here (app/NOTES-overnight.md).
    nonisolated static func monogram(for name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "·"
    }

    init(_ l: TaskList) {
        id = l.id
        name = l.name
        order = l.order
        archivedAt = l.archivedAt
        createdAt = l.createdAt
        colorSlot = Self.slot(for: l.id)
    }

    func update(from l: TaskList) {
        if name != l.name { name = l.name }
        if order != l.order { order = l.order }
        if archivedAt != l.archivedAt { archivedAt = l.archivedAt }
        if createdAt != l.createdAt { createdAt = l.createdAt }
    }

    func matches(_ l: TaskList) -> Bool {
        name == l.name && order == l.order && archivedAt == l.archivedAt && createdAt == l.createdAt
    }

    /// FNV-1a over the id's bytes, mod 7. Stable across processes and Macs (unlike `hashValue`).
    public static func slot(for id: EntityID) -> Int {
        var h: UInt32 = 2_166_136_261
        for b in id.utf8 {
            h ^= UInt32(b)
            h = h &* 16_777_619
        }
        return Int(h % 7)
    }
}

/// The current day, observed by rows whose badges depend on it ("Overdue · 2d", "Due today").
@MainActor
@Observable
public final class DayModel {
    public internal(set) var day: Day

    init(_ day: Day) { self.day = day }
}
