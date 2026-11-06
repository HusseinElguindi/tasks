import SwiftUI
import TasksCore

// Headings (INTERACTIONS-v2 §23), the Mac's rules (app/Tasks/Window/Headings.swift). A heading is a task with
// `kind: "heading"`: a row in its list's order with a name and notes, and no checkbox, dates or completion. Its name
// and notes are typed in place, as a `Draft` (AppModel), so they end and write as a new task's row does. The writes are
// the core's `createHeading`, `setTitle`, `setNotes` and `delete`.
extension AppModel {
    func isHeading(_ id: EntityID) -> Bool { task(id)?.isHeading == true }

    // MARK: Adding, renaming, notes

    /// New Heading in a list's menu (at the bottom), or New Heading Above in a task's (above it, and it becomes the
    /// section's first task). It shows in place, named as it's typed; nothing is written until it has a name.
    func newHeading(in list: EntityID, before: EntityID? = nil) {
        guard projection.isActive(list: list) else { return }
        startDraft(.list(list), .heading(before: before))
    }

    /// Rename in its menu (a tap on its name does nothing): always in place.
    func renameHeading(_ id: EntityID) {
        guard let h = task(id), h.isHeading, !isTrashed(h) else { return }
        startDraft(.list(h.list), .rename(heading: id, original: h.title), text: h.title)
    }

    /// Add Notes or Edit Notes in its menu, or a tap on them: the notes editor, under it. It expands first.
    func editHeadingNotes(_ id: EntityID) {
        guard let h = task(id), h.isHeading, !isTrashed(h), selecting == nil else { return }
        expand(id)
        startDraft(.list(h.list), .notes(heading: id, original: h.notes), text: h.notes)
    }

    /// New Task in "<heading>": a new task's row at the end of its section. It expands first, so the row is seen.
    func newTask(inHeading id: EntityID) {
        guard let h = task(id), h.isHeading, !isTrashed(h) else { return }
        expand(id)
        startDraft(.list(h.list), .taskIn(heading: id))
    }

    /// A heading's draft ends: a new one is created with its name (none leaves nothing: no op, no undo step); a
    /// rename writes only a changed, non-empty name (an empty one keeps the old); notes write once, if changed.
    /// Always false: no next row follows.
    func writeHeading(_ d: Draft) -> Bool {
        switch d.kind {
        case let .heading(before):
            guard case let .list(list) = d.source, !d.title.isEmpty else { return false }
            let at: Ordering.Anchor = before.map { .before($0) } ?? .bottom
            undoable("New Heading") { store.createHeading(title: d.title, in: list, at: at, undoManager: undo) != nil }
        case let .rename(h, original):
            if !d.title.isEmpty, let name = EditSession.write(d.title, original: original, current: task(h)?.title) {
                undoable("Rename Heading", ids: [h]) { store.setTitle(h, name, name: "Rename Heading", undoManager: undo) }
            }
        case let .notes(h, original):
            if let notes = EditSession.write(d.title, original: original, current: task(h)?.notes) {
                undoable("Edit Notes", ids: [h]) { store.setNotes(h, notes, name: "Edit Notes", undoManager: undo) }
            }
        case .task, .taskIn, .listNotes: break
        }
        return false
    }

    /// Where "New Task in <heading>" lands: the end of its section, after its last open task, or right under the
    /// heading when it has none; the bottom when it's the last section. The Mac's `newTaskAnchor(in:under:)`.
    func sectionEnd(_ heading: EntityID, in list: EntityID) -> Ordering.Anchor {
        let items = projection.openTasks(in: list).ids
        guard let i = items.firstIndex(of: heading) else { return .bottom }
        var j = i + 1
        while j < items.count, !isHeading(items[j]) { j += 1 }
        guard j < items.count else { return .bottom }
        return j > i + 1 ? .after(items[j - 1]) : .after(heading)
    }

    // MARK: A list's notes

    /// Add Notes or Edit Notes in the list's menu, or a tap on them: the notes editor under its large title
    /// (IX:1540–1543, the Mac's NotesView.swift:674).
    func editListNotes(_ id: EntityID) {
        guard projection.isActive(list: id), let l = list(id) else { return }
        startDraft(.list(id), .listNotes(original: l.notes), text: l.notes)
    }

    /// The list's notes end: one `list.update`, only if the user changed them, "Edit List Notes". Always false.
    func writeListNotes(_ d: Draft) -> Bool {
        guard case let .listNotes(original) = d.kind, case let .list(id) = d.source,
              let notes = EditSession.write(d.title, original: original, current: list(id)?.notes) else { return false }
        setNotes(list: id, notes, name: "Edit List Notes")
        return false
    }

    // MARK: Collapsing (local to this device, never synced)

    /// The chevron, or Collapse or Expand in its menu. Collapsing folds its notes and tasks up into its row as they
    /// fade out (150 ms ease-out); expanding plays it backwards as they fade in (220 ms ease-in). The rows move on
    /// `layout`'s spring: the collection view's fold (TaskCollection+Fold).
    /// Reduce Motion turns both off (`animate`).
    func toggleCollapse(_ id: EntityID) {
        guard let h = task(id), h.isHeading else { return }
        let collapse = !collapsed.contains(id)
        if collapse {
            // Typing in the section that folds away ends first; an iPad's selected task that folds away leaves the
            // selection, as on the Mac.
            let gone = Set(projection.section(of: id).dropFirst())
            if let d = draft, d.kind == .taskIn(heading: id) || d.editedHeading == id { endDraft() }
            if let s = selectedTask, gone.contains(s) { selectedTask = nil }
        }
        animate(collapse ? .easeOut(duration: 0.15) : .easeIn(duration: 0.22)) {
            if collapse { collapsed.insert(id) } else { collapsed.remove(id) }
        }
    }

    func expand(_ id: EntityID) {
        if collapsed.contains(id) { toggleCollapse(id) }
    }

    // MARK: Deleting

    /// Delete Heading: the heading only. Its tasks stay where they are, under the heading above (or none). It isn't
    /// listed in Trash; the notice's Undo brings it back.
    func deleteHeading(_ id: EntityID) {
        guard let h = task(id), h.isHeading else { return }
        if draft?.editedHeading == id { cancelDraft() }
        var done = false
        animate(Motion.layout) { done = undoable("Delete Heading", ids: [id]) { store.delete([id], name: "Delete Heading", undoManager: undo) } }
        guard done else { return }
        show(Notice(text: "Deleted heading \(quote(h.title))", undo: undoStep))
    }
}
