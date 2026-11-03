import SwiftUI
import TasksCore

/// A task on the row grid: checkbox, title, the notes hint, the quiet When after it, the list's name where the view
/// mixes lists, and the deadline capsule at the end.
struct TaskRow: View {
    let task: TaskModel
    let source: Source
    var indent = false
    var groupDay: CalendarDate? = nil
    /// In a month group of Completed or Trash: the day, after the list's name.
    var day: CalendarDate? = nil
    var selected = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trashed: Bool { app.isTrashed(task) }
    private var done: Bool { task.isDone }
    private var settled: Bool { done && !app.completing.contains(task.id) }

    var body: some View {
        Button { open() } label: {
            HStack(spacing: 0) {
                Checkbox(checked: done, title: title, cue: app.cue(task, in: source), readOnly: trashed) {
                    app.toggle(task.id)
                }
                .padding(.leading, Metric.rowPad - 11)   // the 44pt hit area centres the 22pt ring
                .padding(.trailing, Metric.titleGap - 11)

                TitleThenName(after: task.deadline != nil && showsDates ? 8 : 0) {
                    TitleSlot {
                        HStack(spacing: 8) {
                            // Cut off, its last 31pt fade out (§24); the notes hint after it stays whole.
                            Text(title)
                                .font(Typo.row)
                                .foregroundStyle(titleColor)
                                // Struck at once, as on the Mac; the row moves when the checks settle (§8).
                                .strikethrough(done, color: p.inkQuiet)
                                .animation(reduceMotion ? nil : .easeOut(duration: done ? 0.7 : 0.2), value: done)
                                .fadeTruncation(Metric.titleFade, text: title)
                            if !settled { NotesHint(summary: task.notesSummary).fixedSize() }
                        }
                        if let w = task.when, shows(when: w) { QuietWhen(date: w) }
                    }
                    if let name = whereName {
                        Text(name)
                            .font(Typo.quiet)
                            .foregroundStyle(p.inkTertiary)
                            .fadeTruncation(Metric.titleFade, text: name)
                    }
                }
                if let d = task.deadline, showsDates { DeadlineChip(date: d, groupDay: groupDay) }
            }
            .padding(.trailing, 12)
            .padding(.leading, indent ? 30 : 0)
            .frame(minHeight: Metric.rowHeight)
        }
        .buttonStyle(RowStyle(selected: selected, fadesOut: !app.isSplit))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String { task.title.isEmpty ? "New Task" : task.title }

    private var titleColor: Color {
        if done { return p.inkTertiary }
        if trashed { return p.inkSecondary }
        return task.title.isEmpty ? p.inkTertiary : p.ink
    }

    /// Done and trashed rows show no dates (§24, §22).
    private var showsDates: Bool { !done && !trashed }

    /// Only the date that places the row is hidden: in Today a When on or before today, in Upcoming its group's own
    /// day (the Mac's `TaskListView.swift:345`).
    private func shows(when w: CalendarDate) -> Bool {
        showsDates && !(source == .today && w <= app.today) && w != groupDay
    }

    /// Where each task lives, in views that mix lists: Upcoming, Completed and Trash, with the day in a month group
    /// ("School · Oct 22"); Today's Completed group. Not under a deleted list's row (§28). The Mac's `whereText`.
    private var whereName: String? {
        guard !indent else { return nil }
        let name = app.listName(task.list)
        switch source {
        case .upcoming, .completed, .trash: return name + (day.map { " · " + DateLabel.monthDay($0) } ?? "")
        case .today: return settled ? name : nil
        default: return nil
        }
    }

    private func open() {
        if app.isSplit { app.selectedTask = task.id } else { app.detailTask = task.id }
    }
}

/// What a row shows of the notes (MARKDOWN.md §7, `NotesSummary`): the checklist's count, "2/5", or the notes glyph.
struct NotesHint: View {
    let summary: NotesSummary
    @Environment(\.palette) private var p
    var body: some View {
        if summary.total > 0 {
            Text("\(summary.checked)/\(summary.total)")
                .font(Typo.chip).monospacedDigit()
                .foregroundStyle(p.inkQuiet)
                .accessibilityLabel("\(summary.checked) of \(summary.total) checked")
        } else if summary.hasNotes {
            Image(systemName: "text.alignleft")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.inkQuiet)
                .accessibilityLabel("Has notes")
        }
    }
}

/// A heading (§23): its name, 15 semibold ink at the checkbox's edge, on a hairline; its notes under it, a step
/// quieter; the chevron at the right, always shown (there's no hover). Collapsed, its open tasks' count follows the
/// name. A tap on the name renames it in place (the phone has no heading details to select it for), a tap on its notes
/// edits them, and the chevron takes its own tap: it never renames.
struct HeadingRow: View {
    let heading: TaskModel
    let count: Int
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: DetailField?

    private var collapsed: Bool { app.collapsed.contains(heading.id) }
    private var renaming: Bool {
        if case let .rename(h, _)? = app.draft?.kind { h == heading.id } else { false }
    }
    private var editingNotes: Bool {
        if case let .notes(h, _)? = app.draft?.kind { h == heading.id } else { false }
    }
    private var text: Binding<String> { Binding(get: { app.draft?.title ?? "" }, set: { app.draft?.title = $0 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if renaming { nameField } else { name }
                chevron
            }
            .hairline(renaming ? .clear : p.lineSeparator, leading: Metric.rowPad, trailing: Metric.rowPad)
            if !collapsed { notes }
        }
        .padding(.top, 11)
        .padding(.bottom, 4)
        .onChange(of: focus) { old, new in
            // The caret left the field (a tap elsewhere, the keyboard put away): it's written, once.
            if old != nil, new == nil, renaming || editingNotes { app.endDraft() }
        }
    }

    private var name: some View {
        Button { app.renameHeading(heading.id) } label: {
            HStack(spacing: 8) {
                Text(heading.title).font(Typo.heading).foregroundStyle(p.ink).lineLimit(1)
                if collapsed {
                    Text("\(count)").font(Typo.chip).monospacedDigit().foregroundStyle(p.inkTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Metric.rowPad)
            .padding(.vertical, 9)
        }
        .buttonStyle(RowStyle())
        .accessibilityLabel(heading.title)
        .accessibilityValue(collapsed ? "Collapsed, \(count) open" : "")
        .accessibilityHint("Renames it")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("heading")
    }

    /// Renaming: the field in place, in the heading's font, with the new-task row's look.
    private var nameField: some View {
        TextField("New Heading", text: text, prompt: Text("New Heading").foregroundStyle(p.inkTertiary))
            .font(Typo.heading)
            .foregroundStyle(p.ink)
            .focused($focus, equals: .title)
            .submitLabel(.done)
            .onSubmit { app.submitDraft() }
            .accessibilityIdentifier("headingName")
            .padding(.leading, Metric.rowPad)
            .padding(.vertical, 9)
            .background(p.base, in: RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
            .onAppear { DispatchQueue.main.async { focus = .title } }
    }

    /// Down when open, right when collapsed, turning in 200 ms ease-out. Above the row's press: it never renames.
    private var chevron: some View {
        Button { app.toggleCollapse(heading.id) } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.inkTertiary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: collapsed)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Expand \(heading.title)" : "Collapse \(heading.title)")
        .accessibilityIdentifier("chevron")
    }

    /// Its notes, at its name's edge: rendered at rest (a box toggles in one op), the notes editor while editing.
    @ViewBuilder private var notes: some View {
        if editingNotes {
            NotesEditor(text: text, focus: $focus, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5, minHeight: 60) { _, _ in }
                .accessibilityIdentifier("headingNotes")
                .padding(.horizontal, Metric.rowPad)
                .padding(.top, 3)
                .padding(.bottom, 8)
                .onAppear { DispatchQueue.main.async { focus = .notes } }
        } else if !heading.notes.isEmpty {
            MarkdownText(text: heading.notes, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5) { new, checking in
                app.setNotes(heading.id, new, name: checking ? "Check Item" : "Uncheck Item")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { app.editHeadingNotes(heading.id) }
            .padding(.horizontal, Metric.rowPad)
            .padding(.top, 3)
            .padding(.bottom, 8)
        }
    }
}

/// "Completed 4": the disclosure at a list's end.
struct CompletedToggleRow: View {
    /// A list's id, or `AppModel.todayDone`.
    let key: String
    let count: Int
    let open: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Button {
            animate(Motion.layout) {
                if open { app.showCompleted.remove(key) } else { app.showCompleted.insert(key) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 22)
                Text("Completed").font(Typo.rowMedium).foregroundStyle(p.inkSecondary)
                Text("\(count)").font(Typo.row).monospacedDigit().foregroundStyle(p.inkTertiary)
                Spacer()
            }
            .foregroundStyle(p.inkTertiary)
            .padding(.leading, Metric.rowPad)
            .frame(minHeight: Metric.rowHeight)
        }
        .buttonStyle(RowStyle())
        .padding(.top, 8)
        .accessibilityLabel(open ? "Hide completed tasks" : "Show \(count) completed tasks")
    }
}

/// A deleted list in Trash: one row on the day it was deleted, its tile on the checkbox's column, "11 tasks", and a
/// chevron that shows what it holds.
struct DeletedListRow: View {
    let list: ListModel
    let open: Bool
    /// In a month group: the day it was deleted, after its count ("2 tasks · Oct 22").
    var day: CalendarDate? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 0) {
                ListTile(content: .mono(list.monogram), hue: p.tile(slot: list.colorSlot))
                    .frame(width: 44)
                    .padding(.leading, Metric.rowPad - 11)
                    .padding(.trailing, Metric.titleGap - 11)
                // A title on the Mac (its TaskRowView): cut off, it fades out; the count after it stays whole.
                Text(list.name).font(Typo.rowMedium).foregroundStyle(p.inkSecondary)
                    .fadeTruncation(Metric.titleFade, text: list.name)
                Text(app.deletedListCount(list.id) + (day.map { " · " + DateLabel.monthDay($0) } ?? ""))
                    .font(Typo.quiet).foregroundStyle(p.inkTertiary).fixedSize().padding(.leading, 8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.inkTertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 30, height: 30)
            }
            .padding(.trailing, 8)
            .frame(minHeight: Metric.rowHeight)
        }
        .buttonStyle(RowStyle())
        .accessibilityLabel("\(list.name), deleted list, \(app.deletedListCount(list.id))")
        .accessibilityHint(open ? "Hides its tasks" : "Shows its tasks")
    }
    private func toggle() {
        animate(Motion.layout) {
            if open { app.expandedTrash.remove(list.id) } else { app.expandedTrash.insert(list.id) }
        }
    }
}

/// The row a new task is typed into: the row's own fill with a 1.5pt accent ring and a quiet placeholder box. A new
/// heading's is the heading's row, with the same look on its name (§23).
struct DraftRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    let token: UUID

    private var heading: Bool {
        if case .heading? = app.draft?.kind { true } else { false }
    }
    private var text: Binding<String> { Binding(get: { app.draft?.title ?? "" }, set: { app.draft?.title = $0 }) }

    var body: some View {
        Group {
            if heading {
                TextField("New Heading", text: text, prompt: Text("New Heading").foregroundStyle(p.inkTertiary))
                    .font(Typo.heading)
                    .foregroundStyle(p.ink)
                    .focused($focused)
                    .accessibilityIdentifier("draft")
                    .submitLabel(.done)
                    .onSubmit { app.submitDraft() }
                    .padding(.leading, Metric.rowPad)
                    .padding(.vertical, 9)
                    .padding(.trailing, 44)
                    .background(p.base, in: RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
                    .padding(.top, 11)
                    .padding(.bottom, 4)
            } else {
                HStack(spacing: 0) {
                    Checkbox(checked: false, placeholder: true)
                        .padding(.leading, Metric.rowPad - 11)
                        .padding(.trailing, Metric.titleGap - 11)
                    TextField("New Task", text: text, prompt: Text("New Task").foregroundStyle(p.inkTertiary))
                        .font(Typo.row)
                        .foregroundStyle(p.ink)
                        .focused($focused)
                        .accessibilityIdentifier("draft")
                        .submitLabel(.next)
                        .onSubmit { app.submitDraft() }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 12)
                .frame(minHeight: Metric.rowHeight)
                .background(p.base, in: RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) { _, now in
            // The caret left the row (a tap elsewhere, the keyboard swiped away): a title is written, an empty row goes.
            guard !now, app.draft?.token == token else { return }
            app.endDraft()
        }
    }
}

/// A view's empty state, centred in the pane.
struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String
    @Environment(\.palette) private var p
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(p.inkQuiet).padding(.bottom, 4)
            Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(p.inkSecondary)
            if !message.isEmpty {
                Text(message).font(Typo.body).foregroundStyle(p.inkTertiary).multilineTextAlignment(.center).frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// The title and the quiet When after it, as the Mac lays them out when narrow: the title keeps up to 156pt; the When
/// drops before the title goes under that.
struct TitleSlot: Layout {
    var minTitle: CGFloat = Metric.titleKeep
    var gap: CGFloat = 8

    private func plan(_ width: CGFloat, _ subviews: Subviews) -> (title: CGFloat, when: CGSize?) {
        let t = subviews[0].sizeThatFits(.unspecified)
        guard subviews.count > 1 else { return (min(t.width, width), nil) }
        let w = subviews[1].sizeThatFits(.unspecified)
        if width - w.width - gap >= min(minTitle, t.width) { return (min(t.width, width - w.width - gap), w) }
        return (min(t.width, width), nil)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let p = plan(width, subviews)
        // The title's own answer: its width, or more when it can't go that narrow (its notes hint stays whole).
        let t = subviews[0].sizeThatFits(ProposedViewSize(width: p.title, height: nil))
        let total = t.width + (p.when.map { $0.width + gap } ?? 0)
        return CGSize(width: total, height: max(t.height, p.when?.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(bounds.width, subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: p.title, height: bounds.height))
        guard subviews.count > 1 else { return }
        if let w = p.when {
            subviews[1].place(at: CGPoint(x: bounds.minX + p.title + gap, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(w))
        } else {
            // Dropped: placed out of sight (a layout can't remove a child).
            subviews[1].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.midY), anchor: .leading, proposal: .zero)
        }
    }
}

/// A row's title slot and, in the views that mix lists, the list's name at the row's end, shared out as the Mac shares
/// a short row (INTERACTIONS-v2 §24 "A short row", the Mac's TaskRowView): the title keeps up to 156pt and its notes
/// hint, the name up to 94pt (the Mac's 72); room beyond those goes to the title first, then to the name, which is cut
/// and fades out like a title. A name that would show less than 42pt (the Mac's 32), or less than all of a shorter
/// one, goes, and the title gets its room. The title's slot ends 8 short of what follows; the name sits at the end,
/// `after` short of it (the gap before the deadline), only when it shows.
struct TitleThenName: Layout {
    var after: CGFloat = 0
    var titleKeep: CGFloat = Metric.titleKeep
    var nameKeep: CGFloat = Metric.listNameKeep
    var nameMin: CGFloat = Metric.listNameMin
    var gap: CGFloat = 8

    private func plan(_ width: CGFloat, _ subviews: Subviews) -> (lead: CGFloat, name: CGFloat) {
        let lead = subviews[0].sizeThatFits(.unspecified).width
        let room = max(0, width - gap)
        guard subviews.count > 1 else { return (min(lead, room), 0) }
        let name = subviews[1].sizeThatFits(.unspecified).width
        let avail = room - after
        if lead + name <= avail { return (lead, name) }
        // What the slot keeps: up to 156pt of the title, plus what it can't give up (the hint).
        let hint = subviews[0].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        let leadKeep = min(lead, titleKeep + hint)
        let cut = min(name, max(min(name, nameKeep), avail - lead), max(0, avail - leadKeep))
        // Less than a few letters of the name reads as noise: then it goes (the Mac's `whereMin`).
        if cut < min(name, nameMin) { return (min(lead, room), 0) }
        return (min(lead, avail - cut), cut)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews[0].sizeThatFits(.unspecified).width + gap
            + (subviews.count > 1 ? subviews[1].sizeThatFits(.unspecified).width + after : 0)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural
        let p = plan(width, subviews)
        let h = subviews.indices.map { i in
            subviews[i].sizeThatFits(ProposedViewSize(width: i == 0 ? p.lead : p.name, height: nil)).height
        }.max() ?? 0
        // It fills the row, as the Spacer between them did.
        return CGSize(width: width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(bounds.width, subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: p.lead, height: bounds.height))
        guard subviews.count > 1 else { return }
        guard p.name > 0 else {
            // Gone: placed out of sight, as TitleSlot drops the When (a layout can't remove a child).
            subviews[1].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.midY), anchor: .leading, proposal: .zero)
            return
        }
        subviews[1].place(at: CGPoint(x: bounds.maxX - after, y: bounds.midY), anchor: .trailing,
                          proposal: ProposedViewSize(width: p.name, height: bounds.height))
    }
}
