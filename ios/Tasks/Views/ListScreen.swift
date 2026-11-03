import SwiftUI
import TasksCore

/// One list, or one of the views, on the row grid. The large title scrolls with the rows; the bar's title fades in once
/// it has gone under the bar.
struct ListScreen: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @State private var folded = false
    /// The frame of the row being typed into (a new task or heading, a heading's name or notes), so a tap outside it
    /// can end adding.
    @State private var draftFrame: CGRect?
    /// Counts drops that wrote something, for the light haptic on drop.
    @State private var dropped = 0
    /// Today's all-done sun turns in as it next appears: when Today opens already all done, or its last row settles
    /// while it's open (IX §13). Not when it scrolls back into view.
    @State private var sunRise = true
    /// Counts the times Today became all done while open, for the light haptic as the sun appears.
    @State private var sunHaptic = 0

    private static let space = "rows"
    private var adding: Bool { app.draft?.source == source }
    /// The list's notes are being typed, under its title.
    private var editingNotes: Bool { adding && app.draft?.editsListNotes == true }

    var body: some View {
        let lines = app.lines(source)
        let allDone = lines.contains { $0.isAllDone }
        ScrollViewReader { proxy in
            List {
                header
                    .endsAddingOnTap(!editingNotes)
                    .pressesShowAtOnce()
                    .listRow()
                if let runs = app.dragRuns(lines, source) {
                    // Drag to reorder (Reorder.swift: the iPhone's own drag, and its three accepted differences from
                    // the Mac). Each run is its own ForEach, so a drop stays in its Today or Undated group.
                    ForEach(runs) { run in
                        ForEach(run.lines) { line in
                            listLine(line)
                                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
                                .moveDisabled(!line.canDrag)
                        }
                        .onMove { from, to in
                            if app.drop(from, to, in: run.lines, source: source) { dropped += 1 }
                        }
                    }
                } else {
                    ForEach(lines) { line in listLine(line) }
                }
                Color.clear.frame(height: app.isSplit ? 24 : Metric.bottomClearance)
                    .listRow()
            }
            .listStyle(.plain)
            // A new heading's row (at the bottom, or above a task) and a new task's in a heading are scrolled into
            // view as adding starts; a new task's own row is at the top, where + is pressed from. The next row after
            // Return is under the last one, already in view.
            .onChange(of: app.draft?.kind) { _, kind in
                guard let kind, adding, kind != .task, app.draft?.editedHeading == nil, !editingNotes else { return }
                animate(Motion.layout) { proxy.scrollTo("draft") }
            }
            // Show in <list>: the task is scrolled into view once the list is up.
            .task(id: app.revealTask) {
                guard let id = app.revealTask, source == .list(app.task(id)?.list ?? "") else { return }
                try? await Task.sleep(for: .milliseconds(350))
                animate(Motion.layout) { proxy.scrollTo("t:" + id, anchor: .center) }
                app.revealTask = nil
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: dropped)
        // A soft echo of the last check, as the sun appears (1.5 s after it, when the rows settle).
        .sensoryFeedback(.impact(weight: .light), trigger: sunHaptic)
        .onChange(of: allDone) { _, now in
            guard now else { return }
            sunRise = true
            sunHaptic += 1
        }
        .coordinateSpace(.named(Self.space))
        // While adding, a tap anywhere outside the new-task row ends it. On a row or the header the tap goes no further
        // (`endsAddingOnTap`: the row doesn't open, its box doesn't check); this catches the rest, the list's empty
        // space. Not adding, the list's taps are left alone.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { tap in
            if !(draftFrame?.contains(tap.location) ?? false) { app.endDraft() }
        }, including: adding ? .all : .subviews)
        // A swipe on the list puts the keyboard away, which ends adding.
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await app.syncNow() }
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background {
            ZStack {
                if !app.isSplit { AppBackground() }
                if source == .today { Sunrise(shown: allDone) }
            }
        }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 40
        } action: { _, now in
            animate(.easeOut(duration: 0.15)) { folded = now }
        }
        .navigationTitle(app.title(source))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    app.tile(for: source, palette: p, scale: 0.8)
                    Text(app.title(source)).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                }
                .opacity(folded ? 1 : 0)
                .accessibilityHidden(!folded)
            }
            if adding, app.draft?.editsNotes == true {
                // A heading's or the list's notes: Done ends them, as Esc does on the Mac.
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { app.endDraft() }
                }
            } else if adding {
                // While adding: Cancel drops the row with whatever was typed, and a heading's rename keeps its old
                // name (the list's menu is back after).
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel") { app.cancelDraft() }
                }
            } else if case let .list(id) = source {
                ToolbarItem(placement: .primaryAction) { ListMenu(listID: id) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 11) {
                    app.tile(for: source, palette: p, scale: 1.2)
                    Text(app.title(source))
                        .font(Typo.largeTitle)
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    if let sub = subtitle {
                        Text(sub).font(Typo.body).foregroundStyle(p.inkTertiary).lineLimit(1).padding(.top, 4)
                    }
                }
                if case let .list(id) = source, !editingNotes, let notes = app.list(id)?.notes, !notes.isEmpty {
                    // A list's notes are a step quieter (§23), in the same Markdown as a task's. A tap on them edits
                    // them; a checklist box toggles in one op (IX:1540–1543).
                    MarkdownText(text: notes, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5) { new, checking in
                        app.setNotes(list: id, new, name: checking ? "Check Item" : "Uncheck Item")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { app.editListNotes(id) }
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("listHeader")
            if editingNotes {
                ListNotesEditor()
                    .padding(.top, 2)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { draftFrame = $0 }
            }
        }
        .padding(.leading, Metric.rowPad)
        .padding(.trailing, 8)
        .padding(.top, app.isSplit ? 14 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Today's date after its title. A list's title has no count (the user, 2026-10-31; IX:1564).
    private var subtitle: String? {
        source == .today ? DateLabel.long(app.today, today: app.today) : nil
    }

    // MARK: Rows

    private func listLine(_ line: Line) -> some View {
        row(line)
            .endsAddingOnTap(!line.isDraft && !isEdited(line))
            .listRow()
    }

    /// A heading whose name or notes are being typed, in place.
    private func isEdited(_ line: Line) -> Bool {
        switch line {
        case let .heading(h, _): if case .rename(h.id, _)? = app.draft?.kind { true } else { false }
        case let .headingNotes(h): if case .notes(h.id, _)? = app.draft?.kind { true } else { false }
        default: false
        }
    }

    @ViewBuilder private func row(_ line: Line) -> some View {
        switch line {
        case let .group(_, title, sub, quiet):
            GroupLabel(title: title, sub: sub, quiet: quiet)
        case let .heading(h, count):
            HeadingRow(heading: h, count: count)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                    if case .rename(h.id, _)? = app.draft?.kind { draftFrame = $0 }
                }
                .contextMenu { HeadingMenu(heading: h) }
        case let .headingNotes(h):
            HeadingNotesRow(heading: h)
                .motionTransition(.opacity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                    if case .notes(h.id, _)? = app.draft?.kind { draftFrame = $0 }
                }
                .contextMenu { HeadingMenu(heading: h) }
        case let .task(t, indent, groupDay, day):
            // On the phone the row whose details are open keeps the selected fill, then fades out as they close.
            TaskRow(task: t, source: source, indent: indent, groupDay: groupDay, day: day,
                    selected: app.isSplit ? app.selectedTask == t.id : app.detailTask == t.id)
                .motionTransition(.opacity)
                .modifier(TaskSwipes(task: t, source: source))
                .contextMenu { TaskMenu(task: t, source: source) }
        case let .completedToggle(key, count, open):
            CompletedToggleRow(key: key, count: count, open: open)
        case let .deletedList(l, _, open, day):
            DeletedListRow(list: l, open: open, day: day)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { app.restoreList(l.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
                .contextMenu {
                    Button { app.restoreList(l.id) } label: { Label("Restore List", systemImage: "arrow.uturn.backward") }
                }
        case .draft:
            if let token = app.draft?.token {
                DraftRow(token: token)
                    .id(token)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { draftFrame = $0 }
            }
        case let .empty(title, message, symbol):
            EmptyState(title: title, message: message, symbol: symbol)
        case .allDone:
            AllDoneSun(rise: $sunRise)
        }
    }
}

/// A list's notes being typed, under its title: the notes editor, written once as it ends ("Edit List Notes").
private struct ListNotesEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @FocusState private var focus: DetailField?
    private var text: Binding<String> { Binding(get: { app.draft?.title ?? "" }, set: { app.draft?.title = $0 }) }

    var body: some View {
        NotesEditor(text: text, focus: $focus, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5, minHeight: 60) { _, _ in }
            .accessibilityIdentifier("listNotes")
            .onAppear { DispatchQueue.main.async { focus = .notes } }
            // The caret left the notes (a tap elsewhere, the keyboard put away): they're written, once.
            .onChange(of: focus) { old, new in
                if old != nil, new == nil, app.draft?.editsListNotes == true { app.endDraft() }
            }
    }
}

/// Swipe right completes; swipe left sets the When or deletes. In Trash, swipe right puts back.
private struct TaskSwipes: ViewModifier {
    let task: TaskModel
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        if source == .trash {
            content.swipeActions(edge: .leading, allowsFullSwipe: true) {
                if app.canPutBack(task) {
                    Button { app.putBack(task.id) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
            }
        } else {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { app.toggle(task.id) } label: {
                        Label(task.isDone ? "Not Done" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(p.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { app.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
                        .tint(p.danger)
                    Button { app.dateTarget = DateTarget(taskID: task.id, kind: .when) } label: {
                        Label("When", systemImage: "calendar")
                    }
                    .tint(p.list(.magenta))
                }
        }
    }
}

/// A task's long-press menu.
struct TaskMenu: View {
    let task: TaskModel
    let source: Source
    @Environment(AppModel.self) private var app
    var body: some View {
        if case let .list(id) = source {
            // Above this task, which becomes the heading's first (§23). A done one isn't in the order: at the bottom,
            // as on the Mac.
            Button { app.newHeading(in: id, before: task.isDone ? nil : task.id) } label: {
                Label("New Heading Above", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Divider()
        }
        if let name = app.showInName(task, from: source) {
            // From Today or a view: its list, with it shown (the Mac's Show in, Menus.swift:60).
            Button { app.showInList(task.id) } label: {
                Label(MenuName.fit(name, width: 150), systemImage: "arrow.right.circle")
            }
            Divider()
        }
        if source == .trash {
            if app.canPutBack(task) {
                Button { app.putBack(task.id) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }
            }
        } else {
            Button { app.toggle(task.id) } label: {
                Label(task.isDone ? "Mark as Not Completed" : "Complete", systemImage: task.isDone ? "circle" : "checkmark.circle")
            }
            Button { app.setDate(task.id, .when, app.today) } label: { Label("Today", systemImage: "sun.max") }
            Button { app.setDate(task.id, .when, app.today.adding(days: 1)) } label: { Label("Tomorrow", systemImage: "sunrise") }
            Button { app.dateTarget = DateTarget(taskID: task.id, kind: .when) } label: { Label("When…", systemImage: "calendar") }
            Button { app.dateTarget = DateTarget(taskID: task.id, kind: .deadline) } label: { Label("Deadline…", systemImage: "flag") }
            Menu {
                ForEach(app.activeLists) { l in
                    Button(MenuName.fit(l.name)) { app.move(task.id, to: l.id) }.disabled(l.id == task.list)
                }
            } label: { Label("Move to", systemImage: "arrow.right.square") }
            Divider()
            Button(role: .destructive) { app.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// A heading's long-press menu (§23): Rename, its notes, New Task in it, Collapse or Expand, Delete Heading. Dragging
/// covers the Mac's Move Up and Move Down.
struct HeadingMenu: View {
    let heading: TaskModel
    @Environment(AppModel.self) private var app
    var body: some View {
        let collapsed = app.collapsed.contains(heading.id)
        Button { app.renameHeading(heading.id) } label: { Label("Rename", systemImage: "pencil") }
        Button { app.editHeadingNotes(heading.id) } label: {
            Label(heading.notes.isEmpty ? "Add Notes" : "Edit Notes", systemImage: "text.alignleft")
        }
        Button { app.newTask(inHeading: heading.id) } label: {
            // One line, as Move to keeps a list's name (`MenuName`): the name is cut to what's left of the menu's 150pt
            // (it holds "New Task in “Labs”" whole, and wraps a longer one; measured on the simulator, 2026-11-03).
            Label("New Task in “\(MenuName.fit(heading.title, width: 150 - MenuName.width("New Task in “”")))”",
                  systemImage: "plus")
        }
        Divider()
        Button { app.toggleCollapse(heading.id) } label: {
            Label(collapsed ? "Expand" : "Collapse", systemImage: collapsed ? "chevron.down" : "chevron.right")
        }
        Divider()
        Button(role: .destructive) { app.deleteHeading(heading.id) } label: { Label("Delete Heading", systemImage: "trash") }
    }
}

/// A list's menu in the bar: Rename, Add Notes or Edit Notes, New Heading, show or hide completed, Delete List (at
/// once, with Undo).
struct ListMenu: View {
    let listID: EntityID
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            Button { app.listEditor = .init(listID: listID, name: app.list(listID)?.name ?? "") } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { app.editListNotes(listID) } label: {
                Label(app.list(listID)?.notes.isEmpty ?? true ? "Add Notes" : "Edit Notes", systemImage: "text.alignleft")
            }
            Button { app.newHeading(in: listID) } label: {
                Label("New Heading", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                animate(Motion.layout) {
                    if app.showCompleted.contains(listID) { app.showCompleted.remove(listID) } else { app.showCompleted.insert(listID) }
                }
            } label: {
                Label(app.showCompleted.contains(listID) ? "Hide Completed" : "Show Completed", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) { app.deleteList(listID) } label: { Label("Delete List", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(p.ink)
        .accessibilityLabel("List actions")
    }
}

extension View {
    /// A row in one of the app's plain lists: no separator, no background, inset to the row grid.
    func listRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: Metric.rowInset, bottom: 0, trailing: Metric.rowInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
