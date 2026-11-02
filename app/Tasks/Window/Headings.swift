import AppKit
import SwiftUI
import TasksCore

/// Headings, a list's text and the large title (design/INTERACTIONS-v2.md §23). A heading is a task with
/// `kind: "heading"`: a row in its list's order with a name and notes, and no checkbox, dates or completion.
extension WindowActions {
    func isHeading(_ id: EntityID) -> Bool { p.task(id)?.isHeading == true }

    /// The selected rows that are tasks: what completing, dates and Move to act on (§23 Keys).
    var taskTargetIDs: [EntityID] { targetIDs.filter { !isHeading($0) } }

    // MARK: Adding and renaming

    /// ⌥⌘N, or New Heading Above in a task's menu: above the first selected row, which becomes the heading's first
    /// task, or at the bottom. It shows in its row, renaming, until Return writes it (dc:3371–3383).
    func newHeading() {
        guard case .list(let listID) = window.route, p.isActive(list: listID) else { return }
        endEdits()
        let L = layout
        let before = L.order.first { window.selection.contains($0) && !L.isDone($0) && p.task($0) != nil }
        let id = store.newID()
        window.focus = .list
        window.rename = .init(kind: .heading, id: id, caret: .all, text: "", newHeading: .init(list: listID, before: before))
        select([id])
        window.taskList?.scrollToVisible(id)
    }

    /// Double-click, Return, or Rename in its menu: always in place (Settings ▸ Edit tasks is about tasks).
    func startHeadingRename(_ id: EntityID, caret: WindowState.Rename.Caret = .all) {
        guard let t = p.task(id), t.isHeading, !t.deleted, !inTrash else { return }
        endEdits()
        select([id])
        window.focus = .list
        window.rename = .init(kind: .heading, id: id, caret: caret, text: t.title)
    }

    /// Double-clicking the large title, or the band's once the list has scrolled (it scrolls back up first).
    func startTitleRename() {
        guard case .list(let id) = window.route, let l = p.list(id), l.archivedAt == nil else { return }
        endEdits()
        window.taskList?.scrollToTop()
        window.focus = .list
        window.rename = .init(kind: .title, id: id, caret: .all, text: l.name)
    }

    // MARK: Notes in the list pane

    /// Click into them, Add Notes or Edit Notes in its menu, or Tab from its rename.
    func editHeadingNotes(_ id: EntityID) {
        guard isHeading(id), !inTrash else { return }
        endEdits()
        select([id])
        expand(id)
        window.taskList?.startPaneNotes(.task(id))
    }

    /// The list's notes: a click in them, or Tab from the title's rename.
    func editListNotes() {
        guard let id = window.route.listID else { return }
        endEdits()
        window.taskList?.startPaneNotes(.list(id))
    }

    // MARK: Collapsing (local to the Mac, never synced)

    /// The chevron, Space with headings selected, Collapse or Expand in the menu. `to` nil toggles: they all collapse
    /// unless they all are. Selected tasks that fold away leave the selection; if nothing's left, the heading takes it.
    func toggleCollapse(_ ids: [EntityID], to: Bool? = nil) {
        let hs = ids.filter(isHeading)
        guard !hs.isEmpty else { return }
        let collapse = to ?? !hs.allSatisfy(window.collapsed.contains)
        var c = window.collapsed
        for h in hs { if collapse { c.insert(h) } else { c.remove(h) } }
        guard c != window.collapsed else { return }
        if collapse {
            var gone = Set<EntityID>()
            for h in hs { gone.formUnion(p.section(of: h).dropFirst()) }
            if !window.selection.isDisjoint(with: gone) {
                var sel = window.selection.subtracting(gone)
                if sel.isEmpty { sel = [hs[0]] }
                window.selection = sel
                window.anchor = hs[0]
                window.cursor = hs[0]
            }
        }
        window.collapsed = c
    }

    func expand(_ id: EntityID) {
        if window.collapsed.contains(id) { toggleCollapse([id], to: false) }
    }

    /// Today's Completed folds as a heading does (v2 feedback 15): its chevron, or Space with its label selected.
    /// Selected done rows that fold away leave the selection; if nothing's left, the label takes it.
    func toggleTodayDone(to: Bool? = nil) {
        let collapse = to ?? !window.todayDoneCollapsed
        guard collapse != window.todayDoneCollapsed else { return }
        if collapse {
            let done = Set(p.todayDone.ids)
            if !window.selection.isDisjoint(with: done) {
                var sel = window.selection.subtracting(done)
                if sel.isEmpty { sel = [TaskLayout.doneGroup] }
                window.selection = sel
                window.anchor = sel.first
                window.cursor = sel.first
            }
        }
        window.todayDoneCollapsed = collapse
    }

    // MARK: Moving a section

    /// ⌥⌘↑ ⌥⌘↓ on a heading, or Move Up and Move Down in its menu: past the previous or next section, never above the
    /// tasks that have no heading (dc:3445–3455).
    func moveSectionBy(_ hid: EntityID, _ delta: Int) {
        guard let t = p.task(hid), t.isHeading else { return }
        let heads = p.headings(in: t.list).ids
        guard let i = heads.firstIndex(of: hid) else { return }
        let anchor: Ordering.Anchor
        if delta < 0 {
            guard i > 0 else { return }
            anchor = .before(heads[i - 1])
        } else {
            guard i + 1 < heads.count else { return }
            anchor = i + 2 < heads.count ? .before(heads[i + 2]) : .bottom
        }
        moveSection(hid, to: anchor)
    }

    /// Writes the heading and every task under it, completed ones included: one op each, one undo step.
    func moveSection(_ hid: EntityID, to anchor: Ordering.Anchor) {
        undoable("Move Heading") { store.moveSection(hid, at: anchor, name: "Move Heading", undoManager: undo) }
        window.taskList?.scrollToVisible(hid)
    }

    // MARK: Where a new task goes

    /// In a list with headings: the end of `under`'s section (a heading's +), else of the selected row's (⌘N, the
    /// header +, a double-click). Nil is the bottom of the list, as before, and as with nothing selected (§23).
    /// Its heading, if collapsed, expands so the new task is seen.
    func newTaskAnchor(in list: EntityID, under: EntityID? = nil) -> Ordering.Anchor? {
        let heads = p.headings(in: list).ids
        guard !heads.isEmpty else { return nil }
        var head: EntityID?
        if let under {
            head = under
        } else {
            guard window.route == .list(list), let sel = targetIDs.first, let t = p.task(sel), t.list == list,
                  t.completedAt == nil || t.isHeading else { return nil }
            head = t.isHeading ? sel : p.heading(of: sel)
        }
        if let head { expand(head) }
        let items = p.openTasks(in: list).ids
        var j = head.flatMap { items.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let start = j
        while j < items.count, !isHeading(items[j]) { j += 1 }
        guard j < items.count else { return nil }
        if j > start { return .after(items[j - 1]) }
        return head.map { .after($0) } ?? .before(items[j])
    }
}
