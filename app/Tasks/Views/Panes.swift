import SwiftUI
import TasksCore

/// Today: tasks whose `when` or deadline has arrived, grouped by list in sidebar order (spec §4).
struct TodayPane: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        let p = store.projection
        let isEmpty = window.quickAdd == nil && p.todayDone.ids.isEmpty
            && p.activeLists.ids.allSatisfy { p.todayTasks(in: $0).ids.isEmpty }
        PaneChrome("Today", systemImage: "sun.max", subtitle: DateText.header(p.dayModel.day.date),
                   isActive: window.focus == .list || window.detailTaskID == nil) {
            PaneActions(window: window, actions: actions)
        } content: {
            if isEmpty {
                TodayEmpty(actions: actions)
            } else {
                TaskListView(store: store, window: window, mode: .today)
                    .padding(.top, 2)
            }
        }
    }
}

struct TodayEmpty: View {
    let actions: WindowActions
    @Environment(\.pane) private var pane

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing for today.").font(PaneFont.headline).foregroundStyle(pane.ink)
            Text("Tasks show up here on their when date, or on their deadline if that comes first.")
                .font(PaneFont.subheadline)
                .foregroundStyle(pane.inkSecondary)
                .frame(maxWidth: 360, alignment: .leading)
            HStack(spacing: 8) {
                Button("New task") { actions.newTask() }.buttonStyle(.pane(.tinted))
                PaneKeyHint(text: "⌘N")
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22))
    }
}

/// The header actions every task pane shares: new task, details split, and a menu.
struct PaneActions: View {
    @Bindable var window: WindowState
    let actions: WindowActions
    var listID: EntityID? = nil

    var body: some View {
        PaneIconButton("plus", help: "New Task (⌘N)") { actions.newTask() }
        PaneIconButton("sidebar.right", help: window.detailTaskID == nil ? "Show Details (⌘D)" : "Hide Details (⌘D)") {
            actions.toggleDetail()
        }
        Menu {
            if let listID {
                Button("Rename…") { window.renamingList = listID }
                if actions.store.projection.list(listID)?.archivedAt == nil {
                    Button("Archive List") { actions.archive(list: listID) }
                } else {
                    Button("Unarchive") { actions.store.unarchive(list: listID, undoManager: window.undoManager) }
                }
                Divider()
            }
            Button("Sync Now") { actions.store.requestSync(force: true) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

/// A list screen: its open tasks in manual order, then a collapsed Completed section (spec §4). An archived list
/// opens here too, with a banner; nothing about it is read-only.
struct ListPane: View {
    let store: Store
    @Bindable var window: WindowState
    let listID: EntityID
    @Environment(\.pane) private var pane
    @FocusState private var renameFocused: Bool
    @State private var nameDraft = ""

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        if let list = store.projection.listModel(listID) {
            let count = store.projection.openTasks(in: listID).count
            PaneChrome(list.name.isEmpty ? "Untitled" : list.name,
                       subtitle: count == 0 ? "No tasks" : count == 1 ? "1 task" : "\(count) tasks",
                       isActive: window.focus == .list || window.detailTaskID == nil) {
                PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot), size: 16)
            } actions: {
                if list.isArchived { PaneChip(text: "Archived") }
                PaneActions(window: window, actions: actions, listID: listID)
            } content: {
                VStack(spacing: 0) {
                    if window.renamingList == listID {
                        renameField(list)
                    }
                    if let archivedAt = list.archivedAt {
                        ArchivedBanner(archivedAt: archivedAt) {
                            store.unarchive(list: listID, undoManager: window.undoManager)
                            window.route = .list(listID)
                        }
                    }
                    TaskListView(store: store, window: window, mode: .list(listID))
                        .padding(.top, 2)
                }
            }
        }
    }

    private func renameField(_ list: ListModel) -> some View {
        HStack(spacing: 8) {
            TextField("List name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(PaneFont.headline)
                .focused($renameFocused)
                .onSubmit { commitRename() }
                .onExitCommand { window.renamingList = nil }
            PaneKeyHint(text: "↩ Rename")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(pane.selected, in: RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous).strokeBorder(pane.focusRing, lineWidth: 2) }
        .padding(EdgeInsets(top: 4, leading: 12, bottom: 6, trailing: 12))
        .onAppear {
            nameDraft = list.name
            renameFocused = true
        }
        .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
    }

    private func commitRename() {
        guard window.renamingList == listID else { return }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { store.rename(list: listID, to: name, undoManager: window.undoManager) }
        window.renamingList = nil
    }
}

/// "Archived Apr 28 — its tasks stay out of Today and the sidebar. Everything still works here." + Unarchive.
struct ArchivedBanner: View {
    let archivedAt: Int
    let unarchive: () -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Archived \(Date(timeIntervalSince1970: TimeInterval(archivedAt) / 1000).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(PaneFont.body)
                    .foregroundStyle(pane.ink)
                Text("Its tasks stay out of Today and the sidebar. Everything still works here.")
                    .font(PaneFont.subheadline)
                    .foregroundStyle(pane.inkSecondary)
            }
            Spacer(minLength: 8)
            Button("Unarchive", action: unarchive).buttonStyle(.pane(.tinted))
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(pane.selected, in: RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous))
        .padding(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
    }
}

/// The Archive: archived lists, most recently archived first, each with Unarchive. The selected one opens beside
/// it as a normal list screen.
struct ArchivePane: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane

    var body: some View {
        let ids = store.projection.archivedLists.ids
        PaneChrome("Archive", systemImage: "archivebox", subtitle: ids.count == 1 ? "1 list" : "\(ids.count) lists",
                   isActive: window.archiveSelection == nil) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(ids, id: \.self) { id in
                        if let list = store.projection.listModel(id) {
                            archivedRow(list)
                        }
                    }
                    if ids.isEmpty {
                        Text("Nothing is archived.")
                            .font(PaneFont.subheadline)
                            .foregroundStyle(pane.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
            }
        }
    }

    private func archivedRow(_ list: ListModel) -> some View {
        let tasks = store.projection.openTasks(in: list.id).count + store.projection.completedTasks(in: list.id).count
        let date = list.archivedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000).formatted(.dateTime.month(.abbreviated).day()) } ?? ""
        return HStack(spacing: 10) {
            PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot))
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name.isEmpty ? "Untitled" : list.name).foregroundStyle(pane.ink)
                Text("\(tasks) \(tasks == 1 ? "task" : "tasks") · archived \(date)")
                    .font(PaneFont.subheadline)
                    .foregroundStyle(pane.inkSecondary)
            }
            Spacer(minLength: 8)
            Button("Unarchive") {
                store.unarchive(list: list.id, undoManager: window.undoManager)
                if window.archiveSelection == list.id { window.archiveSelection = nil }
            }
            .buttonStyle(.pane())
        }
        .font(PaneFont.body)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background {
            if window.archiveSelection == list.id {
                RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous).fill(pane.selected)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { window.archiveSelection = list.id }
    }
}

/// ⌘⇧M: move the selected tasks to an active list (⌘1–9), at its bottom.
struct MovePicker: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        let lists = store.projection.activeLists.ids
        let current = actions.targetIDs.compactMap { store.projection.task($0)?.list }
        VStack(alignment: .leading, spacing: 0) {
            PaneGroupLabel(text: "Move to").padding(EdgeInsets(top: 4, leading: 8, bottom: 6, trailing: 8))
            ForEach(Array(lists.enumerated()), id: \.element) { index, id in
                if let list = store.projection.listModel(id) {
                    PaneMenuItem(isHot: false, shortcut: index < 9 ? "⌘\(index + 1)" : nil) {
                        actions.move(to: id)
                    } label: {
                        PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot), size: 16)
                        Text(list.name.isEmpty ? "Untitled" : list.name)
                        if current.count == 1, current.first == id {
                            Text("current").font(PaneFont.subheadline).foregroundStyle(pane.inkQuiet)
                        }
                    }
                    .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : KeyEquivalent("0"),
                                      modifiers: index < 9 ? .command : [.command, .option, .control, .shift])
                }
            }
            PaneMenuSeparator()
            PaneMenuItem(isHot: false, shortcut: "esc") { window.movePickerPresented = false } label: { Text("Cancel") }
                .keyboardShortcut(.cancelAction)
        }
        .padding(6)
        .frame(width: 260)
        .background(pane.isDark ? pane.card : pane.base)
    }
}
