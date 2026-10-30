import Foundation

/// The user's actions, as ops (spec §3, §4). Views call these; they never compute keys or build ops.
extension Store {
    static let maxTitle = 1_000
    static let maxNotes = 20_000
    static let maxName = 200

    /// New tasks created outside a list go to the first active list in sidebar order (spec §2).
    public var defaultListID: EntityID? { projection.activeLists.ids.first }

    // MARK: Tasks

    /// Creates a task at the bottom of `list` (or the default list). Returns its id, or nil if no list is active.
    @discardableResult
    public func createTask(title: String, notes: String = "", in list: EntityID? = nil, when: CalendarDate? = nil,
                           deadline: CalendarDate? = nil, undoManager: UndoManager? = nil) -> EntityID? {
        guard let list = list ?? defaultListID else { return nil }
        let id = newID()
        let key = Ordering.append([id], after: projection.orderedOpenTasks(in: list))
        var ops = key.filter { $0.id != id }.map { taskOp($0.id, Patch(list: list, order: $0.order)) }
        ops.append(Op(id: newID(), at: nowMs, type: .taskCreate, target: id,
                      set: Patch(list: list, order: key.first { $0.id == id }!.order,
                                 title: Self.clamp(title, Self.maxTitle), notes: Self.clamp(notes, Self.maxNotes),
                                 when: when.map { .some($0) }, deadline: deadline.map { .some($0) })))
        perform(ops, undoManager: undoManager, actionName: "New Task")
        return id
    }

    public func setTitle(_ id: EntityID, _ title: String, undoManager: UndoManager? = nil) {
        let title = Self.clamp(title, Self.maxTitle)
        guard let t = projection.task(id), t.title != title else { return }
        perform([taskOp(id, Patch(title: title))], undoManager: undoManager, actionName: "Edit Title")
    }

    public func setNotes(_ id: EntityID, _ notes: String, undoManager: UndoManager? = nil) {
        let notes = Self.clamp(notes, Self.maxNotes)
        guard let t = projection.task(id), t.notes != notes else { return }
        perform([taskOp(id, Patch(notes: notes))], undoManager: undoManager, actionName: "Edit Notes")
    }

    public func setWhen(_ ids: [EntityID], _ date: CalendarDate?, undoManager: UndoManager? = nil) {
        let ops = ids.filter { projection.task($0).map { $0.when != date } ?? false }
            .map { taskOp($0, Patch(when: .some(date))) }
        perform(ops, undoManager: undoManager, actionName: date == nil ? "Remove When" : "Set When")
    }

    public func setDeadline(_ ids: [EntityID], _ date: CalendarDate?, undoManager: UndoManager? = nil) {
        let ops = ids.filter { projection.task($0).map { $0.deadline != date } ?? false }
            .map { taskOp($0, Patch(deadline: .some(date))) }
        perform(ops, undoManager: undoManager, actionName: date == nil ? "Remove Deadline" : "Set Deadline")
    }

    /// Checks or unchecks. Completing doesn't touch `order`, so unchecking puts a task back in its old spot.
    public func toggleComplete(_ ids: [EntityID], undoManager: UndoManager? = nil) {
        let tasks = ids.compactMap(projection.task)
        let complete = tasks.contains { $0.completedAt == nil }
        let now = nowMs
        let ops = tasks.filter { ($0.completedAt == nil) == complete }
            .map { taskOp($0.id, Patch(completedAt: .some(complete ? now : nil))) }
        perform(ops, undoManager: undoManager, actionName: complete ? "Complete" : "Mark as Not Done")
    }

    public func delete(_ ids: [EntityID], undoManager: UndoManager? = nil) {
        let ops = ids.filter { projection.task($0)?.deleted == false }.map { taskOp($0, Patch(deleted: true)) }
        perform(ops, undoManager: undoManager, actionName: ops.count == 1 ? "Delete Task" : "Delete Tasks")
    }

    /// "Move to…" or a drop on a sidebar list: the tasks land at the bottom of `list`, in the given order.
    public func move(_ ids: [EntityID], to list: EntityID, undoManager: UndoManager? = nil) {
        let moving = ids.filter { projection.task($0).map { $0.list != list } ?? false }
        guard !moving.isEmpty else { return }
        let placed = Ordering.append(moving, after: projection.orderedOpenTasks(in: list))
        perform(placed.map { taskOp($0.id, Patch(list: list, order: $0.order)) }, undoManager: undoManager,
                actionName: moving.count == 1 ? "Move Task" : "Move Tasks")
    }

    /// A drag within a list (or a Today group): writes `list` and `order` together, one op per moved task, plus
    /// any re-keyed neighbours for ties or a rebalance (spec §3).
    public func reorder(_ ids: [EntityID], in list: EntityID, at anchor: Ordering.Anchor, undoManager: UndoManager? = nil) {
        guard !ids.isEmpty else { return }
        let placed = Ordering.place(ids, at: anchor, in: projection.orderedOpenTasks(in: list))
        let ops = placed.filter { p in projection.task(p.id).map { $0.order != p.order || $0.list != list } ?? false }
            .map { taskOp($0.id, Patch(list: list, order: $0.order)) }
        perform(ops, undoManager: undoManager, actionName: "Reorder")
    }

    // MARK: Lists

    /// Creates a list at the bottom of the sidebar.
    @discardableResult
    public func createList(name: String, undoManager: UndoManager? = nil) -> EntityID {
        let id = newID()
        let order = Ordering.append([id], after: projection.orderedActiveLists()).first { $0.id == id }!.order
        perform([Op(id: newID(), at: nowMs, type: .listCreate, target: id,
                    set: Patch(order: order, name: Self.clamp(name, Self.maxName)))],
                undoManager: undoManager, actionName: "New List")
        return id
    }

    public func rename(list id: EntityID, to name: String, undoManager: UndoManager? = nil) {
        let name = Self.clamp(name, Self.maxName)
        guard let l = projection.list(id), l.name != name else { return }
        perform([listOp(id, Patch(name: name))], undoManager: undoManager, actionName: "Rename List")
    }

    /// "Delete list" is archiving: one op, whatever the list size; its tasks are untouched (spec §2).
    public func archive(list id: EntityID, undoManager: UndoManager? = nil) {
        guard projection.list(id)?.archivedAt == nil else { return }
        perform([listOp(id, Patch(archivedAt: .some(nowMs)))], undoManager: undoManager, actionName: "Archive List")
    }

    /// Unarchiving restores the list to its old sidebar spot, by its old key.
    public func unarchive(list id: EntityID, undoManager: UndoManager? = nil) {
        guard projection.list(id)?.archivedAt != nil else { return }
        perform([listOp(id, Patch(archivedAt: .some(nil)))], undoManager: undoManager, actionName: "Unarchive List")
    }

    public func reorderLists(_ ids: [EntityID], at anchor: Ordering.Anchor, undoManager: UndoManager? = nil) {
        let placed = Ordering.place(ids, at: anchor, in: projection.orderedActiveLists())
        let ops = placed.filter { p in projection.list(p.id).map { $0.order != p.order } ?? false }
            .map { listOp($0.id, Patch(order: $0.order)) }
        perform(ops, undoManager: undoManager, actionName: "Reorder Lists")
    }

    // MARK: Helpers

    func taskOp(_ id: EntityID, _ set: Patch) -> Op {
        Op(id: newID(), at: nowMs, type: .taskUpdate, target: id, set: set)
    }

    func listOp(_ id: EntityID, _ set: Patch) -> Op {
        Op(id: newID(), at: nowMs, type: .listUpdate, target: id, set: set)
    }

    /// Keeps a string within the server's limit in UTF-16 code units (spec §5), cutting on a character boundary.
    static func clamp(_ s: String, _ limit: Int) -> String {
        guard s.utf16.count > limit else { return s }
        var count = 0
        var end = s.startIndex
        for i in s.indices {
            let n = s[i].utf16.count
            if count + n > limit { break }
            count += n
            end = s.index(after: i)
        }
        return String(s[..<end])
    }
}
