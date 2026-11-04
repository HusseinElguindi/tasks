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
    /// A drop that wrote nothing (Upcoming: a month, past a deadline, its own day). List keeps the row where it was
    /// dropped until the rows are drawn again; this draws them, and the row goes back to its place.
    @State private var refused = 0
    /// Today's all-done sun turns in as it next appears: when Today opens already all done, or its last row settles
    /// while it's open (IX §13). Not when it scrolls back into view.
    @State private var sunRise = true
    /// Counts the times Today became all done while open, for the light haptic as the sun appears.
    @State private var sunHaptic = 0
    /// The two-finger swipe that selects (§3), on this list's scroll view.
    @State private var swipe = SwipeSelect()
    /// The collection's scrolling, on the UICollectionView path (`ListContainer`).
    @State private var collection = CollectionProxy()

    private static let space = "rows"
    private var adding: Bool { app.draft?.source == source }
    /// The list's notes are being typed, under its title.
    private var editingNotes: Bool { adding && app.draft?.editsListNotes == true }
    /// In select mode (§3).
    private var selecting: Bool { app.isSelecting(source) }

    var body: some View {
        let lines = app.lines(source)
        let allDone = lines.contains { $0.isAllDone }
        let shownIDs = lines.compactMap { if case let .task(t, _, _, _) = $0 { t.id } else { nil } }
        let picks = Picks(lines, selected: selecting ? app.selected : [])
        ScrollViewReader { proxy in
            Group {
            if ListContainer.collection {
                TaskCollection(source: source, lines: lines, sizes: TaskCollection.signatures(app, source, lines),
                               proxy: collection,
                               folded: Binding(get: { folded }, set: { v in animate(.easeOut(duration: 0.15)) { folded = v } }),
                               sunRise: $sunRise)
                    // Its own insets: the keyboard's, and the floating controls' clearance (TaskCollection.swift).
                    .ignoresSafeArea(.all, edges: .bottom)
                    // A new one for another screen: the stack can swap a screen's source in place (an undo's).
                    .id(source)
            } else {
            List {
                if let l = app.deletedList(source) {
                    // Above the large title, 10 in from the sides and 4 under the bar (§28's banner, the sheet's
                    // metrics). It fades out as the list is restored, while the rows close up on `layout`.
                    DeletedListBanner(list: l)
                        .motionTransition(.opacity.animation(.easeOut(duration: 0.15)))
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 0, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                header
                    .endsAddingOnTap(!editingNotes)
                    .pressesShowAtOnce()
                    .swipeSelects(swipe)
                    .listRow()
                if let runs = app.dragRuns(lines, source) {
                    // Drag to reorder (Reorder.swift: the iPhone's own drag, and its three accepted differences from
                    // the Mac). Each run is its own ForEach, so a drop stays in its Today or Undated group; Upcoming
                    // is one run, across its days.
                    let airless = DragRun.airless(runs)
                    let _ = refused
                    ForEach(runs) { run in
                        ForEach(run.lines) { line in
                            listLine(line, airless: airless.contains(line.id), picks: picks)
                                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
                                // Nothing lifts in select mode: the reorder brief drags one row at a time.
                                .moveDisabled(selecting || (!line.canDrag && !line.takesDrops))
                        }
                        .onMove { from, to in
                            if app.drop(from, to, in: run.lines, source: source) { dropped += 1 } else {
                                animate(Motion.layout) { refused += 1 }
                            }
                        }
                    }
                } else {
                    ForEach(lines) { line in listLine(line, picks: picks) }
                }
                Color.clear.frame(height: app.isSplit ? 24 : Metric.bottomClearance)
                    .listRow()
            }
            .listStyle(.plain)
            }
            }
            // A new heading's row (at the bottom, or above a task) and a new task's in a heading are scrolled into
            // view as adding starts; a new task's own row is at the top, where + is pressed from. The next row after
            // Return is under the last one, already in view.
            .onChange(of: app.draft?.kind) { _, kind in
                guard let kind, adding, kind != .task, app.draft?.editedHeading == nil, !editingNotes else { return }
                reveal("draft", proxy)
            }
            // An undo or a redo: the first row it touched, scrolled into view (the least that shows it).
            .task(id: app.undoReveal) {
                guard let r = app.undoReveal, app.shown == source else { return }
                try? await Task.sleep(for: .milliseconds(50))
                reveal("t:" + r.id, proxy)
                app.undoReveal = nil
            }
            // Show in <list>: the task is scrolled into view once the list is up.
            .task(id: app.revealTask) {
                guard let id = app.revealTask, source == .list(app.task(id)?.list ?? "") else { return }
                try? await Task.sleep(for: .milliseconds(350))
                reveal("t:" + id, proxy, center: true)
                app.revealTask = nil
            }
        }
        // Deleted on another device while open: it turns read-only in place, a row being typed is dropped, and select
        // mode ends.
        .onChange(of: app.deletedList(source) != nil) { _, deleted in
            if deleted, adding { app.cancelDraft() }
            if deleted, selecting { app.endSelecting() }
        }
        // The rows a swipe can cross; a task that's no longer shown leaves the selection.
        .onChange(of: shownIDs, initial: true) { _, ids in
            swipe.order = ids
            if app.isSelecting(source) { app.pruneSelection(ids) }
        }
        .onAppear { setUpSwipe() }
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
        }, including: adding && !ListContainer.collection ? .all : .subviews)
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
        // While selecting, the back button and the edge swipe back are off, so a stray swipe can't drop the selection.
        .navigationBarBackButtonHidden(selecting)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if selecting {
                    // "3 Selected", or "Select Tasks" while nothing is.
                    let n = app.selectedIDs(source).count
                    Text(n == 0 ? "Select Tasks" : "\(n) Selected")
                        .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(n == 0 ? p.inkTertiary : p.ink)
                        .accessibilityIdentifier("selectTitle")
                } else {
                    HStack(spacing: 7) {
                        app.tile(for: source, palette: p, scale: 0.8)
                        Text(app.title(source)).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                    }
                    .opacity(folded ? 1 : 0)
                    .accessibilityHidden(!folded)
                }
            }
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    // ⌘A on a hardware keyboard, while it reads Select All (IX §5).
                    let all = app.allSelected(source)
                    Button(all ? "Deselect All" : "Select All") { app.toggleSelectAll(source) }
                        .tint(p.ink)
                        .keyboardShortcut(all ? nil : KeyboardShortcut("a", modifiers: .command))
                }
                ToolbarItem(placement: .primaryAction) {
                    // Esc on a hardware keyboard, unless the date sheet is up (it takes Esc itself).
                    Button("Done") { app.endSelecting() }
                        .keyboardShortcut(app.dateTarget == nil ? .cancelAction : nil)
                }
            } else if adding, app.draft?.editsNotes == true {
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
            } else if let l = app.deletedList(source) {
                // Where the Mac's header has its ↶; nothing in the "…" applies to a deleted list.
                ToolbarItem(placement: .primaryAction) {
                    Button { app.restoreList(l.id) } label: { Image(systemName: "arrow.uturn.backward") }
                        .tint(p.ink)
                        .accessibilityLabel("Restore List")
                }
            } else if case let .list(id) = source {
                ToolbarItem(placement: .primaryAction) { ListMenu(listID: id) }
            } else {
                ToolbarItem(placement: .primaryAction) { ViewMenu(source: source) }
            }
        }
    }

    /// A row scrolled into view: the least that shows it, or centred.
    private func reveal(_ id: String, _ proxy: ScrollViewProxy, center: Bool = false) {
        if ListContainer.collection {
            collection.scrollTo(id, center: center)
        } else {
            animate(Motion.layout) { proxy.scrollTo(id, anchor: center ? .center : nil) }
        }
    }

    /// The swipe's view of this screen: the app's state, and the floating bar over the list's foot.
    private func setUpSwipe() {
        let app = app, source = source
        swipe.foot = app.isSplit ? 8 : Metric.fab + 6
        swipe.canStart = { app.shown == source && app.deletedList(source) == nil && app.dateTarget == nil }
        swipe.enter = { app.startSelecting(source) }
        swipe.selection = { app.isSelecting(source) ? app.selected : [] }
        swipe.apply = { app.selected = $0 }
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
                    // them; a checklist box toggles in one op (IX:1540–1543). A deleted list's only read.
                    let live = app.deletedList(source) == nil
                    MarkdownText(text: notes, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5,
                                 onToggle: live ? { new, checking in
                                     app.setNotes(list: id, new, name: checking ? "Check Item" : "Uncheck Item")
                                 } : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if live { app.editListNotes(id) } }
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
    /// A deleted list's, "In Trash" (§28).
    private var subtitle: String? {
        if app.deletedList(source) != nil { return "In Trash" }
        return source == .today ? DateLabel.long(app.today, today: app.today) : nil
    }

    // MARK: Rows

    private func listLine(_ line: Line, airless: Bool = false, picks: Picks) -> some View {
        row(line, airless: airless, picks: picks)
            .endsAddingOnTap(!line.isDraft && !isEdited(line))
            .listRow()
    }

    /// A heading whose name or notes are being typed, in place.
    private func isEdited(_ line: Line) -> Bool {
        switch line {
        case let .heading(h, _, notes):
            if case .rename(h.id, _)? = app.draft?.kind { true } else if notes, case .notes(h.id, _)? = app.draft?.kind { true } else { false }
        case let .headingNotes(h): if case .notes(h.id, _)? = app.draft?.kind { true } else { false }
        default: false
        }
    }

    /// A heading's notes: in its row, or their own row around a fold, drawn the same way so the switch doesn't show.
    private func headingNotes(_ h: TaskModel) -> some View {
        HeadingNotesRow(heading: h)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                if case .notes(h.id, _)? = app.draft?.kind { draftFrame = $0 }
            }
            .contextMenu { if !selecting { HeadingMenu(heading: h) } }
    }

    @ViewBuilder private func row(_ line: Line, airless: Bool = false, picks: Picks) -> some View {
        switch line {
        case let .group(_, title, sub, quiet):
            GroupLabel(title: title, sub: sub, quiet: quiet, top: airless ? 0 : GroupLabel.air)
                .allowsHitTesting(false)
        case let .heading(h, count, notes):
            // Its notes in its row: they lift with it, and no drag opens a gap between them.
            VStack(spacing: 0) {
                HeadingRow(heading: h, count: count, top: 0)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                        if case .rename(h.id, _)? = app.draft?.kind { draftFrame = $0 }
                    }
                    // In select mode a heading isn't selectable, and its menu is off; its chevron still folds (§3).
                    .contextMenu { if !selecting { HeadingMenu(heading: h) } }
                if notes { headingNotes(h) }
            }
        case let .headingNotes(h):
            headingNotes(h)
                .motionTransition(.opacity)
        case let .task(t, indent, groupDay, day):
            // On the phone the row whose details are open keeps the selected fill, then fades out as they close.
            let row = TaskRow(task: t, source: source, indent: indent, groupDay: groupDay, day: day,
                              selected: app.flashed.contains(t.id) || (app.isSplit ? app.selectedTask == t.id : app.detailTask == t.id),
                              picked: picks.selected.contains(t.id), joinTop: picks.above.contains(t.id),
                              joinBottom: picks.below.contains(t.id))
                .motionTransition(.opacity)
                // The swipe's map of the rows on screen.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { swipe.frames[t.id] = $0 }
                .onDisappear { swipe.frames[t.id] = nil }
            if app.deletedList(source) != nil {
                // A deleted list's rows are deaf, as on the Mac (§28, the user's A): a task comes out from Trash's
                // row for its list, where a tap opens its details.
                row.disabled(true)
            } else {
                // In select mode, swipes are off and a long-press is the selection's menu, with the row added to the
                // selection as the menu comes up (§3). The menu's content appears only then; a gesture on the row
                // would stop the menu, and a hold beside it on the list never begins.
                row
                    .modifier(TaskSwipes(task: t, source: source, enabled: !selecting))
                    .contextMenu {
                        if selecting {
                            SelectionMenu(ids: app.menuTargets(source, adding: t.id), source: source)
                                .onAppear { if app.isSelecting(source) { app.selected.insert(t.id) } }
                        } else {
                            TaskMenu(task: t, source: source)
                        }
                    }
            }
        case let .completedToggle(key, count, open):
            CompletedToggleRow(key: key, count: count, open: open, top: 0)
        case let .deletedList(l, _, open, day):
            // Not selectable: in select mode its chevron still expands it, and the tasks inside it select (§3).
            DeletedListRow(list: l, open: open, day: day)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !selecting {
                        Button { app.restoreList(l.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                            .tint(p.accent)
                    }
                }
                .contextMenu {
                    if !selecting {
                        // The Mac's Open · Show Details · ── · Restore List; on the phone they open the same thing.
                        Button { app.openDeletedList(l.id) } label: { Label("Open", systemImage: "arrow.right.circle") }
                        Divider()
                        Button { app.restoreList(l.id) } label: { Label("Restore List", systemImage: "arrow.uturn.backward") }
                    }
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
        case let .edge(_, height):
            Color.clear.frame(height: height).accessibilityHidden(true)
        }
    }
}

/// A list's notes being typed, under its title: the notes editor, written once as it ends ("Edit List Notes").
struct ListNotesEditor: View {
    /// Typed into as it appears (`NotesEditor.live`), on the collection view.
    var live = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @FocusState private var focus: DetailField?
    private var text: Binding<String> { Binding(get: { app.draft?.title ?? "" }, set: { app.draft?.title = $0 }) }

    var body: some View {
        NotesEditor(text: text, live: live, focus: $focus, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5, minHeight: 60) { _, _ in }
            .accessibilityIdentifier("listNotes")
            .onAppear { DispatchQueue.main.async { focus = .notes } }
            // The caret left the notes (a tap elsewhere, the keyboard put away): they're written, once.
            .onChange(of: focus) { old, new in
                if old != nil, new == nil, app.draft?.editsListNotes == true { app.endDraft() }
            }
    }
}

/// Swipe right completes; swipe left sets the When or deletes. In Trash, swipe right puts back. None in select mode
/// (`enabled`), where the rows keep their place in the view tree.
struct TaskSwipes: ViewModifier {
    let task: TaskModel
    let source: Source
    var enabled = true
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        if source == .trash {
            content.swipeActions(edge: .leading, allowsFullSwipe: true) {
                if enabled, app.canPutBack(task) {
                    Button { app.putBack(task.id) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
            }
        } else {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if enabled {
                        Button { app.toggle(task.id) } label: {
                            Label(task.isDone ? "Not Done" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(p.accent)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if enabled {
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
}

/// In select mode, which rows are selected, and which join the selected row above or below them: their shared corners
/// go square, so neighbours read as one block (§3). A heading, a label or the Completed row breaks the block.
struct Picks {
    var selected: Set<EntityID> = []
    var above: Set<EntityID> = []
    var below: Set<EntityID> = []

    @MainActor init(_ lines: [Line], selected: Set<EntityID>) {
        self.selected = selected
        guard !selected.isEmpty else { return }
        var prev: EntityID?
        for line in lines {
            if case let .task(t, _, _, _) = line, selected.contains(t.id) {
                if let p = prev {
                    above.insert(t.id)
                    below.insert(p)
                }
                prev = t.id
            } else {
                prev = nil
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
            // Put Back · Put Back in ▸; one whose list is in Trash has nowhere to go back to: Put Back in ▸ (the
            // Mac's `Menus.trash`; a tap stands in for Show Details).
            if app.canPutBack(task) {
                Button { app.putBack(task.id) } label: { Label("Put Back", systemImage: "arrow.uturn.backward") }
            }
            Menu {
                PutBackInItems(task: task)
            } label: { Label("Put Back in", systemImage: "tray.and.arrow.up") }
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

/// "Put back in" (§28; the Mac's `putBackInItems`): every live list and the tasks' own deleted lists, in the sidebar's
/// order, under the menu's "Put back in". Their own deleted lists are disabled, "In Trash" the second line; one task's
/// own live list is checked, and picking it is a plain Put Back. Names are cut as Move to cuts them.
struct PutBackInItems: View {
    let ids: [EntityID]
    @Environment(AppModel.self) private var app
    init(task: TaskModel) { ids = [task.id] }
    /// A selection's (§3).
    init(ids: [EntityID]) { self.ids = ids }
    var body: some View {
        Section("Put back in") {
            ForEach(app.putBackTargets(ids.compactMap(app.task))) { target in
                let name = MenuName.fit(app.listName(target.id))
                Button { app.putBackTasks(ids, in: target.id) } label: {
                    if target.inTrash {
                        Text(name)
                        Text("In Trash")
                    } else if target.home {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
                .disabled(target.inTrash)
            }
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
        let fold = Button { app.toggleCollapse(heading.id) } label: {
            Label(collapsed ? "Expand" : "Collapse", systemImage: collapsed ? "chevron.down" : "chevron.right")
        }
        // In a deleted list it folds, and that's all (§28, the Mac's `readOnlyHeading`).
        if app.isTrashed(heading) {
            fold
        } else {
            menu(fold)
        }
    }

    @ViewBuilder private func menu(_ fold: some View) -> some View {
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
        fold
        Divider()
        Button(role: .destructive) { app.deleteHeading(heading.id) } label: { Label("Delete Heading", systemImage: "trash") }
    }
}

/// A list's "…" (batch 2 §0): Undo and Redo, Select, then New Heading, Rename, Add Notes or Edit Notes, show or hide
/// completed, and Delete List (at once, with Undo).
struct ListMenu: View {
    let listID: EntityID
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            UndoItems()
            SelectItem(source: .list(listID))
            Divider()
            Button { app.newHeading(in: listID) } label: {
                Label("New Heading", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { app.listEditor = .init(listID: listID, name: app.list(listID)?.name ?? "") } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { app.editListNotes(listID) } label: {
                Label(app.list(listID)?.notes.isEmpty ?? true ? "Add Notes" : "Edit Notes", systemImage: "text.alignleft")
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
