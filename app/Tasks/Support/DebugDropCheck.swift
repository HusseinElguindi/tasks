#if DEBUG
import AppKit
import TasksCore

/// Debug aid for the drop rule (design/DECLARATIVE-DRAGGING.md, borrow 2): a drag's preview is the layout of the state
/// its drop writes. `act:dropcheck:/path.txt` checks it in the open view with no pointer and no frames: for every row
/// that drags (a task, a heading with its section, two selected tasks apart) and every place it can drop (each slot
/// of its group, or each day in Upcoming), it lays the view out mid-drag as `TaskListView.updateDrag` sets it, writes
/// the drop as `endDrag` does, lays it out again as the landing renders it, and undoes. Every row and label must be
/// where the preview drew it. Appends a line per disagreement and a summary (`ok` or `FAIL`).
///
/// What it allows, by design: a heading's tasks and notes are folded into its copy until it lands (§23), so for a
/// heading only it and the rows above its gap are compared; a task dropped right under a collapsed heading folds into
/// its section (it lands on the heading's row, `endDrag`).
@MainActor
enum DebugDropCheck {
    private struct Snap: Equatable {
        var rows: [EntityID: CGFloat] = [:]
        var labels: [EntityID: CGFloat] = [:]
        var folded: [EntityID: EntityID] = [:]
    }

    private static func snap(_ L: TaskLayout) -> Snap {
        var s = Snap()
        for id in L.order { s.rows[id] = L.y(id) }
        s.labels = L.labels
        s.folded = L.folded
        return s
    }

    static func run(_ w: WindowState, store: Store, path: String) {
        let a = WindowActions(store: store, window: w)
        let p = store.projection
        let routeName = a.routeName(w.route)
        var out: [String] = []
        var checks = 0, fails = 0
        func name(_ id: EntityID) -> String { p.task(id)?.title ?? p.list(id)?.name ?? id }
        func names(_ ids: [EntityID]) -> String { "[" + ids.map(name).joined(separator: " + ") + "]" }
        // Each drop is written as `endDrag` writes it, an undo step of its own, and undone at once.
        guard w.undoManager != nil else {
            append("dropcheck \(routeName): FAIL no undo manager", to: path)
            return
        }
        w.drag = nil
        w.selection = []
        w.viewDates.invalidate()
        let L0 = TaskLayout.make(store: store, window: w)
        let base = snap(L0)

        func layout() -> TaskLayout { TaskLayout.make(store: store, window: w) }

        /// Undoes the drop's write (if it made one) and checks the view is back as it was.
        func restore(_ wrote: Bool) -> Bool {
            w.drag = nil
            if wrote { a.performUndo() }
            w.viewDates.invalidate()
            if snap(layout()) != base {
                out.append("FAIL \(routeName): the undo didn't put the view back; stopping")
                fails += 1
                return false
            }
            return true
        }

        /// The rows and labels where the preview `pre` and the landing `post` disagree. `only`: compare just these rows
        /// (and the labels above `above`).
        func diff(_ pre: Snap, _ post: Snap, dragged: [EntityID], only: Set<EntityID>? = nil, above: CGFloat? = nil) -> [String] {
            var bad: [String] = []
            let keys = only.map(Array.init) ?? Array(pre.rows.keys)
            for id in keys.sorted(by: { (pre.rows[$0] ?? 0) < (pre.rows[$1] ?? 0) }) {
                guard let y0 = pre.rows[id] else { continue }
                if let above, y0 >= above, !dragged.contains(id) { continue }
                guard let y1 = post.rows[id] else {
                    // Folded into a collapsed heading's section: it lands on the heading's row.
                    if let h = post.folded[id], w.collapsed.contains(h), dragged.contains(id) { continue }
                    bad.append("'\(name(id))' preview y \(Int(y0)), landed not shown")
                    continue
                }
                if abs(y0 - y1) > 0.5 { bad.append("'\(name(id))'\(dragged.contains(id) ? " (dragged)" : "") preview y \(Int(y0)), landed \(Int(y1))") }
            }
            for (lid, y0) in pre.labels.sorted(by: { $0.value < $1.value }) {
                if let above, y0 >= above { continue }
                let y1 = post.labels[lid]
                if y1.map({ abs($0 - y0) > 0.5 }) ?? true {
                    bad.append("label '\(name(lid))' preview y \(Int(y0)), landed \(y1.map { "\(Int($0))" } ?? "gone")")
                }
            }
            return bad
        }

        func record(_ what: String, _ bad: [String]) {
            checks += 1
            guard !bad.isEmpty else { return }
            fails += 1
            out.append("FAIL \(routeName) \(what): " + bad.prefix(6).joined(separator: "; ") + (bad.count > 6 ? "; +\(bad.count - 6) more" : ""))
        }

        if w.route == .upcoming {
            // Upcoming (§22): onto any day (not a month, not past a dragged task's deadline), as `dayTarget` allows.
            let days = L0.groups.filter { $0.kind == .day && $0.day != nil }
            var drags: [(ids: [EntityID], group: EntityID)] = []
            for g in days {
                let ids = g.ids.filter { $0 != w.draft?.id && p.task($0) != nil }
                for id in ids { drags.append(([id], g.listID)) }
                if ids.count >= 2 { drags.append(([ids[0], ids[ids.count - 1]], g.listID)) }
            }
            outer: for d in drags {
                for g in days {
                    guard let day = g.day, d.ids.allSatisfy({ p.task($0)?.deadline.map { day <= $0 } ?? true }) else { continue }
                    var drag = WindowState.Drag(kind: .tasks(ids: d.ids, group: d.group), target: 0, mode: .days)
                    drag.toDay = day
                    w.drag = drag
                    _ = layout()
                    // `endViewDrag`: a day that changes a task's is written, and the copy flies into the layout at the
                    // release (the drop's state: the days the rows left no longer kept); on their own day it flies home.
                    let writes = d.ids.contains { id in p.task(id).flatMap { ViewGroups.upDay(when: $0.when, deadline: $0.deadline) } != day }
                    if !writes { w.drag?.toDay = nil }
                    w.drag?.phase = .fly
                    let pre = snap(layout())
                    if writes { a.dropOnDay(d.ids, day) }
                    w.drag?.phase = .done
                    let post = writes ? snap(layout()) : base
                    record("\(names(d.ids)) onto \(day.string)", diff(pre, post, dragged: d.ids))
                    if !restore(writes) { break outer }
                }
            }
        } else if w.route == .today || w.route == .undated || w.route.listID != nil {
            // A list's open tasks, Today's and Undated's groups (§14): each slot of the group, as `updateDrag` picks
            // them; a heading's section only before another heading or at the end (§23).
            var drags: [(ids: [EntityID], group: TaskLayout.Group, heading: Bool)] = []
            for g in L0.groups where g.listID != TaskLayout.doneGroup {
                let tasks = g.ids.filter { $0 != w.draft?.id && !L0.isHeading($0) && !L0.listRows.contains($0) && p.task($0) != nil }
                for id in g.ids where id != w.draft?.id && p.task(id) != nil && !L0.listRows.contains(id) {
                    if L0.isHeading(id) {
                        drags.append(([id] + p.section(of: id).dropFirst().filter { L0.contains($0) }, g, true))
                    } else {
                        drags.append(([id], g, false))
                    }
                }
                // Two selected tasks apart: they travel together and land together.
                if tasks.count >= 3 { drags.append(([tasks[0], tasks[2]], g, false)) }
            }
            outer: for d in drags {
                let g = d.group
                let others = g.ids.filter { !d.ids.contains($0) }
                let tops = L0.slotTops(g, others: others)
                let first = g.ids.firstIndex(of: d.ids[0]) ?? 0
                let orig = g.ids[..<first].filter { !d.ids.contains($0) }.count
                let allowed = d.heading ? tops.indices.filter { $0 == others.count || L0.isHeading(others[$0]) } : Array(tops.indices)
                for t in allowed {
                    w.drag = WindowState.Drag(kind: .tasks(ids: d.ids, group: g.listID), target: t, mode: .group)
                    let Lp = layout()
                    let pre = snap(Lp)
                    // Where `endDrag` flies the copy: the slot's top in the layout mid-drag. It must be the gap's.
                    if let gp = Lp.groups.first(where: { $0.listID == g.listID }), let gy = Lp.y(d.ids[0]) {
                        let fly = Lp.slotTops(gp, others: others)[min(t, others.count)] + Lp.rowOffset(d.ids[0])
                        if abs(fly - gy) > 0.5 { record("\(names(d.ids)) to slot \(t)", ["the copy flies to y \(Int(fly)), the gap is at \(Int(gy))"]) }
                    }
                    w.drag?.phase = .fly
                    // The copy flies into the layout at the release: the same as mid-drag.
                    let fly = snap(layout())
                    if fly != pre { record("\(names(d.ids)) to slot \(t)", ["the layout changes at the release"]) }
                    let wrote = a.dropInGroup(d.ids, group: g.listID, target: t, from: orig)
                    w.drag?.phase = .done
                    let post = wrote ? snap(layout()) : base
                    let gapTop = pre.rows[d.ids[0]] ?? 0
                    if d.heading {
                        record("\(names([d.ids[0]])) section to slot \(t)", diff(pre, post, dragged: [d.ids[0]], only: Set(others + [d.ids[0]]), above: gapTop))
                    } else if d.ids.allSatisfy({ post.rows[$0] == nil && post.folded[$0].map(w.collapsed.contains) == true }) {
                        // Right under a collapsed heading: the rows fold into its section and the gap closes after.
                        record("\(names(d.ids)) to slot \(t), folded", diff(pre, post, dragged: d.ids, above: gapTop))
                    } else {
                        record("\(names(d.ids)) to slot \(t)", diff(pre, post, dragged: d.ids))
                    }
                    if !restore(wrote) { break outer }
                }
            }
        } else {
            out.append("dropcheck \(routeName): nothing drags here")
        }
        w.drag = nil
        w.viewDates.invalidate()
        let collapsed = w.collapsed.compactMap { p.task($0)?.title }.sorted()
        out.append("dropcheck \(routeName)\(collapsed.isEmpty ? "" : " collapsed=\(collapsed)"): \(fails == 0 ? "ok" : "FAIL") \(checks) checks, \(fails) failed")
        append(out.joined(separator: "\n"), to: path)
    }

    private static func append(_ s: String, to path: String) {
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}
#endif
