import AppKit
import TasksCore

/// The context menus (§15) as native NSMenus, with the prototype's items (dc:1029–1093). Items that don't apply are
/// disabled, not hidden.
@MainActor
enum Menus {
    final class Item: NSMenuItem {
        private var handler: (() -> Void)?

        convenience init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                         enabled: Bool = true, action: (() -> Void)? = nil) {
            self.init(title: title, action: action == nil ? nil : #selector(fire), keyEquivalent: key)
            keyEquivalentModifierMask = modifiers
            handler = action
            target = self
            isEnabled = enabled && action != nil
        }

        @objc private func fire() { handler?() }
    }

    /// A Return key equivalent shown as ↩ (Rename).
    static let returnKey = "\r"

    /// A name as a menu item shows it: cut with an ellipsis at 280pt in the menu's font, so a 200-character list name
    /// doesn't make the menu as wide as the screen (v2 feedback 16).
    static func fit(_ s: String, width: CGFloat = 280, font: NSFont = NSFont.menuFont(ofSize: 0)) -> String {
        func w(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: [.font: font]).width }
        guard w(s) > width else { return s }
        var lo = 0, hi = s.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if w(String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…") <= width { lo = mid } else { hi = mid - 1 }
        }
        return String(s.prefix(lo)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func menu(_ items: [NSMenuItem]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        items.forEach(m.addItem)
        return m
    }

    // MARK: A task (dc:1029–1060)

    static func task(_ ids: [EntityID], actions a: WindowActions) -> NSMenu {
        if a.inTrash { return trash(ids, actions: a) }
        let p = a.p
        let tasks = ids.compactMap(p.task)
        let one = tasks.count == 1
        let n = tasks.count
        let anyOpen = tasks.contains { $0.completedAt == nil }
        var items: [NSMenuItem] = []
        if one, let t = tasks.first {
            items.append(Item("Show Details", key: "d") { a.select([t.id]); a.openDetail() })
            items.append(Item("Rename", key: returnKey, modifiers: []) { a.editTask(t.id, caret: .all) })
            if a.window.route.listID == nil {
                items.append(Item(fit("Show in \(a.listName(t.list))")) { a.go(.list(t.list), select: [t.id]) })
            }
        }
        if a.window.route.listID != nil {
            // §23: above the first selected row, which becomes the heading's first task.
            items.append(Item("New Heading Above", key: "n", modifiers: [.command, .option]) { a.newHeading() })
        }
        items.append(.separator())
        items.append(Item(anyOpen ? (one ? "Complete" : "Complete \(n) Tasks") : "Mark as Not Done", key: "k") { a.toggleComplete(ids) })
        let today = a.today
        let when = NSMenuItem(title: "When", action: nil, keyEquivalent: "")
        when.submenu = menu([
            Item("Today", key: "t") { a.setDate(ids, .when, today) },
            Item("Tomorrow") { a.setDate(ids, .when, today.adding(days: 1)) },
            Item("This Weekend") { a.setDate(ids, .when, DatePhrase.weekend(from: today)) },
            Item("Next Week") { a.setDate(ids, .when, DatePhrase.nextWeek(from: today)) },
            .separator(),
            Item("Choose Date…", key: "s") { a.openPicker(.when, ids: ids) },
            .separator(),
            Item("Remove", enabled: tasks.contains { $0.when != nil }) { a.setDate(ids, .when, nil) },
        ])
        items.append(when)
        let deadline = NSMenuItem(title: "Deadline", action: nil, keyEquivalent: "")
        deadline.submenu = menu([
            Item("Choose Date…", key: "d", modifiers: [.command, .shift]) { a.openPicker(.deadline, ids: ids) },
            .separator(),
            Item("Remove", enabled: tasks.contains { $0.deadline != nil }) { a.setDate(ids, .deadline, nil) },
        ])
        items.append(deadline)
        let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        move.submenu = menu([header("Move to")] + moveItems(ids, actions: a))
        items.append(move)
        items.append(.separator())
        items.append(Item(one ? "Delete" : "Delete \(n) Tasks", key: "\u{8}") { a.delete(ids) })
        return menu(items)
    }

    /// A heading (§23, dc:3554–3575): Rename, its notes, New Task in it, Collapse or Expand, Move Up and Down, Delete.
    static func heading(_ ids: [EntityID], actions a: WindowActions) -> NSMenu {
        let p = a.p
        let heads = ids.compactMap(p.task).filter(\.isHeading)
        guard let h = heads.first else { return menu([]) }
        let one = heads.count == 1
        let name = h.title.isEmpty ? "this heading" : h.title
        var items: [NSMenuItem] = []
        if one {
            items.append(Item("Rename", key: returnKey, modifiers: []) { a.startHeadingRename(h.id) })
            items.append(Item(h.notes.isEmpty ? "Add Notes" : "Edit Notes") { a.editHeadingNotes(h.id) })
            items.append(Item(fit("New Task in \(name)")) { a.newTask(in: h.list, under: h.id) })
            items.append(.separator())
        }
        let collapse = !heads.allSatisfy { a.window.collapsed.contains($0.id) }
        items.append(Item(collapse ? "Collapse" : "Expand", key: " ", modifiers: []) { a.toggleCollapse(heads.map(\.id), to: collapse) })
        if one {
            let order = p.headings(in: h.list).ids
            let i = order.firstIndex(of: h.id) ?? 0
            items.append(.separator())
            items.append(Item("Move Up", key: String(UnicodeScalar(NSUpArrowFunctionKey)!), modifiers: [.command, .option],
                              enabled: i > 0) { a.moveSectionBy(h.id, -1) })
            items.append(Item("Move Down", key: String(UnicodeScalar(NSDownArrowFunctionKey)!), modifiers: [.command, .option],
                              enabled: i + 1 < order.count) { a.moveSectionBy(h.id, 1) })
        }
        items.append(.separator())
        items.append(Item(one ? "Delete Heading" : "Delete \(heads.count) Headings", key: "\u{8}") { a.delete(heads.map(\.id)) })
        return menu(items)
    }

    /// A task in the Trash: Show Details, Put Back, Put Back in ▸ (§22, dc:2422–2430).
    static func trash(_ ids: [EntityID], actions a: WindowActions) -> NSMenu {
        let p = a.p
        let tasks = ids.compactMap(p.task)
        let n = tasks.count
        var items: [NSMenuItem] = []
        if n == 1, let t = tasks.first {
            items.append(Item("Show Details", key: "d") { a.select([t.id]); a.openDetail() })
            items.append(.separator())
        }
        items.append(Item(n == 1 ? "Put Back" : "Put Back \(n) Tasks", key: "\u{8}") { a.putBack(ids) })
        let into = NSMenuItem(title: "Put Back in", action: nil, keyEquivalent: "")
        into.submenu = menu([header("Put back in")] + p.activeLists.ids.map { listID in
            let item = Item(fit(a.listName(listID))) { a.putBack(ids, in: listID) }
            if let m = p.listModel(listID) { item.image = tileImage(monogram: m.monogram, slot: m.colorSlot, palette: a.window.palette) }
            if n == 1 && tasks[0].list == listID { item.state = .on }
            return item
        })
        items.append(into)
        return menu(items)
    }

    /// Every active list with its tile and ⌘1–⌘9; the current list checked and disabled.
    static func moveItems(_ ids: [EntityID], actions a: WindowActions) -> [NSMenuItem] {
        let p = a.p
        let tasks = ids.compactMap(p.task)
        return p.activeLists.ids.enumerated().map { i, listID in
            let all = !tasks.isEmpty && tasks.allSatisfy { $0.list == listID }
            let item = Item(fit(a.listName(listID)), key: i < 9 ? "\(i + 1)" : "", enabled: !all) { a.move(ids, to: listID) }
            if let m = p.listModel(listID) {
                item.image = tileImage(monogram: m.monogram, slot: m.colorSlot, palette: a.window.palette)
            }
            if tasks.count == 1 && all { item.state = .on }
            return item
        }
    }

    static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// ⇧⌘M: the "Move to" menu under the first selected row, 34 in from its left and 2 below it, with the first other
    /// list highlighted (dc:1079–1087). `at` is in `view`'s coordinates.
    static func popMoveMenu(_ ids: [EntityID], at point: NSPoint, in view: NSView, actions a: WindowActions) {
        guard let first = ids.first.flatMap(a.p.task) else { return }
        let title = ids.count > 1 ? "Move \(ids.count) tasks to" : "Move \(a.quote(first.title)) to"
        let m = menu([header(title)] + moveItems(ids, actions: a))
        // Highlight the first enabled list, as the prototype does, by stepping into the menu once it's open.
        let highlighter = MenuHighlighter()
        m.delegate = highlighter
        objc_setAssociatedObject(m, &MenuHighlighter.key, highlighter, .OBJC_ASSOCIATION_RETAIN)
        m.popUp(positioning: nil, at: point, in: view)
    }

    /// The detail pane's List pop-up: the same lists, under the pop-up (dc:1088–1093).
    static func popListMenu(_ ids: [EntityID], current: EntityID?, at point: NSPoint, in view: NSView, actions a: WindowActions) {
        let items = a.p.activeLists.ids.enumerated().map { i, listID -> NSMenuItem in
            let item = Item(fit(a.listName(listID)), key: i < 9 ? "\(i + 1)" : "") { a.move(ids, to: listID) }
            if let m = a.p.listModel(listID) { item.image = tileImage(monogram: m.monogram, slot: m.colorSlot, palette: a.window.palette) }
            if listID == current { item.state = .on }
            return item
        }
        menu(items).popUp(positioning: nil, at: point, in: view)
    }

    // MARK: Lists (dc:1061–1078)

    static func list(_ id: EntityID, actions a: WindowActions) -> NSMenu {
        let p = a.p
        guard let l = p.list(id) else { return NSMenu() }
        if l.archivedAt != nil {
            return menu([
                Item("Unarchive") { a.unarchive(list: id) },
                Item("Rename", key: returnKey, modifiers: []) { a.startListRename(id) },
            ])
        }
        let lists = p.activeLists.ids
        let i = lists.firstIndex(of: id) ?? 0
        return menu([
            Item(fit("New Task in \(a.listName(id))")) {
                a.go(.list(id))
                DispatchQueue.main.async { a.newTask(in: id) }
            },
            Item("Rename", key: returnKey, modifiers: []) { a.startListRename(id) },
            .separator(),
            Item("Move Up", key: String(UnicodeScalar(NSUpArrowFunctionKey)!), modifiers: [.command, .option], enabled: i > 0) { a.moveListBy(id, -1) },
            Item("Move Down", key: String(UnicodeScalar(NSDownArrowFunctionKey)!), modifiers: [.command, .option], enabled: i < lists.count - 1) { a.moveListBy(id, 1) },
            .separator(),
            Item("Archive", key: "\u{8}") { a.archive(list: id) },
        ])
    }

    static func sidebarEmpty(actions a: WindowActions) -> NSMenu {
        menu([Item("New List", key: "n", modifiers: [.command, .shift]) { a.newList() }])
    }

    // MARK: Tile images for menu items

    private struct TileKey: Hashable {
        let monogram: String
        let slot: Int
        let palette: TK.Palette
    }

    nonisolated(unsafe) private static var tileCache: [TileKey: NSImage] = [:]

    static func tileImage(monogram: String, slot: Int, palette: TK.Palette) -> NSImage {
        let key = TileKey(monogram: monogram, slot: slot, palette: palette)
        if let img = tileCache[key] { return img }
        let img = TileLayer.image(monogram: monogram, hue: palette.tile(slot: slot), palette: palette)
        tileCache[key] = img
        return img
    }
}

/// Moves the highlight onto the first enabled item when a menu opens (the prototype's Move-to menu opens that way).
final class MenuHighlighter: NSObject, NSMenuDelegate {
    nonisolated(unsafe) static var key = 0

    func menuWillOpen(_ menu: NSMenu) {
        DispatchQueue.main.async {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: 0, context: nil, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                                           charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!), isARepeat: false, keyCode: 125)
            else { return }
            NSApp.postEvent(e, atStart: true)
        }
    }
}
