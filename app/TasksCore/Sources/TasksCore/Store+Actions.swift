import Foundation

/// The user's actions, as ops (spec §3, §4). Views call these; they never compute keys or build ops.
extension Store {
    static let maxTitle = 1_000
    static let maxNotes = 20_000
    static let maxName = 200

    /// New tasks created outside a list go to the first active list in sidebar order (spec §2).
    public var defaultListID: EntityID? { projection.activeLists.ids.first }

    // MARK: Tasks

    /// Creates a task at the bottom of `list` (or the default list), or at `anchor` in it (the end of a heading's
    /// section, §23). Returns its id, or nil if no list is active.
    @discardableResult
    /// `id` lets a draft keep the id it was shown with (the app's new-task draft, design/INTERACTIONS-v2.md §6).
    public func createTask(id: EntityID? = nil, title: String, notes: String = "", in list: EntityID? = nil,
                           at anchor: Ordering.Anchor = .bottom, when: CalendarDate? = nil, deadline: CalendarDate? = nil,
                           undoManager: UndoManager? = nil) -> EntityID? {
        create(id: id, title: title, notes: notes, in: list, at: anchor, kind: nil, when: when, deadline: deadline,
               undoManager: undoManager, actionName: "New Task")
    }

    /// A heading (§23): a task with `kind: "heading"`, at `anchor` in `list` (above the first selected row, or the
    /// bottom). One `task.create`, "New Heading".
    @discardableResult
    public func createHeading(id: EntityID? = nil, title: String, notes: String = "", in list: EntityID,
                              at anchor: Ordering.Anchor = .bottom, undoManager: UndoManager? = nil) -> EntityID? {
        create(id: id, title: title, notes: notes, in: list, at: anchor, kind: Patch.heading, when: nil, deadline: nil,
               undoManager: undoManager, actionName: "New Heading")
    }

    private func create(id: EntityID?, title: String, notes: String, in list: EntityID?, at anchor: Ordering.Anchor,
                        kind: String?, when: CalendarDate?, deadline: CalendarDate?, undoManager: UndoManager?,
                        actionName: String) -> EntityID? {
        guard let list = list ?? defaultListID else { return nil }
        let id = id ?? newID()
        let key = Ordering.place([id], at: anchor, in: projection.orderedOpenTasks(in: list))
        var ops = key.filter { $0.id != id }.map { taskOp($0.id, Patch(list: list, order: $0.order)) }
        ops.append(Op(id: newID(), at: nowMs, type: .taskCreate, target: id,
                      set: Patch(list: list, order: key.first { $0.id == id }!.order,
                                 title: Self.clamp(title, Self.maxTitle), notes: Self.clamp(notes, Self.maxNotes),
                                 when: when.map { .some($0) }, deadline: deadline.map { .some($0) }, kind: kind)))
        perform(ops, undoManager: undoManager, actionName: actionName)
        return id
    }

    @discardableResult
    public func setTitle(_ id: EntityID, _ title: String, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let title = Self.clamp(title, Self.maxTitle)
        guard let t = projection.task(id), t.title != title else { return false }
        return perform([taskOp(id, Patch(title: title))], undoManager: undoManager, actionName: name ?? "Edit Title")
    }

    @discardableResult
    public func setNotes(_ id: EntityID, _ notes: String, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let notes = Self.clamp(notes, Self.maxNotes)
        guard let t = projection.task(id), t.notes != notes else { return false }
        return perform([taskOp(id, Patch(notes: notes))], undoManager: undoManager, actionName: name ?? "Edit Notes")
    }

    @discardableResult
    public func setWhen(_ ids: [EntityID], _ date: CalendarDate?, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let ops = ids.filter { projection.task($0).map { !$0.isHeading && $0.when != date } ?? false }
            .map { taskOp($0, Patch(when: .some(date))) }
        return perform(ops, undoManager: undoManager, actionName: name ?? (date == nil ? "Remove When" : "Set When"))
    }

    @discardableResult
    public func setDeadline(_ ids: [EntityID], _ date: CalendarDate?, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let ops = ids.filter { projection.task($0).map { !$0.isHeading && $0.deadline != date } ?? false }
            .map { taskOp($0, Patch(deadline: .some(date))) }
        return perform(ops, undoManager: undoManager, actionName: name ?? (date == nil ? "Remove Deadline" : "Set Deadline"))
    }

    /// Checks or unchecks. Completing doesn't touch `order`, so unchecking puts a task back in its old spot. Headings
    /// are skipped: they have no completion (§23).
    @discardableResult
    public func toggleComplete(_ ids: [EntityID], name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let tasks = ids.compactMap(projection.task).filter { !$0.isHeading }
        let complete = tasks.contains { $0.completedAt == nil }
        let now = nowMs
        let ops = tasks.filter { ($0.completedAt == nil) == complete }
            .map { taskOp($0.id, Patch(completedAt: .some(complete ? now : nil))) }
        return perform(ops, undoManager: undoManager, actionName: name ?? (complete ? "Complete" : "Mark as Not Done"))
    }

    @discardableResult
    public func delete(_ ids: [EntityID], name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let ops = ids.filter { projection.task($0)?.deleted == false }.map { taskOp($0, Patch(deleted: true)) }
        return perform(ops, undoManager: undoManager, actionName: name ?? (ops.count == 1 ? "Delete Task" : "Delete Tasks"))
    }

    /// "Move to…" or a drop on a sidebar list: the tasks land at the bottom of `list`, in the given order. Headings
    /// stay in their list (§23).
    @discardableResult
    public func move(_ ids: [EntityID], to list: EntityID, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let moving = ids.filter { projection.task($0).map { !$0.isHeading && $0.list != list } ?? false }
        guard !moving.isEmpty else { return false }
        let placed = Ordering.append(moving, after: projection.orderedOpenTasks(in: list))
        return perform(placed.map { taskOp($0.id, Patch(list: list, order: $0.order)) }, undoManager: undoManager,
                actionName: name ?? (moving.count == 1 ? "Move Task" : "Move Tasks"))
    }

    /// A drag within a list (or a Today group): writes `list` and `order` together, one op per moved task, plus
    /// any re-keyed neighbours for ties or a rebalance (spec §3).
    @discardableResult
    public func reorder(_ ids: [EntityID], in list: EntityID, at anchor: Ordering.Anchor, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        guard !ids.isEmpty else { return false }
        let placed = Ordering.place(ids, at: anchor, in: projection.orderedOpenTasks(in: list))
        let ops = placed.filter { p in projection.task(p.id).map { $0.order != p.order || $0.list != list } ?? false }
            .map { taskOp($0.id, Patch(list: list, order: $0.order)) }
        return perform(ops, undoManager: undoManager, actionName: name ?? "Reorder")
    }

    /// Moves a heading with its section (§23): the heading and every task under it, completed ones included, get
    /// keys at `anchor` among the list's tasks, one op each. `anchor` is `.before(another heading)` or `.bottom`;
    /// where the section already is, nothing is written.
    @discardableResult
    public func moveSection(_ heading: EntityID, at anchor: Ordering.Anchor, name: String? = nil,
                            undoManager: UndoManager? = nil) -> Bool {
        guard let h = projection.task(heading), h.isHeading, !h.deleted else { return false }
        let section = projection.section(of: heading)
        let placed = Ordering.place(section, at: anchor, in: projection.orderedTasksIncludingCompleted(in: h.list))
        let ops = placed.filter { p in projection.task(p.id).map { $0.order != p.order || $0.list != h.list } ?? false }
            .map { taskOp($0.id, Patch(list: h.list, order: $0.order)) }
        return perform(ops, undoManager: undoManager, actionName: name ?? "Move Heading")
    }

    // MARK: Lists

    /// Creates a list at the bottom of the sidebar.
    @discardableResult
    public func createList(id: EntityID? = nil, name: String, undoManager: UndoManager? = nil) -> EntityID {
        let id = id ?? newID()
        let order = Ordering.append([id], after: projection.orderedActiveLists()).first { $0.id == id }!.order
        perform([Op(id: newID(), at: nowMs, type: .listCreate, target: id,
                    set: Patch(order: order, name: Self.clamp(name, Self.maxName)))],
                undoManager: undoManager, actionName: "New List")
        return id
    }

    @discardableResult
    public func rename(list id: EntityID, to name: String, undoManager: UndoManager? = nil) -> Bool {
        let name = Self.clamp(name, Self.maxName)
        guard let l = projection.list(id), l.name != name else { return false }
        return perform([listOp(id, Patch(name: name))], undoManager: undoManager, actionName: "Rename List")
    }

    /// The list's notes (§23): one `list.update`, "Edit List Notes".
    @discardableResult
    public func setNotes(list id: EntityID, _ notes: String, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let notes = Self.clamp(notes, Self.maxNotes)
        guard let l = projection.list(id), l.notes != notes else { return false }
        return perform([listOp(id, Patch(notes: notes))], undoManager: undoManager, actionName: name ?? "Edit List Notes")
    }

    /// Delete List (design/INTERACTIONS-v2.md §28): one op, `archivedAt` = now, whatever the list holds. Its tasks
    /// aren't touched: while it's in Trash they count as deleted (SPEC §2), and they come back with it.
    @discardableResult
    public func deleteList(_ id: EntityID, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        guard projection.list(id)?.archivedAt == nil else { return false }
        return perform([listOp(id, Patch(archivedAt: .some(nowMs)))], undoManager: undoManager, actionName: name ?? "Delete List")
    }

    /// Restore List: `archivedAt: null`, one op. The list goes back to its old place by its old key, with everything
    /// it held; a task deleted on its own before stays deleted.
    @discardableResult
    public func restoreList(_ id: EntityID, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        guard projection.list(id)?.archivedAt != nil else { return false }
        return perform([listOp(id, Patch(archivedAt: .some(nil)))], undoManager: undoManager, actionName: name ?? "Restore List")
    }

    /// The tasks Put Back can take out of Trash (§22, §28): deleted ones, and ones whose list is deleted. Headings come
    /// back only with ⌘Z or their list (§23).
    public func trashedTasks(_ ids: [EntityID]) -> [EntityID] {
        ids.filter { id in projection.task(id).map { !$0.isHeading && ($0.deleted || !projection.isActive(list: $0.list)) } ?? false }
    }

    /// Put Back (§22): without `list`, `deleted: false`, and the task returns to its list at its old place; a task
    /// whose list is in Trash has no place to go back to, so it's skipped. "Put back in" `list` (§28): at the bottom of
    /// that live list, in the order given, `set {list, order}` plus `deleted: false` where it was deleted on its own.
    /// Returns whether anything was written.
    @discardableResult
    public func putBack(_ ids: [EntityID], in list: EntityID? = nil, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let ids = trashedTasks(ids)
        if let list, !projection.isActive(list: list) { return false }
        let now = nowMs
        var ops: [Op] = []
        let moving = list.map { l in ids.filter { projection.task($0)?.list != l } } ?? []
        if let list, !moving.isEmpty {
            // At the bottom of the other list, in the order they were in (as Move does); re-keyed neighbours too.
            let movingSet = Set(moving)
            for item in Ordering.append(moving, after: projection.orderedOpenTasks(in: list)) {
                var p = Patch(list: list, order: item.order)
                if movingSet.contains(item.id), projection.task(item.id)?.deleted == true { p.deleted = false }
                ops.append(Op(id: newID(), at: now, type: .taskUpdate, target: item.id, set: p))
            }
        }
        for id in ids where !moving.contains(id) {
            guard let t = projection.task(id), t.deleted, projection.isActive(list: t.list) else { continue }
            ops.append(Op(id: newID(), at: now, type: .taskUpdate, target: id, set: Patch(deleted: false)))
        }
        return perform(ops, undoManager: undoManager, actionName: name ?? (ids.count > 1 ? "Put Back \(ids.count) Tasks" : "Put Back"))
    }

    @discardableResult
    public func reorderLists(_ ids: [EntityID], at anchor: Ordering.Anchor, name: String? = nil, undoManager: UndoManager? = nil) -> Bool {
        let placed = Ordering.place(ids, at: anchor, in: projection.orderedActiveLists())
        let ops = placed.filter { p in projection.list(p.id).map { $0.order != p.order } ?? false }
            .map { listOp($0.id, Patch(order: $0.order)) }
        return perform(ops, undoManager: undoManager, actionName: name ?? "Reorder Lists")
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
