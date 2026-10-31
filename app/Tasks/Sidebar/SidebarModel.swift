import AppKit
import TasksCore

/// The sidebar's geometry, in points (css:97–140, dc:395–396). Row positions are in the scrolled content, whose
/// top is the window's y 50 (`TK.M.sidebarTop`).
enum SB {
    /// `.sbi`: the capsule, x 10–219 in the 230pt sidebar (11 short of its right edge), 30 tall, radius 15 **Rex**.
    /// The sidebar can be resized (v2 feedback 4); the capsule spans it the same way.
    static let rowX: CGFloat = 10
    static let rowRightPad: CGFloat = 11
    static func rowWidth(sidebar width: CGFloat) -> CGFloat { max(0, width - rowX - rowRightPad) }
    static let rowHeight: CGFloat = 30
    static let radius: CGFloat = 15
    /// `.srow` padding-left: the tile, 20×16, sits 10 in.
    static let tileX: CGFloat = 10
    /// `.tl`: 7 after the tile, nudged up 0.5 (`translateY(-0.5px)`), to the capsule's end (its 34pt right padding
    /// stays inside the box, under the mask).
    static let titleX: CGFloat = 37
    static let titleLineTop: CGFloat = 6.5
    /// css:112: `#000 calc(100% − 46px), transparent calc(100% − 30px)`: a 16pt fade ending 30 before the capsule's
    /// right edge, clear of the count.
    static let titleFade: CGFloat = 16
    static let titleFadeEnd: CGFloat = 30
    /// `.ct`: right-aligned 8 from the capsule's right edge, centered on the row.
    static let countRight: CGFloat = 8
    /// `.ri`: the rename field, 7 after the tile, 10 short of the capsule's end, its text centered in the row.
    static let fieldRightPad: CGFloat = 10
    /// `.glabel`: a 32pt slot, the text 12 in and 10 down (11/14 semibold).
    static let labelHeight: CGFloat = 32
    static let labelTextX: CGFloat = 12
    static let labelTextTop: CGFloat = 10
    /// `.gbtn`: 22×22, radius 6, 5 from the label's right, 6 down.
    static let buttonSize: CGFloat = 22
    static let buttonRight: CGFloat = 5
    static let buttonTop: CGFloat = 6
    /// `S.height = y + 16` (dc:700): the content ends 16 below the last row.
    static let bottomPad: CGFloat = 16
    /// The gap above the Archive label (dc:695).
    static let archiveGap: CGFloat = 8
    /// `.sbhead`: the brand header, 34 tall at the top of the content, and Today 6 below it (v2 feedback 12).
    static let headerHeight: CGFloat = 34
    static let headerGap: CGFloat = 6

    /// The + / chevron button, in the label's coordinates.
    static func buttonFrame(rowWidth: CGFloat) -> CGRect {
        CGRect(x: rowWidth - buttonRight - buttonSize, y: buttonTop, width: buttonSize, height: buttonSize)
    }

    /// `monogram()` (dc:418): the first letter or digit, upper-cased, else "·". (TasksCore's is internal.)
    static func monogram(_ name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "·"
    }
}

/// What the sidebar shows, read from the store and the window state (the prototype's `sidebarLayout()`, dc:678–701,
/// and its sidebar view model, dc:1971–2004). `make` is called inside `withObservationTracking`, so everything it
/// reads re-renders the sidebar when it changes.
@MainActor
struct SidebarModel {
    /// A row is a place to go: Today, a view (§22) or a list.
    typealias Key = WindowState.Route

    struct Row: Equatable {
        var key: Key
        var y: CGFloat
        var name: String
        /// nil: Today's or a view's glyph (§22).
        var monogram: String?
        var slot = 0
        /// "" when zero or archived; "⌘3" while ⌘ is held (`hint`).
        var count = ""
        var hint = false
        var archived = false
        var current = false
        var drop = false
        var editing = false
        var dragSource = false
        /// The new list being named (§12 Create): not in the store yet.
        var draft = false
    }

    /// A sidebar list drag, as the layout needs it: the dragged list and the slot it would land in.
    struct Drag: Equatable {
        var id: EntityID
        var target: Int
    }

    var rows: [Row] = []
    var listsLabelY: CGFloat = 0
    /// nil when nothing is archived.
    var archiveLabelY: CGFloat?
    var archiveOpen = false
    var height: CGFloat = 0
    /// Where the first active list sits (`S.listTop`).
    var listTop: CGFloat = 0
    /// The active lists as laid out without a drag, the new-list draft last.
    var active: [EntityID] = []
    var route: WindowState.Route = .today
    var current: Key = .today
    /// ↑ ↓ walk these: Today, the active lists, then the archived ones while the group is open (dc:735).
    var keys: [Key] = []
    var renaming: EntityID?
    var sidebarVisible = true

    func row(_ key: Key) -> Row? { rows.first { $0.key == key } }

    static func make(store: Store, window w: WindowState, drag: Drag?) -> SidebarModel {
        let p = store.projection
        let pitch = TK.M.pitch
        var m = SidebarModel()
        m.route = w.route
        m.current = w.route
        m.sidebarVisible = w.sidebarVisible
        m.archiveOpen = w.archiveOpen
        let rename = w.rename?.kind == .list ? w.rename : nil
        m.renaming = rename?.id
        let over = w.drag?.over
        let hints = w.cmdHints

        let stored = p.activeLists.ids
        var active = stored
        if let r = rename, r.isNewList, !active.contains(r.id) { active.append(r.id) }
        m.active = active
        let archived = p.archivedLists.ids

        // ⌘1–⌘9 on the first nine rows, top to bottom (the draft has none), in place of the counts (§22).
        let numbered = hints ? Array(WindowState.Route.sidebarOrder(p).prefix(9)) : []
        func hint(_ key: Key) -> String? {
            guard hints, let i = numbered.firstIndex(of: key) else { return nil }
            return "⌘\(i + 1)"
        }
        func countText(_ n: Int) -> String { n > 0 ? String(n) : "" }

        func listRow(_ id: EntityID, y: CGFloat, archived: Bool) -> Row {
            let key = Key.list(id)
            let editing = rename?.id == id
            var row = Row(key: key, y: y, name: "")
            row.editing = editing
            row.archived = archived
            row.current = m.current == key
            row.drop = over == .list(id)
            row.dragSource = drag?.id == id
            if let r = rename, r.isNewList, r.id == id {
                row.draft = true
                row.name = r.text
                row.monogram = SB.monogram(r.text)
                row.slot = r.colorSlot
                return row
            }
            let model = p.listModel(id)
            let name = model?.name ?? ""
            row.name = name.isEmpty ? "Untitled" : name
            // While a name is typed, the tile's letter follows it (dc:2000).
            row.monogram = editing ? SB.monogram(rename?.text ?? "") : (model?.monogram ?? "·")
            row.slot = model?.colorSlot ?? ListModel.slot(for: id)
            if let h = hint(key) {
                row.count = h
                row.hint = true
            } else if !archived {
                // Headings aren't counted (§23).
                row.count = countText(p.openTaskCount(in: id))
            }
            return row
        }

        var y = SB.headerHeight + SB.headerGap
        var today = Row(key: .today, y: y, name: "Today")
        today.current = m.current == .today
        today.drop = over == .today
        if let h = hint(.today) {
            today.count = h
            today.hint = true
        } else {
            // Open tasks in Today across the active lists (dc:1910).
            today.count = countText(stored.reduce(0) { $0 + p.todayTasks(in: $1).count })
        }
        m.rows.append(today)
        y += pitch
        // The views you plan from, under Today; the logbook and the Trash after the lists. No counts (§22, dc:2236–2242).
        func viewRow(_ key: Key) {
            var r = Row(key: key, y: y, name: key.viewName ?? "")
            r.current = m.current == key
            r.drop = (key == .completed && over == .completed) || (key == .trash && over == .trash)
            if let h = hint(key) {
                r.count = h
                r.hint = true
            }
            m.rows.append(r)
            y += pitch
        }
        viewRow(.upcoming)
        viewRow(.undated)
        m.listsLabelY = y
        y += pitch
        m.listTop = y

        // While a list is dragged the others part around the slot it would land in (dc:686–690).
        let others = drag.map { d in active.filter { $0 != d.id } } ?? active
        let target = drag.map { min(max($0.target, 0), others.count) } ?? -1
        for (i, id) in others.enumerated() {
            let slot = CGFloat(i + (drag != nil && i >= target ? 1 : 0))
            m.rows.append(listRow(id, y: y + slot * pitch, archived: false))
        }
        if let d = drag, active.contains(d.id) {
            m.rows.append(listRow(d.id, y: y + CGFloat(target) * pitch, archived: false))
        }
        y += CGFloat(active.count) * pitch
        y += SB.archiveGap
        viewRow(.completed)
        viewRow(.trash)

        if !archived.isEmpty {
            y += SB.archiveGap
            m.archiveLabelY = y
            y += pitch
            if w.archiveOpen {
                for id in archived {
                    m.rows.append(listRow(id, y: y, archived: true))
                    y += pitch
                }
            }
        }
        m.height = y + SB.bottomPad
        m.keys = WindowState.Route.sidebarOrder(p) + (w.archiveOpen ? archived.map(Key.list) : [])
        return m
    }
}
