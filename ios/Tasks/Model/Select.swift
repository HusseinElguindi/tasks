import SwiftUI
import TasksCore

// Multi-select (batch 2 §3; IX §5, §8–§10, §22, §28). Select in a screen's "…", a two-finger swipe over the rows, or
// ⌘A puts it in select mode: a tap selects a row, the bar at the bottom acts on everything selected, and Done (or Esc)
// leaves. It's the app's own state, not List's edit mode, whose circles the brief rejects (B): the Mac's look instead,
// `fill-row-selected` with neighbours joined. Each action is the Mac's for a mixed selection, one step with the Mac's
// name, and ends select mode once done (the Mac keeps the selection: the brief's touch difference). The writes are the
// core's `toggleComplete`, `setWhen`, `setDeadline`, `move`, `delete` and `putBack`, which all take several ids.
extension AppModel {
    /// Whether `s` is the screen in select mode.
    func isSelecting(_ s: Source?) -> Bool { s != nil && selecting == s }

    /// The task rows shown on `s`, in order: what a tap or a swipe selects. Headings, labels, the Completed row and a
    /// deleted list's row in Trash aren't selectable; rows folded away aren't shown.
    func taskRows(_ s: Source) -> [TaskModel] {
        lines(s).compactMap { if case let .task(t, _, _, _) = $0 { t } else { nil } }
    }

    /// What Select All and ⌘A take (IX §5): every open task row shown; in Completed and Trash, every task row shown.
    func selectAllIDs(_ s: Source) -> [EntityID] {
        let rows = taskRows(s)
        return (s == .completed || s == .trash ? rows : rows.filter { !$0.isDone }).map(\.id)
    }

    /// Select in the "…": a live list or a view with a task row to select.
    func canSelect(_ s: Source) -> Bool { deletedList(s) == nil && !taskRows(s).isEmpty }

    /// The selection, in the screen's order: each action's tasks (the Mac's `targetIDs`).
    func selectedIDs(_ s: Source) -> [EntityID] {
        guard isSelecting(s), !selected.isEmpty else { return [] }
        return taskRows(s).map(\.id).filter(selected.contains)
    }

    /// A long-press in select mode: the menu acts on the selection, with the pressed row in it (it's added as the
    /// press is held; the Mac selects only that row instead, the brief's touch difference).
    func menuTargets(_ s: Source, adding id: EntityID) -> [EntityID] {
        let ids = selected.union([id])
        return taskRows(s).map(\.id).filter(ids.contains)
    }

    // MARK: Entering and leaving

    /// Select in the "…" (nothing selected), a two-finger swipe (the rows it crosses), ⌘A (all). Adding ends first.
    func startSelecting(_ s: Source, _ ids: [EntityID] = []) {
        guard deletedList(s) == nil, s == shown, !isSelecting(s) else { return }
        endDraft()
        selected = Set(ids)
        animate(Motion.natural) { selecting = s }
    }

    /// Done, Esc, or an action once it's done. The fills go at once: selection never animates (IX §5).
    func endSelecting() {
        guard selecting != nil else { return }
        selected = []
        animate(Motion.natural) { selecting = nil }
    }

    /// Ends select mode if its screen isn't the one now shown (an undo that goes elsewhere; the back button is hidden).
    func endSelecting(unlessShowing s: Source?) {
        if let sel = selecting, sel != s { endSelecting() }
    }

    func toggleSelected(_ id: EntityID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Everything Select All takes is selected: the button reads Deselect All.
    func allSelected(_ s: Source) -> Bool {
        let all = selectAllIDs(s)
        return !all.isEmpty && Set(all).isSubset(of: selected)
    }

    /// Select All, or Deselect All.
    func toggleSelectAll(_ s: Source) {
        selected = allSelected(s) ? [] : Set(selectAllIDs(s))
    }

    /// ⌘A: select mode, if it's off, with every row Select All takes.
    func selectAll(_ s: Source) {
        guard !selectAllIDs(s).isEmpty else { return }
        startSelecting(s)
        guard isSelecting(s) else { return }
        selected = Set(selectAllIDs(s))
    }

    /// The rows still shown: a task that sync removes, or one folded under a heading or a closed Completed row, leaves
    /// the selection (IX §2.4: you can't act on what you can't see).
    func pruneSelection(_ shown: [EntityID]) {
        guard !selected.isEmpty else { return }
        let keep = selected.intersection(shown)
        if keep != selected { selected = keep }
    }

    // MARK: The actions (§3's table). With one task, the single wording: "Deleted “Buy milk”".

    /// Complete: the open ones; if all are done, all not done (`Store.toggleComplete`). Each box it checks sparks, one
    /// haptic for them all, and the rows wait 1.5 s, then move together. "Completed 3 tasks", with Undo; none for Not
    /// Done. "Complete 3 Tasks" or "Mark as Not Done" (the Mac's `toggleComplete`, named for what's selected).
    func completeTasks(_ ids: [EntityID]) {
        endSelecting()
        let tasks = ids.compactMap(task).filter { !$0.isHeading && !isTrashed($0) }
        guard !tasks.isEmpty else { return }
        if tasks.count == 1 { return toggle(tasks[0].id) }
        let checking = tasks.contains { !$0.isDone }
        let changing = tasks.filter { checking ? !$0.isDone : $0.isDone }.map(\.id)
        let name = checking ? "Complete \(tasks.count) Tasks" : "Mark as Not Done"
        quietChecks = Set(changing)
        if checking {
            guard undoable(name, ids: changing, { store.toggleComplete(changing, name: name, undoManager: undo) }) else { return }
            completing.formUnion(changing)
            bulkChecks += 1
            restartSettle()
            let one = changing.count == 1 ? task(changing[0])?.title : nil
            show(Notice(text: one.map { "Completed \(quote($0))" } ?? "Completed \(changing.count) tasks", undo: undoStep))
        } else {
            completing.subtract(changing)
            var done = false
            animate(Motion.layout) { done = undoable(name, ids: changing) { store.toggleComplete(changing, name: name, undoManager: undo) } }
            if done { bulkUnchecks += 1 }
            restartSettle()
        }
        // The boxes have taken their new state by now; later checks are heard again.
        let quiet = quietChecks
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if self?.quietChecks == quiet { self?.quietChecks = [] }
        }
    }

    /// Delete: all at once, with no confirmation (IX §2.3). "Deleted 3 tasks", with Undo; "Delete 3 Tasks".
    func deleteTasks(_ ids: [EntityID]) {
        endSelecting()
        let ids = ids.filter { task($0).map { !$0.deleted && !$0.isHeading } == true }
        guard !ids.isEmpty else { return }
        if ids.count == 1 { return delete(ids[0]) }
        let name = "Delete \(ids.count) Tasks"
        var done = false
        animate(Motion.layout) { done = undoable(name, ids: ids) { store.delete(ids, name: name, undoManager: undo) } }
        guard done else { return }
        show(Notice(text: "Deleted \(ids.count) tasks", undo: undoStep))
    }

    /// Move: a task already in the list stays where it is; the rest go to its bottom. Out of the list on screen, "Moved
    /// 3 tasks to School", with Undo; in a view they stay, regrouped, and nothing is said (IX §10, §22). "Move 3 Tasks".
    func moveTasks(_ ids: [EntityID], to listID: EntityID) {
        endSelecting()
        let moving = ids.compactMap(task).filter { $0.list != listID && !$0.isHeading && !isTrashed($0) }.map(\.id)
        guard !moving.isEmpty else { return }
        if moving.count == 1 { return move(moving[0], to: listID) }
        let name = "Move \(moving.count) Tasks"
        var done = false
        animate(Motion.layout) { done = undoable(name, ids: moving) { store.move(moving, to: listID, name: name, undoManager: undo) } }
        guard done, case .list? = shown else { return }
        show(Notice(text: "Moved \(moving.count) tasks to \(listName(listID))", undo: undoStep))
    }

    /// Whether every task can go home: each was deleted on its own from a live list. If any can't, Put Back opens Put
    /// back in for all of them (IX §28, the Mac's `takeOutOfTrash`).
    func allGoHome(_ ids: [EntityID]) -> Bool {
        let tasks = ids.compactMap(task)
        return !tasks.isEmpty && tasks.allSatisfy(canPutBack)
    }

    /// Put Back (home, each at its old place) or, given `list`, Put back in (at its bottom). "Put back 3 tasks", plus
    /// " in Home" when they share a list, with Undo; "Put Back 3 Tasks" (the Mac's `putBack`).
    func putBackTasks(_ ids: [EntityID], in list: EntityID? = nil) {
        endSelecting()
        let ids = store.trashedTasks(ids).filter { id in list != nil || task(id).map(canPutBack) == true }
        guard !ids.isEmpty else { return }
        if ids.count == 1 { return putBack(ids[0], in: list) }
        if let list, !projection.isActive(list: list) { return }
        let homes = Set(ids.compactMap { list ?? task($0)?.list })
        let name = "Put Back \(ids.count) Tasks"
        var done = false
        animate(Motion.layout) { done = undoable(name, ids: ids) { store.putBack(ids, in: list, name: name, undoManager: undo) } }
        guard done else { return }
        let home = homes.count == 1 ? homes.first.map { " in \(listName($0))" } ?? "" : ""
        show(Notice(text: "Put back \(ids.count) tasks" + home, undo: undoStep))
    }
}
