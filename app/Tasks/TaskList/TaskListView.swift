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
    private let completedRow = CompletedRowView()
    private var completedWidth: CGFloat = 0
    private let ghost = GhostRowView()
    private let empty = EmptyStateView()
    private let banner = BannerView()
    private var renameField: InlineField?
    private var renamingID: EntityID?

    private var renderScheduled = false
    private var paletteChanged = true
    private var firstRender = true
    private var lastWidth: CGFloat = 0
    private var pendingScroll: EntityID?
    private var cleanupTimer: Timer?

    // Pointer
    private enum Target: Equatable {
        case row(EntityID, TaskRowView.Part)
        case label(EntityID, plus: Bool)
        case completed
        case addZone
        case banner
        case empty
    }
    private var hover: Target?
    private var press: (target: Target, point: CGPoint, event: NSEvent)?
    private var pendingCollapse: EntityID?
    private var drag: DragSession?
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
        doc.addSubview(ghost)
        doc.addSubview(completedRow)
        doc.addSubview(empty)
        doc.addSubview(banner)
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
        Self.phaseT = 0; Self.phase()
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
        let L = TaskLayout.make(store: store, window: state)
        Self.phase()
        let now = CACurrentMediaTime()
        let sameView = prevKey == L.key
        let animate = allowAnimation && sameView && !firstRender && !paletteChanged && !TK.CA.reduce
        if !sameView { leaving.values.forEach { recycle($0.view) }; leaving = [:]; labelsLeaving.values.forEach { $0.view.removeFromSuperview() }; labelsLeaving = [:] }
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
        let paneFocused = state.focus == .list
        let selection = state.selection
        let rename = state.rename?.kind == .task ? state.rename : nil
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

        for id in needed {
            guard let y = L.y(id) else { continue }
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
            if isDraft, let draft {
                let untitled = draft.title.isEmpty
                m = RowModel(id: id, title: draft.title, untitled: untitled, done: false, draft: true)
                if let when = draft.when, !(inToday && when <= today) {
                    m.chips.append(.init(field: .when, content: .init(text: DateLabel.whenChip(when, today: today), glyph: .calendar)))
                }
            } else if let t = p.taskModel(id) {
                m = RowModel(id: id, title: t.title, untitled: t.title.isEmpty, done: t.isDone, draft: false)
                if !t.isDone {
                    if let when = t.when, !(inToday && when <= today) {
                        m.chips.append(.init(field: .when, content: .init(text: DateLabel.whenChip(when, today: today), glyph: .calendar)))
                    }
                    if let dl = t.deadline {
                        let c = DateLabel.deadlineChip(dl, today: today)
                        let tone: ChipLayer.Tone = c.tone == .late ? .late : c.tone == .due ? .due : .neutral
                        m.chips.append(.init(field: .deadline, content: .init(text: c.text, glyph: .flag, tone: tone)))
                    }
                }
                if inToday && L.isDone(id) { m.whereText = actions.listName(t.list) }
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
                if animate, let oldY = prevLayout?.y(id), oldY != y {
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
        }

        Self.phase()
        renderLabels(L, rowW: rowW, animate: animate, now: now)
        renderExtras(L, width: width, rowW: rowW, contentH: contentH, animate: animate)

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
        updateRenameField(rename, layout: L)
        if !leaving.isEmpty || !labelsLeaving.isEmpty || !keepUntil.isEmpty { scheduleCleanup() }
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
        if v.superview !== doc { doc.addSubview(v, positioned: .above, relativeTo: ghost) }
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

    // MARK: Labels, the Completed row, the ghost row, the empty state and the banner

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
        for key in L.labelOrder {
            guard let y = L.labels[key] else { continue }
            let isDone = key == TaskLayout.doneGroup
            let name = isDone ? "Completed" : actions.listName(key)
            var isNew = false
            let v: GroupLabelView
            if let existing = labels[key] { v = existing } else {
                v = GroupLabelView()
                v.layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
                doc.addSubview(v, positioned: .above, relativeTo: ghost)
                labels[key] = v
                isNew = true
            }
            _ = p
            v.configure(key: key, name: name, plus: !isDone, palette: palette, width: rowW)
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
        // The ghost row and the add zone (a list, not during a drag).
        if let gy = L.ghostY, state.route.listID != nil {
            ghost.isHidden = false
            ghost.configure(palette: palette)
            if ghost.frame.minY != gy || ghost.frame.width != rowW { place(ghost, y: gy, width: rowW) }
        } else {
            ghost.isHidden = true
            ghost.show(false, animated: false)
        }
        // The empty states: never clickable; 34% down (40pt for All done).
        if let kind = L.empty, !(kind == .list && state.route.listID.flatMap { p.list($0)?.archivedAt } != nil) {
            empty.isHidden = false
            empty.configure(kind, palette: palette, width: width)
            let visibleH = scroll.contentView.bounds.height
            let top: CGFloat = kind == .allDone ? 40 : (visibleH * 0.34).rounded()
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

    // MARK: - Rename in place (§7)

    private func updateRenameField(_ rename: WindowState.Rename?, layout L: TaskLayout) {
        guard let rename, let row = rows[rename.id], L.contains(rename.id) else {
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
            f.font = TK.Font.body
            f.placeholderString = "New Task"
            f.stringValue = rename.text
            let a = actions
            f.onChange = { a.setRenameText($0) }
            f.onKey = { [weak self] key in
                switch key {
                case .returnKey, .tab, .backtab, .commandReturn:
                    a.commitRename()
                    self?.takeKeys()
                case .escape:
                    a.cancelRename()
                    self?.takeKeys()
                }
                return true
            }
            f.onEnd = { _ in if a.window.rename?.kind == .task { a.commitRename() } }
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
        // The field replaces the title in place: same font, origin and color (NSTextField draws its text 2pt in).
        let t = row.titleFrame
        f.frame = CGRect(x: row.frame.minX + t.minX - 2, y: row.frame.minY + t.minY - 0.5, width: t.width + 4, height: 17)
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
                let plus = labels[key].map { $0.plusContains(CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY)) } ?? false
                return .label(key, plus: plus)
            }
        }
        if state.route.listID != nil, let gy = L.ghostY, p.y >= gy, state.drag == nil { return .addZone }
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
        completedRow.setHover(t == .completed)
        ghost.show(t == .addZone && state.drag == nil)
        for (key, v) in labels {
            if case .label(let k, let plus) = t, k == key { v.setHover(true, overPlus: plus) } else { v.setHover(false, overPlus: false) }
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
        case .label(let key, plus: true):
            if let v = labels[key] {
                overlays.hoverTip("New Task in \(actions.listName(key))", for: windowRect(v.plus.frame, from: v), windowWidth: window?.frame.width ?? 1200)
            }
        default:
            // Only the tips this list showed: the pointer may have moved onto another control with its own.
            if case .row(_, .open) = old { overlays.hideTip() } else if case .label(_, plus: true) = old { overlays.hideTip() }
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
        // An untitled new task keeps its caret when the press lands on an add control (dc:1316).
        let keepsCaret: Bool = {
            if !untitled { return false }
            if t == .addZone { return true }
            if case .label(_, plus: true) = t { return true }
            return false
        }()
        if !keepsCaret {
            a.endEdits()
            if state.focus != .list { a.focus(.list) } else { takeKeys() }
        }
        press = (t, p, event)
        switch t {
        case .row(let id, let part):
            switch part {
            case .body:
                let flags = event.modifierFlags
                pendingCollapse = nil
                if event.clickCount == 2 {
                    if let task = store.projection.task(id), task.completedAt == nil, id != state.draft?.id {
                        let local = rows[id].map { CGPoint(x: p.x - $0.frame.minX, y: p.y - $0.frame.minY) } ?? p
                        let caret = rows[id]?.caretIndex(at: local)
                        a.startRename(id, caret: caret.map { .at($0) } ?? .end)
                    }
                    press = nil
                    return
                }
                let order = currentLayout?.order ?? []
                if flags.contains(.command) {
                    var sel = state.selection
                    if sel.contains(id) { sel.remove(id) } else { sel.insert(id) }
                    state.selection = sel
                    state.anchor = id
                } else if flags.contains(.shift), let anchor = state.anchor, let ai = order.firstIndex(of: anchor), let bi = order.firstIndex(of: id) {
                    state.selection = Set(order[min(ai, bi)...max(ai, bi)])
                } else if state.selection.contains(id) && state.selection.count > 1 {
                    // A multi-selection waits for mouse-up, so it can be dragged.
                    pendingCollapse = id
                } else {
                    a.select([id])
                }
                state.cursor = id
            case .check, .chip, .open:
                rows[id]?.setPressed(part)
            }
        case .label(let key, plus: true):
            labels[key]?.plus.pressed = true
        case .banner:
            banner.setButtonState(hovered: true, pressed: true)
        case .addZone:
            press = nil
            if untitled {
                state.titleFocusRequest = .init(selection: .end)
            } else if !editing {
                a.newTask()
            }
        case .empty:
            press = nil
            if !editing, state.route == .today || true, !state.selection.isEmpty { state.selection = [] }
        case .completed, .label:
            break
        }
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
        case .row(let id, .body):
            if hypot(p.x - pr.point.x, p.y - pr.point.y) >= TK.M.dragSlop { beginDrag(id, event: pr.event, now: event) }
        case .row(let id, let part):
            rows[id]?.setPressed(target(at: p) == pr.target ? part : nil)
        case .label(let key, plus: true):
            labels[key]?.plus.pressed = target(at: p) == pr.target
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
        case .label(let key, plus: true):
            labels[key]?.plus.pressed = false
            if inside { a.newTask(in: key) }
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
            if ids.count == 1 { a.startRename(ids[0], caret: .all) } else if ids.isEmpty { a.moveSelection(.by(1), extend: false) }
            return true
        case 49 where !cmd: // Space
            a.toggleComplete()
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
    }

    private func beginDrag(_ id: EntityID, event: NSEvent, now: NSEvent) {
        guard let L = currentLayout, let gid = L.group(id), gid != TaskLayout.doneGroup, id != state.draft?.id,
              let g = L.groups.first(where: { $0.listID == gid }), let v = rows[id], let model = v.model else {
            press = nil
            return
        }
        var ids = state.selection.contains(id) ? L.order.filter { state.selection.contains($0) && L.group($0) == gid && $0 != state.draft?.id } : [id]
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
                           startFrame: frame, origTarget: target, lastPoint: start)
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
        state.drag = .init(kind: .tasks(ids: ids, group: gid), target: target)
        updateDrag(windowPoint: windowPoint(now))
    }

    private func updateDrag(windowPoint p: CGPoint) {
        guard var d = drag, let L = currentLayout, let g = L.groups.first(where: { $0.listID == d.group }) else { return }
        d.lastPoint = p
        drag = d
        var over: WindowState.Drag.Over?
        if state.sidebarVisible, p.x < TK.M.sidebar - 4 {
            over = state.sidebarView?.dropTarget(at: p, groupList: d.group)
            if over == .today && state.route == .today { over = nil }
        }
        var target = state.drag?.target ?? d.origTarget
        var copyOrigin: CGPoint
        if over == nil {
            // The copy stays inside its group: it stops 6pt past the first and last slot (dc:1196–1203).
            let others = g.ids.filter { !d.ids.contains($0) }.count
            let docTop = doc.convert(CGPoint(x: 0, y: 0), to: nil)
            let winH = window?.contentView?.bounds.height ?? 0
            let docOriginY = winH - docTop.y    // window y of the doc's top
            let top = docOriginY + g.top
            let y = min(max(p.y - d.offset.y, top - 6), top + CGFloat(others) * TK.M.pitch + 6)
            target = min(max(Int(((y - top) / TK.M.pitch).rounded()), 0), others)
            copyOrigin = CGPoint(x: p.x - d.offset.x, y: y)
        } else {
            // Over a sidebar list the copy becomes a compact tag at the pointer, so the target stays readable.
            copyOrigin = CGPoint(x: p.x + 12, y: p.y + 8)
        }
        state.dragOverlay?.moveCopy(to: copyOrigin, compact: over != nil)
        if state.drag?.over != over || state.drag?.target != target {
            state.drag?.over = over
            state.drag?.target = target
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
        if cancel {
            // The copy flies back and the gap closes; nothing is written.
            state.drag?.over = nil
            state.drag?.target = d.origTarget
            state.drag?.phase = .fly
            overlay?.flyCopy(to: d.startFrame.origin, shrink: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                overlay?.endCopy()
                self?.state.drag = nil
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
                case .list(let id): a.move(d.ids, to: id)
                }
            }
            return
        }
        // Drop on the list: the copy flies into its slot; at 170 ms the new order is written.
        guard let L = currentLayout, let g = L.groups.first(where: { $0.listID == d.group }) else {
            overlay?.endCopy()
            state.drag = nil
            return
        }
        let slotDoc = CGRect(x: TK.M.rowInset, y: g.top + CGFloat(current.target) * TK.M.pitch, width: 10, height: TK.M.row)
        let slot = windowRect(slotDoc, from: doc)
        state.drag?.phase = .fly
        overlay?.flyCopy(to: CGPoint(x: d.startFrame.minX, y: slot.minY), shrink: false)
        let contiguous = d.ids.enumerated().allSatisfy { i, id in g.ids.firstIndex(of: id) == (g.ids.firstIndex(of: d.ids[0]) ?? 0) + i }
        DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.fly) { [weak self] in
            guard let self else { return }
            if !(contiguous && current.target == d.origTarget) { a.reorder(group: d.group, ids: d.ids, target: current.target) }
            self.state.drag?.phase = .done
            overlay?.endCopy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.state.drag = nil }
        }
    }

    // MARK: - Accessibility

    private func updateAccessibility(_ L: TaskLayout) {
        // Children are computed when asked (accessibilityChildren), so a render costs nothing here.
    }

    override func accessibilityLabel() -> String? {
        state.route == .today ? "Today" : state.route.listID.map(actions.listName) ?? "Tasks"
    }

    override func accessibilityChildren() -> [Any]? {
        guard let L = currentLayout else { return [] }
        return L.order.compactMap { rows[$0] }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        guard let L = currentLayout else { return [] }
        return L.order.compactMap { rows[$0] }.filter { $0.model?.selected == true }
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
