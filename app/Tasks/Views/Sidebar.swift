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
/// something is archived) and New list at the bottom, with the sync state as the footer.
struct Sidebar: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane
    @State private var drop: SidebarDrop?

    var body: some View {
        let p = store.projection
        let actions = WindowActions(store: store, window: window)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                PaneIconButton("sidebar.left", help: "Hide Sidebar") {
                    withAnimation(PaneMotion.natural) { window.sidebarVisible = false }
                }
                .foregroundStyle(pane.inkSecondary)
            }
            .frame(height: 28)
            .padding(.bottom, 8)

            SidebarRow(title: "Today", count: todayCount, isCurrent: window.route == .today) {
                PaneListMark(monogram: "", color: pane.attention, systemImage: "sun.max")
            } action: {
                window.route = .today
            }

            PaneGroupLabel(text: "Lists")
                .padding(EdgeInsets(top: 12, leading: 8, bottom: 4, trailing: 8))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(p.activeLists.ids.enumerated()), id: \.element) { index, id in
                        ListSidebarRow(store: store, window: window, listID: id, isDefault: index == 0, drop: $drop)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)

            if !p.archivedLists.ids.isEmpty {
                SidebarRow(title: "Archive", count: p.archivedLists.count, isCurrent: window.route == .archive, dimmed: true) {
                    Image(systemName: "archivebox").font(.system(size: 13)).frame(width: 20)
                } action: {
                    window.route = .archive
                    if window.archiveSelection.map({ p.list($0)?.archivedAt == nil }) ?? true {
                        window.archiveSelection = p.archivedLists.ids.first
                    }
                }
            }
            SidebarRow(title: "New list", count: nil, isCurrent: false, dimmed: true) {
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

struct SidebarRow<Leading: View>: View {
    var title: String
    var count: Int?
    var isCurrent: Bool
    var dimmed = false
    var isDropTarget = false
    var accessory: AnyView? = nil
    @ViewBuilder var leading: Leading
    var action: () -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading
                Text(title).lineLimit(1).truncationMode(.tail)
                if let accessory { accessory }
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isDropTarget ? pane.accentText : (isCurrent ? pane.ink : pane.inkSecondary))
                }
            }
            .font(PaneFont.body)
            .foregroundStyle(isDropTarget ? pane.accentText : (dimmed && !isCurrent ? pane.inkSecondary : pane.ink))
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background {
                if isDropTarget {
                    Capsule().fill(pane.accentTint)
                        .overlay { Capsule().strokeBorder(pane.focusRing, lineWidth: 2) }
                } else if isCurrent {
                    Capsule().fill(pane.strong).paneShadow(.capsule, in: Capsule())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A list in the sidebar: a drop target for tasks (they land at its bottom) and draggable to reorder lists.
struct ListSidebarRow: View {
    let store: Store
    @Bindable var window: WindowState
    let listID: EntityID
    let isDefault: Bool
    @Binding var drop: SidebarDrop?
    @Environment(\.pane) private var pane
    @State private var hovering = false

    var body: some View {
        if let list = store.projection.listModel(listID) {
            let targeted = drop == .tasks(listID)
            SidebarRow(title: list.name.isEmpty ? "Untitled" : list.name, count: store.projection.openTasks(in: listID).count,
                       isCurrent: window.route == .list(listID), isDropTarget: targeted,
                       accessory: accessory(targeted: targeted, name: list.name)) {
                PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
            } action: {
                window.route = .list(listID)
            }
            .overlay(alignment: .leading) {
                if hovering && drop == nil { PaneGrip().offset(x: 1) }
            }
            .overlay(alignment: drop == .list(listID, above: true) ? .top : .bottom) {
                if case .list(listID, let above) = drop {
                    PaneInsertionLine().padding(.leading, 8).offset(y: above ? -6 : 6)
                }
            }
            .onHover { hovering = $0 }
            .onDrag {
                let p = NSItemProvider()
                let data = Data(listID.utf8)
                p.registerDataRepresentation(forTypeIdentifier: UTType.listID.identifier, visibility: .all) { done in
                    done(data, nil)
                    return nil
                }
                return p
            }
            .onDrop(of: [.taskIDs, .listID], delegate: SidebarDropDelegate(listID: listID, store: store, window: window, drop: $drop))
            .contextMenu {
                Button("Rename…") { window.route = .list(listID); window.renamingList = listID }
                Button("Archive List") { WindowActions(store: store, window: window).archive(list: listID) }
            }
        }
    }

    private func accessory(targeted: Bool, name: String) -> AnyView? {
        if targeted {
            return AnyView(PaneChip(text: "Move to \(name)", systemImage: "arrow.right", kind: .accent))
        }
        if isDefault {
            return AnyView(Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(pane.inkQuiet)
                .help("New tasks go to the first list")
                .accessibilityLabel("Default list for new tasks"))
        }
        return nil
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
                .buttonStyle(.plain)
                .help("Kept in rejected.jsonl in the data folder. Click to dismiss.")
            } else if let r = store.recovery {
                footer("Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())", color: pane.inkSecondary, icon: "arrow.triangle.2.circlepath")
            } else {
                switch store.syncState {
                case .off:
                    Button { openSettings() } label: { footer("Sync off · Set up in Settings", color: pane.inkQuiet, icon: "icloud.slash") }
                        .buttonStyle(.plain)
                case .idle, .syncing:
                    EmptyView()
                case .retrying(_, let reason):
                    footer("Offline · retrying", color: pane.inkSecondary, icon: "wifi.slash").help(reason)
                case .checkToken:
                    Button { openSettings() } label: { footer("Check sync token", color: pane.dangerText, icon: "key") }
                        .buttonStyle(.plain)
                case .failed(let message):
                    Button { openSettings() } label: { footer("Sync error", color: pane.dangerText, icon: "exclamationmark.octagon") }
                        .buttonStyle(.plain)
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
