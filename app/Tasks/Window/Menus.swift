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

    static func menu(_ items: [NSMenuItem]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        items.forEach(m.addItem)
        return m
    }

    // MARK: A task (dc:1029–1060)

    static func task(_ ids: [EntityID], actions a: WindowActions) -> NSMenu {
        let p = a.p
        let tasks = ids.compactMap(p.task)
        let one = tasks.count == 1
        let n = tasks.count
        let anyOpen = tasks.contains { $0.completedAt == nil }
        var items: [NSMenuItem] = []
        if one, let t = tasks.first {
            items.append(Item("Show Details", key: "d") { a.select([t.id]); a.openDetail() })
            items.append(Item("Rename", key: returnKey, modifiers: []) { a.editTask(t.id, caret: .all) })
            if a.window.route == .today {
                items.append(Item("Show in \(a.listName(t.list))") { a.go(.list(t.list), select: [t.id]) })
            }
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

    /// Every active list with its tile and ⌘1–⌘9; the current list checked and disabled.
    static func moveItems(_ ids: [EntityID], actions a: WindowActions) -> [NSMenuItem] {
        let p = a.p
        let tasks = ids.compactMap(p.task)
        return p.activeLists.ids.enumerated().map { i, listID in
            let all = !tasks.isEmpty && tasks.allSatisfy { $0.list == listID }
            let item = Item(a.listName(listID), key: i < 9 ? "\(i + 1)" : "", enabled: !all) { a.move(ids, to: listID) }
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
            let item = Item(a.listName(listID), key: i < 9 ? "\(i + 1)" : "") { a.move(ids, to: listID) }
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
            Item("New Task in \(a.listName(id))") {
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

    nonisolated(unsafe) private static var tileCache: [String: NSImage] = [:]

    static func tileImage(monogram: String, slot: Int, palette: TK.Palette) -> NSImage {
        let key = "\(monogram)-\(slot)-\(palette.isDark)"
        if let img = tileCache[key] { return img }
        let size = TileLayer.dimensions(.small)
        let color = palette.listColor(slot: slot)
        let img = NSImage(size: size, flipped: false) { rect in
            // The small tile (css:123–126): 16×13, radius 3.5, an 8.5pt bold mono letter in the list's color.
            let r = rect.insetBy(dx: 0.25, dy: 0.25)
            let path = NSBezierPath(roundedRect: r, xRadius: 3.5, yRadius: 3.5)
            palette.tileFill.setFill()
            path.fill()
            palette.tileRing.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: TK.Font.tileSmall, .foregroundColor: color]
            let s = (monogram as NSString).size(withAttributes: attrs)
            (monogram as NSString).draw(at: CGPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2), withAttributes: attrs)
            return true
        }
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
