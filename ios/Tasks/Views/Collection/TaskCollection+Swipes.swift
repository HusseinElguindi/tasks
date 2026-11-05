import SwiftUI
import TasksCore
import UIKit

// Swipe actions and long-press menus on the collection view, as UIKit's own: a task's, a heading's and the deleted
// list's row in Trash. Step 3 of the migration.
//
// - Swipes: the list layout's provider, both edges (`actions`). Right completes, left deletes or sets the When; in
//   Trash right puts back; Trash's row for a deleted list restores it. A full swipe does the outermost action.
// - Menus: the collection view's (the controller is its delegate). A task's, a heading's, and a deleted list's row in
//   Trash. A heading's notes have none: held, they'd lift as a row of their own (the user, T31); they're the heading's
//   text, edited with a tap. Select mode's menus are `CollectionSelect`'s (`menu(for:)`).
// - An action runs as it's picked, while the menu closes (the user's call 4): the collection view applies updates
//   during a menu's dismissal, so a heading being renamed or given notes never draws blank.
// - The preview is the row's fill: the cell less its sides' inset and a heading's air, with the row's corners.

@MainActor
final class CollectionSwipes {
    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {}

    private var app: AppModel { owner.app }
    private var source: Source { owner.source }

    /// A deleted list's screen: its rows are deaf, as on the Mac (§28), so they neither swipe nor have a menu.
    var deaf: Bool { app.deletedList(source) != nil }

    /// The task an item draws, if it's a task's row.
    func task(_ id: String) -> TaskModel? {
        guard case let .task(t, _, _, _)? = owner.rows.line(id) else { return nil }
        return app.task(t.id) ?? t
    }

    // MARK: Swipes

    /// The swipe actions for the item at `ip`, on its leading or trailing edge; nil for none.
    func actions(_ ip: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        if owner.select.blocksSwipes { return nil }
        guard !deaf, let id = owner.dataSource.itemIdentifier(for: ip), let line = owner.rows.line(id) else { return nil }
        let app = app, p = owner.palette
        func action(_ title: String, _ symbol: String, _ tint: Color, destructive: Bool = false,
                    _ body: @escaping @MainActor () -> Void) -> UIContextualAction {
            let a = UIContextualAction(style: destructive ? .destructive : .normal, title: title) { _, _, done in
                body()
                done(true)
            }
            a.image = UIImage(systemName: symbol)
            a.backgroundColor = UIColor(tint)
            return a
        }
        func swipes(_ a: [UIContextualAction]) -> UISwipeActionsConfiguration? {
            guard !a.isEmpty else { return nil }
            let c = UISwipeActionsConfiguration(actions: a)
            c.performsFirstActionWithFullSwipe = true
            return c
        }
        switch line {
        case let .task(t, _, _, _):
            let t = app.task(t.id) ?? t, tid = t.id
            if source == .trash {
                guard leading, app.canPutBack(t) else { return nil }
                return swipes([action("Put Back", "arrow.uturn.backward", p.accent) { app.putBack(tid) }])
            }
            if leading {
                return swipes([action(t.isDone ? "Not Done" : "Complete", t.isDone ? "arrow.uturn.backward" : "checkmark",
                                      p.accent) { app.toggle(tid) }])
            }
            // The outermost first: Delete is the full swipe's.
            return swipes([
                action("Delete", "trash", p.danger, destructive: true) { app.delete(tid) },
                action("When", "calendar", p.list(.magenta)) { app.dateTarget = DateTarget(taskID: tid, kind: .when) },
            ])
        case let .deletedList(l, _, _, _):
            guard leading else { return nil }
            let lid = l.id
            return swipes([action("Restore", "arrow.uturn.backward", p.accent) { app.restoreList(lid) }])
        default:
            return nil
        }
    }

    // MARK: Menus

    /// The menu for an item, or nil for none (a heading's notes: none, nor UIKit's preview of them).
    func menu(_ id: String) -> UIMenu? {
        guard !deaf || id.hasPrefix("h:") else { return nil }
        switch owner.rows.line(id) {
        case let .task(t, _, _, _)?: return taskMenu(app.task(t.id) ?? t)
        case let .heading(h, _, _)?: return headingMenu(app.task(h.id) ?? h)
        case let .deletedList(l, _, _, _)?: return deletedListMenu(l.id)
        default: return nil
        }
    }

    private func act(_ title: String, _ symbol: String? = nil, subtitle: String? = nil, destructive: Bool = false,
                     disabled: Bool = false, _ body: @escaping @MainActor () -> Void) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if destructive { attributes.insert(.destructive) }
        if disabled { attributes.insert(.disabled) }
        let a = UIAction(title: title, subtitle: subtitle, image: symbol.flatMap { UIImage(systemName: $0) },
                         attributes: attributes) { _ in body() }
        return a
    }

    /// A group between dividers.
    private func inline(_ children: [UIMenuElement], title: String = "") -> UIMenu {
        UIMenu(title: title, options: .displayInline, children: children)
    }

    /// TaskMenu's, for a task's row.
    private func taskMenu(_ t: TaskModel) -> UIMenu {
        let app = app, source = source, id = t.id
        var groups: [UIMenu] = []
        if case let .list(list) = source {
            // Above this task, which becomes the heading's first (§23). A done one isn't in the order: at the bottom.
            groups.append(inline([act("New Heading Above", "text.line.first.and.arrowtriangle.forward") {
                app.newHeading(in: list, before: t.isDone ? nil : id)
            }]))
        }
        if let name = app.showInName(t, from: source) {
            // From Today or a view: its list, with it shown (the Mac's Show in).
            groups.append(inline([act(MenuName.fit(name, width: 150), "arrow.right.circle") { app.showInList(id) }]))
        }
        if source == .trash {
            // Put Back · Put Back in ▸; one whose list is in Trash has only Put Back in ▸ (the Mac's `Menus.trash`).
            var items: [UIMenuElement] = []
            if app.canPutBack(t) { items.append(act("Put Back", "arrow.uturn.backward") { app.putBack(id) }) }
            items.append(UIMenu(title: "Put Back in", image: UIImage(systemName: "tray.and.arrow.up"),
                                children: [putBackIn([id])]))
            groups.append(inline(items))
        } else {
            let moves = app.activeLists.map { l in
                let lid = l.id
                return act(MenuName.fit(l.name), disabled: l.id == t.list) { app.move(id, to: lid) }
            }
            groups.append(inline([
                act(t.isDone ? "Mark as Not Completed" : "Complete", t.isDone ? "circle" : "checkmark.circle") { app.toggle(id) },
                act("Today", "sun.max") { _ = app.setDate(id, .when, app.today) },
                act("Tomorrow", "sunrise") { _ = app.setDate(id, .when, app.today.adding(days: 1)) },
                act("When…", "calendar") { app.dateTarget = DateTarget(taskID: id, kind: .when) },
                act("Deadline…", "flag") { app.dateTarget = DateTarget(taskID: id, kind: .deadline) },
                UIMenu(title: "Move to", image: UIImage(systemName: "arrow.right.square"), children: moves),
            ]))
            groups.append(inline([act("Delete", "trash", destructive: true) { app.delete(id) }]))
        }
        return UIMenu(children: groups)
    }

    /// PutBackInItems': every live list and the tasks' own deleted lists, in the sidebar's order. Their own deleted
    /// lists are disabled, "In Trash" under the name; one task's own live list is checked.
    private func putBackIn(_ ids: [EntityID]) -> UIMenu {
        let app = app
        let items = app.putBackTargets(ids.compactMap(app.task)).map { target in
            let lid = target.id
            return act(MenuName.fit(app.listName(target.id)), target.home && !target.inTrash ? "checkmark" : nil,
                       subtitle: target.inTrash ? "In Trash" : nil, disabled: target.inTrash) {
                app.putBackTasks(ids, in: lid)
            }
        }
        return inline(items, title: "Put back in")
    }

    /// HeadingMenu's (§23): Rename, its notes, New Task in it, Collapse or Expand, Delete Heading. In a deleted list it
    /// folds, and that's all (the Mac's `readOnlyHeading`).
    private func headingMenu(_ h: TaskModel) -> UIMenu {
        let app = app, id = h.id
        let collapsed = app.collapsed.contains(id)
        let fold = act(collapsed ? "Expand" : "Collapse", collapsed ? "chevron.down" : "chevron.right") { app.toggleCollapse(id) }
        if app.isTrashed(h) { return UIMenu(children: [fold]) }
        // One line: the name is cut to what's left of the menu's 150pt.
        let name = MenuName.fit(h.title, width: 150 - MenuName.width("New Task in “”"))
        return UIMenu(children: [
            inline([
                act("Rename", "pencil") { app.renameHeading(id) },
                act(h.notes.isEmpty ? "Add Notes" : "Edit Notes", "text.alignleft") { app.editHeadingNotes(id) },
                act("New Task in “\(name)”", "plus") { app.newTask(inHeading: id) },
            ]),
            inline([fold]),
            inline([act("Delete Heading", "trash", destructive: true) { app.deleteHeading(id) }]),
        ])
    }

    /// A deleted list's row in Trash: the Mac's Open · Show Details · ── · Restore List; on the phone they open the
    /// same thing.
    private func deletedListMenu(_ id: EntityID) -> UIMenu {
        let app = app
        return UIMenu(children: [
            inline([act("Open", "arrow.right.circle") { app.openDeletedList(id) }]),
            inline([act("Restore List", "arrow.uturn.backward") { app.restoreList(id) }]),
        ])
    }

    // MARK: Previews

    /// The item whose menu is up, and its fill's frame in the collection view as it opened.
    fileprivate var shown: (id: String, frame: CGRect)?
    /// The stand-in a closing menu goes back to when its row has gone (deleted, moved off this screen).
    private var standIn: UIView?

    /// The row's fill, in its cell: the cell less the sides' inset (`Metric.rowInset`) and a heading's air.
    private func fill(_ id: String, in bounds: CGRect) -> CGRect {
        var r = bounds.insetBy(dx: Metric.rowInset, dy: 0)
        if id.hasPrefix("h:") {
            r.origin.y += HeadingRow.air
            r.size.height -= HeadingRow.air
        }
        return r
    }

    private func parameters(_ rect: CGRect) -> UIPreviewParameters {
        let p = UIPreviewParameters()
        p.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: Metric.rowRadius)
        p.backgroundColor = UIColor(owner.palette.base)
        return p
    }

    /// The menu's preview: the row's cell, cut to its fill.
    func highlight(_ id: String) -> UITargetedPreview? {
        guard let ip = owner.dataSource.indexPath(for: id), let cell = owner.cv.cellForItem(at: ip) else { return nil }
        let r = fill(id, in: cell.bounds)
        shown = (id, owner.cv.convert(r, from: cell))
        return UITargetedPreview(view: cell, parameters: parameters(r))
    }

    /// Where the menu goes back to as it closes: the row, wherever it is now; if it has gone, a clear stand-in where it
    /// was, so the menu fades there and never flies to the row that took its place.
    func dismissal(_ id: String) -> UITargetedPreview? {
        if let ip = owner.dataSource.indexPath(for: id), let cell = owner.cv.cellForItem(at: ip) {
            return UITargetedPreview(view: cell, parameters: parameters(fill(id, in: cell.bounds)))
        }
        guard let frame = shown?.frame, shown?.id == id else { return nil }
        let v = UIView(frame: frame)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        owner.cv.addSubview(v)
        standIn = v
        let p = UIPreviewParameters()
        p.visiblePath = UIBezierPath(roundedRect: v.bounds, cornerRadius: Metric.rowRadius)
        p.backgroundColor = .clear
        return UITargetedPreview(view: v, parameters: p)
    }

    func ended() {
        shown = nil
        standIn?.removeFromSuperview()
        standIn = nil
    }
}

// MARK: - The collection view's menu delegate

extension TaskCollectionController {
    func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard ips.count == 1, let id = dataSource.itemIdentifier(for: ips[0]) else { return nil }
        if let m = select.menu(for: id) { return m }
        guard swipes.menu(id) != nil else { return nil }
        // Built as it opens, from the app as it is then.
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
            self?.swipes.menu(id)
        }
    }

    func collectionView(_ cv: UICollectionView, contextMenuConfiguration c: UIContextMenuConfiguration,
                        highlightPreviewForItemAt ip: IndexPath) -> UITargetedPreview? {
        (c.identifier as? String).flatMap(swipes.highlight)
    }

    func collectionView(_ cv: UICollectionView, contextMenuConfiguration c: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt ip: IndexPath) -> UITargetedPreview? {
        (c.identifier as? String).flatMap(swipes.dismissal)
    }

    func collectionView(_ cv: UICollectionView, willEndContextMenuInteraction c: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        guard let animator else { swipes.ended(); return }
        animator.addCompletion { [weak self] in self?.swipes.ended() }
    }
}
