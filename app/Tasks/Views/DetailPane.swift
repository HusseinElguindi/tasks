import SwiftUI
import TasksCore

/// The detail pane: Return or ⌘D splits it to the right of the list, like Rex's "Split right" (design A1).
struct DetailPane: View {
    let store: Store
    @Bindable var window: WindowState
    let taskID: EntityID
    let showsBack: Bool
    @Environment(\.pane) private var pane

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        if let model = store.projection.taskModel(taskID), !model.deleted {
            PaneChrome("Task", systemImage: "text.alignleft", isActive: window.focus == .detail) {
                if showsBack {
                    PaneIconButton("chevron.left", help: "Back to the list") { window.detailTaskID = nil }
                }
                PaneIconButton("arrow.right", help: "Move to… ⇧⌘M") { window.movePickerPresented = true }
                PaneIconButton("trash", help: "Delete ⌘⌫") {
                    window.selection = [taskID]
                    actions.delete()
                }
                PaneIconButton("xmark", help: "Close ⌘D") {
                    window.detailTaskID = nil
                    window.focus = .list
                }
            } content: {
                TaskDetail(model: model, store: store, window: window)
                    .id(taskID)
            }
            .simultaneousGesture(TapGesture().onEnded { window.focus = .detail })
        } else {
            Color.clear.onAppear { window.detailTaskID = nil }
        }
    }
}

struct TaskDetail: View {
    let model: TaskModel
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane
    @State private var title = ""
    @State private var notes = ""
    @State private var notesMode: NotesMode = .preview
    @State private var whenPicker = false
    @State private var deadlinePicker = false
    @State private var titleCommit: Task<Void, Never>?
    @State private var notesCommit: Task<Void, Never>?
    /// Opening a task doesn't take keyboard focus from the list; choosing Edit does.
    @State private var userChoseMode = false
    @FocusState private var focus: Field?

    enum Field { case title, notes }
    enum NotesMode: Hashable { case edit, preview }

    var body: some View {
        let today = store.projection.dayModel.day.date
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Button { store.toggleComplete([model.id], undoManager: window.undoManager) } label: {
                        PaneCheckbox(isDone: model.isDone)
                    }
                    .buttonStyle(PanePressStyle())
                    .padding(.top, 2)
                    TextField("Title", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(PaneFont.title)
                        .foregroundStyle(model.isDone ? pane.inkSecondary : pane.ink)
                        .focused($focus, equals: .title)
                        .onSubmit {
                            commitTitle()
                            focus = nil
                        }
                }
                notesSection
                fields(today: today)
                Text("Created \(Date(timeIntervalSince1970: TimeInterval(model.createdAt) / 1000).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(PaneFont.subheadline)
                    .foregroundStyle(pane.inkSecondary)
                    .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            title = model.title
            notes = model.notes
            notesMode = model.notes.isEmpty ? .edit : .preview
        }
        .onChange(of: model.title) { _, new in if focus != .title { title = new } }
        .onChange(of: model.notes) { _, new in if focus != .notes { notes = new } }
        // Edits commit on end of editing, or after a ~1 s idle debounce, never per keystroke (spec §5).
        .onChange(of: title) { _, _ in
            titleCommit?.cancel()
            titleCommit = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { commitTitle() } }
        }
        .onChange(of: notes) { _, _ in
            notesCommit?.cancel()
            notesCommit = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { commitNotes() } }
        }
        .onChange(of: focus) { old, new in
            if old == .title { commitTitle() }
            if old == .notes { commitNotes() }
            if new != nil { window.focus = .detail }
        }
        .onDisappear {
            commitTitle()
            commitNotes()
        }
    }

    private func commitTitle() {
        titleCommit?.cancel()
        let t = title.replacingOccurrences(of: "\n", with: " ")
        if t != model.title { store.setTitle(model.id, t, undoManager: window.undoManager) }
    }

    private func commitNotes() {
        notesCommit?.cancel()
        if notes != model.notes { store.setNotes(model.id, notes, undoManager: window.undoManager) }
    }

    /// Notes are Markdown: Edit shows the raw text in mono, Preview renders the inline subset (A3's control).
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                PaneSegmented(options: [(NotesMode.edit, "Edit"), (.preview, "Preview")],
                              selection: Binding(get: { notesMode }, set: { notesMode = $0; userChoseMode = true }))
                    .onChange(of: notesMode) { _, mode in
                        if mode == .edit { if userChoseMode { focus = .notes } } else { commitNotes() }
                    }
            }
            if notesMode == .edit {
                TextEditor(text: $notes)
                    .font(PaneFont.mono(12))
                    .lineSpacing(6)
                    .foregroundStyle(pane.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .notes)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(pane.control.opacity(0.6), in: RoundedRectangle(cornerRadius: PaneRadius.swatch, style: .continuous))
            } else if notes.isEmpty {
                Text("Add notes")
                    .font(PaneFont.body)
                    .foregroundStyle(pane.inkQuiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { userChoseMode = true; notesMode = .edit }
            } else {
                PaneMarkdownText(source: notes)
                    .onTapGesture(count: 2) { userChoseMode = true; notesMode = .edit }
            }
        }
        .padding(.leading, 26)
    }

    /// A hairline group of List / When / Deadline rows. List is a pop-up, so moving from here is one click.
    private func fields(today: CalendarDate) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(pane.separator).frame(height: 1)
            fieldRow("List", icon: "list.bullet") {
                Menu {
                    ForEach(store.projection.activeLists.ids, id: \.self) { id in
                        if let list = store.projection.listModel(id) {
                            Button(list.name.isEmpty ? "Untitled" : list.name) {
                                store.move([model.id], to: id, undoManager: window.undoManager)
                            }
                        }
                    }
                } label: {
                    if let list = store.projection.listModel(model.list) {
                        HStack(spacing: 8) {
                            PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot), size: 16)
                            Text(list.name.isEmpty ? "Untitled" : list.name).foregroundStyle(pane.ink)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(pane.inkSecondary)
                                .frame(width: 20, height: 20)
                                .background(pane.track, in: Circle())
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(PanePressStyle())
                .menuIndicator(.hidden)
                .fixedSize()
            }
            fieldRow("When", icon: "calendar") {
                Button { whenPicker = true } label: {
                    if let when = model.when {
                        PaneChip(text: DateText.long(when, today: today), kind: whenPicker ? .accent : .neutral, large: true)
                    } else {
                        PaneChip(text: "Add date", kind: .ghost, large: true)
                    }
                }
                .buttonStyle(PanePressStyle())
                .popover(isPresented: $whenPicker, arrowEdge: .bottom) {
                    DatePopover(title: "When", date: model.when, other: model.deadline, today: today) { picked in
                        store.setWhen([model.id], picked, undoManager: window.undoManager)
                        whenPicker = false
                    }
                }
                if model.when != nil {
                    Text("Shows in Today from this date").font(PaneFont.subheadline).foregroundStyle(pane.inkSecondary)
                }
            }
            fieldRow("Deadline", icon: "flag") {
                Button { deadlinePicker = true } label: {
                    if let deadline = model.deadline {
                        let status = DeadlineStatus(deadline: deadline, today: today)
                        PaneChip(text: DateText.long(deadline, today: today),
                                 kind: deadlinePicker ? .accent : status == .dueToday ? .due : (status.map { if case .overdue = $0 { true } else { false } } ?? false) ? .late : .neutral,
                                 large: true)
                    } else {
                        PaneChip(text: "Add date", kind: .ghost, large: true)
                    }
                }
                .buttonStyle(PanePressStyle())
                .popover(isPresented: $deadlinePicker, arrowEdge: .bottom) {
                    DatePopover(title: "Deadline", date: model.deadline, other: model.when, today: today) { picked in
                        store.setDeadline([model.id], picked, undoManager: window.undoManager)
                        deadlinePicker = false
                    }
                }
                if let deadline = model.deadline {
                    Text(DateText.relative(deadline, today: today)).font(PaneFont.subheadline).foregroundStyle(pane.inkSecondary)
                }
            }
        }
    }

    private func fieldRow<Content: View>(_ label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 12)).foregroundStyle(pane.inkSecondary).frame(width: 14)
                    Text(label).foregroundStyle(pane.ink)
                }
                .frame(width: 96, alignment: .leading)
                content()
                Spacer(minLength: 0)
            }
            .font(PaneFont.body)
            .frame(minHeight: 38)
            Rectangle().fill(pane.separator).frame(height: 1)
        }
    }
}

/// The date popover: a typed-date field, quick picks, a month grid and "No date" (design: "Date popover").
struct DatePopover: View {
    let title: String
    let date: CalendarDate?
    /// The task's other date, ringed in the grid (the deadline while picking When, and vice versa).
    let other: CalendarDate?
    let today: CalendarDate
    let onPick: (CalendarDate?) -> Void
    @Environment(\.pane) private var pane
    @State private var typed = ""
    @State private var month: CalendarDate?
    @FocusState private var typing: Bool

    var body: some View {
        let shown = month ?? firstOfMonth(date ?? today)
        let parsed = DateText.parse(typed, today: today)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(pane.inkSecondary)
                TextField("Type a date: fri, nov 9, 3d", text: $typed)
                    .textFieldStyle(.plain)
                    .focused($typing)
                    .onSubmit { if let parsed { onPick(parsed) } }
            }
            .font(PaneFont.body)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(pane.control, in: Capsule())
            .overlay { Capsule().strokeBorder(typing ? pane.focusRing : .clear, lineWidth: 2) }
            .padding(.bottom, 6)

            if !typed.isEmpty {
                if let parsed {
                    PaneMenuItem(isHot: true, shortcut: "↩") { onPick(parsed) } label: { Text(DateText.long(parsed, today: today)) }
                } else {
                    Text("Try “fri”, “nov 9” or “3d”.").font(PaneFont.subheadline).foregroundStyle(pane.inkSecondary)
                        .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                PaneMenuSeparator()
            }
            PaneMenuItem(isHot: typed.isEmpty && date == today, shortcut: DateText.weekdayName(today)) { onPick(today) } label: { Text("Today") }
            PaneMenuItem(isHot: date == today.adding(days: 1), shortcut: DateText.weekdayName(today.adding(days: 1))) {
                onPick(today.adding(days: 1))
            } label: { Text("Tomorrow") }
            let nextWeek = DateText.nextWeek(from: today)
            PaneMenuItem(isHot: date == nextWeek, shortcut: DateText.long(nextWeek, today: today)) { onPick(nextWeek) } label: { Text("Next week") }
            PaneMenuSeparator()

            HStack {
                Text(DateText.month(shown)).font(PaneFont.headline).foregroundStyle(pane.ink)
                Spacer()
                PaneIconButton("chevron.left", help: "Previous month") { month = addMonths(shown, -1) }
                PaneIconButton("chevron.right", help: "Next month") { month = addMonths(shown, 1) }
            }
            .foregroundStyle(pane.inkSecondary)
            .padding(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 2))

            MonthGrid(month: shown, picked: date, other: other, today: today, onPick: onPick)
                .padding(.horizontal, 2)

            if other != nil {
                HStack(spacing: 6) {
                    Circle().strokeBorder(pane.attention, lineWidth: 1.5).frame(width: 10, height: 10)
                    Text(title == "When" ? "Deadline" : "When")
                }
                .font(PaneFont.subheadline)
                .foregroundStyle(pane.inkSecondary)
                .padding(EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6))
            }
            PaneMenuSeparator()
            PaneMenuItem(isHot: false, shortcut: "⌫") { onPick(nil) } label: { Text("No date") }
                .keyboardShortcut(.delete, modifiers: [])
        }
        .padding(6)
        .frame(width: 256)
        .onAppear { typing = true }
    }

    private func firstOfMonth(_ d: CalendarDate) -> CalendarDate { CalendarDate(year: d.year, month: d.month, day: 1)! }

    private func addMonths(_ d: CalendarDate, _ n: Int) -> CalendarDate {
        let total = d.month - 1 + n
        let year = d.year + Int((Double(total) / 12).rounded(.down))
        let month = ((total % 12) + 12) % 12 + 1
        return CalendarDate(year: year, month: month, day: 1)!
    }
}

/// Days as 26pt capsules: today in accent-text semibold, the pick in accent / on-accent, the other date ringed.
struct MonthGrid: View {
    let month: CalendarDate
    let picked: CalendarDate?
    let other: CalendarDate?
    let today: CalendarDate
    let onPick: (CalendarDate) -> Void
    @Environment(\.pane) private var pane

    var body: some View {
        let firstWeekday = Calendar.current.firstWeekday // 1 = Sunday
        let lead = (month.weekday - firstWeekday + 7) % 7
        let start = month.adding(days: -lead)
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(i + firstWeekday - 1) % 7])
                    .font(PaneFont.label)
                    .foregroundStyle(pane.inkTertiary)
                    .frame(height: 20)
            }
            ForEach(0..<42, id: \.self) { i in
                let d = start.adding(days: i)
                let isPicked = d == picked
                Button { onPick(d) } label: {
                    Text(verbatim: "\(d.day)")
                        .font(.system(size: 13, weight: isPicked || d == today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isPicked ? pane.onAccent : d == today ? pane.accentText : d.month == month.month ? pane.ink : pane.inkQuiet)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background { if isPicked { Capsule().fill(pane.accent) } }
                        .overlay { if d == other && !isPicked { Capsule().strokeBorder(pane.attention, lineWidth: 1.5) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(PanePressStyle())
            }
        }
    }
}
