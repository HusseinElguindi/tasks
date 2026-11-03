import SwiftUI
import TasksCore

/// A task's details: checkbox and title, List / When / Deadline, then its notes. A sheet on the phone, the third pane
/// on iPad.
struct TaskDetailView: View {
    let taskID: EntityID
    var inline = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        @Bindable var app = app
        Group {
            if let t = app.task(taskID), !t.isHeading {
                TaskDetailContent(task: t, inline: inline)
            } else {
                NothingSelected()
            }
        }
        .background(inline ? Color.clear : p.base)
        .sheet(item: inline ? .constant(nil) : $app.dateTarget) { target in
            DatePickerSheet(target: target).themed(app).datePickerPresentation()
        }
    }
}

/// The details of one task. The title and the notes are edited here and written once when their editing ends (leaving
/// the field, or closing the details), as the Mac commits them once per editing session: one op, one undo step, and
/// only if the user changed the text from where the edit began (`EditSession`).
private struct TaskDetailContent: View {
    let task: TaskModel
    let inline: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @FocusState private var focus: DetailField?
    @State private var title: String
    @State private var notes: String
    /// Each field's text when its edit began; nil while it isn't being edited. While a field has the caret it ignores
    /// the model, so a change that syncs in meanwhile shows once the edit ends without a write.
    @State private var titleBase: String?
    @State private var notesBase: String?

    init(task: TaskModel, inline: Bool) {
        self.task = task
        self.inline = inline
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
    }

    private var t: TaskModel { task }

    var body: some View {
        let trashed = app.isTrashed(t)
        VStack(spacing: 0) {
            topBar(trashed: trashed)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if trashed { trashBanner }
                    HStack(alignment: .top, spacing: 0) {
                        Checkbox(checked: t.isDone, title: t.title.isEmpty ? "New Task" : t.title, cue: app.cue(t, in: .list(t.list)),
                                 readOnly: trashed, size: 24, sparks: t.isDone && app.completing.contains(t.id)) {
                            app.toggle(t.id)
                        }
                        .padding(.leading, -10)
                        .padding(.top, -10)
                        .padding(.trailing, 2)
                        TextField("New Task", text: $title, prompt: Text("New Task").foregroundStyle(p.inkTertiary), axis: .vertical)
                            .font(Typo.detailTitle)
                            .foregroundStyle(t.isDone ? p.inkSecondary : p.ink)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                            .disabled(trashed)
                            .onSubmit { focus = nil }
                            // One line (IX:599): a typed Return ends the edit, pasted line breaks become spaces.
                            .onChange(of: title) { old, new in
                                guard focus == .title, new.contains(where: \.isNewline) else { return }
                                if let typed = TitleText.typedReturn(old: old, new: new) {
                                    title = typed
                                    focus = nil
                                } else {
                                    title = TitleText.oneLine(new)
                                }
                            }
                    }
                    .padding(.top, 6)

                    VStack(spacing: 0) {
                        listRow(trashed: trashed)
                        dateRow(.when, trashed: trashed)
                        dateRow(.deadline, trashed: trashed)
                    }
                    .padding(.top, 14)

                    Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.top, 12).padding(.bottom, 14)

                    NotesEditor(text: $notes, readOnly: trashed, focus: $focus) { new, checking in
                        // A box clicked outside editing is its own step, "Check Item" or "Uncheck Item" (§5).
                        notes = new
                        app.setNotes(t.id, new, name: checking ? "Check Item" : "Uncheck Item")
                    }

                    Text(meta)
                        .font(Typo.meta)
                        .foregroundStyle(p.inkTertiary)
                        .lineLimit(1)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: focus) { old, new in
            if old == .title && new != .title { endTitle() }
            if old == .notes && new != .notes { endNotes() }
            if new == .title && old != .title { titleBase = title }
            if new == .notes && old != .notes { notesBase = notes }
        }
        .onDisappear { endTitle(); endNotes() }
        // Leaving the app mid-edit writes what was typed so far, before the app saves on going to the background (iOS
        // may end it there); the edit goes on from that text.
        .onChange(of: phase) { _, now in if now != .active { saveTitle(); saveNotes() } }
        // Another device's edit, or an undo, while this field isn't being edited.
        .onChange(of: t.title) { _, v in if focus != .title { title = v } }
        .onChange(of: t.notes) { _, v in if focus != .notes { notes = v } }
    }

    /// The title's edit ends: one write if the user changed it from where the edit began; otherwise the field shows
    /// the model's title, which a sync may have changed meanwhile. "Rename Task", as on the Mac.
    private func endTitle() {
        guard let base = titleBase else { return }
        titleBase = nil
        if let text = EditSession.write(title, original: base, current: t.title) {
            app.setTitle(t.id, text, name: "Rename Task")
        } else if title != t.title {
            title = t.title
        }
    }

    private func endNotes() {
        guard let base = notesBase else { return }
        notesBase = nil
        if let text = EditSession.write(notes, original: base, current: t.notes) {
            app.setNotes(t.id, text)
        } else if notes != t.notes {
            notes = t.notes
        }
    }

    /// The app leaves the front mid-edit: what the user changed so far is written, and the edit carries on from it. The
    /// field keeps the caret, so it keeps its text either way.
    private func saveTitle() {
        guard let base = titleBase, let text = EditSession.write(title, original: base, current: t.title) else { return }
        app.setTitle(t.id, text, name: "Rename Task")
        titleBase = text
    }

    private func saveNotes() {
        guard let base = notesBase, let text = EditSession.write(notes, original: base, current: t.notes) else { return }
        app.setNotes(t.id, text)
        notesBase = text
    }

    // MARK: Bar

    private func topBar(trashed: Bool) -> some View {
        HStack(spacing: 8) {
            if let l = app.list(t.list) {
                let name = HStack(spacing: 8) {
                    ListTile(content: .mono(l.monogram), hue: p.tile(slot: l.colorSlot), scale: 0.85)
                    Text(l.name).font(Typo.body).foregroundStyle(p.inkSecondary).lineLimit(1)
                }
                if let show = app.showInName(t, from: app.shown ?? .list(t.list)) {
                    // Opened from Today or a view: its list's name is Show in <list> (the Mac's menu item, §9).
                    Button {
                        endTitle(); endNotes()
                        app.showInList(t.id)
                    } label: {
                        HStack(spacing: 4) {
                            name
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(p.inkTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(show)
                } else {
                    name
                }
            }
            Spacer()
            if trashed {
                if app.canPutBack(t) {
                    BarIcon(symbol: "arrow.uturn.backward", label: "Put Back") { app.putBack(t.id) }
                }
            } else {
                BarIcon(symbol: "trash", label: "Delete") {
                    endTitle(); endNotes()
                    if !inline { dismiss() }
                    app.delete(t.id)
                }
            }
            if inline {
                BarIcon(symbol: "xmark", label: "Hide Details") { app.selectedTask = nil }
            } else {
                Button("Done") { focus = nil; dismiss() }
                    .buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: inline ? 46 : 60)
        .padding(.top, inline ? 0 : 6)
    }

    /// Why it's read-only, and the way out: Put Back for a task deleted on its own, Restore List for one that went with
    /// its list (§28). A task is put back, a list is restored (the Mac's `TrashVerb`).
    private var trashBanner: some View {
        let l = app.list(t.list)
        let listGone = l?.isDeleted ?? true
        return HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(p.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(deletedWords).font(Typo.body).foregroundStyle(p.ink)
                // The list's name is in the bar above and the List row below, each on one line; the banner doesn't
                // repeat it, as the Mac's doesn't (§21), so a long name can't turn it into a paragraph.
                Text(app.canPutBack(t) ? "Read-only until you put it back."
                     : t.deleted ? "Its list is in Trash too. Restore the list, then put this task back."
                     : "Its list is in Trash. Restore the list to bring it back.")
                    .font(Typo.meta).foregroundStyle(p.inkSecondary)
            }
            Spacer(minLength: 8)
            if app.canPutBack(t) {
                Button("Put Back") { app.putBack(t.id) }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 30))
            } else if listGone, let l {
                Button("Restore List") { app.restoreList(l.id) }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 30))
            }
        }
        .padding(12)
        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 14)
    }

    private var deletedWords: String {
        if t.deleted, let item = app.projection.task(t.id) { return "Deleted " + day(Projection.deletedAt(item)) }
        if let at = app.list(t.list)?.archivedAt { return "Deleted with its list, " + day(at) }
        return "Deleted"
    }

    // MARK: Properties

    private func propLabel(_ symbol: String, _ word: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 18)
            Text(word).font(Typo.body)
        }
        .foregroundStyle(p.inkSecondary)
        .frame(width: 104, alignment: .leading)
    }

    private func listRow(trashed: Bool) -> some View {
        HStack(spacing: 0) {
            propLabel("tray", "List")
            Menu {
                ForEach(app.activeLists) { l in
                    Button { app.move(t.id, to: l.id) } label: {
                        let name = MenuName.fit(l.name)
                        if l.id == t.list { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let l = app.list(t.list) {
                        ListTile(content: .mono(l.monogram), hue: p.tile(slot: l.colorSlot), scale: 0.85)
                        // One line, cut with an ellipsis, as the Mac's List pop-up is (a long name used to wrap).
                        Text(l.name).font(Typo.body).foregroundStyle(p.ink).lineLimit(1)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.inkTertiary)
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .padding(.leading, -8)
            .disabled(trashed)
            .accessibilityIdentifier("detailList")
            Spacer()
        }
        .frame(minHeight: 44)
    }

    private func dateRow(_ kind: DateKind, trashed: Bool) -> some View {
        let date = kind == .when ? t.when : t.deadline
        let active = app.dateTarget?.taskID == t.id && app.dateTarget?.kind == kind
        return HStack(spacing: 0) {
            propLabel(kind == .when ? "calendar" : "flag", kind == .when ? "When" : "Deadline")
            Button { app.dateTarget = DateTarget(taskID: t.id, kind: kind) } label: {
                DateChip(date: date, kind: kind, active: active)
            }
            .buttonStyle(.plain)
            .disabled(trashed)
            .accessibilityLabel(kind == .when ? "When" : "Deadline")
            .accessibilityValue(date.map { DateLabel.long($0, today: app.today) } ?? "None")
            if let date {
                Text(words(date, kind))
                    .font(Typo.quiet)
                    .foregroundStyle(wordsColor(date, kind))
                    .padding(.leading, 10)
                    .lineLimit(1)
                if !trashed {
                    Button { app.setDate(t.id, kind, nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.inkTertiary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind == .when ? "Clear When" : "Clear Deadline")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }

    /// The Mac's detail words: a deadline's "2 days overdue", "due today", "3 days left"; a When's "tomorrow", "in 3
    /// days", and "· still in Today" once it's past and the task is open.
    private func words(_ d: CalendarDate, _ kind: DateKind) -> String {
        if kind == .deadline { return DateLabel.deadlineWords(d, today: app.today) }
        return DateLabel.relative(d, today: app.today) + (!t.isDone && d < app.today ? " · still in Today" : "")
    }

    private func wordsColor(_ d: CalendarDate, _ kind: DateKind) -> Color {
        guard kind == .deadline else { return p.inkTertiary }
        switch DateLabel.deadlineChip(d, today: app.today).tone {
        case .late: return p.danger
        case .due: return p.attention
        default: return p.inkTertiary
        }
    }

    /// "Created Oct 26 · Completed Oct 30"; in Trash "Created Aug 20 · Deleted Oct 28", or "Deleted with School, Nov 1"
    /// (the Mac's detail pane).
    private var meta: String {
        var s = "Created " + day(t.createdAt)
        if t.deleted, let item = app.projection.task(t.id) {
            s += " · Deleted " + day(Projection.deletedAt(item))
        } else if let l = app.list(t.list), let at = l.archivedAt {
            s += " · Deleted with " + l.name + ", " + day(at)
        } else if let done = t.completedAt {
            s += " · Completed " + day(done)
        }
        return s + NotesLimit.counter(notes)
    }

    private func day(_ ms: Int) -> String { DateLabel.monthDay(app.localDay(ms)) }
}

enum DetailField { case title, notes }

/// A 34pt round icon button for the detail pane's bar.
struct BarIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var p
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(p.inkSecondary)
                .frame(width: 34, height: 34)
                .background(p.fillControl, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct NothingSelected: View {
    @Environment(\.palette) private var p
    var body: some View {
        VStack(spacing: 6) {
            Text("Nothing selected").font(.system(size: 15, weight: .medium)).foregroundStyle(p.inkSecondary)
            Text("Select a task to see it here.").font(Typo.meta).foregroundStyle(p.inkTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Notes

/// The notes: rendered Markdown at rest (TasksCore's reading, `MarkdownText`), the plain text while editing.
struct NotesEditor: View {
    @Binding var text: String
    var readOnly = false
    var focus: FocusState<DetailField?>.Binding
    /// A task's, in the details; a heading's are a step quieter and shorter (§23).
    var font: Font = Typo.detailNotes
    var ink: Color? = nil
    var lineSpacing: CGFloat = 6
    var minHeight: CGFloat = 180
    /// A checklist box clicked at rest: the new text, and whether it checked the box.
    var onToggle: (String, Bool) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    private var editing: Bool { focus.wrappedValue == .notes }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(font)
                .lineSpacing(lineSpacing)
                .foregroundStyle(ink ?? p.ink)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused(focus, equals: .notes)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .padding(.horizontal, -5)
                .padding(.top, -8)
                .opacity(editing ? 1 : 0)
                .disabled(readOnly)
                // Past 20,000 characters the text is cut there, with the Mac's notice (NotesView.swift:703).
                .onChange(of: text) { _, new in
                    guard new.utf16.count > NotesLimit.max else { return }
                    text = NotesLimit.prefix(new)
                    app.show(Notice(text: NotesLimit.notice, undo: nil))
                }
            if !editing {
                Group {
                    if text.isEmpty {
                        Text("Notes").font(font).foregroundStyle(p.inkTertiary)
                    } else {
                        MarkdownText(text: text, font: font, ink: ink, lineSpacing: lineSpacing, onToggle: readOnly ? nil : onToggle)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { if !readOnly { focus.wrappedValue = .notes } }
            }
        }
    }
}
