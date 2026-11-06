import SwiftUI
import TasksCore

// Taking things out of Trash (IX §22, §28; batch 2 §4), the Mac's rules (app/Tasks/Window/DeletedLists.swift). A task
// is put back: home, at its old place, when it was deleted on its own from a live list; or "Put back in" any live list,
// at its bottom, which is the only way out for one whose list is in Trash. A deleted list is restored, and opens
// read-only from its row in Trash: its own list screen, which becomes the live list in place once restored. The
// writes are the core's `putBack(_:in:)` and `restoreList`.
extension AppModel {
    /// The deleted list a list screen shows, read-only until it's restored (§28); nil for a live list or a view.
    func deletedList(_ s: Source?) -> ListModel? {
        guard case let .list(id)? = s, let l = list(id), l.isDeleted else { return nil }
        return l
    }

    /// Whether + adds here: not in Completed or Trash, nor in a deleted list.
    func canAdd(_ s: Source?) -> Bool { s.map { $0.canAdd && deletedList($0) == nil } ?? false }

    /// A tap on a deleted list's row in Trash: the list itself, read-only (§28's Open), pushed over Trash. iPad shows
    /// it in the list pane, as the Mac's detail pane does.
    func openDeletedList(_ id: EntityID) {
        // Not in select mode, where the row isn't selectable and the screen stays put (§3).
        guard projection.isDeleted(list: id), selecting == nil else { return }
        if isSplit {
            selection = .list(id)
            selectedTask = nil
        } else if path.last != .list(id) {
            path.append(.list(id))
        }
    }

    /// Whether Put Back can take the task home: deleted on its own, from a live list.
    func canPutBack(_ t: TaskModel) -> Bool { t.deleted && !t.isHeading && projection.isActive(list: t.list) }

    /// One list in "Put back in".
    struct PutBackTarget: Identifiable {
        let id: EntityID
        /// The task's own list, in Trash: shown, disabled, with "In Trash", so it's clear why it can't go home.
        let inTrash: Bool
        /// The task's own live list: checked, and picking it is a plain Put Back.
        let home: Bool
    }

    /// "Put back in" (the Mac's `putBackInItems`): every live list, and the tasks' own deleted lists, in the sidebar's
    /// order by key. One task's own live list is checked.
    func putBackTargets(_ tasks: [TaskModel]) -> [PutBackTarget] {
        var lists = activeLists
        for h in Set(tasks.map(\.list)).sorted() { if let own = list(h), own.isDeleted { lists.append(own) } }
        lists.sort { orderPrecedes($0.order, $0.id, $1.order, $1.id) }
        let home = tasks.count == 1 ? tasks[0].list : nil
        return lists.map { PutBackTarget(id: $0.id, inTrash: $0.isDeleted, home: $0.id == home) }
    }

    /// Put Back: home, at its old place; or, given `list`, at the bottom of that live list (Put back in). Its details
    /// close, as the Mac's pane moves on with the selection. "Put back “Milk” in Inbox", with Undo; the undo name is
    /// "Put Back" either way (the Mac's `putBack`).
    func putBack(_ id: EntityID, in list: EntityID? = nil) {
        guard let t = task(id), store.trashedTasks([id]) == [id], list != nil || canPutBack(t) else { return }
        let home = list ?? t.list
        guard projection.isActive(list: home) else { return }
        let title = t.title
        let verb = "Put Back"
        var done = false
        animate(Motion.layout) {
            done = undoable(verb, ids: [id]) { store.putBack([id], in: list, name: verb, undoManager: undo) }
        }
        guard done else { return }
        if detailTask == id { detailTask = nil }
        if selectedTask == id { selectedTask = nil }
        show(Notice(text: "Put back \(quote(title)) in \(listName(home))", undo: undoStep))
    }
}
