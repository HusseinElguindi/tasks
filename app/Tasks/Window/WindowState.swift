import AppKit
import SwiftUI
import TasksCore

/// Per-window UI state (design/INTERACTIONS-v2.md): navigation, selection, focus, the detail pane, the new-task
/// draft, inline renames, checked rows that wait, and the drag. Local, never synced. The prototype keeps the same
/// state in `Main.dc.html` dc:504–518.
///
/// Views read single properties, so Observation redraws only what depends on the one that changed. The AppKit lists
/// read it inside `withObservationTracking` and re-render on any change they read.
@MainActor
@Observable
final class WindowState {
    enum Route: Hashable {
        case today
        case list(EntityID)

        var listID: EntityID? {
            if case .list(let id) = self { id } else { nil }
        }
    }

    /// Rex's rule (§4): the pane last pressed in, or moved to with the keys. The sidebar has no focus look of its own;
    /// with it focused, both panes show unfocused.
    enum Focus: Hashable { case sidebar, list, detail }

    /// Where a checked or unchecked task is held until the rows settle (§8, dc:573).
    enum Pin: Equatable {
        /// Checked, still shown among the open tasks.
        case open
        /// Unchecked, still shown among the done ones, sorted by when it was completed.
        case done(completedAt: Int)
    }

    /// A new task before its title commits (§6, §18.4). It isn't in the store: no op, no undo step.
    struct Draft: Equatable {
        let id: EntityID
        var list: EntityID
        var title: String
        var when: CalendarDate?
        let createdAt: Int
        /// The selection and whether the detail pane was open before ⌘N, put back if the draft is dropped.
        var prevSelection: Set<EntityID>
        var prevPaneOpen: Bool
    }

    /// An inline rename in a task row or a sidebar row (§7). The field owns the text; `text` follows it so a list's
    /// tile letter can follow the typing (dc:2000).
    struct Rename: Equatable {
        enum Kind: Equatable { case task, list }
        enum Caret: Equatable { case all, end, at(Int) }
        var kind: Kind
        var id: EntityID
        var caret: Caret
        var text: String
        /// A new list that isn't created yet (§12 Create).
        var isNewList = false
        var colorSlot = 0
    }

    /// What the rows need to know about a drag in progress: which rows travel, and where the gap opens. The copy's
    /// position isn't here; the drag overlay moves it without a redraw.
    struct Drag: Equatable {
        enum Kind: Equatable {
            /// Task rows of one group (a list's open tasks, or one Today group).
            case tasks(ids: [EntityID], group: EntityID)
            /// A sidebar list.
            case list(EntityID)
        }
        enum Over: Equatable { case today, list(EntityID) }
        enum Phase: Equatable { case drag, fly, done }
        var kind: Kind
        var target: Int
        var over: Over?
        /// A task drag's pointer is over the sidebar, on a target or not: the copy stays a tag at the pointer and the
        /// group stays closed up the whole way across, so passing a row that takes no drop (the gap between two rows,
        /// a label, the task's own list) never snaps the copy back into the list for a frame (v2 feedback 7).
        var sidebar = false
        var phase: Phase = .drag
    }

    var route: Route = .today
    var selection: Set<EntityID> = []
    /// ⇧-click and ⇧↑↓ extend from the anchor; ↑↓ move from the cursor.
    @ObservationIgnored var anchor: EntityID?
    @ObservationIgnored var cursor: EntityID?
    var focus: Focus = .list
    var detailOpen = false
    var sidebarVisible = true
    /// The sidebar's and the detail pane's widths as set by their dividers, remembered across launches (v2 feedback
    /// 4); `PaneGeometry` fits them to the window.
    var sidebarWidth = PaneWidth.sidebar.stored
    var detailWidth = PaneWidth.detail.stored
    var completedOpen: Set<EntityID> = []
    var archiveOpen = false
    var pins: [EntityID: Pin] = [:]
    var draft: Draft?
    var rename: Rename?
    /// A text field in the detail pane is being edited (its title or notes): the menu commands that edit text stand
    /// down, and the others end the edit first (§17).
    var detailEditing: DetailField?
    enum DetailField: Equatable { case title, notes }
    /// Holding ⌘ for 450 ms shows ⌘1–⌘9 in the sidebar.
    var cmdHints = false
    var drag: Drag?
    /// Popovers, notices and tooltips: their own observable so they never redraw the panes.
    let overlays = Overlays()

    // Not observed: the AppKit views and timers.
    /// The colors for this window's appearance (set by RootView), for AppKit code that draws (menus' tiles).
    @ObservationIgnored var palette: TK.Palette = .dark
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored weak var nsWindow: NSWindow?
    @ObservationIgnored weak var taskList: TaskListView?
    @ObservationIgnored weak var sidebarView: SidebarView?
    @ObservationIgnored weak var dragOverlay: DragOverlayView?
    /// The detail pane's first responder when none of its fields is editing (Esc, Tab, arrows from there).
    @ObservationIgnored weak var detailKeySink: KeySinkView?
    /// The detail pane's When and Deadline chips, in window coordinates, for ⌘S / ⇧⌘D from there (§11).
    @ObservationIgnored var detailChipFrames: [Overlays.Picker.Field: CGRect] = [:]
    @ObservationIgnored var settleTimer: Timer?
    /// The last task layout and what it was built from (TaskLayout.make reuses it while they're unchanged).
    @ObservationIgnored var layoutCache: (inputs: TaskLayout.Inputs, layout: TaskLayout)?
    @ObservationIgnored var typeBuffer = ""
    @ObservationIgnored var typeAt: TimeInterval = 0
    /// The detail pane asks for the caret in its title (a new task, ⇧Tab from the notes): `.end` or `.all`.
    var titleFocusRequest: TitleFocus?
    struct TitleFocus: Equatable {
        enum Selection: Equatable { case end, all }
        var selection: Selection
        var token = UUID()
    }

    /// The list a new task goes to from here: the open list, or nil (Today decides, §6).
    var currentListID: EntityID? { route.listID }

    /// The detail pane is a split beside the list (or, under ~900pt, replaces it).
    var detailShown: Bool { detailOpen }
}

/// Window-level overlays (§11, §9, §16): the date popover, the notice and the tooltip.
@MainActor
@Observable
final class Overlays {
    struct Picker: Equatable {
        enum Field: Equatable { case when, deadline }
        var field: Field
        var ids: [EntityID]
        /// The anchor in window coordinates (top-left origin): the chip, or a row's right end.
        var anchor: CGRect
        var token = UUID()
    }

    struct Notice: Equatable {
        var id = UUID()
        var text: String
        var undo: Bool
        var leaving = false
    }

    struct Tip: Equatable {
        var text: String
        var keys: String
        /// Top-left in window coordinates.
        var origin: CGPoint
    }

    var picker: Picker?
    var notice: Notice?
    var tip: Tip?

    @ObservationIgnored var noticeTimer: Timer?
    @ObservationIgnored var noticeHovered = false
    @ObservationIgnored var tipTimer: Timer?
    @ObservationIgnored var lastTipClosed: TimeInterval = 0

    // MARK: Notices (§9): 5 s with Undo, 1.8 s without; hovering holds it, and it leaves 2 s after the pointer does.

    func showNotice(_ text: String, undo: Bool) {
        noticeTimer?.invalidate()
        if notice != nil, notice?.leaving == false {
            // A new notice replaces the text in place (no second entrance).
            notice?.text = text
            notice?.undo = undo
        } else {
            notice = Notice(text: text, undo: undo)
        }
        if !noticeHovered { armNotice(undo ? TK.Timer.notice : TK.Timer.noticeInfo) }
    }

    func armNotice(_ after: TimeInterval) {
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideNotice() }
        }
    }

    func hideNotice() {
        guard notice != nil, notice?.leaving == false else { return }
        notice?.leaving = true
        noticeTimer?.invalidate()
        let id = notice?.id
        noticeTimer = Timer.scheduledTimer(withTimeInterval: TK.Timer.noticeOut, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if self?.notice?.id == id { self?.notice = nil } }
        }
    }

    func noticeHover(_ inside: Bool) {
        noticeHovered = inside
        if inside { noticeTimer?.invalidate() } else if notice?.leaving == false { armNotice(TK.Timer.noticeRearm) }
    }

    // MARK: Tooltips (§16): 600 ms, at once within 600 ms of the last one closing; 6pt below the button, its left edge
    // 60pt left of the button's center, kept between 6 and the window's width − 160.

    func hoverTip(_ text: String, keys: String = "", for rect: CGRect, windowWidth: CGFloat) {
        tipTimer?.invalidate()
        let origin = CGPoint(x: min(max(rect.midX - 60, 6), windowWidth - 160), y: rect.maxY + 6)
        let tip = Tip(text: text, keys: keys, origin: origin)
        if Date.timeIntervalSinceReferenceDate - lastTipClosed < TK.Timer.tipWarm || self.tip != nil {
            self.tip = tip
        } else {
            tipTimer = Timer.scheduledTimer(withTimeInterval: TK.Timer.tipDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tip = tip }
            }
        }
    }

    func hideTip() {
        tipTimer?.invalidate()
        tipTimer = nil
        if tip != nil {
            tip = nil
            lastTipClosed = Date.timeIntervalSinceReferenceDate
        }
    }
}

struct WindowStateKey: FocusedValueKey { typealias Value = WindowState }
struct StoreKey: FocusedValueKey { typealias Value = Store }

extension FocusedValues {
    var windowState: WindowState? {
        get { self[WindowStateKey.self] }
        set { self[WindowStateKey.self] = newValue }
    }

    var store: Store? {
        get { self[StoreKey.self] }
        set { self[StoreKey.self] = newValue }
    }
}
