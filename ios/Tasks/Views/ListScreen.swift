import SwiftUI
import TasksCore

/// One list, or one of the views, on the row grid. The large title scrolls with the rows; the bar's title fades in once
/// it has gone under the bar.
struct ListScreen: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @State private var folded = false
    /// Today's all-done sun turns in as it next appears: when Today opens already all done, or its last row settles
    /// while it's open (IX §13). Not when it scrolls back into view.
    @State private var sunRise = true
    /// Counts the times Today became all done while open, for the light haptic as the sun appears.
    @State private var sunHaptic = 0
    /// The collection's scrolling (TaskCollection.swift).
    @State private var collection = CollectionProxy()

    private var adding: Bool { app.draft?.source == source }
    /// The list's notes are being typed, under its title.
    private var editingNotes: Bool { adding && app.draft?.editsListNotes == true }
    /// In select mode (§3).
    private var selecting: Bool { app.isSelecting(source) }

    var body: some View {
        let lines = app.lines(source)
        let allDone = lines.contains { $0.isAllDone }
        let shownIDs = lines.compactMap { if case let .task(t, _, _, _) = $0 { t.id } else { nil } }
        // The rows are a UICollectionView with the app's SwiftUI rows in its cells (TaskCollection.swift and the
        // area files beside it).
        TaskCollection(source: source, lines: lines, sizes: TaskCollection.signatures(app, source, lines),
                       proxy: collection,
                       folded: Binding(get: { folded }, set: { v in animate(.easeOut(duration: 0.15)) { folded = v } }),
                       sunRise: $sunRise)
            // Its own insets: the keyboard's, and the floating controls' clearance (TaskCollection.swift).
            .ignoresSafeArea(.all, edges: .bottom)
            // A new one for another screen: the stack can swap a screen's source in place (an undo's).
            .id(source)
            // A new heading's row (at the bottom, or above a task) and a new task's in a heading are scrolled into
            // view as adding starts; a new task's own row is at the top, where + is pressed from. The next row after
            // Return is under the last one, already in view.
            .onChange(of: app.draft?.kind) { _, kind in
                guard let kind, adding, kind != .task, app.draft?.editedHeading == nil, !editingNotes else { return }
                collection.scrollTo("draft")
            }
            // An undo or a redo: the first row it touched, scrolled into view (the least that shows it).
            .task(id: app.undoReveal) {
                guard let r = app.undoReveal, app.shown == source else { return }
                try? await Task.sleep(for: .milliseconds(50))
                collection.scrollTo("t:" + r.id)
                app.undoReveal = nil
            }
            // Show in <list>: the task is scrolled into view once the list is up.
            .task(id: app.revealTask) {
                guard let id = app.revealTask, source == .list(app.task(id)?.list ?? "") else { return }
                try? await Task.sleep(for: .milliseconds(350))
                collection.scrollTo("t:" + id, center: true)
                app.revealTask = nil
            }
        // Deleted on another device while open: it turns read-only in place, a row being typed is dropped, and select
        // mode ends.
        .onChange(of: app.deletedList(source) != nil) { _, deleted in
            if deleted, adding { app.cancelDraft() }
            if deleted, selecting { app.endSelecting() }
        }
        // A task that's no longer shown leaves the selection.
        .onChange(of: shownIDs, initial: true) { _, ids in
            if app.isSelecting(source) { app.pruneSelection(ids) }
        }
        // A soft echo of the last check, as the sun appears (1.5 s after it, when the rows settle).
        .sensoryFeedback(.impact(weight: .light), trigger: sunHaptic)
        .onChange(of: allDone) { _, now in
            guard now else { return }
            sunRise = true
            sunHaptic += 1
        }
        .background {
            ZStack {
                if !app.isSplit { AppBackground() }
                if source == .today { Sunrise(shown: allDone) }
            }
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
        // Out of SwiftUI's keyboard avoidance: the collection view keeps the rows clear of the keyboard itself (its
        // bottom inset, TaskCollection.swift). Left in it, the screen's background was laid out short as the keyboard
        // went down after the row holding the caret was removed (a heading's notes emptied): its foot stayed at the
        // keyboard's top, 546 of 874 pt, and the window's black showed under it.
        .ignoresSafeArea(.keyboard)
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
