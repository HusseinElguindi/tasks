import SwiftUI
import TasksCore
import UIKit

// Select mode (§3) on the collection view: the joined fill (`Picks`, for each task row), the two-finger swipe
// (`SwipeSelect`, on this collection view, mapping a touch to the row under it), and a long-press's menu for the whole
// selection, with the pressed row added. The SelectBar, Select in the "…", ⌘A and Esc stay in ListScreen and RootView,
// and every action, its one undo step and the end of select mode are AppModel's (Select.swift): they're the same on
// both paths. Step 7 of the migration.
//
// Hooks: `install` and `stop`; `pick(_:)` for a task row's fill (CollectionLine); `menu(for:)` and `blocksSwipes` for
// the swipes and menus area (CollectionSwipes), `blocksDrag` for the drag area.

@MainActor
final class CollectionSelect {
    unowned let owner: TaskCollectionController
    private let swipe = SwipeSelect()

    init(owner: TaskCollectionController) { self.owner = owner }

    private var app: AppModel { owner.app }
    private var source: Source { owner.source }

    /// Select mode is on here.
    var active: Bool { app.isSelecting(source) }
    /// In select mode no row swipes (§3): the bar's actions are the only ones.
    var blocksSwipes: Bool { active }
    /// Nothing lifts in select mode: the reorder brief drags one row at a time.
    var blocksDrag: Bool { active }

    func install() {
        let app = app, source = source
        swipe.foot = app.isSplit ? 8 : Metric.fab + 6
        // The rows a swipe can cross are read as it starts: nothing it does changes them.
        swipe.canStart = { [weak self] in
            guard let self, app.shown == source, app.deletedList(source) == nil, app.dateTarget == nil else { return false }
            self.swipe.order = self.owner.current.compactMap(Self.task)
            return true
        }
        swipe.locate = { [weak self] p in self?.task(at: p) }
        swipe.enter = { app.startSelecting(source) }
        swipe.selection = { app.isSelecting(source) ? app.selected : [] }
        swipe.apply = { app.selected = $0 }
        swipe.install(on: owner.cv)
    }

    func stop() { swipe.cancel() }

    /// A task item's id ("t:<id>"), or nil for any other item.
    private static func task(_ item: String) -> EntityID? { item.hasPrefix("t:") ? String(item.dropFirst(2)) : nil }

    /// The task row under a point in the window.
    private func task(at p: CGPoint) -> EntityID? {
        let cv = owner.cv!
        return cv.indexPathForItem(at: cv.convert(p, from: nil)).flatMap(owner.dataSource.itemIdentifier).flatMap(Self.task)
    }

    // MARK: The joined fill

    /// A task row's fill in select mode: selected, and joined to the selected row above or below it.
    struct Pick {
        var picked = false
        var joinTop = false
        var joinBottom = false
    }

    private var cache: (items: [String], selected: Set<EntityID>, picks: Picks)?

    /// The row's fill. Read from a cell's body, so the row redraws when the selection or the items change (the
    /// selection is observed; the items through the cells' `CollectionRows.version`).
    func pick(_ id: EntityID) -> Pick {
        // Only in select mode (observed) does a row depend on the items: outside it, rows don't redraw as they change.
        guard active else { return Pick() }
        _ = owner.rows.version
        let selected = app.selected
        let picks: Picks
        if let c = cache, c.selected == selected, c.items == owner.current {
            picks = c.picks
        } else {
            picks = Self.picks(owner.current, selected: selected)
            cache = (owner.current, selected, picks)
        }
        return Pick(picked: picks.selected.contains(id), joinTop: picks.above.contains(id), joinBottom: picks.below.contains(id))
    }

    /// `Picks` over the items: neighbouring selected task rows join; any other item between them (a heading, a label,
    /// the Completed row) breaks the block.
    static func picks(_ items: [String], selected: Set<EntityID>) -> Picks {
        var out = Picks([], selected: selected)
        guard !selected.isEmpty else { return out }
        var prev: EntityID?
        for item in items {
            if let t = task(item), selected.contains(t) {
                if let p = prev {
                    out.above.insert(t)
                    out.below.insert(p)
                }
                prev = t
            } else {
                prev = nil
            }
        }
        return out
    }

    // MARK: A long-press

    /// The menu for an item in select mode, for the menus area to return first: nil when select mode is off (the
    /// menus area decides); `.some(nil)` for no menu (a heading's menu is off, and nothing else but a task row has one);
    /// otherwise the selection's menu (IX §15), with the pressed row added to the selection as the menu comes up. Closed without a choice, it stays selected.
    func menu(for item: String) -> UIContextMenuConfiguration?? {
        guard active else { return nil }
        guard let id = Self.task(item), app.deletedList(source) == nil else { return .some(nil) }
        return UIContextMenuConfiguration(identifier: item as NSString, previewProvider: nil) { [weak self] _ in
            guard let self, self.active else { return nil }
            self.app.selected.insert(id)
            return self.selectionMenu(self.app.menuTargets(self.source, adding: id))
        }
    }

    private func act(_ title: String, _ symbol: String? = nil, subtitle: String? = nil, destructive: Bool = false,
                     disabled: Bool = false, _ body: @escaping @MainActor () -> Void) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if destructive { attributes.insert(.destructive) }
        if disabled { attributes.insert(.disabled) }
        let a = UIAction(title: title, image: symbol.flatMap { UIImage(systemName: $0) }, attributes: attributes) { _ in
            MainActor.assumeIsolated { body() }
        }
        a.subtitle = subtitle
        return a
    }

    /// Complete 3 Tasks (Mark as Not Done when all are done) · Today · Tomorrow · When… · Deadline… · Move to ▸ · ──
    /// · Delete 3 Tasks; in Trash, Put Back (when every task has a live list) · Put Back in ▸ (IX §15).
    private func selectionMenu(_ ids: [EntityID]) -> UIMenu {
        let app = app
        let tasks = ids.compactMap(app.task)
        let n = tasks.count
        if source == .trash {
            var items: [UIMenuElement] = []
            if app.allGoHome(ids) {
                items.append(act(n == 1 ? "Put Back" : "Put Back \(n) Tasks", "arrow.uturn.backward") { app.putBackTasks(ids) })
            }
            items.append(UIMenu(title: "Put Back in", image: UIImage(systemName: "tray.and.arrow.up"), children: [putBackIn(ids)]))
            return UIMenu(children: items)
        }
        let anyOpen = tasks.contains { !$0.isDone }
        let today = app.today
        return UIMenu(children: [
            act(anyOpen ? (n == 1 ? "Complete" : "Complete \(n) Tasks") : "Mark as Not Done",
                anyOpen ? "checkmark.circle" : "circle") { app.completeTasks(ids) },
            act("Today", "sun.max") { app.setDate(ids, .when, today) },
            act("Tomorrow", "sunrise") { app.setDate(ids, .when, today.adding(days: 1)) },
            act("When…", "calendar") { app.dateTarget = DateTarget(ids: ids, kind: .when) },
            act("Deadline…", "flag") { app.dateTarget = DateTarget(ids: ids, kind: .deadline) },
            UIMenu(title: "Move to", image: UIImage(systemName: "arrow.right.square"), children: [move(ids)]),
            UIMenu(options: .displayInline, children: [
                act(n == 1 ? "Delete" : "Delete \(n) Tasks", "trash", destructive: true) { app.deleteTasks(ids) },
            ]),
        ])
    }

    /// `MoveItems`: "Move 3 tasks to", then every live list; the list every task is already in is checked and disabled.
    private func move(_ ids: [EntityID]) -> UIMenu {
        let app = app
        let tasks = ids.compactMap(app.task)
        return UIMenu(title: tasks.count == 1 ? "Move to" : "Move \(tasks.count) tasks to", options: .displayInline,
                      children: app.activeLists.map { l in
                          let all = !tasks.isEmpty && tasks.allSatisfy { $0.list == l.id }
                          let id = l.id
                          return act(MenuName.fit(l.name), all ? "checkmark" : nil, disabled: all) { app.moveTasks(ids, to: id) }
                      })
    }

    /// `PutBackInItems`: every live list and the tasks' own deleted lists, theirs disabled with "In Trash" under them.
    private func putBackIn(_ ids: [EntityID]) -> UIMenu {
        let app = app
        return UIMenu(title: "Put back in", options: .displayInline,
                      children: app.putBackTargets(ids.compactMap(app.task)).map { target in
                          let id = target.id
                          return act(MenuName.fit(app.listName(id)), target.home ? "checkmark" : nil,
                                     subtitle: target.inTrash ? "In Trash" : nil, disabled: target.inTrash) {
                              app.putBackTasks(ids, in: id)
                          }
                      })
    }
}
