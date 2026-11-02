import AppKit
import TasksCore

// Delete List (design/INTERACTIONS-v2.md §28): a list's `archivedAt` is its deletion. A deleted list lives in Trash
// with its tasks, one row on the day it was deleted that expands like a heading and opens read-only in the detail pane;
// restoring it puts everything back as it was. Its tasks count as deleted everywhere that decides what's live
// (TasksCore's `isLive`).

/// The two verbs that take something out of Trash. The user kept the design's split: a list is **restored**, a task is
/// **put back** (the Finder's word). Each verb is spelled here once, so unifying them is a one-line change:
/// `list = .putBack`, or `task = .restore`.
enum TrashVerb {
    struct Verb {
        /// A button, a menu item or an undo name: "Restore", "Restore List"; "Put Back", "Put Back 2 Tasks".
        let title: String
        /// A menu header: "Put back in".
        let sentence: String
        /// A notice: "Restored School", "Put back “Milk” in Inbox".
        let past: String
        /// The banner: "Read-only until you restore it."
        let untilYou: String
    }

    static let restore = Verb(title: "Restore", sentence: "Restore", past: "Restored", untilYou: "restore it")
    static let putBack = Verb(title: "Put Back", sentence: "Put back", past: "Put back", untilYou: "put it back")

    /// A deleted list's verb.
    static let list = restore
    /// A deleted task's verb.
    static let task = putBack
}

extension WindowState {
    /// In Trash, or in a deleted list: what's shown reads but doesn't edit (§22, §28).
    @MainActor
    func inTrash(_ p: Projection) -> Bool {
        route == .trash || deletedListOpen(p) != nil
    }

    /// The deleted list this state shows, if that's what's showing: the detail pane's (`detailListState`), or the list
    /// pane's when its list was deleted elsewhere while open (the CLI, another Mac).
    @MainActor
    func deletedListOpen(_ p: Projection) -> EntityID? {
        guard let id = route.listID, p.isDeleted(list: id) else { return nil }
        return id
    }

    /// The window state the detail pane shows a deleted list with (§28 Opening, the user 2026-11-01): the list pane's
    /// own view on its own route, so it draws the banner, the title, the notes, the headings and the rows as the list
    /// pane would, read-only. It uses this window's overlays and shares its folds (`collapsed`, `completedOpen`). It
    /// has no selection (its rows are display-only: the window's selection stays the list's row in Trash, so the keys
    /// and the menu bar keep acting on that), and its view never takes the keys: the detail pane's own key handling does.
    @MainActor
    func detailListState(_ id: EntityID) -> WindowState {
        if let s = detailList, s.route == .list(id) { return s }
        let s = WindowState(overlays: overlays)
        s.host = self
        s.route = .list(id)
        s.focus = .detail
        s.palette = palette
        detailList = s
        return s
    }
}

extension WindowActions {
    /// Trash, or a deleted list opened from it.
    var inTrash: Bool { window.inTrash(p) }

    /// A task Trash holds or shows: deleted, or in a deleted list.
    func isTrashed(_ id: EntityID) -> Bool { p.task(id) != nil && !p.isLive(task: id) }

    /// The deleted list whose row is the selection in Trash (§28 Selecting the row).
    var selectedDeletedList: EntityID? {
        guard window.route == .trash, window.selection.count == 1, let id = window.selection.first, p.isDeleted(list: id) else { return nil }
        return id
    }

    func isDeletedListRow(_ id: EntityID) -> Bool { window.route == .trash && p.isDeleted(list: id) }

    // MARK: Deleting a list (§28 The sidebar)

    /// ⌘⌫ with the sidebar focused, or Delete List in its menu: at once, no confirmation (§2.3). If it's open, the
    /// next list below opens, else the one above, else Today, as ⌘⌫ walks down tasks. "Deleted School", with Undo.
    func deleteList(_ id: EntityID) {
        guard let l = p.list(id), l.archivedAt == nil else { return }
        endEdits()
        let lists = p.activeLists.ids
        let i = lists.firstIndex(of: id) ?? 0
        let next: WindowState.Route = i + 1 < lists.count ? .list(lists[i + 1]) : i > 0 ? .list(lists[i - 1]) : .today
        let wasOpen = window.route == .list(id)
        let name = "Delete List"
        guard undoable(name, { store.deleteList(id, name: name, undoManager: undo) }) else { return }
        if wasOpen { go(next, focus: window.focus == .sidebar ? .sidebar : nil) }
        overlays.showNotice("Deleted \(l.name.isEmpty ? "Untitled" : l.name)", undo: true)
    }

    // MARK: Restoring a list (§28 Restoring)

    /// Restore in the banner, ↶, Restore List in its menu, or ⌘⌫ on its row: one op, and the list is back in its old
    /// place in Lists with everything it held. From Trash (its row, or the detail pane showing it) the selection moves
    /// on as for Put Back; from the list pane, showing a list deleted elsewhere, the pane becomes the live list in place.
    func restoreList(_ id: EntityID) {
        // The detail pane's banner: as from the row, since the row is what's selected.
        if let host = window.host { WindowActions(store: store, window: host).restoreList(id); return }
        guard let l = p.list(id), l.archivedAt != nil else { return }
        endEdits()
        let fromRow = window.route == .trash
        let L = layout
        let leaving = [id] + L.order.filter { L.childOf[$0] == id }
        let next = fromRow ? nextSelection(afterRemoving: leaving) : []
        let name = "\(TrashVerb.list.title) List"
        guard undoable(name, { store.restoreList(id, name: name, undoManager: undo) }) else { return }
        if fromRow {
            select(next)
            if window.detailOpen && next.isEmpty { closeDetail() }
        } else {
            // The pane is the live list now: what was selected in it stays selected.
            window.overlays.picker = nil
        }
        overlays.showNotice("\(TrashVerb.list.past) \(l.name.isEmpty ? "Untitled" : l.name)", undo: true)
    }

    // MARK: Opening and expanding (§28 Expanding, Opening)

    /// Return, a double-click, or Open: the list in the detail pane, its own list view read-only under the banner,
    /// with Trash staying in the middle and the row selected (the user, 2026-11-01). The detail pane takes the keys, so
    /// Esc or closing it gives them back to Trash. Selecting the row with the pane open shows it there too.
    func openDeletedList(_ id: EntityID) {
        guard p.isDeleted(list: id) else { return }
        if window.route != .trash { go(.trash, select: [id]) } else { select([id]) }
        window.taskList?.scrollToVisible(id)
        window.focus = .detail
        if window.detailOpen { focus(.detail) } else { openDetail() }
    }

    /// A list deleted elsewhere while open in the list pane: Esc with nothing left to cancel, or pressing Trash, goes
    /// to Trash with the list's row selected.
    func leaveDeletedList() {
        guard let id = window.deletedListOpen(p) else { return }
        go(.trash, select: [id], focus: .list)
    }

    /// The chevron, Space, → and ←: show or hide a deleted list's tasks under its row. Local, kept by list id.
    func toggleTrashExpanded(_ ids: [EntityID], to expand: Bool? = nil) {
        let lists = ids.filter { p.isDeleted(list: $0) }
        guard !lists.isEmpty else { return }
        let open = expand ?? !lists.allSatisfy { window.trashExpanded.contains($0) }
        var set = window.trashExpanded
        for id in lists { if open { set.insert(id) } else { set.remove(id) } }
        // Collapsing hides its selected tasks: the selection goes to the row.
        if !open {
            let L = layout
            let hidden = window.selection.filter { L.childOf[$0].map(lists.contains) == true }
            if !hidden.isEmpty {
                var sel = window.selection.subtracting(hidden)
                for h in hidden { if let l = L.childOf[h] { sel.insert(l) } }
                select(Array(sel).sorted())
            }
        }
        window.trashExpanded = set
    }

    // MARK: Putting a task back (§22, §28 One task out)

    /// ⌘⌫ in Trash: a deleted list's row restores it; tasks whose lists are all live go back (Put Back); if any has
    /// its list in Trash, "Put back in" pops for all of them, under the first.
    func takeOutOfTrash(_ ids: [EntityID]? = nil) {
        if ids == nil, let id = selectedDeletedList { restoreList(id); return }
        let ids = store.trashedTasks(ids ?? targetIDs)
        guard !ids.isEmpty else { return }
        if ids.allSatisfy({ p.task($0).map { p.isActive(list: $0.list) } == true }) {
            putBack(ids)
        } else {
            popPutBackIn(ids)
        }
    }

    /// Whether a task's own list is in Trash, so Put Back has nowhere to put it.
    func homeIsDeleted(_ id: EntityID) -> Bool { p.task(id).map { p.isDeleted(list: $0.list) } == true }

    /// Put Back: home, at its old place; or, given `list`, at the bottom of that live list (Put back in). The
    /// selection moves on, as a delete's does. "Put back “Milk” in Inbox", with Undo.
    func putBack(_ ids: [EntityID]? = nil, in list: EntityID? = nil) {
        let ids = store.trashedTasks(ids ?? targetIDs).filter { list != nil || !homeIsDeleted($0) }
        guard !ids.isEmpty else { return }
        endEdits()
        let next = nextSelection(afterRemoving: ids)
        let homes = Set(ids.compactMap { list ?? p.task($0)?.list })
        let title = p.task(ids[0])?.title ?? ""
        let verb = TrashVerb.task
        let name = ids.count > 1 ? "\(verb.title) \(ids.count) Tasks" : verb.title
        guard undoable(name, { store.putBack(ids, in: list, name: name, undoManager: undo) }) else { return }
        select(next)
        overlays.picker = nil
        let text = ids.count > 1 ? "\(verb.past) \(ids.count) tasks" : "\(verb.past) \(quote(title))"
        overlays.showNotice(text + (homes.count == 1 ? " in \(listName(homes.first!))" : ""), undo: true)
        if window.detailOpen && next.isEmpty { closeDetail() }
    }

    /// "Put back in" under the first row, placed and keyed as ⇧⌘M's Move to (§10), the first live list highlighted.
    func popPutBackIn(_ ids: [EntityID]) {
        guard let first = ids.first, let list = window.taskList else { return }
        overlays.hideTip()
        guard let point = list.moveMenuPoint(for: first) else { return }
        Menus.popPutBackIn(ids, at: point, in: list, actions: self)
    }
}

extension Menus {
    /// A deleted list's row in Trash (§28, `Del-Menu-Trash`): Open ↩ · Show Details ⌘D · ── · Restore List ⌘⌫.
    static func deletedList(_ id: EntityID, actions a: WindowActions) -> NSMenu {
        menu([
            Item("Open", key: returnKey, modifiers: []) { a.openDeletedList(id) },
            Item("Show Details", key: "d") { a.select([id]); a.openDetail() },
            .separator(),
            Item("\(TrashVerb.list.title) List", key: "\u{8}") { a.restoreList(id) },
        ])
    }

    /// A heading in a deleted list shown in the list pane: it folds, and that's all (§28).
    static func readOnlyHeading(_ ids: [EntityID], actions a: WindowActions) -> NSMenu {
        let heads = ids.filter(a.isHeading)
        let collapse = !heads.allSatisfy { a.window.collapsed.contains($0) }
        return menu([Item(collapse ? "Collapse" : "Expand", key: " ", modifiers: []) { a.toggleCollapse(heads, to: collapse) }])
    }

    /// "Put back in": every live list with its tile; a task's own deleted list is there, disabled, with "In Trash" at
    /// the right, so it's clear why it can't go home (§28).
    static func putBackInItems(_ ids: [EntityID], actions a: WindowActions) -> [NSMenuItem] {
        let p = a.p
        let tasks = ids.compactMap(p.task)
        let homes = Set(tasks.map(\.list))
        // The lists in the sidebar's order, with the tasks' deleted homes where their keys put them.
        var lists = p.activeLists.ids.compactMap(p.list)
        for h in homes where p.isDeleted(list: h) { if let l = p.list(h) { lists.append(l) } }
        lists.sort { orderPrecedes($0.order, $0.id, $1.order, $1.id) }
        let font = NSFont.menuFont(ofSize: 0)
        let widest = lists.map { (fit(a.listName($0.id)) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return lists.map { l in
            let deleted = l.archivedAt != nil
            let item = Item(fit(a.listName(l.id)), enabled: !deleted) { a.putBack(ids, in: l.id) }
            if let m = p.listModel(l.id) { item.image = tileImage(monogram: m.monogram, slot: m.colorSlot, palette: a.window.palette) }
            if deleted {
                // "In Trash" at the right, where a key equivalent goes.
                let title = NSMutableAttributedString(string: item.title + "\t", attributes: [.font: font])
                title.append(NSAttributedString(string: "In Trash", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
                let para = NSMutableParagraphStyle()
                let tag = ("In Trash" as NSString).size(withAttributes: [.font: font]).width
                para.tabStops = [NSTextTab(textAlignment: .right, location: ceil(widest + 32 + tag))]
                title.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: title.length))
                item.attributedTitle = title
            } else if tasks.count == 1 && tasks[0].list == l.id {
                item.state = .on
            }
            return item
        }
    }

    /// ⌘⌫ (or ↶) on tasks whose list is in Trash: the menu under the first row, the first live list highlighted.
    static func popPutBackIn(_ ids: [EntityID], at point: NSPoint, in view: NSView, actions a: WindowActions) {
        let m = menu([header("\(TrashVerb.task.sentence) in")] + putBackInItems(ids, actions: a))
        let highlighter = MenuHighlighter()
        m.delegate = highlighter
        objc_setAssociatedObject(m, &MenuHighlighter.key, highlighter, .OBJC_ASSOCIATION_RETAIN)
        m.popUp(positioning: nil, at: point, in: view)
    }
}
