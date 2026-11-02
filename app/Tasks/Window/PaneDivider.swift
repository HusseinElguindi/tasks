import AppKit
import SwiftUI

/// The two widths the user can drag (v2 feedback 4), and where they're kept.
enum PaneWidth {
    case sidebar, detail

    var defaultWidth: CGFloat { self == .sidebar ? TK.M.sidebar : TK.M.detail }
    private var key: String { self == .sidebar ? "sidebarWidth" : "detailWidth" }

    var stored: CGFloat {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : defaultWidth
    }

    func store(_ w: CGFloat) {
        if w == defaultWidth { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(Double(w), forKey: key) }
    }
}

/// The panes' widths for a window width: the stored widths, fitted so the list pane keeps `listMin`. The sidebar wins
/// (it stays at its width down to `sidebarMin`), then the detail pane gives way down to `detailMin`; below that, or under
/// 900, the window is narrow and the detail pane replaces the list (A3's drill-in).
@MainActor
struct PaneGeometry {
    let width: CGFloat
    let sidebar: CGFloat
    let detail: CGFloat
    let narrow: Bool
    /// The list pane's left edge: the sidebar's width, or the gutter with the sidebar hidden.
    let lead: CGFloat

    init(width: CGFloat, window: WindowState) {
        let g = TK.M.gutter
        self.width = width
        sidebar = max(TK.M.sidebarMin, min(window.sidebarWidth, TK.M.sidebarMax, width - g - TK.M.listMin))
        lead = window.sidebarVisible ? sidebar : g
        // lead | list | gutter | detail | gutter
        let room = width - lead - 2 * g - TK.M.listMin
        narrow = width < TK.M.narrowWidth || room < TK.M.detailMin
        detail = narrow ? TK.M.detail : max(TK.M.detailMin, min(window.detailWidth, room))
    }

    /// The detail pane is beside the list (neither is zoomed, §29).
    func detailBeside(_ window: WindowState) -> Bool { window.detailOpen && !narrow && !window.zoomed }

    /// The list pane's width beside the detail pane: what it keeps under a zoomed detail pane (§29), so its rows don't
    /// reflow and it comes back as it was.
    var listWidth: CGFloat { max(TK.M.listMin, width - lead - 2 * TK.M.gutter - detail) }

    /// How far each divider can go: the sidebar until the list reaches its minimum (with the detail pane as it is), the
    /// detail pane likewise.
    func range(_ kind: PaneWidth, _ window: WindowState) -> ClosedRange<CGFloat> {
        let g = TK.M.gutter
        switch kind {
        case .sidebar:
            let beside = detailBeside(window) ? detail + g : 0
            return TK.M.sidebarMin...max(TK.M.sidebarMin, min(TK.M.sidebarMax, width - g - beside - TK.M.listMin))
        case .detail:
            return TK.M.detailMin...max(TK.M.detailMin, width - lead - 2 * g - TK.M.listMin)
        }
    }

    func current(_ kind: PaneWidth) -> CGFloat { kind == .sidebar ? sidebar : detail }
}

/// A divider: the sidebar's edge, or the gap between the list and the detail pane. No handle; the pointer turns into
/// the column-resize cursor over it (one way only at a limit, as `NSSplitView` does). Dragging resizes at once, with no
/// animation; a double-click springs back to the default width (`natural`). Widths are written when the drag ends.
struct PaneDividerRepresentable: NSViewRepresentable {
    let kind: PaneWidth
    let window: WindowState
    let geometry: PaneGeometry

    func makeNSView(context: Context) -> PaneDividerView {
        let v = PaneDividerView()
        v.kind = kind
        v.state = window
        v.geometry = geometry
        return v
    }

    func updateNSView(_ v: PaneDividerView, context: Context) {
        v.kind = kind
        v.state = window
        v.geometry = geometry
        v.window?.invalidateCursorRects(for: v)
    }
}

final class PaneDividerView: NSView {
    var kind = PaneWidth.sidebar
    weak var state: WindowState?
    var geometry: PaneGeometry?
    private var drag: (startX: CGFloat, startWidth: CGFloat)?

    /// Dragging the sidebar's edge right widens it; dragging the detail gap right narrows the detail pane.
    private var sign: CGFloat { kind == .sidebar ? 1 : -1 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }

    /// Both ways, or only the way that's left at a limit.
    private var cursor: NSCursor {
        guard let state, let g = geometry else { return .resizeLeftRight }
        let r = g.range(kind, state)
        let w = drag != nil ? (kind == .sidebar ? state.sidebarWidth : state.detailWidth) : g.current(kind)
        let canGrow = w < r.upperBound - 0.5, canShrink = w > r.lowerBound + 0.5
        // The pointer moves right to grow the sidebar, left to grow the detail pane.
        let right = sign > 0 ? canGrow : canShrink
        let left = sign > 0 ? canShrink : canGrow
        if #available(macOS 15, *) {
            return .columnResize(directions: left && right ? .all : left ? .left : right ? .right : .all)
        }
        return left && right ? .resizeLeftRight : left ? .resizeLeft : right ? .resizeRight : .resizeLeftRight
    }

    override func mouseDown(with event: NSEvent) {
        guard let state, let g = geometry else { return }
        if event.clickCount == 2 {
            drag = nil
            withAnimation(TK.Motion.natural) { set(kind.defaultWidth, state) }
            kind.store(kind.defaultWidth)
            cursor.set()
            return
        }
        drag = (event.locationInWindow.x, g.current(kind))
        cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, let g = geometry, let d = drag else { return }
        let r = g.range(kind, state)
        let w = (d.startWidth + sign * (event.locationInWindow.x - d.startX)).rounded()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { set(min(max(w, r.lowerBound), r.upperBound), state) }
        // Kept while the pointer runs past the divider at a limit (nothing else may set it during the drag).
        cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil, let state else { return }
        drag = nil
        kind.store(kind == .sidebar ? state.sidebarWidth : state.detailWidth)
        window?.invalidateCursorRects(for: self)
    }

    private func set(_ w: CGFloat, _ state: WindowState) {
        switch kind {
        case .sidebar: if state.sidebarWidth != w { state.sidebarWidth = w }
        case .detail: if state.detailWidth != w { state.detailWidth = w }
        }
    }

    // MARK: Accessibility: a splitter whose value is the width; increment and decrement move it 10pt.

    override func accessibilityLabel() -> String? { kind == .sidebar ? "Sidebar width" : "Details width" }
    override func accessibilityValue() -> Any? { geometry.map { NSNumber(value: Double($0.current(kind))) } }

    override func accessibilityPerformIncrement() -> Bool { nudge(10) }
    override func accessibilityPerformDecrement() -> Bool { nudge(-10) }

    private func nudge(_ dw: CGFloat) -> Bool {
        guard let state, let g = geometry else { return false }
        let r = g.range(kind, state)
        let w = min(max(g.current(kind) + dw, r.lowerBound), r.upperBound)
        set(w, state)
        kind.store(w)
        return true
    }
}
