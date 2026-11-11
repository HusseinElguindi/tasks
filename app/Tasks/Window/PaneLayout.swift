import CoreGraphics
import Foundation

/// The window's panes, the one source of truth for which exist (T50, the user 2026-11-11: "the way panes work should
/// be like rex and tmux. dynamic panes, resizing, moving, etc. … i want to make sure we don't close this possibility").
///
/// Today it holds the list pane and, while it's open or closing, the detail pane. Each pane has a stable id. Closing a
/// pane doesn't take it out: it stays mounted, marked closing, while it slides away, and leaves a moment later by
/// `unmount` with the token the close handed out, with no transition. So what's drawn never depends on SwiftUI
/// finishing a removal transition, which it sometimes doesn't (the stuck detail pane, `Scripts/repro-stuck-detail.sh`).
/// Reopening a closing pane keeps it and voids that token.
///
/// Splitting, moving and more than one detail pane are not built: they'd be more entries (and, for splits in two
/// directions, a tree), placed by `PaneFrames`.
struct PaneLayout: Equatable, Sendable {
    struct ID: Hashable, Sendable, CustomStringConvertible {
        let raw: String
        static let list = ID(raw: "list")
        static let detail = ID(raw: "detail")
        var description: String { raw }
    }

    enum Kind: Hashable, Sendable { case list, detail }

    struct Pane: Identifiable, Equatable, Sendable {
        let id: ID
        let kind: Kind
        /// Set while the pane is closing: the token `unmount` must bring. Nil while it's open.
        var closing: Int?
        var isOpen: Bool { closing == nil }
    }

    /// Left to right. The list is always first and never closes (it's the window's main pane).
    private(set) var panes: [Pane] = [Pane(id: .list, kind: .list)]
    private var nextToken = 0

    func pane(_ id: ID) -> Pane? { panes.first { $0.id == id } }
    /// Open: on screen, or on its way. A closing pane isn't.
    func isOpen(_ id: ID) -> Bool { pane(id)?.isOpen == true }
    /// Drawn: open or closing.
    func isMounted(_ id: ID) -> Bool { pane(id) != nil }

    /// Opens `id` after `after` (or at the end). A closing pane opens again where it is, keeping its view. Returns
    /// whether anything changed.
    @discardableResult
    mutating func open(_ id: ID, kind: Kind, after: ID? = nil) -> Bool {
        if let i = panes.firstIndex(where: { $0.id == id }) {
            guard panes[i].closing != nil else { return false }
            panes[i].closing = nil
            return true
        }
        let pane = Pane(id: id, kind: kind)
        if let after, let i = panes.firstIndex(where: { $0.id == after }) { panes.insert(pane, at: i + 1) } else { panes.append(pane) }
        return true
    }

    /// Starts closing `id`: it stays mounted until `unmount(id, token:)` with the token returned. Nil if it isn't open,
    /// or is the list.
    mutating func close(_ id: ID) -> Int? {
        guard id != .list, let i = panes.firstIndex(where: { $0.id == id }), panes[i].closing == nil else { return nil }
        nextToken += 1
        panes[i].closing = nextToken
        return nextToken
    }

    /// Takes `id` out once its close has played, unless it opened again since (the token no longer matches).
    @discardableResult
    mutating func unmount(_ id: ID, token: Int) -> Bool {
        guard let i = panes.firstIndex(where: { $0.id == id }), panes[i].closing == token else { return false }
        panes.remove(at: i)
        return true
    }
}

/// Where each pane is drawn, from the window's width and the layout: one rect per pane, an opacity, and whether it
/// takes presses. A closing pane gets its open rect pushed off the trailing edge (as `.move(edge: .trailing)` did)
/// and no opacity, so it slides away with the spring the open/close runs on (`natural`, §4).
///
/// The cases are today's (§4, §29): the list alone; the list and the detail pane beside it; the detail pane zoomed over
/// the list (which keeps its width and fades); and, in a narrow window, the detail pane in the list's place.
struct PaneFrames: Equatable {
    struct Frame: Equatable {
        var rect: CGRect
        var opacity: Double
        var interactive: Bool
    }

    let list: Frame
    let detail: Frame?
    /// How far the detail pane slides in from (and out to): from its leading edge to the panes' trailing edge.
    let detailSlide: CGFloat

    /// - Parameters: the window's `width` and `height`; `lead`, the list's left edge (the sidebar's width, or the gutter);
    ///   `detailWidth`, the detail pane's width beside the list; `gutter`, the gap around and between panes.
    init(layout: PaneLayout, width: CGFloat, height: CGFloat, lead: CGFloat, detailWidth: CGFloat, gutter g: CGFloat,
         narrow: Bool, zoomed: Bool) {
        let detailOpen = layout.isOpen(.detail)
        let paneHeight = max(0, height - 2 * g)
        let alone = max(0, width - lead - g)                      // lead | pane | gutter
        let beside = max(0, width - lead - 2 * g - detailWidth)   // lead | list | gutter | detail | gutter
        let zoomed = zoomed && !narrow && detailOpen
        // The list keeps its width beside the detail pane under a zoom, so its rows don't reflow; a narrow window's
        // drill-in hides it where it was.
        let listWidth = zoomed || (detailOpen && !narrow) ? beside : alone
        let listHidden = detailOpen && (zoomed || narrow)
        list = Frame(rect: CGRect(x: lead, y: g, width: listWidth, height: paneHeight),
                     opacity: listHidden ? 0 : 1, interactive: !listHidden)
        guard let pane = layout.pane(.detail) else {
            detail = nil
            detailSlide = 0
            return
        }
        // Zoomed or narrow, it has the list's room as well; else its own width at the right.
        let full = (zoomed || narrow)
        let rect = full ? CGRect(x: lead, y: g, width: alone, height: paneHeight)
                        : CGRect(x: width - g - detailWidth, y: g, width: detailWidth, height: paneHeight)
        detailSlide = rect.width
        var shown = rect
        if !pane.isOpen { shown.origin.x += rect.width }
        detail = Frame(rect: shown, opacity: pane.isOpen ? 1 : 0, interactive: pane.isOpen)
    }
}
