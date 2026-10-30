import SwiftUI
import TasksCore
import UniformTypeIdentifiers

extension UTType {
    /// Dragged tasks: a JSON array of task ids (in-app only).
    static let taskIDs = UTType(exportedAs: "com.elguindi.tasks.task-ids")
    /// A dragged sidebar list: its id.
    static let listID = UTType(exportedAs: "com.elguindi.tasks.list-id")
}

/// Rex's session tabs: Today pinned, then the lists as capsule rows under a "Lists" label, then Archive (only when
/// something is archived) and New list at the bottom, with the sync state as the footer. Rows are navigation: their
/// titles rest in ink-secondary and brighten on hover (design/INTERACTIONS.md). Rex's metrics: 230pt wide, 30pt
/// capsules 10pt in from the left and 11pt from the right, on a 32pt pitch.
struct Sidebar: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane
    @State private var drop: SidebarDrop?

    var body: some View {
        let p = store.projection
        let actions = WindowActions(store: store, window: window)
        VStack(alignment: .leading, spacing: 2) {
            // The traffic lights and the sidebar toggle (drawn over everything by MainLayout) live in this band;
            // Today's capsule then spans 46–76, where Rex's first row sits.
            Color.clear.frame(height: 34)

            NavRow(window: window, item: .today, title: "Today", count: todayCount) {
                PaneListMark(monogram: "", color: pane.attention, systemImage: "sun.max")
            } action: {
                window.route = .today
            }

            SidebarGroupLabel(window: window, item: .listsLabel, text: "Lists", help: "New List ⇧⌘N") { actions.newList() }

            // 5pt of room inside the clip, taken back outside it, so an insertion line above the first list or below
            // the last isn't cut off.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(p.activeLists.ids, id: \.self) { id in
                        ListSidebarRow(store: store, window: window, listID: id, drop: $drop)
                    }
                }
                .padding(.vertical, 5)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.vertical, -5)

            Spacer(minLength: 0)

            if !p.archivedLists.ids.isEmpty {
                NavRow(window: window, item: .archive, title: "Archive", count: p.archivedLists.count) {
                    Image(systemName: "archivebox").font(.system(size: 13))
                } action: {
                    window.route = .archive
                    if window.archiveSelection.map({ p.list($0)?.archivedAt == nil }) ?? true {
                        window.archiveSelection = p.archivedLists.ids.first
                    }
                }
            }
            NavRow(window: window, item: .newList, title: "New list", count: nil) {
                Image(systemName: "plus").font(.system(size: 13))
            } action: {
                actions.newList()
            }
            SyncFooter(store: store)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 11))
        // Leaving the sidebar clears its hover, whatever exit a row may have missed.
        .onHover { inside in if !inside { window.sidebarHover.clear("left sidebar") } }
    }

    private var todayCount: Int {
        store.projection.activeLists.ids.reduce(0) { $0 + store.projection.todayTasks(in: $1).count }
    }
}

/// What the sidebar's hover region tracks.
enum SidebarItem: Hashable {
    case today, listsLabel, archive, newList
    case list(EntityID)
}

enum SidebarDrop: Equatable {
    /// Tasks dragged over a list: "Move to …".
    case tasks(EntityID)
    /// A list dragged in the sidebar: the insertion line goes above or below this list.
    case list(EntityID, above: Bool)
}

/// A group label that reveals its ⊕ on hover, as Rex's group headers do: the label in ink-tertiary at the rows' text
/// inset, the ⊕ in the rows' trailing-action slot. Used by the sidebar and by Today's groups.
struct SidebarGroupLabel: View {
    let window: WindowState
    var item: SidebarItem
    var text: String
    var help: String
    var action: () -> Void

    var body: some View {
        // Rex's group labels sit a little low in their slot: the baseline 27pt above the next row's middle.
        PaneGroupLabelRow(text: text, help: help, isHovered: window.sidebarHover.isHovered(item), action: action, labelOffset: 1)
            .padding(.leading, 12)
            .frame(height: PaneSize.row)
            .onHover { window.sidebarHover.update(item, inside: $0) }
            .onDisappear { window.sidebarHover.vanished(item) }
    }
}

/// A sidebar row whose hover and current state live in the window's sidebar flags.
struct NavRow<Leading: View>: View {
    let window: WindowState
    var item: SidebarItem
    var title: String
    var count: Int?
    @ViewBuilder var leading: Leading
    var action: () -> Void

    var body: some View {
        SidebarRow(title: title, count: count, isCurrent: window.sidebarCurrent.isOn(item), isHovered: window.sidebarHover.isHovered(item),
                   leading: { leading }, action: action)
            .onHover { window.sidebarHover.update(item, inside: $0) }
            .onDisappear { window.sidebarHover.vanished(item) }
    }
}

/// A Rex session row: a 30pt capsule holding the 20pt tile column, the title (7pt after it) and the trailing slot.
/// The title rests in ink-secondary and goes to ink on hover or when current; long titles fade out rather than ending
/// in "…". The count sits in the trailing slot, right-aligned with the ••• that replaces it on hover (overlaid by the
/// caller). The fill belongs to the current row alone (PaneSidebarRowStyle).
struct SidebarRow<Leading: View>: View {
    var title: String
    var count: Int?
    /// The count gives way to the row's ••• (it stays in the layout, hidden, so nothing is rebuilt).
    var countHidden = false
    var isCurrent: Bool
    var isHovered = false
    var isDropTarget = false
    var accessory: AnyView? = nil
    @ViewBuilder var leading: Leading
    var action: () -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                leading.frame(width: PaneSize.tile)
                // Rex sets row text 1pt above center (baseline 4pt below the row's middle).
                PaneFadingText(text: title)
                    .foregroundStyle(isDropTarget ? pane.accentText : (isCurrent || isHovered ? pane.ink : pane.inkSecondary))
                    .offset(y: -1)
                if let accessory { accessory }
                Text(verbatim: count.map { $0 > 0 ? "\($0)" : "" } ?? "")
                    .monospacedDigit()
                    .foregroundStyle(isDropTarget ? pane.accentText : pane.inkTertiary)
                    .padding(.trailing, 3.5)
                    .offset(y: -1)
                    .opacity(countHidden ? 0 : 1)
                    .frame(width: PaneSize.rowAction, alignment: .trailing)
            }
            .font(PaneFont.body)
            .padding(.leading, 10)
            .padding(.trailing, PaneSize.rowActionInset)
            .frame(height: PaneSize.row)
        }
        .buttonStyle(PaneSidebarRowStyle(isCurrent: isCurrent, isDropTarget: isDropTarget))
    }
}

/// A list in the sidebar: a drop target for tasks (they land at its bottom) and draggable to reorder lists.
struct ListSidebarRow: View {
    let store: Store
    @Bindable var window: WindowState
    let listID: EntityID
    @Binding var drop: SidebarDrop?
    @Environment(\.pane) private var pane

    /// Hover gets no fill (design/INTERACTIONS.md): the title brightens and the trailing ••• takes the count's place,
    /// as Rex reveals a session row's action. The current list keeps its ••• shown.
    var body: some View {
        if let list = store.projection.listModel(listID) {
            let item = SidebarItem.list(listID)
            let hovered = window.sidebarHover.isHovered(item)
            let targeted = drop == .tasks(listID)
            let isCurrent = window.sidebarCurrent.isOn(item)
            let showMenu = (isCurrent || hovered) && drop == nil
            SidebarRow(title: list.name.isEmpty ? "Untitled" : list.name,
                       count: store.projection.openTasks(in: listID).count, countHidden: showMenu,
                       isCurrent: isCurrent, isHovered: hovered, isDropTarget: targeted,
                       accessory: targeted ? AnyView(PaneChip(text: "Move to \(list.name)", systemImage: "arrow.right", kind: .accent)) : nil) {
                PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
            } action: {
                window.route = .list(listID)
            }
            .overlay(alignment: .trailing) {
                PaneRowMenu(visible: showMenu, live: hovered, help: "List Actions") {
                    Button("Rename…") { window.route = .list(listID); window.renamingList = listID }
                    Button("Archive List") { WindowActions(store: store, window: window).archive(list: listID) }
                }
                .padding(.trailing, PaneSize.rowActionInset)
            }
            .onHover { window.sidebarHover.update(item, inside: $0) }
            .onDisappear { window.sidebarHover.vanished(item) }
            .overlay(alignment: drop == .list(listID, above: true) ? .top : .bottom) {
                // Centered in the 2pt gap between rows.
                if case .list(listID, let above) = drop {
                    PaneInsertionLine().padding(.leading, 8).offset(y: above ? -5 : 5)
                }
            }
            .onDrag {
                window.sidebarHover.clear()
                window.dragged = .list(listID)
                let p = NSItemProvider()
                let data = Data(listID.utf8)
                p.registerDataRepresentation(forTypeIdentifier: UTType.listID.identifier, visibility: .all) { done in
                    done(data, nil)
                    return nil
                }
                return p
            } preview: {
                // The lifted list: a fill-strong capsule with shadow-lift.
                HStack(spacing: 7) {
                    PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
                    Text(list.name.isEmpty ? "Untitled" : list.name).font(PaneFont.body).foregroundStyle(pane.ink)
                }
                .padding(.horizontal, 10)
                .frame(width: PaneSize.sidebar - 21, height: PaneSize.row, alignment: .leading)
                .background(pane.strong, in: Capsule())
                .paneShadow(.lift, in: Capsule())
                .environment(\.pane, pane)
            }
            .onDrop(of: [.taskIDs, .listID], delegate: SidebarDropDelegate(listID: listID, store: store, window: window, drop: $drop))
            .contextMenu {
                Button("Rename…") { window.route = .list(listID); window.renamingList = listID }
                Button("Archive List") { WindowActions(store: store, window: window).archive(list: listID) }
            }
        }
    }

}

struct SidebarDropDelegate: DropDelegate {
    let listID: EntityID
    let store: Store
    let window: WindowState
    @Binding var drop: SidebarDrop?

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.taskIDs, .listID]) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if drop == .tasks(listID) || drop == .list(listID, above: true) || drop == .list(listID, above: false) { drop = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = drop
        drop = nil
        // Read the payload recorded when the drag started: a dragged List row's item provider is cancelled before an
        // async load of it completes.
        let dragged = window.dragged
        window.dragged = nil
        switch dragged {
        case .tasks(let ids):
            store.move(ids, to: listID, undoManager: window.undoManager)
            return true
        case .list(let id):
            guard id != listID, case .list(_, let above) = target else { return true }
            store.reorderLists([id], at: above ? .before(listID) : .after(listID), undoManager: window.undoManager)
            return true
        case nil:
            return false
        }
    }

    /// Only while one of our drags is live: SwiftUI calls dropUpdated again after performDrop.
    private func update(_ info: DropInfo) {
        switch window.dragged {
        case .tasks: drop = .tasks(listID)
        case .list: drop = .list(listID, above: info.location.y < 15)
        case nil: break
        }
    }
}

/// The sidebar footer: quiet when all is well, otherwise the one thing to know about sync.
struct SyncFooter: View {
    let store: Store
    @Environment(\.pane) private var pane
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let notice = store.notice {
                Button {
                    store.notice = nil
                } label: {
                    footer(notice, color: pane.attention, icon: "exclamationmark.triangle")
                }
                .buttonStyle(PanePressStyle())
                .help("Kept in rejected.jsonl in the data folder. Click to dismiss.")
            } else if let r = store.recovery {
                footer("Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())", color: pane.inkSecondary, icon: "arrow.triangle.2.circlepath")
            } else {
                switch store.syncState {
                case .off:
                    Button { openSettings() } label: { footer("Sync off · Set up in Settings", color: pane.inkQuiet, icon: "icloud.slash") }
                        .buttonStyle(PanePressStyle())
                case .idle, .syncing:
                    EmptyView()
                case .retrying(_, let reason):
                    footer("Offline · retrying", color: pane.inkSecondary, icon: "wifi.slash").help(reason)
                case .checkToken:
                    Button { openSettings() } label: { footer("Check sync token", color: pane.dangerText, icon: "key") }
                        .buttonStyle(PanePressStyle())
                case .failed(let message):
                    Button { openSettings() } label: { footer("Sync error", color: pane.dangerText, icon: "exclamationmark.octagon") }
                        .buttonStyle(PanePressStyle())
                        .help(message)
                }
            }
        }
        .padding(.top, 4)
    }

    private func footer(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(PaneFont.subheadline).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(minHeight: 22)
    }
}
