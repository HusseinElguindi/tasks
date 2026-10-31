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
        /// The four views beside Today (§22): their rows are queries over the tasks (`TaskLayout.buildView`).
        case upcoming, undated, completed, trash
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
        /// In a list with headings, the end of a section (§23); nil is the bottom of the list.
        var anchor: Ordering.Anchor? = nil
    }

    /// An inline rename in a task row or a sidebar row (§7), a heading's row or the list's large title (§23). The field
    /// owns the text; `text` follows it so a list's tile letter can follow the typing (dc:2000).
    struct Rename: Equatable {
        enum Kind: Equatable { case task, list, heading, title }
        enum Caret: Equatable { case all, end, at(Int) }
        var kind: Kind
        var id: EntityID
        var caret: Caret
        var text: String
        /// A new list that isn't created yet (§12 Create).
        var isNewList = false
        var colorSlot = 0
        /// A new heading that isn't created yet (§23 Adding a heading): its row shows in `list` above `before` (the
        /// bottom when nil) until Return writes it; Esc or no name leaves nothing.
        var newHeading: NewHeading?
        struct NewHeading: Equatable {
            var list: EntityID
            var before: EntityID?
        }
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
        enum Over: Equatable { case today, list(EntityID), completed, trash }
        enum Phase: Equatable { case drag, fly, done }
        /// How the rows answer (§22): within a group (§14); onto any day in Upcoming; or not at all in Completed and
        /// Trash, where only the sidebar takes the drop.
        enum Mode: Equatable { case group, days, sidebarOnly }
        var kind: Kind
        var target: Int
        var over: Over?
        var mode: Mode = .group
        /// Upcoming: the day the dragged rows are laid out on (nil: at home, over a month or past a deadline).
        var toDay: CalendarDate?
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
    /// The pointer is over the sidebar's header row: the sync cloud shows even when synced or off (§26).
    var sidebarHeaderHovered = false
    /// The sidebar's header row has scrolled out of view: offline and stopped show in the title band (§26).
    var sidebarHeaderHidden = false
    /// The sidebar's and the detail pane's widths as set by their dividers, remembered across launches (v2 feedback
    /// 4); `PaneGeometry` fits them to the window.
    var sidebarWidth = PaneWidth.sidebar.stored
    var detailWidth = PaneWidth.detail.stored
    /// Lists whose "› Completed" row is open. Local like a heading's collapse, and kept across launches (v2 feedback 15).
    var completedOpen: Set<EntityID> = Set(UserDefaults.standard.stringArray(forKey: WindowState.completedOpenKey) ?? []) {
        didSet { if completedOpen != oldValue { UserDefaults.standard.set(completedOpen.sorted(), forKey: Self.completedOpenKey) } }
    }
    static let completedOpenKey = "completedOpenLists"
    /// Today's Completed group is collapsed (v2 feedback 15): local, kept across launches, never synced.
    var todayDoneCollapsed: Bool = UserDefaults.standard.bool(forKey: WindowState.todayDoneCollapsedKey) {
        didSet { if todayDoneCollapsed != oldValue { UserDefaults.standard.set(todayDoneCollapsed, forKey: Self.todayDoneCollapsedKey) } }
    }
    static let todayDoneCollapsedKey = "todayCompletedCollapsed"
    var archiveOpen = false
    var pins: [EntityID: Pin] = [:]
    var draft: Draft?
    var rename: Rename?
    /// A text field in the detail pane is being edited (its title or notes): the menu commands that edit text stand
    /// down, and the others end the edit first (§17).
    var detailEditing: DetailField?
    enum DetailField: Equatable { case title, notes }
    /// A list's or a heading's notes being edited in the list pane (§23): text-editing menu commands work there too.
    var paneNotes: NotesHost.Target?
    /// The list has scrolled 24pt: the band's own tile and title fade in (§23 On scroll).
    var titleScrolled = false
    /// Collapsed headings (§23): local to the Mac like a window's size, kept in UserDefaults by heading id, never synced.
    /// A new heading starts open.
    var collapsed: Set<EntityID> = Set(UserDefaults.standard.stringArray(forKey: WindowState.collapsedKey) ?? []) {
        didSet { if collapsed != oldValue { UserDefaults.standard.set(collapsed.sorted(), forKey: Self.collapsedKey) } }
    }
    static let collapsedKey = "collapsedHeadings"
    /// Holding ⌘ for 450 ms shows ⌘1–⌘9 in the sidebar.
    var cmdHints = false
    var drag: Drag?
    /// Upcoming and Undated (§22): bumped when an open task's dates or a list's open tasks change (`ViewDates`), so the
    /// views' rows are read again; and those rows as last read.
    var viewDatesRevision = 0
    @ObservationIgnored let viewDates = ViewDates()
    @ObservationIgnored var viewItemsCache: (key: ViewItems.CacheKey, items: ViewItems)?
    /// Popovers, notices and tooltips: their own observable so they never redraw the panes.
    let overlays = Overlays()

    // Not observed: the AppKit views and timers.
    /// The colors for this window's appearance (set by RootView), for AppKit code that draws (menus' tiles).
    @ObservationIgnored var palette: TK.Palette = .dark
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored weak var nsWindow: NSWindow?
    @ObservationIgnored weak var taskList: TaskListView?
    @ObservationIgnored weak var sidebarView: SidebarView?
    /// Opens the Settings window (set by the scene, which has `openSettings`).
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored private var syncIndicator: SyncIndicator?

    /// The window's sync indicator (§26), made on first use.
    func sync(_ store: Store) -> SyncIndicator {
        if let s = syncIndicator { return s }
        let s = SyncIndicator(store: store)
        syncIndicator = s
        return s
    }
    @ObservationIgnored weak var dragOverlay: DragOverlayView?
    /// The detail pane's first responder when none of its fields is editing (Esc, Tab, arrows from there).
    @ObservationIgnored weak var detailKeySink: KeySinkView?
    /// The detail pane's When and Deadline chips, in window coordinates, for ⌘S / ⇧⌘D from there (§11).
    @ObservationIgnored var detailChipFrames: [Overlays.Picker.Field: CGRect] = [:]
    @ObservationIgnored var settleTimer: Timer?
    /// The last task layout and what it was built from (TaskLayout.make reuses it while they're unchanged).
    @ObservationIgnored var layoutCache: (inputs: TaskLayout.Inputs, layout: TaskLayout)?
    /// The list pane's notes heights as last measured (§23): a heading's by its id, a list's by
    /// `TaskLayout.listNotesKey`. The list view measures its editors before each layout.
    @ObservationIgnored var noteHeights: [EntityID: CGFloat] = [:]
    @ObservationIgnored var typeBuffer = ""
    @ObservationIgnored var typeAt: TimeInterval = 0
    /// The detail pane asks for the caret in its title (a new task, ⇧Tab from the notes, editing a task from the list):
    /// `.end` or `.all`.
    var titleFocusRequest: TitleFocus?
    struct TitleFocus: Equatable {
        enum Selection: Equatable { case end, all }
        var selection: Selection
        /// Only this task's title takes it, so a request made as the selection changes waits for the new title instead
        /// of landing in the old one (nil: whichever title is showing).
        var id: EntityID?
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
        /// A second line in `ink-tertiary` (the sync cloud's, §26).
        var detail = ""
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

    /// `above`: over the control rather than under it (the sidebar's foot, at the window's bottom, §27).
    func hoverTip(_ text: String, detail: String = "", keys: String = "", for rect: CGRect, windowWidth: CGFloat, above: Bool = false) {
        tipTimer?.invalidate()
        // A long name ("New Task in" a 200-character list) is cut at 300pt, and the tip stays inside the window, by
        // its measured width (v2 feedback 16).
        let text = Menus.fit(text, width: 300, font: TK.Font.tooltip)
        func w(_ s: String) -> CGFloat { s.isEmpty ? 0 : ceil((s as NSString).size(withAttributes: [.font: TK.Font.tooltip]).width) }
        let width = max(w(text) + (keys.isEmpty ? 0 : 6 + w(keys)), w(detail)) + 14
        // One line is 22 tall (11/14 and 4 above and below); a detail adds 14.
        let height: CGFloat = detail.isEmpty ? 22 : 36
        let origin = CGPoint(x: max(6, min(max(rect.midX - 60, 6), windowWidth - width - 6)), y: above ? rect.minY - 6 - height : rect.maxY + 6)
        let tip = Tip(text: text, detail: detail, keys: keys, origin: origin)
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
