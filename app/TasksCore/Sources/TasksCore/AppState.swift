import Foundation

public struct TaskItem: Hashable, Sendable, Codable {
    public let id: EntityID
    public var list: EntityID
    /// Fractional index key within its list (spec §3).
    public var order: String
    public var title: String
    /// Markdown.
    public var notes: String
    /// A heading (design/INTERACTIONS-v2.md §23): a row in its list's order that groups the tasks under it. Set by
    /// `task.create`'s `kind: "heading"` and never changed; it has no dates and no completion.
    public var isHeading: Bool
    public var when: CalendarDate?
    public var deadline: CalendarDate?
    /// Epoch ms; nil = open.
    public var completedAt: Int?
    public var deleted: Bool
    /// Derived from the `at` of the first and last op that touched the task. Never written as fields.
    public var createdAt: Int
    public var updatedAt: Int

    public init(id: EntityID, list: EntityID, order: String, title: String = "", notes: String = "",
                isHeading: Bool = false, when: CalendarDate? = nil, deadline: CalendarDate? = nil,
                completedAt: Int? = nil, deleted: Bool = false, createdAt: Int = 0, updatedAt: Int = 0) {
        self.id = id
        self.list = list
        self.order = order
        self.title = title
        self.notes = notes
        self.isHeading = isHeading
        self.when = when
        self.deadline = deadline
        self.completedAt = completedAt
        self.deleted = deleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TaskList: Hashable, Sendable, Codable {
    public let id: EntityID
    public var name: String
    /// Fractional index key in the sidebar (spec §3).
    public var order: String
    /// The list's text under its title, Markdown (design/INTERACTIONS-v2.md §23).
    public var notes: String
    /// Epoch ms: when the list was deleted (it's in Trash, design/INTERACTIONS-v2.md §28); nil = live. The wire name
    /// is Archive's, kept: a deleted list is exactly an archived one.
    public var archivedAt: Int?
    public var createdAt: Int
    public var updatedAt: Int

    public init(id: EntityID, name: String, order: String, notes: String = "", archivedAt: Int? = nil, createdAt: Int = 0,
                updatedAt: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
        self.notes = notes
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - The reducer (spec §5, "the whole conflict model")

/// Per-entity reduction. Every op touches exactly one entity, its `target` (spec §9), so the reducer is a
/// function of (entity before, op) and never looks at anything else.
public enum Reducer {
    /// Applies a task op to the slot for `op.target`. Returns true if the op took effect.
    @discardableResult
    public static func apply(_ op: Op, to task: inout TaskItem?) -> Bool {
        switch op.type {
        case .taskCreate:
            // Rule 1: a create on an id that already exists (live or deleted) is ignored.
            guard task == nil, let created = TaskItem(creating: op) else { return false }
            task = created
            return true
        case .taskUpdate:
            // Rule 3: an update on an unknown id is ignored.
            guard task != nil else { return false }
            task!.update(with: op.set, at: op.at)
            return true
        default:
            return false
        }
    }

    @discardableResult
    public static func apply(_ op: Op, to list: inout TaskList?) -> Bool {
        switch op.type {
        case .listCreate:
            guard list == nil, let created = TaskList(creating: op) else { return false }
            list = created
            return true
        case .listUpdate:
            guard list != nil else { return false }
            list!.update(with: op.set, at: op.at)
            return true
        default:
            return false
        }
    }
}

extension TaskItem {
    /// `task.create`: `list` and `order` are required; only create keys are read (rule 6). `kind` is read here
    /// only: an update never changes it.
    init?(creating op: Op) {
        guard let list = op.set.list, let order = op.set.order else { return nil }
        self.init(id: op.target, list: list, order: order,
                  title: op.set.title ?? "", notes: op.set.notes ?? "", isHeading: op.set.kind == Patch.heading,
                  when: op.set.when ?? nil, deadline: op.set.deadline ?? nil,
                  completedAt: op.set.completedAt ?? nil, deleted: false,
                  createdAt: op.at, updatedAt: op.at)
    }

    /// `task.update`: each present key overwrites (rule 2). `deleted` is an ordinary field (rule 4).
    mutating func update(with p: Patch, at: Int) {
        if let v = p.list { list = v }
        if let v = p.order { order = v }
        if let v = p.title { title = v }
        if let v = p.notes { notes = v }
        if let v = p.when { when = v }
        if let v = p.deadline { deadline = v }
        if let v = p.completedAt { completedAt = v }
        if let v = p.deleted { deleted = v }
        updatedAt = at
    }
}

extension TaskList {
    init?(creating op: Op) {
        guard let name = op.set.name, let order = op.set.order else { return nil }
        self.init(id: op.target, name: name, order: order, notes: op.set.notes ?? "", archivedAt: nil, createdAt: op.at,
                  updatedAt: op.at)
    }

    mutating func update(with p: Patch, at: Int) {
        if let v = p.name { name = v }
        if let v = p.order { order = v }
        if let v = p.notes { notes = v }
        if let v = p.archivedAt { archivedAt = v }
        updatedAt = at
    }
}

/// The confirmed state: every task and list reduced from the log, deleted ones included.
public struct AppState: Hashable, Sendable, Codable {
    public var tasks: [EntityID: TaskItem]
    public var lists: [EntityID: TaskList]

    public init(tasks: [EntityID: TaskItem] = [:], lists: [EntityID: TaskList] = [:]) {
        self.tasks = tasks
        self.lists = lists
    }

    /// The reducer. Pure and deterministic; returns the one id it changed, nil if the op was ignored.
    @discardableResult
    public mutating func apply(_ op: Op) -> EntityID? {
        switch op.type {
        case .taskCreate:
            guard tasks[op.target] == nil, let created = TaskItem(creating: op) else { return nil }
            tasks[op.target] = created
        case .taskUpdate:
            guard tasks[op.target] != nil else { return nil }
            tasks[op.target]!.update(with: op.set, at: op.at)
        case .listCreate:
            guard lists[op.target] == nil, let created = TaskList(creating: op) else { return nil }
            lists[op.target] = created
        case .listUpdate:
            guard lists[op.target] != nil else { return nil }
            lists[op.target]!.update(with: op.set, at: op.at)
        case .unknown:
            return nil
        }
        return op.target
    }

    public static func replay<S: Sequence>(_ ops: S) -> AppState where S.Element == Op {
        var state = AppState()
        for op in ops { state.apply(op) }
        return state
    }
}

// MARK: - Inverse ops (undo as `git revert`, spec §6)

public enum Inverse {
    /// The op that undoes `op`, given the visible task before it, or nil if `op` would have no effect.
    /// For an update it sets exactly the keys `op` wrote back to their previous values; undoing a create deletes.
    public static func of(_ op: Op, beforeTask before: TaskItem?, id: String, at: Int) -> Op? {
        switch op.type {
        case .taskCreate:
            guard before == nil, TaskItem(creating: op) != nil else { return nil }
            return Op(id: id, at: at, type: .taskUpdate, target: op.target, set: Patch(deleted: true))
        case .taskUpdate:
            guard let b = before else { return nil }
            let s = op.set
            var p = Patch()
            if s.list != nil { p.list = b.list }
            if s.order != nil { p.order = b.order }
            if s.title != nil { p.title = b.title }
            if s.notes != nil { p.notes = b.notes }
            if s.when != nil { p.when = .some(b.when) }
            if s.deadline != nil { p.deadline = .some(b.deadline) }
            if s.completedAt != nil { p.completedAt = .some(b.completedAt) }
            if s.deleted != nil { p.deleted = b.deleted }
            return Op(id: id, at: at, type: .taskUpdate, target: op.target, set: p)
        default:
            return nil
        }
    }

    /// Undoing a list create deletes it, which for a list is `archivedAt` (it goes to Trash, spec §2).
    public static func of(_ op: Op, beforeList before: TaskList?, id: String, at: Int) -> Op? {
        switch op.type {
        case .listCreate:
            guard before == nil, TaskList(creating: op) != nil else { return nil }
            return Op(id: id, at: at, type: .listUpdate, target: op.target, set: Patch(archivedAt: .some(at)))
        case .listUpdate:
            guard let b = before else { return nil }
            let s = op.set
            var p = Patch()
            if s.name != nil { p.name = b.name }
            if s.order != nil { p.order = b.order }
            if s.notes != nil { p.notes = b.notes }
            if s.archivedAt != nil { p.archivedAt = .some(b.archivedAt) }
            return Op(id: id, at: at, type: .listUpdate, target: op.target, set: p)
        default:
            return nil
        }
    }
}
