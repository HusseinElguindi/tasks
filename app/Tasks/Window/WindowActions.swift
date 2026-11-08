import AppKit
import SwiftUI
import TasksCore

/// Everything the user can do, shared by the menus, the keys, the rows and the panes. Ported from the prototype's
/// component (`design/prototype-v2/Main.dc.html` dc:703–1008); each section cites its source.
@MainActor
struct WindowActions {
    let store: Store
    let window: WindowState

    var p: Projection { store.projection }
    var undo: UndoManager? { window.undoManager }
    var overlays: Overlays { window.overlays }
    var today: CalendarDate { p.day.date }
    var nowMs: Int { Int((Date().timeIntervalSince1970 * 1000).rounded()) }

    // MARK: - Reading

    /// The open view's rows as they stand (cheap: a pass over its buckets).
    var layout: TaskLayout { TaskLayout.make(store: store, window: window) }

    /// The selected tasks that exist (never the draft), top to bottom. In Trash (and a deleted list opened from it),
    /// the trashed ones: deleted, or in a deleted list (§22, §28). A deleted list's own row isn't a task.
    var targetIDs: [EntityID] {
        let trash = inTrash
        let sel = window.selection.filter { id in id != window.draft?.id && p.task(id) != nil && isTrashed(id) == trash }
        guard !sel.isEmpty else { return [] }
        let order = layout.order
        var ids = order.filter(sel.contains)
        if ids.count < sel.count { ids += sel.filter { !ids.contains($0) }.sorted() }
        return ids
    }

    /// A new task whose title is still empty isn't a task yet (§6): commands that need a task do nothing.
    var untitledDraft: Bool {
        guard let d = window.draft else { return false }
        return d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func listName(_ id: EntityID) -> String {
        let n = p.list(id)?.name ?? ""
        return n.isEmpty ? "Untitled" : n
    }

    /// “Buy milk”, cut at 28 characters (dc:423).
    func quote(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = t.isEmpty ? "Untitled" : t
        return "“" + (s.count > 28 ? String(s.prefix(27)) + "…" : s) + "”"
    }

    // MARK: - Undo (§9): every change is undoable, named, and restores the view and selection it was made from.

    /// Runs `body` (store calls that register their own inverse ops) as one undo step named `name`, plus a step that
    /// puts back the view and the selection from before the change.
    @discardableResult
    func undoable(_ name: String, selection before: Set<EntityID>? = nil, _ body: () -> Bool) -> Bool {
        let route = window.route
        let sel = before ?? window.selection
        guard let um = undo else { return body() }
        return UndoStep.run(um, name: name) {
            let did = body()
            if did { Self.registerRestore(um, store: store, window: window, route: route, selection: sel, name: name) }
            return did
        }
    }

    private static func registerRestore(_ um: UndoManager, store: Store, window: WindowState, route: WindowState.Route,
                                        selection: Set<EntityID>, name: String) {
        let manager = UnsafeSendableBox(um)
        um.registerUndo(withTarget: window) { w in
            MainActor.assumeIsolated {
                let um = manager.value
                let verb = um.isUndoing ? "Undo" : "Redo"
                // The counterpart, for redo (or undo again): the view and selection as they are now.
                registerRestore(um, store: store, window: w, route: w.route, selection: w.selection, name: name)
                // The store's inverse ops run after this in the same group; restore once they have.
                DispatchQueue.main.async {
                    WindowActions(store: store, window: w).restore(route: route, selection: selection)
                    w.overlays.showNotice("\(verb) \(name)", undo: false)
                }
            }
        }
    }

    /// dc:598–606: back to the view where the change was made, with what was selected then, scrolled into view.
    func restore(route: WindowState.Route, selection: Set<EntityID>) {
        window.rename = nil
        if window.draft != nil { dropDraft() }
        overlays.picker = nil
        settleNow()
        var route = route
        if case .list(let id) = route, p.list(id) == nil { route = .today }
        // Restoring a list from inside it, then undoing: the pane it was made from is the deleted list's, still there.
        let trash = route == .trash || route.listID.map(p.isDeleted) == true
        let sel = selection.filter { id in
            (p.task(id) != nil && isTrashed(id) == trash) || (route == .trash && p.isDeleted(list: id))
        }
        if route != window.route {
            go(route, select: Array(sel))
        } else {
            window.selection = sel
            window.anchor = sel.first
            window.cursor = sel.first
        }
        if let first = layout.order.first(where: sel.contains) { window.taskList?.scrollToVisible(first) }
    }

    func performUndo() {
        guard let um = undo, um.canUndo else { return }
        endEdits()
        um.undo()
    }

    func performRedo() {
        guard let um = undo, um.canRedo else { return }
        endEdits()
        um.redo()
    }

    // MARK: - Focus (§4: the pane last pressed in or moved to with the keys)

    func focus(_ f: WindowState.Focus) {
        if window.focus != f { window.focus = f }
        switch f {
        case .list: window.taskList?.takeKeys()
        case .sidebar: window.sidebarView?.takeKeys()
        case .detail: window.detailKeySink?.takeKeys()
        }
    }

    /// Ends whatever is being typed, the way a press elsewhere does: renames and the draft commit (an untitled draft
    /// is dropped), and the detail pane's fields commit as they resign.
    func endEdits() {
        if let w = window.nsWindow, let editor = w.firstResponder as? NSTextView, w.contentView.map(editor.isDescendant(of:)) == true {
            w.makeFirstResponder(nil)
        }
        if window.rename != nil { commitRename() }
        if window.draft != nil { commitDraft() }
        // A field that resigned may have handed the keys on (a dropped draft gives them to the list) before the
        // window took them back; give them to the focused pane.
        if let w = window.nsWindow, w.firstResponder === w { focus(window.focus) }
    }

    /// Quit, logout and restart (`willTerminate`): AppKit ends no edit and takes no view out of its window on the way
    /// out, so whatever is being typed in any window is written now, before the store's last flush.
    static func endAllEdits(store: Store) {
        for w in WindowState.windows.allObjects where w.nsWindow != nil { WindowActions(store: store, window: w).endEdits() }
    }

    // MARK: - Selection (§5, dc:703–727)

    func select(_ ids: [EntityID], anchor: EntityID? = nil) {
        let set = Set(ids)
        if window.selection != set { window.selection = set }
        window.anchor = anchor ?? ids.last
        window.cursor = ids.last
    }

    enum Step { case by(Int), first, last }

    /// ↑ ↓ (⇧ extends from the anchor), ⌘↑ ⌘↓ Home End. With several rows selected, ↓ goes below the last of them and
    /// ↑ above the first (dc:706–720).
    func moveSelection(_ step: Step, extend: Bool) {
        let order = layout.order
        guard !order.isEmpty else { return }
        // From Today's Completed label (v2 feedback 15): ↓ to its first row, ↑ to the row above it.
        if window.selection == [TaskLayout.doneGroup], case .by(let d) = step, let ly = layout.labels[TaskLayout.doneGroup] {
            let L = layout
            let next = d > 0 ? order.first { (L.y($0) ?? 0) > ly } : order.last { (L.y($0) ?? 0) < ly }
            if let next {
                select([next])
                window.taskList?.scrollToVisible(next)
            }
            return
        }
        let sel = window.selection
        let index: (EntityID) -> Int = { order.firstIndex(of: $0) ?? -1 }
        var cur: EntityID?
        if !sel.isEmpty {
            if extend, let c = window.cursor, sel.contains(c) {
                cur = c
            } else {
                let visible = sel.filter { order.contains($0) }
                if case .by(let d) = step, d < 0 { cur = visible.min { index($0) < index($1) } } else { cur = visible.max { index($0) < index($1) } }
            }
        }
        var i: Int
        switch step {
        case .first: i = 0
        case .last: i = order.count - 1
        case .by(let d):
            if let cur, let ci = order.firstIndex(of: cur) { i = min(max(ci + d, 0), order.count - 1) } else { i = d > 0 ? 0 : order.count - 1 }
        }
        let id = order[i]
        if extend, let a = window.anchor, let ai = order.firstIndex(of: a) {
            window.selection = Set(order[min(ai, i)...max(ai, i)])
            window.cursor = id
        } else {
            select([id])
        }
        window.taskList?.scrollToVisible(id)
    }

    /// ⌘A: every open task in the view, never headings (§23).
    func selectAll() {
        let L = layout
        let ids = L.order.filter { !L.isDone($0) && $0 != window.draft?.id && p.task($0).map { !$0.isHeading } == true }
        window.selection = Set(ids)
        window.anchor = ids.first
        window.cursor = ids.last
        focus(.list)
    }

    /// Letters and digits: the first title starting with what was typed within the last second (dc:1450–1462).
    func typeSelect(_ ch: String, inSidebar: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        window.typeBuffer = now - window.typeAt > TK.Timer.typeSelect ? ch.lowercased() : window.typeBuffer + ch.lowercased()
        window.typeAt = now
        let buf = window.typeBuffer
        if inSidebar {
            // Lists before Today and the views, so "t" goes to "Tasks app" and "u" to Upcoming (§22, dc:1500).
            if let id = p.activeLists.ids.first(where: { (p.list($0)?.name.lowercased() ?? "").hasPrefix(buf) }) {
                go(.list(id), focus: .sidebar)
            } else if let r = WindowState.Route.sidebarOrder(p).first(where: { !$0.isList && routeName($0).lowercased().hasPrefix(buf) }) {
                go(r, focus: .sidebar)
            }
            return
        }
        // A deleted list's row in Trash goes by its name (§28).
        if let id = layout.order.first(where: { ((p.task($0)?.title ?? p.list($0)?.name)?.lowercased() ?? "").hasPrefix(buf) }) {
            select([id])
            // From a zoomed task the keys stay in it, and it shows the task typed to (§29).
            if !window.zoomed { focus(.list) }
            window.taskList?.scrollToVisible(id)
        }
    }

    /// The row to select after `ids` leave the view: the next open row below, else above, so repeated ⌘⌫ walks down
    /// the list like Mail (dc:900–909).
    func nextSelection(afterRemoving ids: [EntityID]) -> [EntityID] {
        let L = layout
        let order = L.order.filter { !L.isDone($0) }
        let gone = Set(ids)
        guard order.contains(where: { !gone.contains($0) }) else { return [] }
        let firstIdx = order.firstIndex(where: gone.contains) ?? 0
        let lastIdx = order.lastIndex(where: gone.contains) ?? -1
        if let after = order[(lastIdx + 1)...].first(where: { !gone.contains($0) }) { return [after] }
        if let before = order[..<max(firstIdx, 0)].last(where: { !gone.contains($0) }) { return [before] }
        return []
    }

    // MARK: - Navigation (dc:729–741, §21 Switching views)

    func go(_ route: WindowState.Route, select ids: [EntityID] = [], focus f: WindowState.Focus? = nil) {
        endEdits()
        settleNow()
        overlays.picker = nil
        let sel = Set(ids)
        // A zoomed task goes with its view (§29): the list comes back, already showing the new one.
        if window.zoomed, window.route != route { setZoom(false) }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            if window.route != route { window.route = route }
            if window.selection != sel { window.selection = sel }
        }
        window.anchor = ids.first
        window.cursor = ids.first
        if let f { focus(f) }
        if let first = ids.first { window.taskList?.scrollToVisible(first) } else { window.taskList?.scrollToTop() }
    }

    /// ⌘1–⌘9: the sidebar's first nine rows, top to bottom (§22): Today, Upcoming, Undated, then the lists.
    func goNumber(_ n: Int) {
        let order = WindowState.Route.sidebarOrder(p)
        guard n >= 1, n <= min(9, order.count) else { return }
        go(order[n - 1])
    }

    // MARK: - Detail pane (§4: v1's transition, unchanged)

    func openDetail() {
        guard !window.detailOpen else { return }
        withAnimation(TK.Motion.natural) { window.detailOpen = true }
    }

    func closeDetail() {
        guard window.detailOpen else { return }
        endEdits()
        withAnimation(TK.Motion.natural) { window.detailOpen = false }
        if window.focus == .detail { focus(.list) }
    }

    func toggleDetail() {
        if window.detailOpen { closeDetail() } else { openDetail() }
    }

    // MARK: - Zoom (§29, the user 2026-11-01: Rex's Zoom Pane ⇧⌘↩)

    /// The detail pane can zoom: it's open beside the list. In a narrow window it's already in the list's place.
    var canZoom: Bool { window.detailOpen && !window.narrow }

    /// ⇧⌘↩, the zoom button or View ▸ Zoom Pane: the detail pane takes the list's room, or gives it back. From the list
    /// or the sidebar too, since it's the one pane that zooms.
    func toggleZoom() { setZoom(!window.zoomed) }

    /// The detail pane's left edge moves to the list's on `natural` (its own open and close) and covers the list,
    /// which keeps its width and place underneath and fades, so its rows don't reflow or scroll. Unzooming runs it
    /// backwards. The sidebar doesn't change. Zooming gives the detail pane the keys, since the list they'd be in hides;
    /// a caret already in the pane stays where it is. Reduce Motion: at once.
    func setZoom(_ on: Bool) {
        guard window.zoomed != on, !on || canZoom else { return }
        withAnimation(TK.Motion.natural) { window.zoomed = on }
        if on, window.focus != .detail { focus(.detail) }
    }

    // MARK: - Adding: a new task opens in the detail pane (§6, dc:837–872)

    /// `under`: a heading's +, which adds at the end of its section (§23).
    func newTask(in listID: EntityID? = nil, day: CalendarDate? = nil, under: EntityID? = nil) {
        // Completed and Trash add in the default list (§22), and so does a deleted list opened from Trash (§28).
        if window.route.noAdd || inTrash { addInDefault(); return }
        if untitledDraft, let d = window.draft {
            // Already adding and nothing typed: back to that title. From another Today group's +, the draft moves there;
            // from another day's, to that day.
            if let listID, listID != d.list { window.draft?.list = listID }
            if let day, window.route == .upcoming, day != d.when { window.draft?.when = day }
            window.titleFocusRequest = .init(selection: .end)
            window.taskList?.scrollToVisible(d.id)
            return
        }
        endEdits()
        var list = listID ?? window.route.listID
        if list == nil {
            if let sel = targetIDs.first, let t = p.task(sel), p.isActive(list: t.list) { list = t.list } else { list = store.defaultListID }
        }
        guard let list else {
            overlays.showNotice("Create a list first: ⇧⌘N", undo: false)
            return
        }
        let id = store.newID()
        let anchor = window.route.listID == list ? newTaskAnchor(in: list, under: under) : nil
        let draft = WindowState.Draft(id: id, list: list, title: "", when: newTaskWhen(day: day),
                                      createdAt: nowMs, prevSelection: window.selection, prevPaneOpen: window.detailOpen,
                                      anchor: anchor)
        overlays.picker = nil
        window.draft = draft
        select([id])
        window.focus = .detail
        openDetail()
        window.titleFocusRequest = .init(selection: .end)
        window.taskList?.scrollToVisible(id)
    }

    /// The draft's title as typed (its row follows each keystroke).
    func setDraftTitle(_ text: String) {
        guard window.draft != nil else { return }
        window.draft?.title = text.replacingOccurrences(of: "\n", with: " ")
    }

    /// One `task.create` when the title commits (§6 "Writing it"); untitled, the draft is dropped.
    func commitDraft() {
        guard let d = window.draft else { return }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { dropDraft(); return }
        window.draft = nil
        undoable("New Task", selection: d.prevSelection) {
            store.createTask(id: d.id, title: title, in: d.list, at: d.anchor ?? .bottom, when: d.when, undoManager: undo) != nil
        }
    }

    /// No op, no undo step, no notice (§6 "Dropping an untitled task", dc:820–831).
    func dropDraft() {
        guard let d = window.draft else { return }
        window.draft = nil
        let untouched = window.selection == [d.id]
        let sel = untouched ? d.prevSelection.filter { p.task($0).map { !$0.deleted } == true } : window.selection.subtracting([d.id])
        window.selection = sel
        window.anchor = sel.first
        window.cursor = sel.first
        if !d.prevPaneOpen {
            withAnimation(TK.Motion.natural) { window.detailOpen = false }
        }
        if window.focus == .detail { focus(.list) }
    }

    // MARK: - Editing a task: Settings ▸ Edit tasks (v2 feedback 8, §7)

    /// Double-click, Return and Rename in the menu. "Open in detail pane" (the default) shows the task there with the
    /// caret at the end of its title, and only focuses the title if the pane already shows it; "Rename in the list"
    /// renames it in its row with `caret`.
    func editTask(_ id: EntityID, caret: WindowState.Rename.Caret = .all) {
        // Trash reads but doesn't edit, and so does a deleted list opened from it: Return and a double-click show the
        // task in the detail pane (§22, §28).
        if inTrash {
            select([id])
            openDetail()
            return
        }
        // Headings always rename in place: Settings ▸ Edit tasks is about tasks (§23).
        if isHeading(id) { startHeadingRename(id, caret: caret); return }
        guard AppModel.TaskEditing.current == .detail else { startRename(id, caret: caret); return }
        guard let t = p.task(id), !t.deleted else { return }
        endEdits()
        select([id])
        if window.focus != .detail { window.focus = .detail }
        openDetail()
        window.titleFocusRequest = .init(selection: .end, id: id)
    }

    // MARK: - Renaming in place (§7, dc:760–809)

    func startRename(_ id: EntityID, caret: WindowState.Rename.Caret = .all) {
        guard let t = p.task(id), !t.deleted, !inTrash else { return }
        endEdits()
        select([id])
        window.focus = .list
        window.rename = .init(kind: .task, id: id, caret: caret, text: t.title, original: t.title)
    }

    func startListRename(_ id: EntityID) {
        // A deleted list is read-only until it's restored (§28).
        guard let l = p.list(id), l.archivedAt == nil else { return }
        endEdits()
        window.focus = .sidebar
        window.rename = .init(kind: .list, id: id, caret: .all, text: l.name, original: l.name)
    }

    func setRenameText(_ text: String) {
        guard window.rename != nil, window.rename?.text != text else { return }
        window.rename?.text = text
    }

    /// Return, Tab or a press elsewhere: one update, only if the user changed the name from where the rename began
    /// (`EditSession`): an untouched rename never writes its old name back over one that synced in meanwhile. A task
    /// title keeps the text as typed; a list name can't be empty (§7, §21).
    func commitRename() {
        guard let r = window.rename else { return }
        window.rename = nil
        let name = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = r.original.trimmingCharacters(in: .whitespacesAndNewlines)
        switch r.kind {
        case .task:
            guard let t = p.task(r.id), let text = EditSession.write(r.text, original: r.original, current: t.title) else { return }
            undoable("Rename Task") { store.setTitle(r.id, text, name: "Rename Task", undoManager: undo) }
        case .list:
            if r.isNewList {
                guard !name.isEmpty else { return }
                undoable("New List") { _ = store.createList(id: r.id, name: name, undoManager: undo); return true }
                go(.list(r.id), focus: .list)
            } else if !name.isEmpty, EditSession.write(name, original: original, current: p.list(r.id)?.name) != nil {
                undoable("Rename List") { store.rename(list: r.id, to: name, undoManager: undo) }
            }
        case .title:
            // The list's large title (§23): as its sidebar row renames.
            if !name.isEmpty, EditSession.write(name, original: original, current: p.list(r.id)?.name) != nil {
                undoable("Rename List") { store.rename(list: r.id, to: name, undoManager: undo) }
            }
        case .heading:
            // A new heading is written now, with its name; without one it leaves nothing. An empty name keeps the old
            // one (§23, dc:2987).
            if let n = r.newHeading {
                guard !name.isEmpty else { dropNewHeading(); return }
                undoable("New Heading", selection: []) {
                    store.createHeading(id: r.id, title: name, in: n.list, at: n.before.map { .before($0) } ?? .bottom,
                                        undoManager: undo) != nil
                }
                select([r.id])
            } else if !name.isEmpty, EditSession.write(name, original: original, current: p.task(r.id)?.title) != nil {
                undoable("Rename Heading") { store.setTitle(r.id, name, name: "Rename Heading", undoManager: undo) }
            }
        }
    }

    /// Esc on a new heading, or no name: no op, no undo step, and nothing selected.
    private func dropNewHeading() {
        window.selection = []
        window.anchor = nil
        window.cursor = nil
    }

    /// Esc: the old text comes back; a new list or heading is never created.
    func cancelRename() {
        guard let r = window.rename else { return }
        window.rename = nil
        if r.newHeading != nil { dropNewHeading() }
        focus(r.kind == .list ? .sidebar : .list)
    }

    // MARK: - Completing (§8, dc:883–899)

    func toggleComplete(_ ids: [EntityID]? = nil) {
        guard !inTrash else { return }
        // A heading has nothing to complete (§23).
        let ids = (ids ?? targetIDs).filter { p.task($0).map { !$0.isHeading } == true }
        let tasks = ids.compactMap(p.task)
        guard !tasks.isEmpty else { return }
        let completing = tasks.contains { $0.completedAt == nil }
        // Pins keep toggled rows where they are until the settle. A row toggled back before then is already in place:
        // one completed a moment ago is still among the open rows, so un-completing it just drops its pin (pinning it
        // among the done ones hid it in a folded Completed group); one un-completed a moment ago keeps its pin among
        // the done ones (v2 feedback 18).
        var pins = window.pins
        for t in tasks {
            if completing {
                if t.completedAt == nil, pins[t.id] == nil { pins[t.id] = .open }
            } else if let c = t.completedAt {
                if pins[t.id] == .open { pins[t.id] = nil } else { pins[t.id] = .done(completedAt: c) }
            }
        }
        let name = completing ? (ids.count > 1 ? "Complete \(ids.count) Tasks" : "Complete") : "Mark Not Done"
        window.pins = pins
        undoable(name) { store.toggleComplete(ids, name: name, undoManager: undo) }
        armSettle()
    }

    /// Checked rows stay put until 1.5 s pass with no further checks, then move together (§8).
    func armSettle() {
        window.settleTimer?.invalidate()
        let w = window
        window.settleTimer = Timer.scheduledTimer(withTimeInterval: TK.Timer.settle, repeats: false) { _ in
            MainActor.assumeIsolated { if !w.pins.isEmpty { w.pins = [:] } }
        }
    }

    /// Leaving the view, or undoing, settles them at once.
    func settleNow() {
        window.settleTimer?.invalidate()
        window.settleTimer = nil
        if !window.pins.isEmpty { window.pins = [:] }
    }

    // MARK: - Deleting (§9, dc:910–918)

    func delete(_ ids: [EntityID]? = nil) {
        // ⌘⌫ in Trash takes things out, as in the Finder (§22, §28): Put Back, Put back in, or Restore List.
        if inTrash { takeOutOfTrash(ids); return }
        let ids = (ids ?? targetIDs).filter { p.task($0).map { !$0.deleted } == true }
        guard !ids.isEmpty else { return }
        let next = nextSelection(afterRemoving: ids)
        // A heading deletes alone: its tasks stay, under the heading above it (§23).
        let heads = ids.filter(isHeading).count
        let name = ids.count > 1 ? (heads > 0 ? "Delete \(ids.count) Items" : "Delete \(ids.count) Tasks") : heads > 0 ? "Delete Heading" : "Delete"
        let title = p.task(ids[0])?.title ?? ""
        endEdits()
        guard undoable(name, { store.delete(ids, name: name, undoManager: undo) }) else { return }
        select(next)
        overlays.picker = nil
        let notice = ids.count > 1 ? (heads > 0 ? "Deleted \(ids.count) items" : "Deleted \(ids.count) tasks")
            : heads > 0 ? "Deleted heading \(quote(title))" : "Deleted \(quote(title))"
        overlays.showNotice(notice, undo: true)
        if window.detailOpen && next.isEmpty { closeDetail() }
    }

    // MARK: - Moving between lists (§10, dc:919–929)

    func move(_ ids: [EntityID]? = nil, to list: EntityID) {
        guard !inTrash else { return }
        if let d = window.draft, (ids ?? Array(window.selection)) == [d.id] {
            window.draft?.list = list
            return
        }
        let ids = (ids ?? targetIDs).filter { p.task($0).map { $0.list != list && !$0.isHeading } == true }
        guard !ids.isEmpty else { return }
        let leaves = window.route.listID != nil
        let next = leaves ? nextSelection(afterRemoving: ids) : Array(window.selection)
        let name = ids.count > 1 ? "Move \(ids.count) Tasks" : "Move"
        guard undoable(name, { store.move(ids, to: list, name: name, undoManager: undo) }) else { return }
        overlays.picker = nil
        if leaves {
            select(next)
            overlays.showNotice(ids.count > 1 ? "Moved \(ids.count) tasks to \(listName(list))" : "Moved to \(listName(list))", undo: true)
        }
    }

    /// Drag within a group, ⌥⌘↑ ⌥⌘↓: the rows land at `target` among the group's other rows (dc:942–961).
    func reorder(group: EntityID, ids: [EntityID], target: Int) {
        let L = layout
        guard let g = L.groups.first(where: { $0.listID == group }) else { return }
        let moving = ids.filter { p.task($0).map { $0.completedAt == nil && !$0.isHeading } == true && $0 != window.draft?.id }
        guard !moving.isEmpty else { return }
        let open = Set(p.openTasks(in: group).ids)
        let others = g.ids.filter { !ids.contains($0) }
        let t = min(max(target, 0), others.count)
        let anchor: Ordering.Anchor
        if let prev = others[..<t].last(where: open.contains) {
            // Right under a collapsed heading: the end of its section, where it stays folded (§23).
            if window.collapsed.contains(prev), isHeading(prev),
               let last = p.section(of: prev).dropFirst().last(where: { open.contains($0) && !moving.contains($0) }) {
                anchor = .after(last)
            } else {
                anchor = .after(prev)
            }
        } else if let next = others[t...].first(where: open.contains) {
            anchor = .before(next)
        } else {
            anchor = window.route.listID == nil ? .bottom : .top
        }
        let name = moving.count > 1 ? "Move \(moving.count) Tasks" : "Move"
        undoable(name) { store.reorder(moving, in: group, at: anchor, name: name, undoManager: undo) }
    }

    /// ⌥⌘↑ ⌥⌘↓ (dc:962–975).
    func moveSelectionBy(_ delta: Int) {
        if viewMoveBy(delta) || inTrash { return }
        // A heading moves with its section, past the previous or next one (§23).
        if let h = targetIDs.first(where: isHeading) { moveSectionBy(h, delta); return }
        let L = layout
        let ids = targetIDs.filter { L.group($0) != nil && !L.isDone($0) }
        guard let first = ids.first, let gid = L.group(first), let g = L.groups.first(where: { $0.listID == gid }) else { return }
        let mine = g.ids.filter(ids.contains)
        let othersCount = g.ids.count - mine.count
        guard let firstIdx = g.ids.firstIndex(of: mine[0]) else { return }
        let before = g.ids[..<firstIdx].filter { !mine.contains($0) }.count
        let target = min(max(before + delta, 0), othersCount)
        guard target != before else { return }
        reorder(group: gid, ids: mine, target: target)
        window.taskList?.scrollToVisible(mine[0])
    }

    // MARK: - Dates (§11, dc:930–941)

    func setDate(_ ids: [EntityID]? = nil, _ field: Overlays.Picker.Field, _ date: CalendarDate?) {
        guard !inTrash else { return }
        let ids = (ids ?? targetIDs).filter { p.task($0).map { !$0.isHeading } == true }
        guard !ids.isEmpty else { return }
        let name = field == .when ? (date == nil ? "Remove When" : "Set When") : (date == nil ? "Remove Deadline" : "Set Deadline")
        // Today's rule, and Upcoming's and Undated's (§22).
        let leavesToday = leavesView(ids) { t in (field == .when ? date : t.when, field == .deadline ? date : t.deadline) }
        let next = leavesToday ? nextSelection(afterRemoving: ids) : []
        overlays.picker = nil
        let did = undoable(name) {
            field == .when ? store.setWhen(ids, date, name: name, undoManager: undo)
                : store.setDeadline(ids, date, name: name, undoManager: undo)
        }
        guard did else { return }
        if leavesToday {
            select(next)
            let text: String
            if let date {
                text = (field == .when ? "Scheduled for " : "Due ") + DateLabel.long(date, today: today)
            } else {
                text = "Removed from \(window.route.viewName ?? "Today")"
            }
            overlays.showNotice(text, undo: true)
        }
    }

    /// Opens the date popover for `ids` under `anchor` (window coordinates), or from the keyboard under the detail
    /// pane's chip when it's focused and shows these tasks, else the row's chip, else the row's right end (dc:1128–1138).
    func openPicker(_ field: Overlays.Picker.Field, ids: [EntityID]? = nil, anchor: CGRect? = nil) {
        let ids = (ids ?? targetIDs).filter { !isHeading($0) }
        guard !ids.isEmpty else { return }
        endEdits()
        var rect = anchor
        if rect == nil, window.focus == .detail, window.detailOpen, Set(ids) == window.selection {
            rect = window.detailChipFrames[field]
        }
        if rect == nil { rect = window.taskList?.anchorRect(for: ids[0], field: field) }
        guard let rect else { return }
        overlays.hideTip()
        overlays.picker = .init(field: field, ids: ids, anchor: rect)
    }

    // MARK: - Lists (§12, dc:977–1007)

    func newList() {
        endEdits()
        let id = store.newID()
        overlays.picker = nil
        window.focus = .sidebar
        window.rename = .init(kind: .list, id: id, caret: .all, text: "", isNewList: true, colorSlot: ListModel.slot(for: id))
    }

    /// Puts `id` at `target` among the other active lists.
    func moveList(_ id: EntityID, to target: Int) {
        let others = p.activeLists.ids.filter { $0 != id }
        let t = min(max(target, 0), others.count)
        let anchor: Ordering.Anchor = t > 0 ? .after(others[t - 1]) : (others.isEmpty ? .top : .before(others[0]))
        undoable("Move List") { store.reorderLists([id], at: anchor, name: "Move List", undoManager: undo) }
    }

    func moveListBy(_ id: EntityID, _ delta: Int) {
        let lists = p.activeLists.ids
        guard let i = lists.firstIndex(of: id) else { return }
        let t = min(max(i + delta, 0), lists.count - 1)
        if t != i { moveList(id, to: t) }
    }

    // MARK: - Sidebar

    func toggleSidebar() {
        withAnimation(TK.Motion.sidebar) { window.sidebarVisible.toggle() }
        if !window.sidebarVisible && window.focus == .sidebar { focus(.list) }
    }
}

/// Carries a non-Sendable reference into an undo closure that only ever runs on the main actor.
struct UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
