import AppKit
import QuartzCore
import SwiftUI
import TasksCore

/// The task list (§5–§9, §13, §14): an AppKit view so it can select on mouse-down, track hover once for the whole
/// list, drag its own rows and rename in place (§18). It renders `TaskLayout` like the prototype renders its
/// `layout()` (dc:1835–1889): one view per visible task, positioned by y, moving on the `layout` spring, entering
/// with a 180 ms fade and leaving with a 150 ms one. A list switch rebinds the views already built and never animates.
///
/// It reads the store and the window state inside `withObservationTracking`, so any change it depends on schedules
/// one render on the next run loop turn.
final class TaskListView: NSView {
    let store: Store
    unowned let state: WindowState
    var palette: TK.Palette = .dark {
        didSet { if palette != oldValue { paletteChanged = true; setNeedsRender() } }
    }

    private let scroll = NSScrollView()
    let doc = TaskListDocument()
    private(set) var currentLayout: TaskLayout?
    private var prevKey: String?
    private var prevLayout: TaskLayout?
    private var prevLabels: [EntityID: CGFloat] = [:]
    private var prevCompletedY: CGFloat?
    private var rows: [EntityID: TaskRowView] = [:]
    private var pool: [TaskRowView] = []
    private var leaving: [EntityID: (view: TaskRowView, until: CFTimeInterval)] = [:]
    private var keepUntil: [EntityID: CFTimeInterval] = [:]
    private var labels: [EntityID: GroupLabelView] = [:]
    private var labelsLeaving: [EntityID: (view: GroupLabelView, until: CFTimeInterval)] = [:]
    /// Today's Completed label's fold state as last drawn (to raise it over rows that fold and unfold).
    private var lastDoneCollapsed: Bool?
    private let completedRow = CompletedRowView()
    private var completedWidth: CGFloat = 0
    private let empty = EmptyStateView()
    private let banner = BannerView()
    private var renameField: InlineField?
    private var renamingID: EntityID?
    // Headings, the title block and the list pane's notes (§23).
    private var heads: [EntityID: HeadingRowView] = [:]
    private var headsLeaving: [EntityID: (view: HeadingRowView, until: CFTimeInterval)] = [:]
    let titleView = ListTitleView()
    private var titleField: InlineField?
    private var titleFieldID: EntityID?
    /// The notes editors in the list pane: the list's (in the title block) and each heading's with notes.
    final class PaneEditor {
        let view: NotesTextView
        let editor: NotesField.Coordinator
        var measured: (text: String, width: CGFloat, height: CGFloat)?
        /// Shown under its heading in the last render (for the fold and unfold).
        var shown = false
        init(view: NotesTextView, editor: NotesField.Coordinator) {
            self.view = view
            self.editor = editor
        }
    }
    private(set) var paneEditors: [NotesHost.Target: PaneEditor] = [:]

    private var renderScheduled = false
    private var paletteChanged = true
    private var firstRender = true
    private var lastWidth: CGFloat = 0
    private var pendingScroll: EntityID?
    private var cleanupTimer: Timer?

    // Pointer
    private enum Target: Equatable {
        case row(EntityID, TaskRowView.Part)
        /// A heading's row: its + and chevron are parts of their own, asked first (§23).
        case head(EntityID, HeadingRowView.Part)
        /// A group label: Today's lists, the views' days, and Today's Completed with its chevron (v2 feedback 15).
        case label(EntityID, part: GroupLabelView.Part)
        case completed
        case banner
        case empty
    }
    private var hover: Target?
    private var press: (target: Target, point: CGPoint, event: NSEvent)?
    private var pendingCollapse: EntityID?
    private var drag: DragSession?
    /// While the hand-off renders: the row the dragged copy has just landed on (`land(on:_:)`).
    private var landing: EntityID?
    private var autoscrollTimer: Timer?

    init(store: Store, window: WindowState) {
        self.store = store
        self.state = window
        super.init(frame: .zero)
        wantsLayer = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.drawsBackground = false
        scroll.documentView = doc
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)
        doc.owner = self
        doc.addSubview(completedRow)
        doc.addSubview(empty)
        doc.addSubview(banner)
        doc.addSubview(titleView)
        titleView.onDoubleClickTitle = { [weak self] in self?.actions.startTitleRename() }
        titleView.onHover = { [weak self] _ in self?.updateTitlePlaceholder(animated: true) }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
    }

    required init?(coder: NSCoder) { fatalError() }

    var actions: WindowActions { WindowActions(store: store, window: state) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if state.focus != .list { state.focus = .list }
        return true
    }

    func takeKeys() {
        guard let w = window, w.firstResponder !== self else { return }
        w.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            render(animated: false)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setNeedsRender()
            // Keys work from the start, as in Rex.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.focus == .list, self.window?.firstResponder is NSWindow else { return }
                self.takeKeys()
            }
        }
    }

    @objc private func scrolled() {
        updateTitleScrolled()
        render(animated: false, scrolling: true)
        updateHoverFromMouse()
        if let d = drag { updateDrag(windowPoint: d.lastPoint) }
    }

    // MARK: - Render

    func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    private func render(animated: Bool = true, scrolling: Bool = false) {
        withObservationTracking {
            renderNow(animated: animated, scrolling: scrolling)
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.setNeedsRender() } }
        }
    }

    #if DEBUG
    /// `-debugRenderTimes <file>`: each render's duration (ms) and row count, for the §9 budgets.
    private static let renderLog: FileHandle? = {
        guard let path = UserDefaults.standard.string(forKey: "debugRenderTimes") else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()
    #endif

    #if DEBUG
    static var phases: [Double] = []
    static var phaseT = 0.0
    static func phase() { let t = CACurrentMediaTime(); if phaseT > 0 { phases.append(t - phaseT) }; phaseT = t }
    #else
    static func phase() {}
    #endif

    private func renderNow(animated allowAnimation: Bool, scrolling: Bool) {
        #if DEBUG
        Self.phaseT = 0
        #endif
        Self.phase()
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer {
            if let log = Self.renderLog {
                log.write(String(format: "%.3f\t%d\t%@\t%@\n", (CACurrentMediaTime() - t0) * 1000, currentLayout?.order.count ?? 0, scrolling ? "scroll" : "change", Self.phases.map { String(format: "%.2f", $0 * 1000) }.joined(separator: " ")).data(using: .utf8)!)
                Self.phases = []
            }
        }
        #endif
        guard window != nil else { return }
        let p = store.projection
        // The list pane's notes are measured before the layout, which leaves room for them (§23).
        syncPaneEditors()
        let L = TaskLayout.make(store: store, window: state)
        Self.phase()
        let now = CACurrentMediaTime()
        let sameView = prevKey == L.key
        let animate = allowAnimation && sameView && !firstRender && !paletteChanged && !TK.CA.reduce
        if !sameView {
            leaving.values.forEach { recycle($0.view) }; leaving = [:]
            labelsLeaving.values.forEach { $0.view.removeFromSuperview() }; labelsLeaving = [:]
            headsLeaving.values.forEach { $0.view.removeFromSuperview() }; headsLeaving = [:]
            for (_, v) in heads { v.removeFromSuperview() }
            heads = [:]
        }
        let width = scroll.contentView.bounds.width
        let rowW = max(0, width - 2 * TK.M.rowInset)
        let visibleH = scroll.contentView.bounds.height
        let contentH = max(L.height, visibleH)
        if doc.frame.size != CGSize(width: width, height: contentH) {
            doc.frame = CGRect(x: 0, y: 0, width: width, height: contentH)
        }
        let vis = scroll.contentView.bounds.insetBy(dx: 0, dy: -max(200, visibleH / 2))
        let inToday = state.route == .today
        let today = p.day.date
        let detailOpen = state.detailOpen
        // Alone in the window the pane shows no focus: selected rows keep the focused fill (v2 feedback 3).
        let paneFocused = state.focus == .list || !detailOpen
        let selection = state.selection
        let rename = state.rename.flatMap { $0.kind == .task || $0.kind == .heading ? $0 : nil }
        let picker = state.overlays.picker
        let dragIDs: Set<EntityID> = {
            if let d = state.drag, d.phase != .done, case .tasks(let ids, _) = d.kind { return Set(ids) }
            return []
        }()
        let draft = state.draft

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Rows that left the view since the last render: they keep their place (or slide into the Completed row
        // when they were just completed in a list) and fade out while the rest close up (dc:1795–1808).
        if animate {
            // Only rows near the visible rect can be seen leaving.
            let prev = prevLayout!
            let near = vis.insetBy(dx: 0, dy: -TK.M.pitch)
            var i = prev.firstIndex(atOrBelow: near.minY)
            while i < prev.order.count, prev.yList[i] <= near.maxY {
                let id = prev.order[i]
                let oldY = prev.yList[i]
                i += 1
                guard !L.contains(id), leaving[id] == nil else { continue }
                guard let v = rows.removeValue(forKey: id) else { continue }
                var to = oldY
                if let cy = L.completedY, let t = p.task(id), !t.deleted, t.completedAt != nil, t.list == state.route.listID {
                    to = cy
                }
                // Folding: up under its heading's row (or Today's Completed label, or a list's Completed row), on
                // `layout`, as it fades (§23 Collapsing, v2 feedback 15).
                if let h = L.folded[id], let hy = L.foldY(h) { to = hy }
                leaving[id] = (v, now + TK.Timer.motionWindow)
                v.setHover(row: false, part: nil)
                move(v, toY: to, animate: true)
                v.layer?.animate("opacity", to: 0, TK.CA.fadeOutT)
            }
        }
        for (id, l) in leaving where now >= l.until || L.contains(id) {
            leaving[id] = nil
            recycle(l.view)
        }

        Self.phase()
        // Which rows need a view: the ones in (or near) the visible rect, and the ones still moving.
        var needed: [EntityID] = []
        var i = L.firstIndex(atOrBelow: vis.minY - TK.M.pitch)
        while i < L.order.count, L.yList[i] <= vis.maxY {
            needed.append(L.order[i])
            i += 1
        }
        var neededSet = Set(needed)
        for (id, until) in keepUntil {
            if now < until, L.contains(id), rows[id] != nil { if neededSet.insert(id).inserted { needed.append(id) } } else { keepUntil[id] = nil }
        }
        if let sel = rename?.id, L.contains(sel), neededSet.insert(sel).inserted { needed.append(sel) }
        for (id, v) in rows where !neededSet.contains(id) {
            rows[id] = nil
            recycle(v)
        }

        // Selected rows join into one block when adjacent (css:182–186).
        let selectedYs: Set<CGFloat> = Set(selection.compactMap { id in dragIDs.contains(id) ? nil : L.y(id) })

        var headNeeded: [EntityID] = []
        for id in needed {
            guard let y = L.y(id) else { continue }
            if L.isHeading(id) { headNeeded.append(id); continue }
            var isNew = false
            let v: TaskRowView
            if let existing = rows[id] {
                v = existing
            } else {
                v = dequeue()
                rows[id] = v
                isNew = true
            }
            let isDraft = id == draft?.id
            var m: RowModel
            // In Upcoming a day group's own date isn't repeated on its rows (§22, dc:1921).
            let groupDay = L.groupDay(id)
            if isDraft, let draft {
                let untitled = draft.title.isEmpty
                m = RowModel(id: id, title: draft.title, untitled: untitled, done: false, draft: true)
                if let when = draft.when, !(inToday && when <= today), when != groupDay {
                    m.chips.append(.init(field: .when, content: .init(text: DateLabel.whenChip(when, today: today), glyph: .calendar)))
                }
            } else if let t = p.taskModel(id) {
                m = RowModel(id: id, title: t.title, untitled: t.title.isEmpty, done: t.isDone, draft: false)
                m.notes = t.notesSummary
                if !t.isDone {
                    if let when = t.when, !(inToday && when <= today), when != groupDay {
                        m.chips.append(.init(field: .when, content: .init(text: DateLabel.whenChip(when, today: today), glyph: .calendar)))
                    }
                    if let dl = t.deadline {
                        let c = dl == groupDay ? (text: "Due", tone: DateLabel.Tone.neutral) : DateLabel.deadlineChip(dl, today: today)
                        let tone: ChipLayer.Tone = c.tone == .late ? .late : c.tone == .due ? .due : .neutral
                        m.chips.append(.init(field: .deadline, content: .init(text: c.text, glyph: .flag, tone: tone)))
                    }
                }
                if inToday && L.isDone(id) { m.whereText = actions.listName(t.list) }
                if state.route.isView, let w = viewWhere(L, id: id, list: t.list) { m.whereText = w.name; m.whereSuffix = w.suffix }
                m.trashed = t.deleted
            } else {
                continue
            }
            let sel = selection.contains(id) && !dragIDs.contains(id)
            m.selected = sel
            m.joinTop = sel && selectedYs.contains(y - TK.M.pitch)
            m.joinBottom = sel && selectedYs.contains(y + TK.M.pitch)
            m.paneFocused = paneFocused
            m.renaming = rename?.id == id
            m.dragSource = dragIDs.contains(id)
            m.openAllowed = !m.renaming && !m.done && !detailOpen
            if let picker, picker.ids.contains(id) { m.pickerField = picker.field }
            if isNew {
                let a = actions
                v.onCheck = { a.toggleComplete([id]) }
                v.onOpen = { a.select([id]); a.openDetail() }
            }
            if v.model != m || paletteChanged || isNew || v.frame.width != rowW {
                v.configure(m, palette: palette, width: rowW, animated: !isNew && animate)
            }
            // Position: new views start where the task was (and spring to its new place) or fade in; others spring.
            if isNew {
                if animate, let h = prevLayout?.folded[id], let hy = L.foldY(h) ?? prevLayout?.foldY(h) {
                    // Expanding: from under the heading's row to its place on `layout`, with the rows below on the same
                    // curve, fading in (ease-in, so faint while it still overlaps the heading). Never faded in where it
                    // ends up while its neighbours move (§23 "Bugs the prototype had").
                    place(v, y: hy, width: rowW)
                    move(v, toY: y, animate: true)
                    v.layer?.removeAnimation(forKey: "opacity")
                    v.layer?.add(TK.CA.basic("opacity", TK.CA.unfoldT, from: 0, to: 1), forKey: "enter")
                    keepUntil[id] = now + 0.45
                } else if animate, let oldY = prevLayout?.y(id), oldY != y {
                    place(v, y: oldY, width: rowW)
                    move(v, toY: y, animate: true)
                } else {
                    place(v, y: y, width: rowW)
                    if animate && prevLayout?.contains(id) != true {
                        v.layer?.removeAnimation(forKey: "opacity")
                        v.layer?.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: 1), forKey: "enter")
                    }
                }
            } else if v.frame.minY != y {
                move(v, toY: y, animate: animate)
                if animate { keepUntil[id] = now + 0.45 }
            } else if v.frame.width != rowW {
                place(v, y: y, width: rowW)
            }
            if id == landing, let layer = v.layer {
                // The copy settled on this row: it shows at once, exactly where the copy is (any move toward the gap
                // that was still running unseen is cut), under the fading copy (v2 feedback 5).
                for key in layer.animationKeys() ?? [] where key == "opacity" || key.hasPrefix("move-") {
                    layer.removeAnimation(forKey: key)
                }
                layer.opacity = 1
            }
        }

        renderHeadings(L, needed: headNeeded, rowW: rowW, animate: animate, now: now, selection: selection,
                       paneFocused: paneFocused, rename: rename, dragIDs: dragIDs)
        renderTitle(L, width: width)
        renderPaneEditors(L, width: width, animate: animate, now: now, dragIDs: dragIDs)
        Self.phase()
        renderLabels(L, rowW: rowW, animate: animate, now: now)
        renderExtras(L, width: width, rowW: rowW, contentH: contentH, animate: animate)
        // In this transaction, so the field and the title it replaces swap in one frame. Added after the commit, the
        // field drew a frame late: the title was already hidden, and the row showed no title for a frame (v2 feedback 5).
        updateRenameField(rename, layout: L)

        CATransaction.commit()
        Self.phase()

        #if DEBUG
        if !sameView, !L.order.isEmpty { DebugTiming.rowAppeared() }
        #endif
        currentLayout = L
        prevKey = L.key
        prevLayout = L
        prevLabels = L.labels
        prevCompletedY = L.completedY
        paletteChanged = false
        firstRender = false
        if !leaving.isEmpty || !labelsLeaving.isEmpty || !keepUntil.isEmpty || !headsLeaving.isEmpty { scheduleCleanup() }
        if let id = pendingScroll, L.contains(id) {
            pendingScroll = nil
            ensureVisible(id, in: L)
        }
        Self.phase()
        if !scrolling { updateHoverFromMouse() }
        Self.phase()
        updateAccessibility(L)
        Self.phase()
    }

    private func dequeue() -> TaskRowView {
        let v = pool.popLast() ?? TaskRowView()
        v.layer?.removeAllAnimations()
        v.layer?.setInstant { v.layer?.opacity = 1 }
        v.isHidden = false
        if v.superview !== doc { doc.addSubview(v, positioned: .below, relativeTo: completedRow) }
        return v
    }

    private func recycle(_ v: TaskRowView) {
        v.setHover(row: false, part: nil)
        v.setPressed(nil)
        v.isHidden = true
        v.layer?.removeAllAnimations()
        pool.append(v)
    }

    private func place(_ v: NSView, y: CGFloat, width: CGFloat, x: CGFloat = TK.M.rowInset, height: CGFloat = TK.M.row) {
        v.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    /// Moves a view to `y`, on the `layout` spring when animating: the frame jumps and an additive translation runs
    /// from the old place to the new, so interrupted moves compose.
    private func move(_ v: NSView, toY y: CGFloat, animate: Bool) {
        let from = v.frame.minY
        guard from != y else { return }
        v.frame.origin.y = y
        guard animate, let layer = v.layer else { return }
        let a = TK.CA.spring("transform.translation.y", TK.CA.layout, from: from - y, to: 0)
        a.isAdditive = true
        layer.add(a, forKey: "move-\(CACurrentMediaTime())")
    }

    private func scheduleCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: TK.Timer.motionWindow + 0.02, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(animated: true) }
        }
    }

    // MARK: Labels, the Completed row, the empty state and the banner

    private func renderLabels(_ L: TaskLayout, rowW: CGFloat, animate: Bool, now: CFTimeInterval) {
        let p = store.projection
        if animate {
            for (key, y) in prevLabels where L.labels[key] == nil && labelsLeaving[key] == nil {
                guard let v = labels.removeValue(forKey: key) else { continue }
                labelsLeaving[key] = (v, now + TK.Timer.motionWindow)
                _ = y
                v.layer?.animate("opacity", to: 0, TK.CA.fadeOutT)
            }
        }
        for (key, l) in labelsLeaving where now >= l.until || L.labels[key] != nil {
            labelsLeaving[key] = nil
            l.view.removeFromSuperview()
        }
        for (key, v) in labels where L.labels[key] == nil {
            labels[key] = nil
            v.removeFromSuperview()
        }
        let dropDay: EntityID? = {
            guard let d = state.drag, d.mode == .days, d.phase == .drag, !d.sidebar, let day = d.toDay else { return nil }
            return "d:" + day.string
        }()
        for key in L.labelOrder {
            guard let y = L.labels[key] else { continue }
            let isDone = key == TaskLayout.doneGroup
            let info = L.labelInfo[key]
            let name = info.map { $0.list.map(actions.listName) ?? $0.name } ?? (isDone ? "Completed" : actions.listName(key))
            var isNew = false
            let v: GroupLabelView
            if let existing = labels[key] { v = existing } else {
                v = GroupLabelView()
                v.layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
                doc.addSubview(v, positioned: .below, relativeTo: completedRow)
                labels[key] = v
                isNew = true
            }
            _ = p
            // Today's Completed folds (v2 feedback 15): its chevron, its count while collapsed, and its fill when it's
            // selected (Space folds it).
            let folds = isDone && state.route == .today
            v.configure(key: key, name: name, plus: info?.plus ?? !isDone, palette: palette, width: rowW, sub: info?.sub,
                        quiet: info?.quiet ?? false, chevron: folds, collapsed: folds && state.todayDoneCollapsed,
                        count: L.doneCount, selected: folds && state.selection.contains(key),
                        paneFocused: state.focus == .list || !state.detailOpen, animated: animate && !isNew)
            if folds, !isNew, v.collapsed != lastDoneCollapsed {
                // Rows folding into it and unfolding from it pass under it: it goes above the rows.
                doc.addSubview(v, positioned: .below, relativeTo: completedRow)
            }
            if folds { lastDoneCollapsed = v.collapsed }
            v.setDrop(key == dropDay, animated: animate)
            if isNew {
                if animate, let old = prevLabels[key], old != y {
                    place(v, y: old, width: rowW, height: TK.M.pitch)
                    move(v, toY: y, animate: true)
                } else {
                    place(v, y: y, width: rowW, height: TK.M.pitch)
                    if animate && prevLabels[key] == nil {
                        v.layer?.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: 1), forKey: "enter")
                    }
                }
            } else {
                if v.frame.minY != y { move(v, toY: y, animate: animate) }
                if v.frame.width != rowW { place(v, y: y, width: rowW, height: TK.M.pitch) }
            }
        }
    }

    private func renderExtras(_ L: TaskLayout, width: CGFloat, rowW: CGFloat, contentH: CGFloat, animate: Bool) {
        let p = store.projection
        // The Completed row (a list): fades in when the first task is completed, disappears at once with the last.
        if let cy = L.completedY, case .list(let listID) = state.route {
            let open = state.completedOpen.contains(listID)
            let wasHidden = completedRow.isHidden
            completedRow.isHidden = false
            completedWidth = completedRow.configure(count: L.doneCount, open: open, palette: palette, animated: animate && !wasHidden)
            if wasHidden || !animate {
                place(completedRow, y: cy, width: completedWidth)
                if animate && prevCompletedY == nil {
                    completedRow.layer?.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: 1), forKey: "enter")
                }
            } else {
                completedRow.frame.size.width = completedWidth
                move(completedRow, toY: cy, animate: true)
            }
        } else {
            completedRow.isHidden = true
        }
        // The empty states: never clickable; 34% down (40pt for All done).
        if let kind = L.empty, !(kind == .list && state.route.listID.flatMap { p.list($0)?.archivedAt } != nil) {
            empty.isHidden = false
            empty.configure(kind, palette: palette, width: width)
            let visibleH = scroll.contentView.bounds.height
            let top: CGFloat = L.emptyTop ?? (kind == .allDone ? 40 : (visibleH * 0.34).rounded())
            empty.frame.origin = CGPoint(x: 0, y: top)
        } else {
            empty.isHidden = true
        }
        // An archived list's banner, 6 from the header, 10 in from the sides.
        if let id = state.route.listID, let l = p.list(id), let at = l.archivedAt {
            banner.isHidden = false
            let date = CalendarDate(Date(timeIntervalSince1970: TimeInterval(at) / 1000))
            let h = banner.configure(archivedOn: DateLabel.monthDay(date), palette: palette, width: rowW)
            banner.frame = CGRect(x: TK.M.rowInset, y: 6, width: rowW, height: h)
        } else {
            banner.isHidden = true
        }
    }

    /// The list's name after the title in Upcoming, Completed and Trash; in a month group, the day too (dc:2321–2327),
    /// kept whole when the name is cut (v2 feedback 16).
    private func viewWhere(_ L: TaskLayout, id: EntityID, list: EntityID) -> (name: String, suffix: String?)? {
        let name = actions.listName(list)
        switch state.route {
        case .upcoming: return (name, nil)
        case .completed, .trash:
            guard L.groupKind(id) == .month, let t = store.projection.task(id) else { return (name, nil) }
            let at = state.route == .trash ? ViewItems.deletedAt(t) : t.completedAt
            guard let at else { return (name, nil) }
            return (name, " · " + DateLabel.monthDay(CalendarDate(Date(timeIntervalSince1970: TimeInterval(at) / 1000))))
        default: return nil
        }
    }

    // MARK: - Headings, the title block and the list pane's notes (§23)

    /// Heading rows: one view per heading on screen, moving with the rows; a deleted one fades where it was.
    private func renderHeadings(_ L: TaskLayout, needed: [EntityID], rowW: CGFloat, animate: Bool, now: CFTimeInterval,
                                selection: Set<EntityID>, paneFocused: Bool, rename: WindowState.Rename?,
                                dragIDs: Set<EntityID>) {
        let p = store.projection
        let neededSet = Set(needed)
        for (id, v) in heads where !neededSet.contains(id) {
            heads[id] = nil
            if animate, !L.contains(id), prevLayout?.contains(id) == true, headsLeaving[id] == nil {
                headsLeaving[id] = (v, now + TK.Timer.motionWindow)
                v.setHover(row: false, part: nil)
                v.layer?.animate("opacity", to: 0, TK.CA.fadeOutT)
            } else {
                v.removeFromSuperview()
            }
        }
        for (id, l) in headsLeaving where now >= l.until || L.contains(id) {
            headsLeaving[id] = nil
            l.view.removeFromSuperview()
        }
        guard !needed.isEmpty else { return }
        // A collapsed heading's count: its open tasks, folded under it.
        var folded: [EntityID: Int] = [:]
        for (_, h) in L.folded { folded[h, default: 0] += 1 }
        for id in needed {
            guard let y = L.y(id) else { continue }
            var isNew = false
            let v: HeadingRowView
            if let existing = heads[id] { v = existing } else {
                v = HeadingRowView()
                v.layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
                // Above the task rows: rows folding and unfolding pass under it.
                doc.addSubview(v)
                heads[id] = v
                isNew = true
            }
            let renaming = rename?.id == id
            let title = renaming && rename?.newHeading != nil ? "" : (p.taskModel(id)?.title ?? "")
            let m = HeadingModel(id: id, title: title, collapsed: state.collapsed.contains(id), count: folded[id] ?? 0,
                                 selected: selection.contains(id) && !dragIDs.contains(id), paneFocused: paneFocused,
                                 renaming: renaming, dragSource: dragIDs.contains(id))
            if v.model != m || paletteChanged || isNew || v.frame.width != rowW {
                v.configure(m, palette: palette, width: rowW, animated: !isNew && animate)
            }
            if isNew {
                if animate, let oldY = prevLayout?.y(id), oldY != y {
                    place(v, y: oldY, width: rowW)
                    move(v, toY: y, animate: true)
                } else {
                    place(v, y: y, width: rowW)
                    if animate && prevLayout?.contains(id) != true {
                        v.layer?.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: 1), forKey: "enter")
                    }
                }
            } else if v.frame.minY != y {
                move(v, toY: y, animate: animate)
            } else if v.frame.width != rowW {
                place(v, y: y, width: rowW)
            }
            if id == landing, let layer = v.layer {
                for key in layer.animationKeys() ?? [] where key == "opacity" || key.hasPrefix("move-") { layer.removeAnimation(forKey: key) }
                layer.opacity = 1
            }
        }
    }

    /// The width of the list pane's notes: from the checkbox's edge to 20 from the right.
    private var paneNotesWidth: CGFloat {
        max(40, scroll.contentView.bounds.width - 2 * (TK.M.rowInset + TK.M.rowPadLeft))
    }

    /// Makes (or updates) the list's and its headings' notes editors and measures them, before the layout: a heading
    /// shows notes when it has some or while they're being edited.
    private func syncPaneEditors() {
        let p = store.projection
        var keep: Set<NotesHost.Target> = []
        let width = paneNotesWidth
        if case .list(let lid) = state.route, let l = p.listModel(lid) {
            let t = NotesHost.Target.list(lid)
            keep.insert(t)
            let e = paneEditor(t, notes: l.notes, parent: titleView)
            state.noteHeights[TaskLayout.listNotesKey(lid)] = measure(e, width: width)
            for h in p.headings(in: lid).ids {
                guard let m = p.taskModel(h) else { continue }
                let target = NotesHost.Target.task(h)
                guard !m.notes.isEmpty || state.paneNotes == target || paneEditors[target]?.editor.session != nil else { continue }
                keep.insert(target)
                let e = paneEditor(target, notes: m.notes, parent: doc)
                state.noteHeights[h] = measure(e, width: width)
            }
        }
        for (t, e) in paneEditors where !keep.contains(t) && e.editor.session == nil {
            e.view.removeFromSuperview()
            paneEditors[t] = nil
        }
    }

    private func paneEditor(_ target: NotesHost.Target, notes: String, parent: NSView) -> PaneEditor {
        let host = paneHost(target, notes: notes)
        if let e = paneEditors[target] {
            e.editor.host = host
            e.editor.apply(force: false)
            return e
        }
        let c = NotesField.Coordinator()
        let v = NotesField.makeEditor(c, host: host)
        v.setAccessibilityLabel(target == state.route.listID.map { .list($0) } ? "List notes" : "Heading notes")
        parent.addSubview(v)
        let e = PaneEditor(view: v, editor: c)
        paneEditors[target] = e
        return e
    }

    private func paneHost(_ target: NotesHost.Target, notes: String) -> NotesHost {
        let a = actions
        return NotesHost(store: store, window: state, target: target, notes: notes, inert: state.route == .trash,
                         palette: palette, inDetail: false,
                         onLayoutChange: { [weak self] in self?.paneNotesChanged(target) },
                         backToTitle: {
                             switch target {
                             case .list: a.startTitleRename()
                             case .task(let h): a.startHeadingRename(h)
                             }
                         })
    }

    private func measure(_ e: PaneEditor, width: CGFloat) -> CGFloat {
        let text = e.view.string
        if let m = e.measured, m.text == text, m.width == width { return m.height }
        let h = e.view.fittingHeight(width: width)
        e.measured = (text, width, h)
        return h
    }

    /// While typing: a new height lays the rows out again.
    private func paneNotesChanged(_ target: NotesHost.Target) {
        guard let e = paneEditors[target] else { return }
        let key: EntityID = switch target {
        case .list(let id): TaskLayout.listNotesKey(id)
        case .task(let id): id
        }
        let h = measure(e, width: paneNotesWidth)
        if state.noteHeights[key] != h {
            state.noteHeights[key] = h
            setNeedsRender()
        }
        updateTitlePlaceholder(animated: true)
    }

    /// Add Notes, Edit Notes, Tab from a rename, or a click: the caret in the list's or a heading's notes.
    func startPaneNotes(_ target: NotesHost.Target) {
        if case .task = target { state.paneNotes = target }
        render(animated: true)
        guard let e = paneEditors[target] else {
            if state.paneNotes == target { state.paneNotes = nil }
            return
        }
        e.editor.startEditing()
        if case .task(let h) = target { ensureVisible(h, in: currentLayout ?? TaskLayout.make(store: store, window: state)) }
    }

    /// The editors' places: the list's in the title block, each heading's 2 below its row's shape, moving with it.
    /// Collapsing folds a heading's notes up under its row as they fade; expanding unfolds them from there.
    private func renderPaneEditors(_ L: TaskLayout, width: CGFloat, animate: Bool, now: CFTimeInterval, dragIDs: Set<EntityID>) {
        let w = paneNotesWidth
        for (target, e) in paneEditors {
            switch target {
            case .list:
                let h = max(19, state.noteHeights[TaskLayout.listNotesKey(state.route.listID ?? "")] ?? 19)
                let f = CGRect(x: TK.M.rowInset + TK.M.rowPadLeft, y: ListTitleView.notesTop, width: w, height: h)
                if e.view.frame != f { e.view.frame = f }
                e.view.isHidden = false
            case .task(let hid):
                let nh = L.noteH[hid] ?? 0
                let show = nh > 0 && L.y(hid) != nil && !dragIDs.contains(hid)
                let layer = e.view.layer
                if show, let hy = L.y(hid) {
                    e.view.inert = state.route == .trash
                    let y = hy + TK.M.pitch
                    let f = CGRect(x: TK.M.rowInset + TK.M.rowPadLeft, y: y, width: w, height: max(19, nh - 6))
                    if !e.shown {
                        // Unfolding (or first shown): from under the heading's row, fading in.
                        e.view.isHidden = false
                        e.view.frame = f
                        if animate {
                            let a = TK.CA.spring("transform.translation.y", TK.CA.layout, from: hy - y, to: 0)
                            a.isAdditive = true
                            layer?.add(a, forKey: "move-\(CACurrentMediaTime())")
                            layer?.removeAnimation(forKey: "opacity")
                            layer?.setInstant { layer?.opacity = 1 }
                            layer?.add(TK.CA.basic("opacity", TK.CA.unfoldT, from: 0, to: 1), forKey: "enter")
                        } else {
                            layer?.setInstant { layer?.opacity = 1 }
                        }
                    } else {
                        if e.view.frame.size != f.size { e.view.frame.size = f.size }
                        move(e.view, toY: y, animate: animate)
                    }
                    e.shown = true
                } else if e.shown {
                    e.shown = false
                    // Folding (or dragged): it passes over the heading's row on its way out, and never takes a press.
                    e.view.inert = true
                    if animate, let hy = L.y(hid), !dragIDs.contains(hid) {
                        // Folding: up under the heading's row as it fades out.
                        move(e.view, toY: hy, animate: true)
                        layer?.animate("opacity", to: 0, TK.CA.fadeOutT)
                    } else {
                        e.view.isHidden = true
                    }
                } else if layer?.opacity == 0 || !animate {
                    e.view.isHidden = true
                }
            }
        }
    }

    /// The title block: the large title, and a list's notes under it (their editor is its subview).
    private func renderTitle(_ L: TaskLayout, width: CGFloat) {
        let p = store.projection
        let today = p.day.date
        var c: ListTitleView.Content
        let renaming = state.rename?.kind == .title
        switch state.route {
        case .list(let id):
            let m = p.listModel(id)
            let name = m?.name ?? ""
            c = .init(mark: .tile(monogram: m?.monogram ?? "·", slot: m?.colorSlot ?? ListModel.slot(for: id)),
                      title: name.isEmpty ? "New List" : name, sub: m?.isArchived == true ? "Archived" : nil, renaming: renaming)
        case .today:
            c = .init(mark: .view(.today), title: "Today", sub: DateLabel.long(today, today: today))
        default:
            c = .init(mark: .view(state.route), title: state.route.viewName ?? "", sub: nil)
        }
        let f = CGRect(x: 0, y: L.headY, width: width, height: max(L.titleHeight, 46))
        if titleView.frame != f { titleView.frame = f }
        titleView.configure(c, palette: palette, width: width)
        updateTitleField(renaming ? state.rename : nil)
        updateTitlePlaceholder(animated: false)
        updateTitleScrolled()
    }

    /// "Notes" over an empty list's notes: while the pointer is over the title block, while it's renamed, or with the
    /// caret in them.
    private func updateTitlePlaceholder(animated: Bool) {
        guard case .list(let lid) = state.route, let e = paneEditors[.list(lid)] else {
            titleView.showPlaceholder(false, animated: false)
            return
        }
        let empty = e.view.string.isEmpty
        let on = empty && (titleView.hovered || state.rename?.kind == .title || e.editor.session != nil)
        titleView.showPlaceholder(on, animated: animated)
    }

    /// The band's tile and title show once the large title has scrolled 24pt (§23 On scroll).
    private func updateTitleScrolled() {
        let s = scroll.contentView.bounds.minY >= 24
        if state.titleScrolled != s { state.titleScrolled = s }
    }

    /// The list's title renames in place: 20/26, 30 tall, radius 6, `fill-control`, a 1.5pt `accent` ring (css:443).
    private func updateTitleField(_ rename: WindowState.Rename?) {
        guard let rename else {
            if let f = titleField {
                titleField = nil
                titleFieldID = nil
                let wasEditing = f.isEditing
                f.onEnd = nil
                f.removeFromSuperview()
                if wasEditing { takeKeys() }
            }
            return
        }
        let f: InlineField
        if let existing = titleField, titleFieldID == rename.id {
            f = existing
        } else {
            titleField?.onEnd = nil
            titleField?.removeFromSuperview()
            f = InlineField(frame: .zero)
            f.font = ListTitleView.font
            f.placeholderString = "New List"
            f.stringValue = rename.text
            f.wantsLayer = true
            f.layer?.cornerRadius = 6
            f.layer?.borderWidth = 1.5
            let a = actions
            f.onChange = { a.setRenameText($0) }
            f.onKey = { [weak self] key in
                switch key {
                case .returnKey, .commandReturn, .backtab:
                    a.commitRename()
                    self?.takeKeys()
                case .tab:
                    // Tab goes on to the list's notes.
                    a.commitRename()
                    a.editListNotes()
                case .escape:
                    a.cancelRename()
                    self?.takeKeys()
                }
                return true
            }
            f.onEnd = { _ in if a.window.rename?.kind == .title { a.commitRename() } }
            titleView.addSubview(f)
            titleField = f
            titleFieldID = rename.id
            DispatchQueue.main.async { f.focus(.all) }
        }
        f.textColor = palette.ink
        f.layer?.backgroundColor = palette.fillControl.cgColor
        f.layer?.borderColor = palette.focus.cgColor
        let x = titleView.titleX - 6
        let w = min(360, max(120, titleView.bounds.width - x - TK.M.rowInset - TK.M.rowPadRight))
        f.frame = CGRect(x: x, y: 4, width: w, height: 30)
        f.displayIfNeeded()
    }

    // MARK: - Rename in place (§7)

    private func updateRenameField(_ rename: WindowState.Rename?, layout L: TaskLayout) {
        let isHeading = rename?.kind == .heading
        let rowView: NSView? = rename.flatMap { r in isHeading ? heads[r.id] : rows[r.id] }
        guard let rename, let row = rowView, L.contains(rename.id) else {
            if let f = renameField {
                renameField = nil
                renamingID = nil
                let wasEditing = f.isEditing
                f.onEnd = nil
                f.removeFromSuperview()
                if wasEditing { takeKeys() }
            }
            return
        }
        let f: InlineField
        if let existing = renameField, renamingID == rename.id {
            f = existing
        } else {
            renameField?.onEnd = nil
            renameField?.removeFromSuperview()
            f = InlineField(frame: .zero)
            f.font = isHeading ? HeadingRowView.font : TK.Font.body
            f.placeholderString = isHeading ? "New Heading" : "New Task"
            f.stringValue = rename.text
            let a = actions
            let kind = rename.kind
            let id = rename.id
            f.onChange = { a.setRenameText($0) }
            f.onKey = { [weak self] key in
                switch key {
                case .tab where kind == .heading:
                    // A heading's Tab writes it and goes on to its notes (§23).
                    let named = !(a.window.rename?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    a.commitRename()
                    if named || a.isHeading(id) { a.editHeadingNotes(id) } else { self?.takeKeys() }
                case .returnKey, .tab, .backtab, .commandReturn:
                    a.commitRename()
                    self?.takeKeys()
                case .escape:
                    a.cancelRename()
                    self?.takeKeys()
                }
                return true
            }
            f.onEnd = { _ in if a.window.rename?.kind == kind, a.window.rename?.id == id { a.commitRename() } }
            doc.addSubview(f)
            renameField = f
            renamingID = rename.id
            DispatchQueue.main.async {
                switch rename.caret {
                case .all: f.focus(.all)
                case .end: f.focus(.end)
                case .at(let i): f.focus(.at(i))
                }
            }
        }
        f.textColor = palette.ink
        // The field replaces the title in place: same font, origin and color (NSTextField draws its text 2pt in). Its
        // text lands on the title's pixels (measured frame by frame across the swap, v2 feedback 5).
        let t = (row as? TaskRowView)?.titleFrame ?? (row as? HeadingRowView)?.nameFrame ?? .zero
        f.frame = CGRect(x: row.frame.minX + t.minX - 2, y: row.frame.minY + t.minY, width: t.width + 4, height: 17)
        // Drawn now, into the transaction that hides the title, not in the window's next display pass.
        f.displayIfNeeded()
    }

    // MARK: - Scrolling

    func scrollToVisible(_ id: EntityID) {
        pendingScroll = id
        setNeedsRender()
    }

    func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// The selected row scrolls into view, ending 8pt below the top or 12pt above the bottom; no animation
    /// (dc:721–727).
    private func ensureVisible(_ id: EntityID, in L: TaskLayout) {
        guard let y = L.y(id) else { return }
        let clip = scroll.contentView.bounds
        var top = clip.minY
        if y < top + 4 { top = max(0, y - 8) } else if y + TK.M.row > clip.maxY - 4 { top = y + TK.M.row - clip.height + 12 } else { return }
        top = min(top, max(0, doc.frame.height - clip.height))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func pageScroll(_ dir: CGFloat) {
        let clip = scroll.contentView.bounds
        let step = max(TK.M.pitch, clip.height - TK.M.pitch)
        let top = min(max(0, clip.minY + dir * step), max(0, doc.frame.height - clip.height))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: - Geometry for others

    /// A rect in this window's top-left coordinates.
    func windowRect(_ r: CGRect, from view: NSView) -> CGRect {
        let wr = view.convert(r, to: nil)
        let h = window?.contentView?.bounds.height ?? 0
        return CGRect(x: wr.minX, y: h - wr.maxY, width: wr.width, height: wr.height)
    }

    func windowPoint(_ event: NSEvent) -> CGPoint {
        let h = window?.contentView?.bounds.height ?? 0
        return CGPoint(x: event.locationInWindow.x, y: h - event.locationInWindow.y)
    }

    /// The date popover's anchor for a row: its chip, else 300pt left of its right end (dc:1134–1137).
    func anchorRect(for id: EntityID, field: Overlays.Picker.Field) -> CGRect? {
        guard let v = rows[id] ?? rowViewForAnchor(id) else { return nil }
        if let chip = v.chipFrame(field) { return windowRect(chip, from: v) }
        let r = windowRect(v.bounds, from: v)
        return CGRect(x: r.maxX - 300, y: r.minY, width: 300, height: r.height)
    }

    private func rowViewForAnchor(_ id: EntityID) -> TaskRowView? {
        guard let L = currentLayout, L.contains(id) else { return nil }
        pendingScroll = id
        render(animated: false)
        return rows[id]
    }

    /// ⇧⌘M's menu point under the first selected row: 34 in from its left, 2 below it, in `doc` coordinates.
    func moveMenuPoint(for id: EntityID) -> NSPoint? {
        guard let v = rows[id] ?? rowViewForAnchor(id) else { return nil }
        return NSPoint(x: v.frame.minX + 34, y: v.frame.maxY + 2)
    }

    // MARK: - Hit-testing (doc coordinates)

    private func target(at p: CGPoint) -> Target {
        guard let L = currentLayout else { return .empty }
        let rowW = doc.bounds.width - 2 * TK.M.rowInset
        if !banner.isHidden, banner.frame.contains(p) {
            return banner.buttonFrame.offsetBy(dx: banner.frame.minX, dy: banner.frame.minY).contains(p) ? .banner : .empty
        }
        let inRows = p.x >= TK.M.rowInset && p.x < TK.M.rowInset + rowW
        if inRows, let id = L.row(at: p.y) {
            if L.isHeading(id) {
                let part = heads[id].map { $0.part(at: CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY)) } ?? .body
                return .head(id, part)
            }
            if let v = rows[id] {
                return .row(id, v.part(at: CGPoint(x: p.x - v.frame.minX, y: p.y - v.frame.minY)))
            }
            return .row(id, .body)
        }
        if !completedRow.isHidden, let cy = L.completedY, p.y >= cy - 1, p.y < cy + TK.M.row + 1,
           p.x >= TK.M.rowInset, p.x < TK.M.rowInset + completedWidth {
            return .completed
        }
        if inRows {
            for (key, y) in L.labels where p.y >= y && p.y < y + TK.M.pitch {
                // The + and the chevron first, whatever their fade (§23 "Bugs the prototype had").
                let part = labels[key].map { $0.part(at: CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY)) } ?? .body
                return .label(key, part: part)
            }
        }
        return .empty
    }

    // MARK: - Hover (one tracker for the whole list, §18.2)

    func pointerMoved(at p: CGPoint) {
        guard drag == nil, press == nil else { return }
        setHover(target(at: p))
    }

    func pointerExited() {
        guard press == nil else { return }
        setHover(nil)
    }

    private func updateHoverFromMouse() {
        guard let w = window, drag == nil, press == nil else { return }
        let inWin = w.mouseLocationOutsideOfEventStream
        let p = doc.convert(inWin, from: nil)
        let inside = scroll.contentView.convert(inWin, from: nil)
        if scroll.contentView.bounds.contains(inside) && w.isKeyWindow || (w.isVisible && NSApp.isActive && scroll.contentView.bounds.contains(inside)) {
            setHover(target(at: p))
        } else {
            setHover(nil)
        }
    }

    private func setHover(_ t: Target?) {
        let old = hover
        hover = t
        var hoveredRow: EntityID?
        var part: TaskRowView.Part?
        if case .row(let id, let pt) = t { hoveredRow = id; part = pt }
        for (id, v) in rows { v.setHover(row: id == hoveredRow, part: id == hoveredRow ? part : nil) }
        var hoveredHead: EntityID?
        var headPart: HeadingRowView.Part?
        if case .head(let id, let pt) = t { hoveredHead = id; headPart = pt }
        for (id, v) in heads { v.setHover(row: id == hoveredHead, part: id == hoveredHead ? headPart : nil) }
        completedRow.setHover(t == .completed)
        for (key, v) in labels {
            if case .label(let k, let part) = t, k == key { v.setHover(true, part: part) } else { v.setHover(false, part: nil) }
        }
        banner.setButtonState(hovered: t == .banner, pressed: false)
        // Tooltips: the row's › ("Show Details ⌘D") and a Today group's + (the name only), §16.
        guard t != old else { return }
        let overlays = state.overlays
        switch t {
        case .row(let id, .open):
            if let v = rows[id] {
                overlays.hoverTip("Show Details", keys: "⌘D", for: windowRect(v.open.frame, from: v), windowWidth: window?.frame.width ?? 1200)
            }
        case .head(let id, .plus):
            if let v = heads[id] {
                let name = store.projection.task(id)?.title ?? ""
                overlays.hoverTip("New Task in " + (name.isEmpty ? "this heading" : name), for: windowRect(v.plus.frame, from: v),
                                  windowWidth: window?.frame.width ?? 1200)
            }
        case .label(let key, part: .plus):
            if let v = labels[key] {
                let info = currentLayout?.labelInfo[key]
                let tip = info?.day != nil ? "New Task for \(info!.name)" : "New Task in \(actions.listName(info?.list ?? key))"
                overlays.hoverTip(tip, for: windowRect(v.plus.frame, from: v), windowWidth: window?.frame.width ?? 1200)
            }
        default:
            // Only the tips this list showed: the pointer may have moved onto another control with its own.
            if case .row(_, .open) = old { overlays.hideTip() } else if case .label(_, part: .plus) = old { overlays.hideTip() }
            else if case .head(_, .plus) = old { overlays.hideTip() }
        }
    }

    // MARK: - Mouse (selection on mouse-down, §5)

    func pointerDown(_ event: NSEvent) {
        let p = doc.convert(event.locationInWindow, from: nil)
        let t = target(at: p)
        let a = actions
        state.overlays.hideTip()
        let editing = state.rename != nil || state.draft != nil || state.detailEditing != nil
        let untitled = a.untitledDraft
        // An untitled new task keeps its caret when the press lands on an add control: a Today group's + (dc:1316).
        let keepsCaret: Bool = {
            if !untitled { return false }
            if case .label(_, part: .plus) = t { return true }
            return false
        }()
        if !keepsCaret {
            a.endEdits()
            if state.focus != .list { a.focus(.list) } else { takeKeys() }
        }
        press = (t, p, event)
        switch t {
        case .head(let id, let part):
            switch part {
            case .body:
                // A click selects the heading, never toggles it (§23); a double-click renames it in place.
                pendingCollapse = nil
                if event.clickCount == 2 {
                    let local = heads[id].map { CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY) }
                    let caret = local.flatMap { headingCaret(id, at: $0) }
                    a.startHeadingRename(id, caret: caret.map { .at($0) } ?? .all)
                    press = nil
                    return
                }
                selectOnPress(id, event: event)
            case .plus, .chevron:
                heads[id]?.setPressed(part)
            }
        case .row(let id, let part):
            switch part {
            case .body:
                pendingCollapse = nil
                if event.clickCount == 2 {
                    if let task = store.projection.task(id), task.completedAt == nil || task.deleted, id != state.draft?.id {
                        let local = rows[id].map { CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY) } ?? p
                        let caret = rows[id]?.caretIndex(at: local)
                        a.editTask(id, caret: caret.map { .at($0) } ?? .end)
                    }
                    press = nil
                    return
                }
                selectOnPress(id, event: event)
            case .check where event.clickCount > 1:
                // A double-click on a checkbox is one click: its second press would toggle the task straight back
                // (v2 feedback 18).
                press = nil
            case .check, .chip, .open:
                rows[id]?.setPressed(part)
            }
        case .label(let key, part: let part) where part != .body:
            labels[key]?.setPressed(part)
        case .banner:
            banner.setButtonState(hovered: true, pressed: true)
        case .empty:
            // Empty space (v2 feedback 2): a press clears the selection, as in Rex and Finder; with something being
            // edited, the first press only ends that edit (a new task is written, or dropped if it has no title). A
            // double-click adds a task, as ⌘N does.
            press = nil
            if event.clickCount == 2 {
                if !state.route.noAdd { a.newTask() }
            } else if !editing, !state.selection.isEmpty {
                state.selection = []
            }
        case .label(let key, part: _):
            // Double-clicking a day's label in Upcoming adds a task for that day (dc:2354).
            if event.clickCount == 2, state.route == .upcoming, let day = currentLayout?.labelInfo[key]?.day {
                press = nil
                a.newTask(day: day)
            } else if key == TaskLayout.doneGroup, state.route == .today {
                // Today's Completed label selects like a heading's row, so Space can fold it (v2 feedback 15).
                press = nil
                a.select([key])
            }
        case .completed:
            break
        }
    }

    /// Mouse-down selection (§5): ⌘ toggles, ⇧ extends from the anchor, a press in a multi-selection waits for
    /// mouse-up so it can be dragged.
    private func selectOnPress(_ id: EntityID, event: NSEvent) {
        let flags = event.modifierFlags
        let order = currentLayout?.order ?? []
        if flags.contains(.command) {
            var sel = state.selection
            if sel.contains(id) { sel.remove(id) } else { sel.insert(id) }
            state.selection = sel
            state.anchor = id
        } else if flags.contains(.shift), let anchor = state.anchor, let ai = order.firstIndex(of: anchor), let bi = order.firstIndex(of: id) {
            state.selection = Set(order[min(ai, bi)...max(ai, bi)])
        } else if state.selection.contains(id) && state.selection.count > 1 {
            pendingCollapse = id
        } else {
            actions.select([id])
        }
        state.cursor = id
    }

    /// The caret index under a point on a heading's name (a double-click puts the caret there).
    private func headingCaret(_ id: EntityID, at p: CGPoint) -> Int? {
        guard let v = heads[id], v.nameFrame.contains(p), let title = store.projection.task(id)?.title else { return nil }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [.font: HeadingRowView.font]))
        let i = CTLineGetStringIndexForPosition(line, CGPoint(x: p.x - v.nameFrame.minX, y: 0))
        return i == kCFNotFound ? nil : i
    }

    func pointerDragged(_ event: NSEvent) {
        if let d = drag {
            _ = d
            updateDrag(windowPoint: windowPoint(event))
            return
        }
        guard let pr = press else { return }
        let p = doc.convert(event.locationInWindow, from: nil)
        switch pr.target {
        case .row(let id, .body), .head(let id, .body):
            if hypot(p.x - pr.point.x, p.y - pr.point.y) >= TK.M.dragSlop { beginDrag(id, event: pr.event, now: event) }
        case .head(let id, let part):
            heads[id]?.setPressed(target(at: p) == pr.target ? part : nil)
        case .row(let id, let part):
            rows[id]?.setPressed(target(at: p) == pr.target ? part : nil)
        case .label(let key, part: let part) where part != .body:
            labels[key]?.setPressed(target(at: p) == pr.target ? part : nil)
        case .banner:
            banner.setButtonState(hovered: target(at: p) == .banner, pressed: target(at: p) == .banner)
        default: break
        }
    }

    func pointerUp(_ event: NSEvent) {
        if drag != nil {
            endDrag(cancel: false)
            press = nil
            return
        }
        guard let pr = press else { return }
        press = nil
        let p = doc.convert(event.locationInWindow, from: nil)
        let inside = target(at: p) == pr.target
        let a = actions
        switch pr.target {
        case .head(let id, let part):
            heads[id]?.setPressed(nil)
            guard inside else { break }
            switch part {
            case .body: if pendingCollapse == id { a.select([id]) }
            // The heading's + adds at the end of its section, expanding it first; the chevron folds or unfolds it.
            case .plus: if let list = store.projection.task(id)?.list { a.newTask(in: list, under: id) }
            case .chevron: a.toggleCollapse([id])
            }
        case .row(let id, let part):
            rows[id]?.setPressed(nil)
            guard inside else { break }
            switch part {
            case .body:
                if pendingCollapse == id { a.select([id]) }
            case .check:
                a.toggleComplete([id])
            case .chip(let field):
                let ids = state.selection.contains(id) ? a.targetIDs : [id]
                if !state.selection.contains(id) { a.select([id]) }
                if let v = rows[id], let chip = v.chipFrame(field) {
                    a.openPicker(field, ids: ids, anchor: windowRect(chip, from: v))
                }
            case .open:
                a.select([id])
                a.focus(.list)
                a.openDetail()
            }
        case .label(let key, part: .plus):
            labels[key]?.setPressed(nil)
            if inside {
                if let info = currentLayout?.labelInfo[key] {
                    if let day = info.day { a.newTask(day: day) } else { a.newTask(in: info.list ?? key) }
                } else {
                    a.newTask(in: key)
                }
            }
        case .label(let key, part: .chevron):
            // Today's Completed folds or unfolds (v2 feedback 15).
            labels[key]?.setPressed(nil)
            if inside { a.toggleTodayDone() }
        case .completed:
            if inside, case .list(let id) = state.route {
                if state.completedOpen.contains(id) { state.completedOpen.remove(id) } else { state.completedOpen.insert(id) }
            }
        case .banner:
            banner.setButtonState(hovered: inside, pressed: false)
            if inside, let id = state.route.listID { a.unarchive(list: id) }
        default: break
        }
        pendingCollapse = nil
        setHover(target(at: p))
    }

    func pointerRightDown(_ event: NSEvent) {
        let p = doc.convert(event.locationInWindow, from: nil)
        if case .head(let id, _) = target(at: p), store.projection.task(id) != nil {
            let a = actions
            a.endEdits()
            state.overlays.hideTip()
            if !state.selection.contains(id) { a.select([id]) }
            a.focus(.list)
            let ids = a.targetIDs.filter(a.isHeading)
            NSMenu.popUpContextMenu(Menus.heading(ids.isEmpty ? [id] : ids, actions: a), with: event, for: doc)
            return
        }
        guard case .row(let id, _) = target(at: p), id != state.draft?.id else { return }
        let a = actions
        a.endEdits()
        state.overlays.hideTip()
        if !state.selection.contains(id) { a.select([id]) }
        a.focus(.list)
        let ids = state.selection.contains(id) ? a.targetIDs : [id]
        NSMenu.popUpContextMenu(Menus.task(ids, actions: a), with: event, for: doc)
    }

    // MARK: - Keys (§5, dc:1341–1431)

    override func keyDown(with event: NSEvent) {
        if handleKey(event) { return }
        super.keyDown(with: event)
    }

    /// Also called by the detail pane's key sink: with it focused but not editing, arrows, letters and Return act on
    /// the list and move focus there (§21).
    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        let a = actions
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)
        let cmd = flags.contains(.command)
        if drag != nil {
            if event.keyCode == 53 { endDrag(cancel: true) }
            return true
        }
        switch event.keyCode {
        case 125, 126: // ↓ ↑
            a.focus(.list)
            let down = event.keyCode == 125
            a.moveSelection(cmd ? (down ? .last : .first) : .by(down ? 1 : -1), extend: shift)
            return true
        case 115: a.moveSelection(.first, extend: shift); return true // Home
        case 119: a.moveSelection(.last, extend: shift); return true  // End
        case 116: pageScroll(-1); return true // Page Up
        case 121: pageScroll(1); return true  // Page Down
        case 123: // ←
            if !cmd { a.focus(.sidebar) }
            return true
        case 36, 76: // Return
            let ids = a.targetIDs
            a.focus(.list)
            if ids.count == 1 { a.editTask(ids[0], caret: .all) } else if ids.isEmpty { a.moveSelection(.by(1), extend: false) }
            return true
        case 49 where !cmd: // Space
            // One press, one toggle: a held Space's auto-repeat would toggle it back (v2 feedback 18).
            guard !event.isARepeat else { return true }
            // On headings, collapse or expand: a heading has nothing to complete (§23). Today's Completed label, when
            // it's what's selected, the same (v2 feedback 15).
            let ids = a.targetIDs
            if state.route == .today, state.selection == [TaskLayout.doneGroup] { a.toggleTodayDone() }
            else if !ids.isEmpty, ids.allSatisfy(a.isHeading) { a.toggleCollapse(ids) } else { a.toggleComplete() }
            return true
        case 53: // Esc
            if state.overlays.picker != nil { a.closePicker() } else if state.detailOpen { a.closeDetail() } else if !state.selection.isEmpty { state.selection = [] }
            return true
        case 48: // Tab
            if shift { a.focus(.sidebar) } else { a.focus(state.detailOpen ? .detail : .sidebar) }
            return true
        default:
            break
        }
        if !cmd, !flags.contains(.control), !flags.contains(.option), let ch = event.characters, ch.count == 1,
           ch.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            a.typeSelect(ch, inSidebar: false)
            return true
        }
        return false
    }

    override func selectAll(_ sender: Any?) { actions.selectAll() }

    // MARK: - Drag (§14, dc:1161–1259)

    private struct DragSession {
        var ids: [EntityID]
        var group: EntityID
        var offset: CGPoint
        var startFrame: CGRect
        var origTarget: Int
        var lastPoint: CGPoint
        var mode: WindowState.Drag.Mode = .group
    }

    private func beginDrag(_ id: EntityID, event: NSEvent, now: NSEvent) {
        if let L = currentLayout, L.isHeading(id) { beginHeadingDrag(id, event: event, now: now, in: L); return }
        guard let L = currentLayout, let gid = L.group(id), gid != TaskLayout.doneGroup, id != state.draft?.id,
              let g = L.groups.first(where: { $0.listID == gid }), let v = rows[id], let model = v.model else {
            press = nil
            return
        }
        // Upcoming's rows go onto any day; in Completed and Trash only the sidebar takes them (§22). The selected rows of
        // the grabbed row's group travel, in every view (dc:1208).
        let mode: WindowState.Drag.Mode = state.route == .upcoming ? .days : state.route.noAdd ? .sidebarOnly : .group
        // Selected headings don't travel with tasks (a heading drags its own section).
        var ids = state.selection.contains(id) ? L.order.filter { state.selection.contains($0) && L.group($0) == gid && $0 != state.draft?.id && !L.isHeading($0) } : [id]
        if !ids.contains(id) { ids = [id] }
        let firstIdx = g.ids.firstIndex(of: ids[0]) ?? 0
        let target = g.ids[..<firstIdx].filter { !ids.contains($0) }.count
        let a = actions
        a.endEdits()
        state.overlays.hideTip()
        state.overlays.picker = nil
        setHover(nil)
        v.setPressed(nil)
        let frame = windowRect(v.bounds, from: v)
        let start = windowPoint(event)
        drag = DragSession(ids: ids, group: gid, offset: CGPoint(x: start.x - frame.minX, y: start.y - frame.minY),
                           startFrame: frame, origTarget: target, lastPoint: start, mode: mode)
        pendingCollapse = nil
        var copy = model
        copy.selected = false
        copy.joinTop = false
        copy.joinBottom = false
        copy.dragSource = false
        copy.renaming = false
        // The copy's chips are text only (the prototype's drag template, dc:171).
        copy.chips = copy.chips.map { var c = $0; c.content.glyph = nil; return c }
        copy.pickerField = nil
        state.dragOverlay?.beginTaskCopy(copy, palette: palette, frame: frame, count: ids.count)
        state.drag = .init(kind: .tasks(ids: ids, group: gid), target: target, mode: mode)
        updateDrag(windowPoint: windowPoint(now))
    }

    /// A heading drags its section (§23): after the slop it lifts, its notes and tasks fold into the copy (the heading's
    /// row, its open tasks' count in the badge), and the gap is the heading's own row (dc:1517–1520, dc:965).
    private func beginHeadingDrag(_ id: EntityID, event: NSEvent, now: NSEvent, in L: TaskLayout) {
        guard let gid = L.group(id), let g = L.groups.first(where: { $0.listID == gid }), let v = heads[id],
              store.projection.task(id) != nil else {
            press = nil
            return
        }
        let p = store.projection
        let section = p.section(of: id)
        let ids = [id] + section.dropFirst().filter { L.contains($0) }
        let others = g.ids.filter { !ids.contains($0) }
        let target = g.ids[..<(g.ids.firstIndex(of: id) ?? 0)].filter { !ids.contains($0) }.count
        _ = others
        let a = actions
        a.endEdits()
        state.overlays.hideTip()
        state.overlays.picker = nil
        setHover(nil)
        v.setPressed(nil)
        let frame = windowRect(v.bounds, from: v)
        let start = windowPoint(event)
        drag = DragSession(ids: ids, group: gid, offset: CGPoint(x: start.x - frame.minX, y: start.y - frame.minY),
                           startFrame: frame, origTarget: target, lastPoint: start, mode: .group)
        pendingCollapse = nil
        let open = section.dropFirst().filter { p.task($0)?.completedAt == nil }.count
        var copy = RowModel(id: id, title: p.task(id)?.title ?? "", untitled: false, done: false, draft: false)
        copy.heading = true
        state.dragOverlay?.beginTaskCopy(copy, palette: palette, frame: frame, count: open, minBadge: 1)
        state.drag = .init(kind: .tasks(ids: ids, group: gid), target: target, mode: .group)
        updateDrag(windowPoint: windowPoint(now))
    }

    private func updateDrag(windowPoint p: CGPoint) {
        // A view's drag can empty the group it started in (a month whose only task moves): only §14's needs it.
        guard var d = drag, let L = currentLayout else { return }
        let g = L.groups.first(where: { $0.listID == d.group })
        if d.mode == .group && g == nil { return }
        d.lastPoint = p
        drag = d
        var over: WindowState.Drag.Over?
        // A heading doesn't drop on the sidebar: moving a section to another list is left out (§23).
        let headingDrag = d.ids.first.map(L.isHeading) ?? false
        let sidebar = !headingDrag && state.sidebarVisible && p.x < (state.sidebarView?.bounds.width ?? TK.M.sidebar) - 4
        if sidebar {
            over = state.sidebarView?.dropTarget(at: p, dragged: d.ids)
        }
        var target = state.drag?.target ?? d.origTarget
        var copyOrigin: CGPoint
        var toDay: CalendarDate?
        if !sidebar && d.mode == .days {
            // Upcoming: the copy follows the pointer down the whole list; the day under its middle takes the drop.
            let r = dayTarget(ids: d.ids, y: p.y - d.offset.y, in: L)
            toDay = r.day
            copyOrigin = CGPoint(x: p.x - d.offset.x, y: r.y)
        } else if !sidebar && d.mode == .sidebarOnly {
            // Completed and Trash: nothing parts; the copy just follows the pointer to the sidebar.
            copyOrigin = CGPoint(x: p.x - d.offset.x, y: p.y - d.offset.y)
        } else if !sidebar, let g {
            // The copy stays inside its group: it stops 6pt past the first and last slot (dc:1196–1203).
            // Rows have different heights once there are headings: the target is the nearest slot top. A heading's
            // section lands only before another heading or at the end (dc:3444, dc:3457–3463).
            let others = g.ids.filter { !d.ids.contains($0) }
            let docTop = doc.convert(CGPoint(x: 0, y: 0), to: nil)
            let winH = window?.contentView?.bounds.height ?? 0
            let docOriginY = winH - docTop.y    // window y of the doc's top
            let tops = L.slotTops(g, others: others)
            let off = d.ids.first.map(L.rowOffset) ?? 0
            let y = min(max(p.y - d.offset.y, docOriginY + tops[0] + off - 6), docOriginY + tops[tops.count - 1] + off + 6)
            let cy = y - docOriginY - off
            let allowed = headingDrag ? tops.indices.filter { $0 == others.count || L.isHeading(others[$0]) } : Array(tops.indices)
            target = allowed.min { abs(tops[$0] - cy) < abs(tops[$1] - cy) } ?? target
            copyOrigin = CGPoint(x: p.x - d.offset.x, y: y)
        } else {
            // Over the sidebar the copy becomes a compact tag at the pointer, so the target stays readable. It stays one
            // between targets too, where nothing is highlighted (v2 feedback 7).
            copyOrigin = CGPoint(x: p.x + 12, y: p.y + 8)
        }
        state.dragOverlay?.moveCopy(to: copyOrigin, compact: sidebar)
        if state.drag?.over != over || state.drag?.sidebar != sidebar || state.drag?.target != target || state.drag?.toDay != toDay {
            state.drag?.over = over
            state.drag?.sidebar = sidebar
            state.drag?.target = target
            state.drag?.toDay = toDay
        }
        autoscroll(p)
    }

    /// Within 24pt of the list's top or bottom, it scrolls 8pt every 16 ms.
    private func autoscroll(_ p: CGPoint) {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
        guard drag != nil else { return }
        let r = windowRect(scroll.contentView.bounds, from: scroll.contentView)
        let dy: CGFloat = p.y < r.minY + TK.M.scrollEdge ? -TK.M.scrollStep : p.y > r.maxY - TK.M.scrollEdge ? TK.M.scrollStep : 0
        guard dy != 0, p.x > r.minX else { return }
        autoscrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.drag != nil else { return }
                let clip = self.scroll.contentView.bounds
                let top = min(max(0, clip.minY + dy), max(0, self.doc.frame.height - clip.height))
                guard top != clip.minY else { return }
                self.scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
                self.scroll.reflectScrolledClipView(self.scroll.contentView)
            }
        }
    }

    private func endDrag(cancel: Bool) {
        guard let d = drag, let current = state.drag else { return }
        drag = nil
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
        let a = actions
        let overlay = state.dragOverlay
        if cancel || (current.sidebar && current.over == nil) {
            // The copy flies back and the gap closes; nothing is written. A drop on the sidebar where no row takes it
            // is a cancel too.
            state.drag?.over = nil
            state.drag?.sidebar = false
            state.drag?.target = d.origTarget
            state.drag?.toDay = nil
            state.drag?.phase = .fly
            overlay?.flyCopy(to: d.startFrame.origin, shrink: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.state.drag = nil
                self?.land(on: d.ids.first, overlay)
            }
            return
        }
        if let over = current.over {
            let rowFrame = state.sidebarView?.rowFrame(for: over)
            state.drag?.phase = .fly
            overlay?.flyCopy(to: CGPoint(x: 10, y: rowFrame?.minY ?? d.lastPoint.y), shrink: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.fly) { [weak self] in
                overlay?.endCopy()
                self?.state.drag = nil
                switch over {
                case .today: a.setDate(d.ids, .when, a.today)
                case .list(let id): if a.inTrash { a.putBack(d.ids, in: id) } else { a.move(d.ids, to: id) }
                case .completed: a.completeTasks(d.ids)
                case .trash: a.delete(d.ids)
                }
            }
            return
        }
        if d.mode != .group {
            endViewDrag(d, current: current, overlay: overlay)
            return
        }
        // Drop on the list: the copy flies into its slot; at 170 ms the new order is written.
        guard let L = currentLayout, let g = L.groups.first(where: { $0.listID == d.group }) else {
            overlay?.endCopy()
            state.drag = nil
            return
        }
        let others = g.ids.filter { !d.ids.contains($0) }
        let tops = L.slotTops(g, others: others)
        let headingDrag = d.ids.first.map(L.isHeading) ?? false
        let slotY = tops[min(max(current.target, 0), tops.count - 1)] + (d.ids.first.map(L.rowOffset) ?? 0)
        let slotDoc = CGRect(x: TK.M.rowInset, y: slotY, width: 10, height: TK.M.row)
        let slot = windowRect(slotDoc, from: doc)
        state.drag?.phase = .fly
        overlay?.flyCopy(to: CGPoint(x: d.startFrame.minX, y: slot.minY), shrink: false)
        let contiguous = d.ids.enumerated().allSatisfy { i, id in g.ids.firstIndex(of: id) == (g.ids.firstIndex(of: d.ids[0]) ?? 0) + i }
        DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.fly) { [weak self] in
            guard let self else { return }
            if headingDrag {
                // The heading and every task in its section, completed ones included; where it started, nothing.
                if current.target != d.origTarget {
                    let t = min(max(current.target, 0), others.count)
                    a.moveSection(d.ids[0], to: t < others.count ? .before(others[t]) : .bottom)
                }
            } else if !(contiguous && current.target == d.origTarget) { a.reorder(group: d.group, ids: d.ids, target: current.target) }
            self.state.drag?.phase = .done
            self.land(on: d.ids.first, overlay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.state.drag = nil }
        }
    }

    /// Upcoming: the copy's top at window y `y`, kept between 6pt above the first label and 6pt below the last row, and
    /// the day group whose label is the last above its middle, if it takes the drop: a day, and not one after any
    /// dragged task's deadline (dc:2463–2474).
    private func dayTarget(ids: [EntityID], y: CGFloat, in L: TaskLayout) -> (day: CalendarDate?, y: CGFloat) {
        let top = windowRect(CGRect(x: 0, y: 0, width: 1, height: 1), from: doc).minY
        let first = L.groups.first.flatMap { L.labels[$0.listID] } ?? 0
        let cy = min(max(y, top + first - 6), top + max(first, L.height - 24 - TK.M.pitch) + 6)
        let mid = cy + TK.M.row / 2 - top
        var pick: TaskLayout.Group?
        for g in L.groups { if let ly = L.labels[g.listID], ly <= mid { pick = g } }
        let p = store.projection
        guard let g = pick, g.kind == .day, let day = g.day,
              ids.allSatisfy({ p.task($0)?.deadline.map { day <= $0 } ?? true }) else { return (nil, cy) }
        return (day, cy)
    }

    /// The drop in Upcoming, Completed and Trash away from the sidebar: on a day that changes a task's, the copy flies
    /// into the gap and When is set to that day (the deadline is never touched); anywhere else it flies home and
    /// nothing is written (dc:2491–2513).
    private func endViewDrag(_ d: DragSession, current: WindowState.Drag, overlay: DragOverlayView?) {
        let a = actions
        let p = store.projection
        if d.mode == .days, let day = current.toDay, d.ids.contains(where: { id in
            p.task(id).flatMap { ViewItems.upDay(when: $0.when, deadline: $0.deadline) } != day
        }), let L = currentLayout, let grabbed = d.ids.first, let y = L.y(grabbed) {
            let slot = windowRect(CGRect(x: TK.M.rowInset, y: y, width: 10, height: TK.M.row), from: doc)
            state.drag?.phase = .fly
            overlay?.flyCopy(to: CGPoint(x: d.startFrame.minX, y: slot.minY), shrink: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.fly) { [weak self] in
                guard let self else { return }
                a.setDate(d.ids, .when, day)
                self.state.drag?.phase = .done
                self.land(on: grabbed, overlay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.state.drag = nil }
            }
            return
        }
        state.drag?.over = nil
        state.drag?.sidebar = false
        state.drag?.toDay = nil
        state.drag?.phase = .fly
        overlay?.flyCopy(to: d.startFrame.origin, shrink: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.state.drag = nil
            self?.land(on: d.ids.first, overlay)
        }
    }

    /// The hand-off when the copy has flown onto its row (a drop in the list, or Esc flying it back): the row is drawn
    /// now, in the same Core Animation transaction as the copy starting to fade, so no frame shows neither. The other
    /// dragged rows, which the copy only counted, fade in as before.
    private func land(on id: EntityID?, _ overlay: DragOverlayView?) {
        landing = id
        render()
        landing = nil
        overlay?.settleCopy()
    }

    #if DEBUG
    /// Debug: hover at a window point (top-left origin), as the tracking area would.
    func debugScroll(_ y: CGFloat) {
        let y = min(max(0, y), max(0, doc.frame.height - scroll.contentView.bounds.height))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Points are from the top of the content layout rect, as the script's `click:` takes them.
    func debugHover(_ p: CGPoint?) {
        guard let p, let w = window else { pointerExited(); return }
        let inWin = NSPoint(x: p.x, y: w.contentLayoutRect.height - p.y)
        pointerMoved(at: doc.convert(inWin, from: nil))
    }

    /// Debug: a task row's checkbox center in window points (top-left origin), for clicking it (v2 feedback 18).
    func debugCheckPoint(_ id: EntityID) -> CGPoint? {
        guard let v = rows[id], let w = window else { return nil }
        let c = v.convert(v.check.position, to: nil)
        return CGPoint(x: c.x, y: w.contentLayoutRect.height - c.y)
    }

    /// Debug: a heading's row, + and chevron centers, and its notes, in window points (top-left origin); and the glyph
    /// sizes and opacities of the + and the chevron.
    func debugWhere(_ id: EntityID) -> String? {
        guard let v = heads[id] else { return "not on screen" }
        func c(_ r: CGRect, in view: NSView) -> String {
            let w = view.convert(r, to: nil)
            return "\(Int(w.midX)),\(Int((window?.contentLayoutRect.height ?? 0) - w.midY))"
        }
        let notes = paneEditors[.task(id)].map { e in e.view.isHidden ? "hidden" : c(e.view.bounds, in: e.view) } ?? "-"
        let chev = v.chevron, plus = v.plus
        return "row=\(c(v.bounds, in: v)) plus=\(c(plus.frame, in: v)) chevron=\(c(chev.frame, in: v)) notes=\(notes)"
            + " chevronGlyph=\(Int(chev.glyph.bounds.width))x\(Int(chev.glyph.bounds.height)) chevronButton=\(Int(chev.bounds.width))"
            + " plusOpacity=\(String(format: "%.2f", plus.presentation()?.opacity ?? plus.opacity))"
            + " chevronOpacity=\(String(format: "%.2f", chev.presentation()?.opacity ?? chev.opacity))"
            + " rotation=\(String(format: "%.2f", (chev.glyph.presentation() ?? chev.glyph).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0))"
    }

    /// Debug: Today's Completed label (its body and chevron centers, the chevron's glyph size, opacity and rotation),
    /// or a list's Completed row; and the done rows laid out (v2 feedback 15).
    func debugDoneWhere() -> String {
        func c(_ r: CGRect, in view: NSView) -> String {
            let w = view.convert(r, to: nil)
            return "\(Int(w.midX)),\(Int((window?.contentLayoutRect.height ?? 0) - w.midY))"
        }
        let L = currentLayout
        let doneRows = L.map { l in l.order.filter { l.isDone($0) }.count } ?? 0
        if let v = labels[TaskLayout.doneGroup] {
            let chev = v.chevron
            return "label=\(c(v.bounds, in: v)) chevron=\(c(chev.frame, in: v)) chevronGlyph=\(Int(chev.glyph.bounds.width))x\(Int(chev.glyph.bounds.height))"
                + " chevronButton=\(Int(chev.bounds.width)) chevronOpacity=\(String(format: "%.2f", chev.presentation()?.opacity ?? chev.opacity))"
                + " rotation=\(String(format: "%.2f", (chev.glyph.presentation() ?? chev.glyph).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0))"
                + " doneRows=\(doneRows) folded=\(L?.folded.values.filter { $0 == TaskLayout.doneGroup }.count ?? 0)"
                + " labelAboveRows=\(doc.subviews.firstIndex(of: v).map { li in doc.subviews.enumerated().allSatisfy { !($0.element is TaskRowView) || $0.element.isHidden || $0.offset < li } } ?? false)"
        }
        if !completedRow.isHidden {
            return "completedRow=\(c(completedRow.bounds, in: completedRow)) doneRows=\(doneRows) folded=\(L?.folded.values.filter { $0 == TaskLayout.completedRowKey }.count ?? 0)"
        }
        return "no Completed label"
    }
    #endif

    // MARK: - Accessibility

    private func updateAccessibility(_ L: TaskLayout) {
        // Children are computed when asked (accessibilityChildren), so a render costs nothing here.
    }

    override func accessibilityLabel() -> String? {
        actions.routeName(state.route)
    }

    override func accessibilityChildren() -> [Any]? {
        guard let L = currentLayout else { return [] }
        return L.order.compactMap { (rows[$0] as NSView?) ?? heads[$0] }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        guard let L = currentLayout else { return [] }
        return L.order.compactMap { id -> NSView? in
            if let r = rows[id] { return r.model?.selected == true ? r : nil }
            if let h = heads[id] { return h.model?.selected == true ? h : nil }
            return nil
        }
    }
}

/// The scroll view's content: forwards the pointer to the list.
final class TaskListDocument: NSView {
    weak var owner: TaskListView?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { owner?.pointerMoved(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { owner?.pointerMoved(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { owner?.pointerExited() }
    override func mouseDown(with event: NSEvent) { owner?.pointerDown(event) }
    override func mouseDragged(with event: NSEvent) { owner?.pointerDragged(event) }
    override func mouseUp(with event: NSEvent) { owner?.pointerUp(event) }
    override func rightMouseDown(with event: NSEvent) { owner?.pointerRightDown(event) }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

struct TaskListRepresentable: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> TaskListView {
        let v = TaskListView(store: store, window: window)
        v.palette = palette
        window.taskList = v
        return v
    }

    func updateNSView(_ nsView: TaskListView, context: Context) {
        nsView.palette = palette
        window.palette = palette
    }
}
