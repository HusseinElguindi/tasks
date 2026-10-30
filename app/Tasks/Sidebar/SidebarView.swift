import AppKit
import SwiftUI
import TasksCore

/// The sidebar (design/INTERACTIONS-v2.md §12, §14, §15; the prototype's dc:19–40, css:97–140): Today, the "Lists"
/// label, the active lists, then the Archive group, drawn in layers on a flipped, layer-backed view. Rows start at
/// window y 50 under the toolbar band (the traffic lights and the toggle are drawn by others), in a scroll view with
/// no scroller.
///
/// It re-renders from `SidebarModel.make` inside `withObservationTracking`, coalesced to the next turn of the run
/// loop. Rows that move spring on `layout`, rows that appear fade in over 180 ms, rows that go fade out over 150 ms;
/// list switches, theme changes and the first frame never animate (css:83, dc:559–563).
///
/// One hover tracker covers the whole sidebar (§18.2): a tracking area plus `mouseMoved`, rows hit-tested from the
/// layout (each 2pt gap split 1/1), recomputed when it scrolls. It's the first responder while the sidebar has the
/// keys (dc:1433–1448).
final class SidebarView: FlippedLayerView {
    let store: Store
    let ui: WindowState
    private(set) var palette: TK.Palette

    private let scroll = NSScrollView()
    private let content = SidebarContentView()
    /// Rows and labels live here, below any subview (the rename field).
    private let host = CALayer()
    private let listsLabel = SidebarLabelLayer(title: "Lists", glyph: .plus)
    private let archiveLabel = SidebarLabelLayer(title: "Archive", glyph: .chevronRight)

    private(set) var model = SidebarModel()
    private var rowLayers: [SidebarModel.Key: SidebarRowLayer] = [:]
    /// Rows fading out, with a token so a row that comes back isn't removed.
    private var leaving: [SidebarModel.Key: Int] = [:]
    private var leaveToken = 0
    private var rendered = false
    private var renderedRoute: WindowState.Route?
    private var renderedDark: Bool?
    private var renderQueued = false
    private var archiveLabelShown = false
    private var labelsDark: Bool?

    private var field: InlineField?
    private var fieldID: EntityID?

    // Hover and presses
    enum Label { case lists, archive }
    enum Hit: Equatable { case row(SidebarModel.Key), label(Label) }
    private var hover: Hit?
    private var hoverButton: Label?
    /// A press on a label's button, or on the Archive label's text (`.gl`, dc:31), that acts on release inside it.
    private var press: (label: Label, rect: CGRect)?
    /// A press on a row that may become a list drag.
    private struct Candidate {
        var key: SidebarModel.Key
        /// The press, in this view's coordinates (y down from the window's top).
        var start: CGPoint
    }
    private var candidate: Candidate?

    // The list drag (§14, dc:1262–1300)
    private struct ListDrag {
        var id: EntityID
        /// The grab offset: the pointer's y minus the row's top.
        var offY: CGFloat
        var from: Int
        var target: Int
        var flying = false
    }
    private var listDrag: ListDrag?
    private var lift: SidebarLiftLayer?

    // Held ⌘ (§12, §18.13)
    nonisolated(unsafe) private var monitor: Any?
    private var cmdTimer: Timer?
    private var cmdDown = false
    /// ↑ ↓ moved the current row: keep it in view after the next render.
    private var revealCurrent = false

    private var actions: WindowActions { WindowActions(store: store, window: ui) }

    init(store: Store, window: WindowState, palette: TK.Palette) {
        self.store = store
        self.ui = window
        self.palette = palette
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.contentView.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView = content
        addSubview(scroll)
        content.owner = self
        content.layer?.addSublayer(host)
        host.anchorPoint = .zero
        host.addSublayer(listsLabel)
        host.addSublayer(archiveLabel)
        archiveLabel.isHidden = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipScrolled(_:)), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        setAccessibilityElement(false)
        render()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    /// Out of AppKit's key-view loop (Tab is handled here), so the window never picks it as its first responder on its own.
    override var canBecomeKeyView: Bool { false }

    /// The band above the rows moves the window, like the rest of the toolbar.
    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        let top = TK.M.sidebarTop
        scroll.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        sizeContent()
    }

    private func sizeContent() {
        let clip = scroll.contentView.bounds.size
        let h = max(model.height, clip.height)
        if content.frame.size != CGSize(width: clip.width, height: h) {
            content.frame = CGRect(x: 0, y: 0, width: clip.width, height: h)
        }
        host.frame = CGRect(x: 0, y: 0, width: clip.width, height: h)
        scroll.verticalScrollElasticity = model.height > clip.height ? .allowed : .none
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let w = window {
            if host.superlayer == nil { content.layer?.addSublayer(host) }
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)), name: NSWindow.didResignKeyNotification, object: w)
            installMonitor()
            host.setScaleDeep(w.backingScaleFactor)
            #if DEBUG
            runDebugIfRequested()
            #endif
        } else {
            removeMonitor()
        }
    }

    // MARK: - Public API

    func setPalette(_ p: TK.Palette) {
        guard p != palette else { return }
        palette = p
        render()
    }

    /// Gives the sidebar the keys (`WindowActions.focus(.sidebar)`).
    func takeKeys() {
        guard let w = window, w.firstResponder !== self else { return }
        w.makeFirstResponder(self)
    }

    /// The sidebar row a task drag is over (window point, top-left origin, y down): Today unless the view is Today,
    /// or an active list other than `groupList`. Archived lists and labels aren't targets (dc:1183–1192).
    func dropTarget(at windowPoint: CGPoint, groupList: EntityID?) -> WindowState.Drag.Over? {
        guard ui.sidebarVisible, windowPoint.x < TK.M.sidebar - 4, let p = contentPoint(fromWindowTopLeft: windowPoint),
              scroll.frame.contains(convert(p, from: content)) else { return nil }
        guard let row = model.rows.first(where: { p.y >= $0.y && p.y < $0.y + SB.rowHeight }) else { return nil }
        switch row.key {
        case .today:
            return ui.route == .today ? nil : .today
        case .list(let id):
            guard !row.archived, !row.draft, id != groupList, store.projection.isActive(list: id) else { return nil }
            return .list(id)
        }
    }

    /// The row's frame in window coordinates (top-left origin), for the dropped copy's flight.
    func rowFrame(for over: WindowState.Drag.Over) -> CGRect? {
        let key: SidebarModel.Key
        switch over {
        case .today: key = .today
        case .list(let id): key = .list(id)
        }
        guard let row = model.row(key) else { return nil }
        return windowTopLeftRect(fromContent: rowRect(row.y))
    }

    // MARK: - Coordinates

    private func rowRect(_ y: CGFloat) -> CGRect { CGRect(x: SB.rowX, y: y, width: SB.rowWidth, height: SB.rowHeight) }

    private var windowHeight: CGFloat { window?.contentView?.bounds.height ?? 0 }

    private func contentPoint(fromWindowTopLeft p: CGPoint) -> CGPoint? {
        guard window != nil else { return nil }
        return content.convert(NSPoint(x: p.x, y: windowHeight - p.y), from: nil)
    }

    private func windowTopLeftRect(fromContent r: CGRect) -> CGRect? {
        guard window != nil else { return nil }
        let w = content.convert(r, to: nil)
        return CGRect(x: w.minX, y: windowHeight - w.maxY, width: w.width, height: w.height)
    }

    /// This view's coordinates (y down) are the window's from its top-left corner, offset by where the sidebar sits.
    private func localPoint(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private var scrollY: CGFloat { scroll.contentView.bounds.origin.y }

    // MARK: - Rendering

    private func scheduleRender() {
        guard !renderQueued else { return }
        renderQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.renderQueued = false
                self.render()
            }
        }
    }

    func render() {
        let drag = listDrag.map { SidebarModel.Drag(id: $0.id, target: $0.target) }
        let m = withObservationTracking {
            SidebarModel.make(store: store, window: ui, drag: drag)
        } onChange: { [weak self] in
            // Called as the change is made (the store and the window state are main-actor types). One hop later the
            // sidebar renders, with every other change of this turn, before the turn's Core Animation commit.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.scheduleRender() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleRender() } }
            }
        }
        // List switches, theme changes and the first frame never animate.
        let animated = rendered && renderedRoute == m.route && renderedDark == palette.isDark && !TK.CA.reduce
        rendered = true
        renderedRoute = m.route
        renderedDark = palette.isDark
        model = m
        if !m.sidebarVisible { setHover(nil, button: nil) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(m, animated: animated)
        CATransaction.commit()

        sizeContent()
        syncField()
        if revealCurrent, let row = m.row(m.current) {
            revealCurrent = false
            content.scrollToVisible(rowRect(row.y).insetBy(dx: 0, dy: -4))
        }
        refreshHover()
        content.rebuildAccessibility()
    }

    private func apply(_ m: SidebarModel, animated: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        var seen = Set<SidebarModel.Key>()
        for r in m.rows {
            seen.insert(r.key)
            let hovered = hover == .row(r.key)
            let opacity: Float = r.dragSource ? 0 : 1
            if let layer = rowLayers[r.key] {
                let returning = leaving.removeValue(forKey: r.key) != nil
                layer.update(r, palette: palette, hovered: hovered, animated: animated)
                if animated {
                    if layer.position.y != r.y { layer.spring("position.y", to: r.y, TK.CA.layout) }
                    if returning {
                        // Back before it finished leaving: it enters again (dc:1827).
                        layer.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: opacity), forKey: "opacity")
                        layer.opacity = opacity
                    } else if layer.opacity != opacity {
                        layer.animate("opacity", to: opacity, TK.CA.fadeOutT)   // the drag source, 150 ms ease-out (css:118)
                    }
                } else {
                    layer.removeAllAnimations()
                    layer.position = CGPoint(x: SB.rowX, y: r.y)
                    layer.opacity = opacity
                }
            } else {
                let layer = SidebarRowLayer()
                layer.position = CGPoint(x: SB.rowX, y: r.y)
                layer.update(r, palette: palette, hovered: hovered, animated: false)
                layer.setScaleDeep(scale)
                host.insertSublayer(layer, at: 0)
                rowLayers[r.key] = layer
                layer.opacity = opacity
                if animated {
                    layer.add(TK.CA.basic("opacity", TK.CA.fadeInT, from: 0, to: opacity), forKey: "opacity")
                }
            }
        }
        for (key, layer) in rowLayers where !seen.contains(key) && leaving[key] == nil {
            if animated {
                // It fades out where it was while the rows below close up (css:159–162), and goes after
                // MOTION_WINDOW_MS (dc:1829).
                leaveToken += 1
                let token = leaveToken
                leaving[key] = token
                layer.animate("opacity", to: Float(0), TK.CA.fadeOutT)
                DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.motionWindow) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.leaving[key] == token else { return }
                        self.leaving[key] = nil
                        let gone = self.rowLayers.removeValue(forKey: key)
                        gone?.setInstant { gone?.removeFromSuperlayer() }
                    }
                }
            } else {
                layer.removeFromSuperlayer()
                rowLayers[key] = nil
            }
        }
        if !animated {
            for (key, _) in leaving {
                rowLayers[key]?.removeFromSuperlayer()
                rowLayers[key] = nil
            }
            leaving.removeAll()
        }

        // Labels: always "Lists"; "Archive" only when something is archived. They appear in place and move with the rows.
        if labelsDark != palette.isDark {
            labelsDark = palette.isDark
            listsLabel.setPalette(palette)
            archiveLabel.setPalette(palette)
            listsLabel.setScaleDeep(scale)
            archiveLabel.setScaleDeep(scale)
        }
        place(listsLabel, y: m.listsLabelY, animated: animated)
        if let y = m.archiveLabelY {
            if archiveLabelShown { place(archiveLabel, y: y, animated: animated) } else {
                archiveLabel.removeAllAnimations()
                archiveLabel.position = CGPoint(x: SB.rowX, y: y)
            }
            archiveLabel.isHidden = false
            archiveLabelShown = true
        } else {
            archiveLabel.isHidden = true
            archiveLabelShown = false
        }
        archiveLabel.setChevron(open: m.archiveOpen, animated: animated)
        updateReveals(animated: animated)
    }

    private func place(_ label: SidebarLabelLayer, y: CGFloat, animated: Bool) {
        if animated, label.position.y != y {
            label.spring("position.y", to: y, TK.CA.layout)
        } else if !animated {
            label.removeAnimation(forKey: "position.y")
        }
        label.position = CGPoint(x: SB.rowX, y: y)
    }

    /// The + shows while "Lists" is hovered; the chevron while "Archive" is hovered or the group is open.
    private func updateReveals(animated: Bool = true) {
        listsLabel.button.reveal(hover == .label(.lists), animated: animated)
        archiveLabel.button.reveal(hover == .label(.archive) || model.archiveOpen, animated: animated)
    }

    // MARK: - The rename field (§7, §12; css:119–120)

    private func syncField() {
        guard let id = model.renaming, let row = model.row(.list(id)), row.editing else {
            if field != nil { removeField() }
            return
        }
        if fieldID != id {
            if field != nil { removeField() }
            let f = InlineField(frame: .zero)
            f.font = TK.Font.body
            f.textColor = palette.ink
            f.stringValue = ui.rename?.text ?? ""
            f.placeholderAttributedString = NSAttributedString(string: "New List", attributes: [.font: TK.Font.body, .foregroundColor: palette.ink3])
            f.cell?.usesSingleLineMode = true
            f.setAccessibilityLabel("List name")
            f.onChange = { [weak self] text in self?.actions.setRenameText(text) }
            f.onKey = { [weak self] key in self?.fieldKey(key) ?? false }
            f.onEnd = { [weak self] _ in
                // A press elsewhere or the keys moving away commit it (dc:1585). Next turn, so the commit never runs inside
                // the responder change that ended the edit.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.ui.rename?.kind == .list, self.ui.rename?.id == id else { return }
                        self.actions.commitRename()
                    }
                }
            }
            f.wantsLayer = true
            f.layer?.zPosition = 10
            content.addSubview(f)
            field = f
            fieldID = id
            placeField(f, rowY: row.y)
            content.scrollToVisible(rowRect(row.y))
            f.focus(.all)
            if let editor = f.currentEditor() as? NSTextView {
                editor.selectedTextAttributes = [.backgroundColor: palette.textSel]
                editor.insertionPointColor = palette.ink
            }
        } else if let f = field {
            placeField(f, rowY: row.y)
            if f.textColor != palette.ink {
                f.textColor = palette.ink
                f.placeholderAttributedString = NSAttributedString(string: "New List", attributes: [.font: TK.Font.body, .foregroundColor: palette.ink3])
            }
        }
    }

    /// `.ri`: from 7 after the tile to 10 short of the capsule's end, its 13/16 line centered in the 30pt row. The
    /// field draws its text 2pt in (the cell's inset), so it starts 2pt early; with a 17pt frame 7 down, its text lands
    /// on the title's pixels (measured on a 2x snapshot).
    private func placeField(_ f: InlineField, rowY: CGFloat) {
        let inset = Self.fieldTextInset
        let h = Self.fieldHeight
        let x = SB.rowX + SB.titleX - inset.x
        let frame = CGRect(x: x, y: rowY + 7 - inset.y, width: SB.rowX + SB.rowWidth - SB.fieldRightPad - x, height: h)
        if f.frame != frame { f.frame = frame }
    }

    /// Where an `NSTextField` draws its first line relative to its frame, so the field's text lands on the CSS line box.
    static let fieldTextInset = CGPoint(x: 2, y: 0)
    static let fieldHeight: CGFloat = 17

    private func removeField() {
        guard let f = field else { return }
        let hadKeys = f.isEditing
        field = nil
        fieldID = nil
        f.onEnd = nil
        f.onKey = nil
        f.onChange = nil
        f.abortEditing()
        f.removeFromSuperview()
        if hadKeys || window?.firstResponder === window {
            if ui.focus == .sidebar { takeKeys() }
        }
    }

    /// Return, Tab, ⇧Tab and ⌘Return commit and hand the keys back (a new list opens with the list focused); Esc puts the
    /// old name back (dc:1590–1598).
    private func fieldKey(_ key: InlineField.Key) -> Bool {
        let a = actions
        switch key {
        case .returnKey, .tab, .backtab, .commandReturn:
            a.commitRename()
            if ui.focus == .sidebar { a.focus(.sidebar) }
        case .escape:
            a.cancelRename()
        }
        return true
    }

    // MARK: - Hover (§18.2: one tracker for the whole sidebar)

    /// The row or label at a point in the content: rows and labels by their boxes, then each 2pt gap split 1/1.
    private func hit(at p: CGPoint) -> Hit? {
        guard p.x >= SB.rowX, p.x < SB.rowX + SB.rowWidth else { return nil }
        if let r = model.rows.first(where: { p.y >= $0.y && p.y < $0.y + SB.rowHeight }) { return .row(r.key) }
        if p.y >= model.listsLabelY && p.y < model.listsLabelY + SB.labelHeight { return .label(.lists) }
        if let a = model.archiveLabelY, p.y >= a && p.y < a + SB.labelHeight { return .label(.archive) }
        let gap = (TK.M.pitch - SB.rowHeight) / 2
        if let r = model.rows.first(where: { p.y >= $0.y - gap && p.y < $0.y + SB.rowHeight + gap }) { return .row(r.key) }
        return nil
    }

    private func labelY(_ l: Label) -> CGFloat? { l == .lists ? model.listsLabelY : model.archiveLabelY }

    private func buttonRect(_ l: Label) -> CGRect? {
        guard let y = labelY(l) else { return nil }
        return SB.buttonFrame.offsetBy(dx: SB.rowX, dy: y)
    }

    /// The Archive label's text button (`.gl`, dc:31): from the text's left to the label's end, 14 tall.
    private func archiveTextRect() -> CGRect? {
        guard let y = model.archiveLabelY else { return nil }
        return CGRect(x: SB.rowX + SB.labelTextX, y: y + SB.labelTextTop, width: SB.rowWidth - SB.labelTextX, height: 14)
    }

    func pointerMoved(to p: CGPoint?) {
        guard let p, canHover, isFrontmost(p) else { setHover(nil, button: nil); return }
        let h = hit(at: p)
        var b: Label?
        if case .label(let l)? = h, let r = buttonRect(l), r.contains(p) { b = l }
        setHover(h, button: b)
    }

    private var canHover: Bool {
        ui.sidebarVisible && ui.drag == nil && listDrag == nil
    }

    /// The pointer is over the sidebar and nothing covers it there (the panes slide over it when it hides; popovers).
    private func isFrontmost(_ p: CGPoint) -> Bool {
        guard let w = window, let frame = w.contentView?.superview else { return false }
        let wp = content.convert(p, to: nil)
        guard let v = frame.hitTest(wp) else { return false }
        return v === content || v.isDescendant(of: self)
    }

    /// The rows moved under a still pointer (a scroll, a render): hover follows them.
    func refreshHover() {
        guard let w = window, press == nil, candidate == nil else { return }
        let p = content.convert(w.mouseLocationOutsideOfEventStream, from: nil)
        pointerMoved(to: content.visibleRect.contains(p) ? p : nil)
    }

    private func setHover(_ h: Hit?, button b: Label?) {
        if h != hover {
            if case .row(let k)? = hover { rowLayers[k]?.setHovered(false) }
            hover = h
            if case .row(let k)? = h { rowLayers[k]?.setHovered(true) }
            updateReveals()
        }
        if b != hoverButton {
            if let old = hoverButton {
                label(old).button.hovered = false
                if old == .lists { ui.overlays.hideTip() }
            }
            hoverButton = b
            if let b {
                label(b).button.hovered = true
                // "New List ⇧⌘N" (dc:36); the chevron has none (§16).
                if b == .lists, let r = buttonRect(.lists).flatMap(windowTopLeftRect(fromContent:)) {
                    ui.overlays.hoverTip("New List", keys: "⇧⌘N", for: r, windowWidth: window?.contentView?.bounds.width ?? 1000)
                }
            }
        }
    }

    private func label(_ l: Label) -> SidebarLabelLayer { l == .lists ? listsLabel : archiveLabel }

    @objc private func clipScrolled(_ n: Notification) { refreshHover() }

    @objc private func windowResignedKey(_ n: Notification) {
        hideHints()
        cmdDown = false
        if let d = listDrag, !d.flying { endDrag(cancel: true) }
    }

    // MARK: - Presses (§12, §16; dc:1668–1706)

    func contentMouseDown(_ e: NSEvent) {
        let p = content.convert(e.locationInWindow, from: nil)
        ui.overlays.hideTip()
        if e.modifierFlags.contains(.control), let menu = contextMenu(at: p) {
            NSMenu.popUpContextMenu(menu, with: e, for: content)
            return
        }
        let a = actions
        switch hit(at: p) {
        case .row(let key)?:
            if let id = key.listID, model.renaming == id {
                // A press on the row being renamed, outside its field, ends the edit (dc:1311–1319).
                a.endEdits()
                a.focus(.sidebar)
                return
            }
            if e.clickCount >= 2 {
                // Double-click renames (Rex, preview.15); Today has no name to change.
                if let id = key.listID, model.row(key)?.draft == false { a.startListRename(id) }
                return
            }
            // A row opens on mouse-down, instantly, and the sidebar takes the keys (§12). The current row only focuses.
            a.endEdits()
            if key != model.current { a.go(key.route, focus: .sidebar) } else { a.focus(.sidebar) }
            candidate = Candidate(key: key, start: localPoint(e))
        case .label(let l)?:
            a.endEdits()
            a.focus(.sidebar)
            if let r = buttonRect(l), r.contains(p) {
                press = (l, r)
                label(l).button.pressed = true
            } else if l == .archive, let r = archiveTextRect(), r.contains(p) {
                press = (l, r)
            }
        case nil:
            a.endEdits()
            a.focus(.sidebar)
        }
    }

    func contentMouseDragged(_ e: NSEvent) {
        if let d = listDrag {
            if !d.flying { updateDrag(e) }
            return
        }
        if press != nil {
            pointerMoved(to: content.convert(e.locationInWindow, from: nil))
            return
        }
        guard let c = candidate, case .list(let id) = c.key, model.renaming != id,
              let row = model.row(c.key), !row.archived, !row.draft,
              store.projection.activeLists.ids.contains(id) else { return }
        // After 4pt of vertical movement the list lifts (dc:1679–1686).
        if abs(localPoint(e).y - c.start.y) >= TK.M.dragSlop { beginDrag(c, id: id, e) }
    }

    func contentMouseUp(_ e: NSEvent) {
        candidate = nil
        if let d = listDrag {
            if !d.flying { endDrag(cancel: false) }
            return
        }
        if let pr = press {
            press = nil
            if pr.rect.contains(content.convert(e.locationInWindow, from: nil)) {
                if pr.label == .lists {
                    label(.lists).button.pressed = false
                    actions.newList()
                } else {
                    label(.archive).button.pressed = false
                    ui.archiveOpen.toggle()
                }
            } else {
                label(pr.label).button.pressed = false
            }
        }
        refreshHover()
    }

    /// Right-click (§15): a list's menu (it doesn't open the list), none for Today, "New List" on the empty space and
    /// the labels (dc:1692–1704).
    func contextMenu(at p: CGPoint) -> NSMenu? {
        let a = actions
        ui.overlays.hideTip()
        candidate = nil
        a.endEdits()
        a.focus(.sidebar)
        switch hit(at: p) {
        case .row(.today)?:
            return nil
        case .row(.list(let id))?:
            guard store.projection.list(id) != nil else { return nil }
            return Menus.list(id, actions: a)
        default:
            return Menus.sidebarEmpty(actions: a)
        }
    }

    // MARK: - List drag (§14 last paragraph, dc:1262–1300)

    private func beginDrag(_ c: Candidate, id: EntityID, _ e: NSEvent) {
        let stored = store.projection.activeLists.ids
        guard let i = stored.firstIndex(of: id), let row = model.row(c.key) else { candidate = nil; return }
        let a = actions
        a.endEdits()
        ui.overlays.hideTip()
        ui.overlays.picker = nil
        let rowTop = TK.M.sidebarTop + row.y - scrollY
        listDrag = ListDrag(id: id, offY: c.start.y - rowTop, from: i, target: i)
        candidate = nil
        setHover(nil, button: nil)
        ui.drag = .init(kind: .list(id), target: i)

        let name = store.projection.listModel(id)?.name ?? ""
        let copy = SidebarLiftLayer(name: name, monogram: SB.monogram(name), slot: row.slot, palette: palette)
        copy.setScaleDeep(window?.backingScaleFactor ?? 2)
        let parent = ui.dragOverlay?.layer ?? layer
        copy.setInstant { parent?.addSublayer(copy) }
        lift = copy
        render()
        updateDrag(e)
    }

    /// The copy follows the pointer vertically at x 10, kept 6pt past the first and last list; the target is the
    /// nearest slot (dc:1271–1285).
    private func updateDrag(_ e: NSEvent) {
        guard var d = listDrag else { return }
        let p = localPoint(e)
        let n = max(1, store.projection.activeLists.ids.count)
        let top = TK.M.sidebarTop + model.listTop - scrollY
        let y = min(max(p.y - d.offY, top - 6), top + CGFloat(n - 1) * TK.M.pitch + 6)
        let target = min(max(Int(((y - top) / TK.M.pitch).rounded()), 0), n - 1)
        moveLift(toY: y, animated: false)
        if target != d.target {
            d.target = target
            listDrag = d
            ui.drag?.target = target
            render()
        }
    }

    /// The drop flies to its slot (160 ms, cubic-bezier(0.2, 0.8, 0.2, 1)) and the order is written at 170 ms; Esc
    /// flies it back and writes nothing (dc:1286–1300).
    private func endDrag(cancel: Bool) {
        guard var d = listDrag, !d.flying else { return }
        let to = cancel ? d.from : d.target
        d.target = to
        d.flying = true
        listDrag = d
        ui.drag?.target = to
        ui.drag?.phase = .fly
        render()
        let ty = TK.M.sidebarTop + model.listTop + CGFloat(to) * TK.M.pitch - scrollY
        moveLift(toY: ty, animated: true)
        let id = d.id, from = d.from
        DispatchQueue.main.asyncAfter(deadline: .now() + TK.Timer.fly) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !cancel && to != from { self.actions.moveList(id, to: to) }
                let copy = self.lift
                copy?.setInstant { copy?.removeFromSuperlayer() }
                self.lift = nil
                self.listDrag = nil
                self.ui.drag = nil
                self.render()
            }
        }
    }

    /// The copy's top-left at sidebar y `y` (window points from the top), x 10.
    private func moveLift(toY y: CGFloat, animated: Bool) {
        guard let lift else { return }
        var pt = CGPoint(x: SB.rowX, y: y)
        if let overlay = ui.dragOverlay, lift.superlayer === overlay.layer {
            pt = overlay.convert(pt, from: self)
        }
        if animated && !TK.CA.reduce {
            lift.animate("position", to: NSValue(point: pt), TK.CA.flightT)
        } else {
            lift.setInstant {
                lift.removeAnimation(forKey: "position")
                lift.position = pt
            }
        }
    }

    // MARK: - Keys (§12 Sidebar keys, dc:1433–1448; §21: Space, ⌘K and ⌘T act on the selected tasks)

    override func keyDown(with e: NSEvent) {
        if !sidebarKey(e) { super.keyDown(with: e) }
    }

    private func sidebarKey(_ e: NSEvent) -> Bool {
        if let d = listDrag {
            if e.keyCode == 53, !d.flying { endDrag(cancel: true) }
            return true
        }
        let a = actions
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command) || flags.contains(.control)
        let alt = flags.contains(.option)
        let shift = flags.contains(.shift)
        let keys = model.keys
        let cur = model.current
        let i = keys.firstIndex(of: cur) ?? -1
        switch e.keyCode {
        case 125, 126:   // ↓ ↑
            if alt && cmd {
                if let id = cur.listID { a.moveListBy(id, e.keyCode == 126 ? -1 : 1) }
                return true
            }
            let next = e.keyCode == 125 ? i + 1 : i - 1
            if e.keyCode == 125 ? i < keys.count - 1 : i > 0 {
                revealCurrent = true
                a.go(keys[next].route, focus: .sidebar)
            }
            a.focus(.sidebar)
            return true
        case 36, 76:     // Return, Enter
            if let id = cur.listID, model.row(cur) != nil { a.startListRename(id) }
            return true
        case 124, 53, 48:   // → Esc Tab ⇧Tab: back to the list
            a.focus(.list)
            return true
        case 49:         // Space
            a.toggleComplete()
            return true
        case 51 where cmd:   // ⌘⌫ archives the open list (the menu usually has it first)
            if let id = cur.listID { a.archive(list: id) }
            return true
        case 115, 119:   // Home, End
            a.moveSelection(e.keyCode == 115 ? .first : .last, extend: shift)
            return true
        case 116, 121:   // Page Up, Page Down scroll the task list a page, the selection staying
            // TODO(task list): forwarded to the list's own keys until it has a page-scroll API; the sidebar keeps focus.
            ui.taskList?.keyDown(with: e)
            if ui.focus != .sidebar { a.focus(.sidebar) } else { takeKeys() }
            return true
        default:
            break
        }
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if cmd && !alt && chars == "k" { a.toggleComplete(); return true }
        if cmd && !alt && !shift && chars == "a" { a.selectAll(); return true }
        if cmd && !alt && chars == "t" { a.setDate(nil, .when, a.today); return true }
        if !cmd && !alt, let s = e.characters, s.count == 1, let ch = s.first, ch.isLetter || ch.isNumber {
            a.typeSelect(String(ch), inSidebar: true)
            return true
        }
        return false
    }

    /// ⌘A from the sidebar selects every open task and gives the list the keys (dc:1388).
    override func selectAll(_ sender: Any?) { actions.selectAll() }

    // MARK: - Held ⌘: ⌘1–⌘9 in place of the counts after 450 ms; any key or letting go hides them (§12, dc:1336–1340)

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            MainActor.assumeIsolated { self?.hintEvent(e) }
            return e
        }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        cmdTimer?.invalidate()
        cmdTimer = nil
    }

    private func hintEvent(_ e: NSEvent) {
        guard e.window === window else { return }
        if e.type == .flagsChanged {
            let cmd = e.modifierFlags.contains(.command)
            if cmd && !cmdDown {
                cmdDown = true
                cmdTimer?.invalidate()
                cmdTimer = Timer.scheduledTimer(withTimeInterval: TK.Timer.hintHold, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.cmdTimer = nil
                        if !self.ui.cmdHints { self.ui.cmdHints = true }
                    }
                }
                return
            }
            cmdDown = cmd
        }
        hideHints()
    }

    private func hideHints() {
        cmdTimer?.invalidate()
        cmdTimer = nil
        if ui.cmdHints { ui.cmdHints = false }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Accessibility (§18.15)

    struct AXRow {
        let key: SidebarModel.Key
        let name: String
        let count: String
        let frame: CGRect
        let selected: Bool
    }

    var accessibilityRows: [AXRow] {
        model.rows.filter { !$0.draft }.sorted { $0.y < $1.y }.map { r in
            AXRow(key: r.key, name: r.key == .today ? "Today" : r.name, count: r.hint ? "" : r.count, frame: rowRect(r.y), selected: r.current)
        }
    }

    func accessibilityPress(_ key: SidebarModel.Key) {
        actions.go(key.route, focus: .sidebar)
    }

    var labelFrames: (lists: CGRect, archive: CGRect?) {
        (CGRect(x: SB.rowX, y: model.listsLabelY, width: SB.rowWidth, height: SB.labelHeight),
         model.archiveLabelY.map { CGRect(x: SB.rowX, y: $0, width: SB.rowWidth, height: SB.labelHeight) })
    }

    func accessibilityNewList() { actions.newList() }
    func accessibilityToggleArchive() { ui.archiveOpen.toggle() }

    #if DEBUG
    /// For the debug script: what's on screen, by presentation values.
    var debugState: String {
        var out: [String] = []
        let p = store.projection
        for (key, layer) in rowLayers.sorted(by: { $0.value.position.y < $1.value.position.y }) {
            let pres = layer.presentation() ?? layer
            let name: String
            switch key {
            case .today: name = "Today"
            case .list(let id): name = p.list(id)?.name ?? "draft"
            }
            let tc = pres.sublayers?.compactMap { $0 as? TextLayer }.first?.presentation()?.foregroundColor
            out.append("\(name) y=\(String(format: "%.1f", pres.position.y)) op=\(String(format: "%.2f", pres.opacity))\(leaving[key] != nil ? " leaving" : "") title=\(tc.map { NSColor(cgColor: $0)?.description ?? "" } ?? "")")
        }
        out.append("label Lists y=\(listsLabel.presentation()?.position.y ?? listsLabel.position.y) Archive y=\(archiveLabel.presentation()?.position.y ?? archiveLabel.position.y) hidden=\(archiveLabel.isHidden) chevron=\(archiveLabel.button.glyph.presentation()?.value(forKeyPath: "transform.rotation.z") ?? 0) reveal=\(listsLabel.button.presentation()?.opacity ?? 0)/\(archiveLabel.button.presentation()?.opacity ?? 0)")
        if let lift { out.append("lift y=\((lift.presentation() ?? lift).position.y) x=\((lift.presentation() ?? lift).position.x)") }
        out.append("route=\(ui.route.listID.flatMap { p.list($0)?.name } ?? "Today") sel=\(ui.selection.count) hover=\(String(describing: hover)) button=\(String(describing: hoverButton)) drag=\(String(describing: ui.drag)) hints=\(ui.cmdHints) rename=\(String(describing: ui.rename)) focus=\(ui.focus) fr=\(window?.firstResponder.map { "\(type(of: $0))" } ?? "-")")
        if let f = field { out.append("field frame=\(f.frame) text='\(f.stringValue)'") }
        return out.joined(separator: "\n")
    }

    func debugHover(at windowTopLeft: CGPoint?) {
        pointerMoved(to: windowTopLeft.flatMap(contentPoint(fromWindowTopLeft:)))
    }
    #endif
}

// MARK: - The scrolled content: hover tracking, presses, menus and the accessibility list

final class SidebarContentView: FlippedLayerView {
    weak var owner: SidebarView?
    private var tracking: NSTrackingArea?
    private var axElements: [NSAccessibilityElement] = []

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { owner?.pointerMoved(to: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { owner?.pointerMoved(to: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { owner?.pointerMoved(to: nil) }
    override func mouseDown(with event: NSEvent) { owner?.contentMouseDown(event) }
    override func mouseDragged(with event: NSEvent) { owner?.contentMouseDragged(event) }
    override func mouseUp(with event: NSEvent) { owner?.contentMouseUp(event) }

    override func menu(for event: NSEvent) -> NSMenu? {
        owner?.contextMenu(at: convert(event.locationInWindow, from: nil))
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        owner?.pointerMoved(to: nil)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        owner?.refreshHover()
    }

    // The sidebar is a list; rows have their name as the label, the current one is selected, and pressing opens it.

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { "Lists" }
    override func accessibilityChildren() -> [Any]? { axElements }
    override func accessibilitySelectedChildren() -> [Any]? { axElements.filter { $0.isAccessibilitySelected() } }

    func rebuildAccessibility() {
        guard let owner else { return }
        var out: [NSAccessibilityElement] = []
        for r in owner.accessibilityRows {
            let el = SidebarAXElement(role: .row) { [weak owner] in owner?.accessibilityPress(r.key) }
            el.setAccessibilityLabel(r.name)
            if !r.count.isEmpty { el.setAccessibilityValue(r.count) }
            el.setAccessibilitySelected(r.selected)
            el.setAccessibilityFrameInParentSpace(r.frame)
            el.setAccessibilityParent(self)
            out.append(el)
        }
        let labels = owner.labelFrames
        let plus = SidebarAXElement(role: .button) { [weak owner] in owner?.accessibilityNewList() }
        plus.setAccessibilityLabel("New List")
        plus.setAccessibilityFrameInParentSpace(SB.buttonFrame.offsetBy(dx: labels.lists.minX, dy: labels.lists.minY))
        plus.setAccessibilityParent(self)
        out.insert(plus, at: min(1, out.count))
        if let a = labels.archive {
            let toggle = SidebarAXElement(role: .button) { [weak owner] in owner?.accessibilityToggleArchive() }
            toggle.setAccessibilityLabel("Show or hide archived lists")
            toggle.setAccessibilityFrameInParentSpace(a)
            toggle.setAccessibilityParent(self)
            out.append(toggle)
        }
        axElements = out
    }
}

final class SidebarAXElement: NSAccessibilityElement {
    private let onPress: () -> Void

    init(role: NSAccessibility.Role, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init()
        setAccessibilityRole(role)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

// MARK: - SwiftUI

struct SidebarRepresentable: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> SidebarView {
        let v = SidebarView(store: store, window: window, palette: palette)
        window.sidebarView = v
        return v
    }

    func updateNSView(_ nsView: SidebarView, context: Context) {
        if window.sidebarView !== nsView { window.sidebarView = nsView }
        nsView.setPalette(palette)
    }
}
