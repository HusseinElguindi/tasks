#if DEBUG
import AppKit
import QuartzCore
import TasksCore

/// Debug aid for the four views (§22): `-debugScript` step `act:<what>[:<arg>]` runs a window action by name, so a
/// script can drive what menu key equivalents would (they don't reach a background app), and records what's on screen.
///
///     act:go:N|<view name>   act:hints:on|off   act:detail   (Show or Hide Details)
///     act:select:<title>[|<title>…]   act:complete   act:delete   act:putback
///     act:rename:<title>   act:renamelist:<list>   act:newlist   (the rename fields)
///     act:putbackin:<list>   act:move:<list>   act:when:+N|none   act:deadline:+N|none   act:moveby:+1|-1
///     act:new   act:newday:+N   act:newin:<list>   act:title:<text>   act:commit   act:undo   act:redo
///     act:typesel:<letters>   (type-select in the sidebar)   act:menu:/path.txt   (the selection's context menu)
///     act:rows:/path.txt   (appends the route, the selection and every laid-out row and label with its window frame)
///     act:day:+N   (the day turns over to N days from now, as at midnight; 0 puts it back)
///     act:dates:/path.txt   (appends every row's When, Deadline and ring as shown, §24)
///     act:trace:MS:/path.txt   (for MS ms, before each commit: the rows' and labels' on-screen y, the drag copy's
///                               origin and opacity, and the lit label; one line per turn that changed)
@MainActor
enum DebugViews {
    static func act(_ arg: String, window w: WindowState, store: Store) {
        let a = WindowActions(store: store, window: w)
        let p = store.projection
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        let what = parts[0]
        let rest = parts.count > 1 ? parts[1] : ""
        func task(_ title: String) -> EntityID? { p.allTaskIDs.sorted().first { p.task($0)?.title == title } }
        func list(_ name: String) -> EntityID? { p.allListIDs.sorted().first { p.list($0)?.name == name } }
        func date(_ s: String) -> CalendarDate? { s == "none" ? nil : Int(s).map { a.today.adding(days: $0) } }
        switch what {
        case "go":
            // A number as ⌘N does, or a view by name (Completed and Trash sit past ⌘9 with six lists).
            if let n = Int(rest) { a.goNumber(n) }
            else if let r = WindowState.Route.sidebarOrder(p).first(where: { a.routeName($0).lowercased() == rest.lowercased() }) { a.go(r) }
        case "hints": w.cmdHints = rest == "on"
        case "frames": DebugFrames.start(rest, window: w)
        case "collapse": if let h = task(rest) { a.toggleCollapse([h]) }
        case "detail": a.toggleDetail()
        case "rename": if let t = task(rest) { a.startRename(t) }
        case "renamelist": if let l = list(rest) { a.startListRename(l) }
        case "newlist": a.newList()
        case "select": a.select(rest.split(separator: "|").compactMap { task(String($0)) })
        case "complete": a.toggleComplete()
        case "delete": a.delete()
        case "putback": a.putBack()
        case "putbackin": if let l = list(rest) { a.putBack(in: l) }
        case "move": if let l = list(rest) { a.move(to: l) }
        case "when": a.setDate(nil, .when, date(rest))
        case "deadline": a.setDate(nil, .deadline, date(rest))
        case "moveby": a.moveSelectionBy(Int(rest) ?? 1)
        case "new": a.newTask()
        case "newday": a.newTask(day: date(rest))
        case "newin": a.newTask(in: list(rest))
        case "title": a.setDraftTitle(rest)
        case "commit": a.endEdits()
        case "undo": a.performUndo()
        case "redo": a.performRedo()
        case "typesel": for ch in rest { a.typeSelect(String(ch), inSidebar: true) }
        case "menu":
            // The selected tasks' context menu: `title[ ▸ sub, …]`, disabled items in parentheses.
            func titles(_ m: NSMenu) -> String {
                m.items.map { i in
                    i.isSeparatorItem ? "--" : (i.isEnabled || i.submenu != nil ? i.title : "(\(i.title))")
                        + (i.submenu.map { " ▸ [" + titles($0) + "]" } ?? "")
                }.joined(separator: ", ")
            }
            append("menu \(a.routeName(w.route)): " + titles(Menus.task(a.targetIDs, actions: a)), to: rest)
        case "rows": append(rows(w, store: store), to: rest)
        case "sync": store.requestSync(force: true)
        // §24: the day turning over, as at midnight: Today and every date's words and rings move to the new day
        // (`act:day:+1`; `act:day:0` puts the real day back).
        case "dates": if let s = w.taskList?.debugDates() { append("dates \(a.routeName(w.route)) today=\(p.day.date.string)\n" + s, to: rest) }
        case "day": store.projection.setDay(Day(containing: Date().addingTimeInterval(86_400 * (Double(rest) ?? 0))))
        case "newheading": a.newHeading()
        case "titlerename": a.startTitleRename()
        case "headingnotes": if let id = task(rest) { a.editHeadingNotes(id) }
        case "selectall": a.selectAll()
        case "scroll": w.taskList?.debugScroll(CGFloat(Double(rest) ?? 0))
        case "lastop":
            // The newest pending op's JSON, and how many are pending.
            let last = store.projection.pending.last.map { String(decoding: $0.json, as: UTF8.self) } ?? "-"
            append("lastop pending=\(store.projection.pending.count) \(last)", to: rest)
        case "state":
            append("state route=\(a.routeName(w.route)) sel=\(w.selection.compactMap { p.task($0)?.title }.sorted()) titleScrolled=\(w.titleScrolled) paneNotes=\(w.paneNotes.map { "\($0)" } ?? "-") rename=\(w.rename.map { "\($0.kind):\($0.text)" } ?? "-") notice=\(w.overlays.notice.map { "'\($0.text)'" } ?? "-") list=\(w.route.listID.flatMap { p.list($0) }.map { "\($0.name)|\($0.notes.debugDescription)" } ?? "-")", to: rest)
        // §23: hover the list at a window point (top-left), log a heading's parts in window points, run a heading's
        // context-menu item by its title.
        case "hover":
            let v = rest.split(separator: ",").compactMap { Double($0) }
            if v.count == 2 { w.taskList?.debugHover(CGPoint(x: v[0], y: v[1])) } else { w.taskList?.debugHover(nil) }
        case "where":
            let t = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if t.count == 2, let id = task(t[0]), let s = w.taskList?.debugWhere(id) { append("where \(t[0]): " + s, to: t[1]) }
        // v2 feedback 15: Today's Completed label (or a list's Completed row): where it is, its chevron and fold state.
        case "donewhere":
            if let s = w.taskList?.debugDoneWhere() {
                append("donewhere: " + s + " collapsed=\(w.todayDoneCollapsed) completedOpen=\(w.completedOpen.count) sel=\(w.selection.map { $0 == TaskLayout.doneGroup ? "<Completed>" : (p.task($0)?.title ?? $0) }.sorted())", to: rest)
            }
        case "donetoggle": a.toggleTodayDone()
        case "headmenu":
            let t = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if t.count == 2, let id = task(t[0]) {
                let m = Menus.heading([id], actions: a)
                if let item = m.items.first(where: { $0.title == t[1] }), let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                } else {
                    print("headmenu: no item \(t[1]) in \(m.items.map(\.title))")
                }
            }
        case "headmenulog":
            let t = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if t.count == 2, let id = task(t[0]) {
                append("headmenu \(t[0]): " + Menus.heading([id], actions: a).items.map { $0.isSeparatorItem ? "--" : ($0.isEnabled ? $0.title : "(\($0.title))") }.joined(separator: ", "), to: t[1])
            }
        case "trace":
            let t = rest.split(separator: ":", maxSplits: 1).map(String.init)
            if t.count == 2, let ms = Int(t[0]) { trace(w, store: store, ms: ms, path: t[1]) }
        default: print("act: unknown \(arg)")
        }
    }

    private static func append(_ s: String, to path: String) {
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// The route, selection and every row and label of the current layout: `title y` (doc coordinates), in order.
    static func rows(_ w: WindowState, store: Store) -> String {
        let p = store.projection
        let a = WindowActions(store: store, window: w)
        let L = TaskLayout.make(store: store, window: w)
        var out = "route=\(a.routeName(w.route)) sel=\(w.selection.compactMap { p.task($0)?.title }.sorted()) detail=\(w.detailOpen) draft=\(w.draft.map { "'\($0.title)' \($0.when?.string ?? "-") \(a.listName($0.list))" } ?? "-") empty=\(L.empty.map { "\($0)" } ?? "-") notice=\(w.overlays.notice.map { "'\($0.text)'" } ?? "-") hints=\(w.cmdHints)"
        var items: [(CGFloat, String)] = L.order.map { id in
            let t = p.task(id)
            let flags = (t?.completedAt != nil ? " done" : "") + (t?.deleted == true ? " deleted" : "")
                + (L.isHeading(id) ? " #heading" + (w.collapsed.contains(id) ? " collapsed" : "") + ((L.noteH[id] ?? 0) > 0 ? " notes=\(Int(L.noteH[id]!))" : "") : "")
            return (L.yList[L.index[id]!], "  \(Int(L.yList[L.index[id]!])) \(t?.title ?? (id == w.draft?.id ? "<draft>" : id))\(flags) when=\(t?.when?.string ?? "-") dl=\(t?.deadline?.string ?? "-") list=\(t.map { a.listName($0.list) } ?? "-")")
        }
        for (key, y) in L.labels {
            let info = L.labelInfo[key]
            let name = info.map { $0.list.map(a.listName) ?? $0.name } ?? a.listName(key)
            items.append((y - 0.5, "  \(Int(y)) [\(name)\(info?.sub.map { " " + $0 } ?? "")\(info?.quiet == true ? " quiet" : "")\(info?.plus == true ? " +" : "")]"))
        }
        out += "\n" + items.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n")
        return out
    }

    /// Samples the list before each Core Animation commit for `ms`: each row view's and label's presentation y and
    /// opacity, the drag copy's presentation origin and opacity, and which label is lit. A line per turn that changed.
    static func trace(_ w: WindowState, store: Store, ms: Int, path: String) {
        guard let list = w.taskList else { return }
        let p = store.projection
        var last = ""
        let t0 = CACurrentMediaTime()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
            MainActor.assumeIsolated {
                var parts: [String] = []
                for v in list.doc.subviews where !v.isHidden {
                    let l = v.layer?.presentation() ?? v.layer
                    let y = (l?.frame.minY ?? v.frame.minY)
                    let op = l?.opacity ?? 1
                    if let r = v as? TaskRowView, let m = r.model {
                        parts.append("\(p.task(m.id)?.title ?? "draft")@\(Int(y.rounded()))\(op < 0.99 ? "/\(String(format: "%.2f", op))" : "")")
                    } else if let h = v as? HeadingRowView, let m = h.model {
                        parts.append("#\(p.task(m.id)?.title ?? "new")@\(Int(y.rounded()))\(op < 0.99 ? "/\(String(format: "%.2f", op))" : "")")
                    } else if v is NotesTextView {
                        parts.append("notes@\(Int(y.rounded()))\(op < 0.99 ? "/\(String(format: "%.2f", op))" : "")")
                    } else if let g = v as? GroupLabelView {
                        parts.append("[\(g.key)]@\(Int(y.rounded()))\(g.debugLit ? "*" : "")")
                    }
                }
                if let copy = w.dragOverlay?.debugCopy {
                    parts.append("copy@\(Int(copy.origin.x)),\(Int(copy.origin.y))/\(String(format: "%.2f", copy.opacity))")
                }
                parts.append("drag=\(w.drag.map { "\($0.phase) to=\($0.toDay?.string ?? "-") over=\($0.over.map { "\($0)" } ?? "-")" } ?? "-")")
                let line = parts.joined(separator: " ")
                guard line != last else { return }
                last = line
                append(String(format: "%.3f ", CACurrentMediaTime() - t0) + line, to: path)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
}
#endif
