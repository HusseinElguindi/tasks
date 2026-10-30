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
/// titles rest in ink-secondary and brighten on hover (design/INTERACTIONS.md).
struct Sidebar: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane
    @State private var drop: SidebarDrop?
    @State private var listsLabelHovered = false

    var body: some View {
        let p = store.projection
        let actions = WindowActions(store: store, window: window)
        VStack(alignment: .leading, spacing: 4) {
            // The traffic lights and the sidebar toggle (drawn over everything by MainLayout) live in this row.
            Color.clear.frame(height: 28).padding(.bottom, 8)

            NavRow(title: "Today", count: todayCount, isCurrent: window.route == .today) {
                PaneListMark(monogram: "", color: pane.attention, systemImage: "sun.max")
            } action: {
                window.route = .today
            }

            // "Lists" reveals ⊕ on hover, as Rex's group headers do.
            HStack(spacing: 4) {
                PaneGroupLabel(text: "Lists")
                Spacer(minLength: 0)
                PaneIconButton("plus.circle", help: "New List ⇧⌘N") { actions.newList() }
                    .opacity(listsLabelHovered ? 1 : 0)
                    .allowsHitTesting(listsLabelHovered)
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 4))
            .frame(height: 30, alignment: .bottom)
            .contentShape(Rectangle())
            .paneHoverLinger($listsLabelHovered)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.activeLists.ids, id: \.self) { id in
                        ListSidebarRow(store: store, window: window, listID: id, drop: $drop)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)

            if !p.archivedLists.ids.isEmpty {
                NavRow(title: "Archive", count: p.archivedLists.count, isCurrent: window.route == .archive) {
                    Image(systemName: "archivebox").font(.system(size: 13)).frame(width: 20)
                } action: {
                    window.route = .archive
                    if window.archiveSelection.map({ p.list($0)?.archivedAt == nil }) ?? true {
                        window.archiveSelection = p.archivedLists.ids.first
                    }
                }
            }
            NavRow(title: "New list", count: nil, isCurrent: false) {
                Image(systemName: "plus").font(.system(size: 13)).frame(width: 20)
            } action: {
                actions.newList()
            }
            SyncFooter(store: store)
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
    }

    private var todayCount: Int {
        store.projection.activeLists.ids.reduce(0) { $0 + store.projection.todayTasks(in: $1).count }
    }
}

enum SidebarDrop: Equatable {
    /// Tasks dragged over a list: "Move to …".
    case tasks(EntityID)
    /// A list dragged in the sidebar: the insertion line goes above or below this list.
    case list(EntityID, above: Bool)
}

/// A sidebar row that tracks its own hover (with Rex's linger) and passes it to SidebarRow.
struct NavRow<Leading: View>: View {
    var title: String
    var count: Int?
    var isCurrent: Bool
    @ViewBuilder var leading: Leading
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        SidebarRow(title: title, count: count, isCurrent: isCurrent, isHovered: hovered, leading: { leading }, action: action)
            .paneHoverLinger($hovered)
    }
}

/// A 30pt capsule row: the title rests in ink-secondary and goes to ink on hover or when current; long titles fade out
/// rather than ending in "…". The fill belongs to the current row alone (PaneSidebarRowStyle).
struct SidebarRow<Leading: View>: View {
    var title: String
    var count: Int?
    var isCurrent: Bool
    var isHovered = false
    var isDropTarget = false
    var accessory: AnyView? = nil
    @ViewBuilder var leading: Leading
    var action: () -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading
                PaneFadingText(text: title)
                    .foregroundStyle(isDropTarget ? pane.accentText : (isCurrent || isHovered ? pane.ink : pane.inkSecondary))
                if let accessory { accessory }
                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isDropTarget ? pane.accentText : pane.inkSecondary)
                }
            }
            .font(PaneFont.body)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
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

    @State private var hovered = false

    /// Hover gets no fill (design/INTERACTIONS.md): the title brightens and the trailing ••• takes the count's place,
    /// as Rex reveals a session row's action. The current list keeps its ••• shown.
    var body: some View {
        if let list = store.projection.listModel(listID) {
            let targeted = drop == .tasks(listID)
            let isCurrent = window.route == .list(listID)
            let showMenu = (isCurrent || hovered) && drop == nil
            SidebarRow(title: list.name.isEmpty ? "Untitled" : list.name,
                       count: showMenu ? nil : store.projection.openTasks(in: listID).count,
                       isCurrent: isCurrent, isHovered: hovered, isDropTarget: targeted,
                       accessory: targeted ? AnyView(PaneChip(text: "Move to \(list.name)", systemImage: "arrow.right", kind: .accent)) : nil) {
                PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
            } action: {
                window.route = .list(listID)
            }
            .overlay(alignment: .trailing) {
                PaneRowMenu(visible: showMenu, help: "List Actions") {
                    Button("Rename…") { window.route = .list(listID); window.renamingList = listID }
                    Button("Archive List") { WindowActions(store: store, window: window).archive(list: listID) }
                }
                .padding(.trailing, 4)
            }
            .paneHoverLinger($hovered)
            .overlay(alignment: drop == .list(listID, above: true) ? .top : .bottom) {
                if case .list(listID, let above) = drop {
                    PaneInsertionLine().padding(.leading, 8).offset(y: above ? -6 : 6)
                }
            }
            .onDrag {
                let p = NSItemProvider()
                let data = Data(listID.utf8)
                p.registerDataRepresentation(forTypeIdentifier: UTType.listID.identifier, visibility: .all) { done in
                    done(data, nil)
                    return nil
                }
                return p
            } preview: {
                // The lifted list: a fill-strong capsule with shadow-lift.
                HStack(spacing: 8) {
                    PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
                    Text(list.name.isEmpty ? "Untitled" : list.name).font(PaneFont.body).foregroundStyle(pane.ink)
                }
                .padding(.horizontal, 8)
                .frame(width: 190, height: 30, alignment: .leading)
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
        let store = store, window = window, listID = listID
        if let provider = info.itemProviders(for: [.taskIDs]).first {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.taskIDs.identifier) { data, _ in
                guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
                Task { @MainActor in
                    store.move(ids, to: listID, undoManager: window.undoManager)
                }
            }
            return true
        }
        if let provider = info.itemProviders(for: [.listID]).first, case .list(_, let above) = target {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.listID.identifier) { data, _ in
                guard let data, let dragged = String(data: data, encoding: .utf8), dragged != listID else { return }
                Task { @MainActor in
                    store.reorderLists([dragged], at: above ? .before(listID) : .after(listID), undoManager: window.undoManager)
                }
            }
            return true
        }
        return false
    }

    private func update(_ info: DropInfo) {
        if info.hasItemsConforming(to: [.taskIDs]) {
            drop = .tasks(listID)
        } else {
            drop = .list(listID, above: info.location.y < 15)
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
