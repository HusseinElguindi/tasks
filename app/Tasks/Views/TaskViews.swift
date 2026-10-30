import SwiftUI
import TasksCore
import UniformTypeIdentifiers

/// The rows of a task pane, reading index buckets only: Today groups in sidebar order, or a list's open tasks then its
/// collapsed Completed section. Views never filter or sort (spec §9).
///
/// A lazy stack, not a `List`: on every list switch the List's table diffed every row out and in and measured each new
/// row's height (30–100 ms). The stack builds the visible rows in one pass. Selection, the keyboard, the context menu
/// and drags are ours (WindowActions, TaskRowCell).
struct TaskListView: View {
    enum Mode: Equatable { case today, list(EntityID) }

    let store: Store
    @Bindable var window: WindowState
    let mode: Mode
    @FocusState private var listFocused: Bool

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        let slots = TaskSlot.slots(mode, store: store, window: window)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(slots) { slot in
                        TaskSlotView(store: store, window: window, kind: slot.kind)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12))
                .overlay(alignment: .topLeading) {
                    // Inset to the row text (A1), centered on the boundary between rows.
                    if let drop = window.rowDrop {
                        PaneInsertionLine()
                            .padding(EdgeInsets(top: 0, leading: 12 + 32, bottom: 0, trailing: 12))
                            .offset(y: drop.y - 4)
                    }
                }
                .onDrop(of: [.taskIDs], delegate: TaskListDropDelegate(store: store, window: window, mode: mode))
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onChange(of: listFocused) { _, focused in if focused { window.focus = .list } }
            // Keys work from the start, as in Rex, where the pane has focus when the window opens.
            .onAppear { if window.quickAdd == nil { listFocused = true } }
            // A click on a row (WindowActions.click) puts keyboard focus here.
            .onChange(of: window.listFocusRequest) { _, _ in listFocused = true }
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                guard let id = actions.moveSelection(down: press.key == .downArrow, extend: press.modifiers.contains(.shift))
                else { return .ignored }
                if let i = TaskSlot.index(of: id, in: slots) { proxy.scrollTo(i) }
                return .handled
            }
            .onKeyPress(.return) {
                guard window.quickAdd == nil, let id = actions.targetIDs.first else { return .ignored }
                window.open(id)
                return .handled
            }
            .onKeyPress(.space) {
                guard window.quickAdd == nil, !actions.targetIDs.isEmpty else { return .ignored }
                actions.toggleComplete()
                return .handled
            }
            .onDeleteCommand { actions.delete() }
            .onExitCommand {
                if window.quickAdd != nil { window.quickAdd = nil } else if window.detailTaskID != nil { window.detailTaskID = nil }
            }
            // Leaving the list clears its hover, whatever exit a row may have missed.
            .onHover { inside in if !inside { window.rowHover.clear("left list") } }
            // ⌘N in a long list opens quick add below the last open task, possibly offscreen, where the lazy stack
            // hasn't built the row yet: bring it into view so its field can take focus.
            .onChange(of: window.quickAdd?.focusToken) { _, token in
                if token != nil, let i = slots.firstIndex(where: { $0.kind.isQuickAdd }) { proxy.scrollTo(i) }
            }
        }
    }
}

extension View {
    /// A row in a task pane: at least Rex's 30pt shape, with the 1pt half-gaps that make the 32pt pitch.
    func paneRow() -> some View {
        frame(minHeight: PaneSize.row).padding(.vertical, 1)
    }

    /// A fixed 32pt row (30pt shape, 1pt half-gaps): the lazy stack sizes it without measuring its content.
    func paneFixedRow() -> some View {
        frame(height: PaneSize.row).padding(.vertical, 1)
    }
}

/// One row of a task pane. Rows are identified by their position in one flat list, so switching lists updates the
/// rows already built (a task row stays a task row and shows another task) rather than building new ones, which was
/// most of what a switch cost. Today: quick add, then each list's group (label, tasks in the list's order), then done
/// today. A list: its open tasks, quick add (or the empty prompt), then Completed.
struct TaskSlot: Identifiable, Equatable {
    enum Kind: Equatable {
        case quickAdd(list: EntityID?)
        case label(EntityID)
        case task(EntityID, TaskRow.Context)
        case gap
        case completedToggle(list: EntityID, count: Int, expanded: Bool)
        case empty(hasCompleted: Bool)

        var isQuickAdd: Bool {
            if case .quickAdd = self { true } else { false }
        }
    }

    let id: Int
    let kind: Kind

    @MainActor
    static func slots(_ mode: TaskListView.Mode, store: Store, window: WindowState) -> [TaskSlot] {
        let p = store.projection
        var kinds: [Kind] = []
        switch mode {
        case .today:
            if window.quickAdd != nil { kinds.append(.quickAdd(list: nil)) }
            for list in p.activeLists.ids {
                let ids = p.todayTasks(in: list).ids
                guard !ids.isEmpty else { continue }
                kinds.append(.label(list))
                kinds += ids.map { .task($0, .today) }
            }
            let done = p.todayDone.ids
            if !done.isEmpty {
                kinds.append(.gap)
                kinds += done.map { .task($0, .todayDone) }
            }
        case .list(let list):
            let open = p.openTasks(in: list).ids
            let completed = p.completedTasks(in: list).ids
            kinds += open.map { .task($0, .list) }
            if window.quickAdd != nil {
                kinds.append(.quickAdd(list: list))
            } else if open.isEmpty {
                kinds.append(.empty(hasCompleted: !completed.isEmpty))
            }
            if !completed.isEmpty {
                let expanded = window.expandedCompleted.contains(list)
                kinds.append(.gap)
                kinds.append(.completedToggle(list: list, count: completed.count, expanded: expanded))
                if expanded { kinds += completed.map { .task($0, .list) } }
            }
        }
        return kinds.enumerated().map { TaskSlot(id: $0.offset, kind: $0.element) }
    }

    static func index(of task: EntityID, in slots: [TaskSlot]) -> Int? {
        slots.firstIndex { if case .task(task, _) = $0.kind { true } else { false } }
    }
}

/// What a slot shows. The same kind at the same position updates in place.
struct TaskSlotView: View {
    let store: Store
    @Bindable var window: WindowState
    let kind: TaskSlot.Kind

    var body: some View {
        switch kind {
        case .task(let id, let context):
            TaskRowCell(store: store, window: window, taskID: id, context: context)
        case .label(let list):
            TodayGroupLabel(window: window, listID: list, name: store.projection.listModel(list).map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "") {
                WindowActions(store: store, window: window).newTask(in: list)
            }
        case .gap:
            Color.clear.frame(height: PaneSize.sidebarRow)
        case .completedToggle(let list, let count, let expanded):
            CompletedToggle(count: count, expanded: expanded) {
                if expanded { window.expandedCompleted.remove(list) } else { window.expandedCompleted.insert(list) }
            }
            .padding(.vertical, 1)
        case .quickAdd(let list):
            QuickAddRow(store: store, window: window, listID: list)
                .paneRow()
                .background {
                    // Its height places the rows below it for drops (TaskListDropDelegate).
                    GeometryReader { g in
                        Color.clear
                            .onAppear { window.quickAddHeight = g.size.height }
                            .onChange(of: g.size.height) { _, h in window.quickAddHeight = h }
                    }
                }
        case .empty(let hasCompleted):
            EmptyListRow(window: window, store: store, hasCompleted: hasCompleted).paneRow()
        }
    }
}

/// A Today group's label, which reveals ⊕ (a new task in that list, for today) on hover as Rex's group headers do.
/// Its hover shares the task rows' region, keyed by the list id.
struct TodayGroupLabel: View {
    let window: WindowState
    let listID: EntityID
    let name: String
    let action: () -> Void

    var body: some View {
        PaneGroupLabelRow(text: name, help: "New Task in \(name)", isHovered: window.rowHover.isHovered(listID), action: action)
            .padding(.leading, 10)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .onHover { window.rowHover.update(listID, inside: $0) }
            .paneFixedRow()
    }
}

/// A row bound to its model: Pane selection, click and double-click, the context menu, and drags (a lifted copy, the
/// source left at 35%, an insertion line between rows of the same list, or a drop on a sidebar list).
struct TaskRowCell: View {
    let store: Store
    @Bindable var window: WindowState
    let taskID: EntityID
    let context: TaskRow.Context
    @Environment(\.pane) private var pane

    /// Exactly one view per id, never an `if` at the top, so the lazy stack can count rows without building them.
    var body: some View {
        #if DEBUG
        let _ = DebugTiming.rowBodies += 1
        #endif
        ZStack {
            if let model = store.projection.taskModel(taskID) {
                TaskRow(model: model, store: store, window: window, dayModel: store.projection.dayModel, context: context,
                        isSelected: window.selection.contains(taskID), isHovered: window.rowHover.isHovered(taskID)) {
                    // Fill, check, strike and dim together (design/INTERACTIONS.md).
                    withAnimation(PaneMotion.snappy) { store.toggleComplete([taskID], undoManager: window.undoManager) }
                }
                .opacity(window.dragged?.contains(taskID) == true ? 0.35 : 1)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { WindowActions(store: store, window: window).click(taskID) }
        .contextMenu { TaskContextMenu(store: store, window: window, ids: WindowActions(store: store, window: window).menuTargets(for: taskID)) }
        .onDrag { dragProvider() } preview: { preview }
        .onHover { inside in window.rowHover.update(taskID, inside: inside) }
        #if DEBUG
        .onAppear { DebugTiming.rowAppeared() }
        #endif
    }

    private var dragIDs: [EntityID] {
        window.selection.contains(taskID)
            ? window.selection.sorted { (store.projection.task($0)?.order ?? "") < (store.projection.task($1)?.order ?? "") }
            : [taskID]
    }

    /// The lifted copy (A1): the row on a raised surface with shadow-lift, and a count when several tasks move.
    private var preview: some View {
        let ids = dragIDs
        return LiftedTaskRow(title: store.projection.task(taskID)?.title ?? "", count: ids.count, pane: pane)
    }

    private func dragProvider() -> NSItemProvider {
        window.rowHover.clear()
        let ids = dragIDs
        window.beginDrag(.tasks(ids))
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

/// One drop target for the whole list (one per row cost every row a drop registration). The pointer's y finds the
/// row from the pane's fixed 32pt rhythm; the insertion line goes above or below it; and only tasks of that row's list
/// may land there, so in Today a task moves within its group.
struct TaskListDropDelegate: DropDelegate {
    let store: Store
    let window: WindowState
    let mode: TaskListView.Mode

    /// The rows a drop can reorder, top to bottom: the task, its list and the y of its top in the stack.
    private func rows() -> [(id: EntityID, list: EntityID, y: CGFloat)] {
        let p = store.projection
        let pitch = PaneSize.sidebarRow
        var out: [(id: EntityID, list: EntityID, y: CGFloat)] = []
        var y: CGFloat = 0
        switch mode {
        case .today:
            if window.quickAdd != nil { y += window.quickAddHeight }
            for list in p.activeLists.ids {
                let ids = p.todayTasks(in: list).ids
                guard !ids.isEmpty else { continue }
                y += pitch  // the group's label
                for id in ids { out.append((id, list, y)); y += pitch }
            }
        case .list(let list):
            for id in p.openTasks(in: list).ids { out.append((id, list, y)); y += pitch }
        }
        return out
    }

    private func target(_ info: DropInfo) -> WindowState.RowDrop? {
        guard case .tasks(let ids) = window.dragged else { return nil }
        let rows = rows()
        guard !rows.isEmpty else { return nil }
        let pitch = PaneSize.sidebarRow
        let row = rows[rows.lastIndex(where: { $0.y <= info.location.y }) ?? 0]
        guard ids.allSatisfy({ store.projection.task($0)?.list == row.list }) else { return nil }
        let above = info.location.y < row.y + pitch / 2
        return WindowState.RowDrop(target: row.id, list: row.list, above: above, y: above ? row.y : row.y + pitch)
    }

    func validateDrop(info: DropInfo) -> Bool {
        if case .tasks = window.dragged { true } else { false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let t = target(info)
        if window.rowDrop != t { window.rowDrop = t }
        return DropProposal(operation: t == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        if window.rowDrop != nil { window.rowDrop = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let t = target(info)
        window.rowDrop = nil
        guard let t, case .tasks(let ids) = window.dragged else { return false }
        window.dragged = nil
        let others = ids.filter { $0 != t.target }
        guard !others.isEmpty else { return true }
        store.reorder(others, in: t.list, at: t.above ? .before(t.target) : .after(t.target), undoManager: window.undoManager)
        return true
    }
}

/// What a dragged task row looks like under the pointer (A1's lifted row).
struct LiftedTaskRow: View {
    let title: String
    let count: Int
    let pane: PaneColors

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous)
        HStack(spacing: 10) {
            PaneCheckbox(isDone: false)
            Text(title.isEmpty ? "New task" : title).lineLimit(1)
            Spacer(minLength: 8)
            if count > 1 {
                Text(verbatim: "\(count)")
                    .font(PaneFont.label)
                    .foregroundStyle(pane.onAccent)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(pane.accent, in: Capsule())
            }
        }
        .font(PaneFont.body)
        .foregroundStyle(pane.ink)
        .padding(.horizontal, 10)
        .frame(width: 360, height: PaneSize.row)
        .background(pane.isDark ? pane.capsule : pane.base, in: shape)
        .paneShadow(.lift, in: shape)
        .environment(\.pane, pane)
    }
}

/// A task row, Rex's 30pt row shape on the 32pt pitch: checkbox, title, and a date chip only when it tells you
/// something (design: "Task row"), then the ••• slot 16pt in from the edge, like the sidebar's.
struct TaskRow: View {
    enum Context: Equatable { case today, list, todayDone }

    let model: TaskModel
    let store: Store
    let window: WindowState
    let dayModel: DayModel
    let context: Context
    let isSelected: Bool
    let isHovered: Bool
    let onToggle: () -> Void
    @Environment(\.pane) private var pane

    /// Hover never fills a row (design/INTERACTIONS.md): it only reveals the trailing •••. Selection fills.
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) { PaneCheckbox(isDone: model.isDone) }
                .buttonStyle(PanePressStyle())
                .accessibilityLabel(model.isDone ? "Mark \(model.title) not done" : "Complete \(model.title)")
            Text(model.title.isEmpty ? "New task" : model.title)
                .foregroundStyle(model.isDone || model.title.isEmpty ? pane.inkSecondary : pane.ink)
                .strikethrough(model.isDone, color: pane.inkQuiet)
                .lineLimit(1)
            Spacer(minLength: 8)
            chips
            PaneRowMenu(visible: isHovered || isSelected, live: isHovered, help: "Actions") {
                TaskContextMenu(store: store, window: window, ids: [model.id])
            }
        }
        .font(PaneFont.body)
        .padding(.leading, 10)
        .padding(.trailing, PaneSize.rowActionInset)
        .frame(height: PaneSize.row)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous).fill(pane.selected)
            }
        }
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
            .frame(height: PaneSize.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanePressStyle())
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
                .frame(minHeight: PaneSize.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanePressStyle())
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

