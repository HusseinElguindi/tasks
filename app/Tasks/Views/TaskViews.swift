import SwiftUI
import TasksCore
import UniformTypeIdentifiers

/// The rows of a task pane, in a lazy `List` (an NSTableView), reading index buckets only: Today groups in sidebar
/// order, or a list's open tasks then its collapsed Completed section. Views never filter or sort (spec §9).
struct TaskListView: View {
    enum Mode: Equatable { case today, list(EntityID) }

    let store: Store
    @Bindable var window: WindowState
    let mode: Mode
    @Environment(\.pane) private var pane

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        List(selection: $window.selection) {
            switch mode {
            case .today:
                if window.quickAdd != nil {
                    QuickAddRow(store: store, window: window, listID: nil).paneRow().selectionDisabled()
                }
                ForEach(store.projection.activeLists.ids, id: \.self) { listID in
                    TodayGroup(store: store, window: window, listID: listID)
                }
                TodayDone(store: store, window: window)
            case .list(let id):
                ListContent(store: store, window: window, listID: id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 32)
        .contextMenu(forSelectionType: EntityID.self) { ids in
            TaskContextMenu(store: store, window: window, ids: Array(ids))
        } primaryAction: { ids in
            if let id = ids.first { window.open(id) }
        }
        .onKeyPress(.return) {
            guard window.quickAdd == nil, let id = actions.targetIDs.first else { return .ignored }
            window.open(id)
            return .handled
        }
        .onDeleteCommand { actions.delete() }
        .onExitCommand {
            if window.quickAdd != nil { window.quickAdd = nil } else if window.detailTaskID != nil { window.detailTaskID = nil }
        }
        .simultaneousGesture(TapGesture().onEnded { window.focus = .list })
    }
}

extension View {
    /// A Pane row inside a List: 12pt pane padding, 2pt gaps, no separators, Pane's own selection drawing.
    func paneRow() -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .background(PaneTableStyle())
    }
}

/// One Today group: a list's tasks that match the Today predicate, in that list's manual order. Drags stay
/// within the group (one ForEach per group).
struct TodayGroup: View {
    let store: Store
    @Bindable var window: WindowState
    let listID: EntityID

    var body: some View {
        let ids = store.projection.todayTasks(in: listID).ids
        if !ids.isEmpty, let list = store.projection.listModel(listID) {
            Section {
                ForEach(ids, id: \.self) { id in
                    TaskRowCell(store: store, window: window, taskID: id, context: .today)
                }
                .onMove { from, to in
                    guard let r = Ordering.anchor(moving: from, to: to, in: ids) else { return }
                    store.reorder(r.moving, in: listID, at: r.anchor, undoManager: window.undoManager)
                }
            } header: {
                PaneGroupLabel(text: list.name.isEmpty ? "Untitled" : list.name)
                    .padding(.leading, 10)
                    .padding(.top, 6)
            }
            .listSectionSeparator(.hidden)
        }
    }
}

/// Tasks completed today stay at the bottom of Today, dimmed, by completion time, until midnight.
struct TodayDone: View {
    let store: Store
    @Bindable var window: WindowState

    var body: some View {
        let ids = store.projection.todayDone.ids
        if !ids.isEmpty {
            Section {
                ForEach(ids, id: \.self) { id in
                    TaskRowCell(store: store, window: window, taskID: id, context: .todayDone)
                }
            } header: {
                Color.clear.frame(height: 4)
            }
            .listSectionSeparator(.hidden)
        }
    }
}

/// A list screen: open tasks (draggable), the quick-add row where new tasks land, then Completed.
struct ListContent: View {
    let store: Store
    @Bindable var window: WindowState
    let listID: EntityID
    @Environment(\.pane) private var pane

    var body: some View {
        let open = store.projection.openTasks(in: listID).ids
        let completed = store.projection.completedTasks(in: listID).ids
        Section {
            ForEach(open, id: \.self) { id in
                TaskRowCell(store: store, window: window, taskID: id, context: .list)
            }
            .onMove { from, to in
                guard let r = Ordering.anchor(moving: from, to: to, in: open) else { return }
                store.reorder(r.moving, in: listID, at: r.anchor, undoManager: window.undoManager)
            }
            if window.quickAdd != nil {
                QuickAddRow(store: store, window: window, listID: listID).paneRow().selectionDisabled()
            } else if open.isEmpty {
                EmptyListRow(window: window, store: store, hasCompleted: !completed.isEmpty).paneRow().selectionDisabled()
            }
        }
        .listSectionSeparator(.hidden)
        if !completed.isEmpty {
            let expanded = window.expandedCompleted.contains(listID)
            Section {
                CompletedToggle(count: completed.count, expanded: expanded) {
                    if expanded { window.expandedCompleted.remove(listID) } else { window.expandedCompleted.insert(listID) }
                }
                .paneRow()
                .selectionDisabled()
                if expanded {
                    ForEach(completed, id: \.self) { id in
                        TaskRowCell(store: store, window: window, taskID: id, context: .list)
                    }
                }
            } header: {
                Color.clear.frame(height: 4)
            }
            .listSectionSeparator(.hidden)
        }
    }
}

/// A row bound to its model, with Pane selection and the drag payload for dropping on a sidebar list.
struct TaskRowCell: View {
    let store: Store
    @Bindable var window: WindowState
    let taskID: EntityID
    let context: TaskRow.Context

    /// Exactly one view per id, never an `if` at the top: a List row count it can't know without building every
    /// row makes the List evaluate all of them on appear (thousands of bodies for a long list).
    var body: some View {
        #if DEBUG
        let _ = DebugTiming.rowBodies += 1
        #endif
        ZStack {
            if let model = store.projection.taskModel(taskID) {
                TaskRow(model: model, store: store, dayModel: store.projection.dayModel, context: context,
                        isSelected: window.selection.contains(taskID)) {
                    store.toggleComplete([taskID], undoManager: window.undoManager)
                }
            }
        }
        .paneRow()
        .itemProvider { dragProvider() }
        #if DEBUG
        .onAppear { DebugTiming.rowAppeared() }
        #endif
    }

    private func dragProvider() -> NSItemProvider {
        let ids = window.selection.contains(taskID)
            ? window.selection.sorted { (store.projection.task($0)?.order ?? "") < (store.projection.task($1)?.order ?? "") }
            : [taskID]
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(ids)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.taskIDs.identifier, visibility: .all) { done in
            done(data, nil)
            return nil
        }
        let titles = ids.compactMap { store.projection.task($0)?.title }.joined(separator: "\n")
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { done in
            done(Data(titles.utf8), nil)
            return nil
        }
        return provider
    }
}

/// A 32pt task row: checkbox, title, and a date chip only when it tells you something (design: "Task row").
struct TaskRow: View {
    enum Context: Equatable { case today, list, todayDone }

    let model: TaskModel
    let store: Store
    let dayModel: DayModel
    let context: Context
    let isSelected: Bool
    let onToggle: () -> Void
    @Environment(\.pane) private var pane
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) { PaneCheckbox(isDone: model.isDone) }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isDone ? "Mark \(model.title) not done" : "Complete \(model.title)")
            Text(model.title.isEmpty ? "New task" : model.title)
                .foregroundStyle(model.isDone || model.title.isEmpty ? pane.inkSecondary : pane.ink)
                .strikethrough(model.isDone, color: pane.inkQuiet)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            chips
        }
        .font(PaneFont.body)
        .padding(.horizontal, 10)
        .frame(minHeight: PaneSize.sidebarRow)
        .background {
            if isSelected || hovering {
                RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous)
                    .fill(pane.selected.opacity(isSelected ? 1 : 0.55))
            }
        }
        .overlay(alignment: .leading) {
            if hovering && context != .todayDone && !model.isDone { PaneGrip().offset(x: 1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(PaneMotion.snappy, value: model.isDone)
    }

    @ViewBuilder private var chips: some View {
        let today = dayModel.day.date
        HStack(spacing: 6) {
            if context == .todayDone {
                if let list = store.projection.listModel(model.list) {
                    HStack(spacing: 6) {
                        Circle().fill(pane.listColor(slot: list.colorSlot)).frame(width: 7, height: 7)
                        Text(list.name).lineLimit(1)
                    }
                    .foregroundStyle(pane.inkSecondary)
                    .frame(width: 92, alignment: .leading)
                }
            } else if !model.isDone {
                if context == .list, let when = model.when, when >= today {
                    PaneChip(text: DateText.short(when, today: today), systemImage: "calendar")
                }
                if let status = DeadlineStatus(deadline: model.deadline, today: today) {
                    switch status {
                    case .overdue(let days):
                        PaneChip(text: "Overdue · \(days)d", systemImage: "flag", kind: .late)
                    case .dueToday:
                        PaneChip(text: "Due today", systemImage: "flag", kind: .due)
                    case .upcoming(let date):
                        let label = DateText.short(date, today: today)
                        PaneChip(text: context == .today ? "Due \(label)" : label, systemImage: "flag")
                    }
                }
            }
        }
    }
}

/// The collapsed "Completed 23" row that ends each list.
struct CompletedToggle: View {
    let count: Int
    let expanded: Bool
    let action: () -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: PaneSize.check)
                Text("Completed").font(PaneFont.bodyMedium)
                Text(verbatim: "\(count)").monospacedDigit()
                Spacer()
            }
            .foregroundStyle(pane.inkSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: PaneSize.sidebarRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .animation(PaneMotion.snappy, value: expanded)
    }
}

/// An empty list: a "New task" prompt where the first task will land.
struct EmptyListRow: View {
    @Bindable var window: WindowState
    let store: Store
    let hasCompleted: Bool
    @Environment(\.pane) private var pane

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                WindowActions(store: store, window: window).newTask()
            } label: {
                HStack(spacing: 10) {
                    PaneCheckbox(isDone: false, style: .placeholder)
                    Text("New task").foregroundStyle(pane.inkSecondary)
                    Spacer()
                    PaneKeyHint(text: "⌘N")
                }
                .padding(.horizontal, 10)
                .frame(minHeight: PaneSize.sidebarRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(hasCompleted ? "Everything here is done." : "Type a task and press Return, or drag tasks here from another list.")
                .font(PaneFont.subheadline)
                .foregroundStyle(pane.inkSecondary)
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 2)
    }
}

/// Right-click menu for the clicked or selected tasks.
struct TaskContextMenu: View {
    let store: Store
    let window: WindowState
    let ids: [EntityID]

    var body: some View {
        let undo = window.undoManager
        let allDone = ids.allSatisfy { store.projection.task($0)?.completedAt != nil }
        Button(allDone ? "Mark as Not Done" : "Complete") { store.toggleComplete(ids, undoManager: undo) }
        if ids.count == 1, let id = ids.first {
            Button("Open") { window.open(id) }
        }
        Menu("When") {
            let today = store.projection.day.date
            Button("Today") { store.setWhen(ids, today, undoManager: undo) }
            Button("Tomorrow") { store.setWhen(ids, today.adding(days: 1), undoManager: undo) }
            Button("Next Week") { store.setWhen(ids, DateText.nextWeek(from: today), undoManager: undo) }
            Divider()
            Button("No Date") { store.setWhen(ids, nil, undoManager: undo) }
        }
        Menu("Move to") {
            ForEach(store.projection.activeLists.ids, id: \.self) { listID in
                if let list = store.projection.listModel(listID) {
                    Button(list.name.isEmpty ? "Untitled" : list.name) { store.move(ids, to: listID, undoManager: undo) }
                }
            }
        }
        Divider()
        Button("Delete") {
            store.delete(ids, undoManager: undo)
            window.selection.subtract(ids)
            if let d = window.detailTaskID, ids.contains(d) { window.detailTaskID = nil }
        }
    }
}
