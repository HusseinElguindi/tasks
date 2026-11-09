import SwiftUI
import TasksCore

/// A task on the row grid (ROW-DENSITY.md §6, option 3; the user, 2026-11-08: "let's go with 3"): the checkbox, then the
/// title alone on line 1, across the row; on a quiet line 2, the list mark (in views that mix lists), the When, the
/// checklist count and the notes glyph, with the deadline capsule at its right edge; 56pt. When the title and all of
/// those fit on one line, nothing cut (`RowFit`, T55), the row is one 48pt line: the title, then the same parts in the
/// same order, the capsule at the trailing edge. A row with nothing for line 2 is one line too (the notes glyph alone
/// stays after the title), in every view, on the phone and the iPad.
struct TaskRow: View {
    let task: TaskModel
    let source: Source
    var indent = false
    var groupDay: CalendarDate? = nil
    /// In a month group of Completed or Trash: the day, after the list mark.
    var day: CalendarDate? = nil
    var selected = false
    /// In select mode (§3): selected, and joined to the selected row above or below.
    var picked = false
    var joinTop = false
    var joinBottom = false
    /// On the collection view: whether the row had line 2 when its cell was configured (its height signature, fitted
    /// to the row's width: `RowFit`), so it gains or loses the line only as the collection view resizes it, on the
    /// layout spring (CollectionEditing). Nil: whenever its details have anything for line 2.
    var twoLineOverride: Bool? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the checks made here, each of which flashes the row once.
    @State private var flashes = 0

    private var trashed: Bool { app.isTrashed(task) }
    private var done: Bool { task.isDone }
    private var settled: Bool { done && !app.completing.contains(task.id) }
    /// Checked here a moment ago (the box, a swipe, the menu): it sparks, and the row and its title flash warm.
    private var sparks: Bool { done && app.completing.contains(task.id) }
    /// In select mode a tap anywhere on the row, its box too, selects it: no sheet, no haptic (§3).
    private var selecting: Bool { app.isSelecting(source) }

    private var details: RowDetails {
        app.rowDetails(task, source: source, indent: indent, groupDay: groupDay, day: day)
    }
    /// Line 2 is drawn: the state the cell was configured with, else the details'.
    private var twoLine: Bool { twoLineOverride ?? details.twoLine }

    var body: some View {
        Button { guard PressGate.allows else { return }; if selecting { app.toggleSelected(task.id) } else { open() } } label: {
            // The flash (COLOR.md §4, the Mac's `sparkFlashT`): 700 ms ease-out, only for a check made here; none under
            // Reduce Motion, where the title takes ink-tertiary at once.
            KeyframeAnimator(initialValue: 0.0, trigger: flashes) { heat in
                label(heat: heat)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(1.0)
                    LinearKeyframe(0, duration: 0.7, timingCurve: .easeOut)
                }
            }
        }
        .onChange(of: done) { _, now in if now, sparks, !reduceMotion { flashes += 1 } }
        .buttonStyle(RowStyle(selected: selected, fadesOut: !app.isSplit, picked: picked, joinTop: joinTop, joinBottom: joinBottom))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected || picked ? .isSelected : [])
    }

    private func label(heat: Double) -> some View {
        let d = details
        let two = twoLine
        return HStack(spacing: 0) {
            Checkbox(checked: done, title: title, cue: app.cue(task, in: source), readOnly: trashed, sparks: sparks,
                     quiet: app.quietChecks.contains(task.id)) {
                if PressGate.allows { app.toggle(task.id) }
            }
            // In select mode it keeps its ring and cue, and takes no tap of its own: one gesture, one meaning (IX §2.1).
            .allowsHitTesting(!selecting)
            .accessibilityHidden(selecting)
            .padding(.leading, Metric.rowPad - 11)   // the 44pt hit area centres the 22pt ring
            .padding(.trailing, Metric.titleGap - 11)

            // The title keeps its place in both shapes, so it moves with the cell as the row changes shape, and the
            // parts fade out of one line and into the other.
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                HStack(spacing: 0) {
                    titleText(heat: heat)
                    if !two { inlineParts(d) }
                }
                if two { DetailLine(details: d, groupDay: groupDay, upcoming: source == .upcoming) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 12)
        .padding(.leading, indent ? 30 : 0)
        .padding(.vertical, two ? Metric.twoLinePad : 0)
        .frame(minHeight: two ? Metric.twoLineHeight : Metric.rowHeight)
        .background {
            // The row's warm flash as it's checked: its rounded fill, the spark at 14% settling to clear.
            if heat > 0 {
                RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).fill(p.spark.opacity(0.14 * heat))
            }
        }
        // Line 2 comes and goes as the cell is resized, on the same spring (CollectionEditing): the title moves up or
        // down with the cell's growth, and the line fades in or out.
        .motion(Motion.layout, value: two)
    }

    /// Cut off, its last 31pt fade out (§24).
    private func titleText(heat: Double) -> some View {
        Text(title)
            .font(Typo.row)
            // Checked here, it goes from the spark to ink-tertiary (700 ms ease-out); unchecked, back in 200 ms. Struck at
            // once, as on the Mac; the row moves when the checks settle (§8).
            .foregroundStyle(heat > 0 ? p.spark.mix(with: titleColor, by: 1 - heat) : titleColor)
            .strikethrough(done, color: p.inkQuiet)
            .motion(done ? nil : .easeOut(duration: 0.2), value: done)
            .fadeTruncation(Metric.titleFade, text: title)
    }

    /// The one-line row's parts after the title (`RowFit`): 8, line 2's parts in its order, 9 apart (the mark's tile
    /// and name 6), and the capsule at the trailing edge, at least 8 after them. It's chosen when they all fit; a title
    /// that's cut here anyway (the notes glyph alone, which keeps one line) fades, and its parts stay whole.
    @ViewBuilder private func inlineParts(_ d: RowDetails) -> some View {
        HStack(spacing: RowFit.gap) {
            if let l = d.mark {
                HStack(spacing: RowFit.markGap) {
                    ListMarkTile(list: l)
                    ListMarkName(list: l)
                }
            }
            if let day = d.day {
                Text(DateLabel.monthDay(day)).font(Typo.quiet).monospacedDigit().foregroundStyle(p.inkTertiary)
            }
            if let w = d.when { QuietWhen(text: w) }
            if let s = d.summary { NotesHint(summary: s) }
        }
        .fixedSize()
        .padding(.leading, d.mark != nil || d.day != nil || d.when != nil || d.summary != nil ? RowFit.titleGap : 0)
        if let dl = d.deadline {
            Spacer(minLength: RowFit.chipGap)
            DeadlineChip(date: dl, groupDay: groupDay, upcoming: source == .upcoming, compact: true)
        }
    }

    private var title: String { task.title.isEmpty ? "New Task" : task.title }

    private var titleColor: Color {
        if done { return p.inkTertiary }
        if trashed { return p.inkSecondary }
        return task.title.isEmpty ? p.inkTertiary : p.ink
    }

    private func open() {
        if app.isSplit { app.selectedTask = task.id } else { app.detailTask = task.id }
    }
}

/// What a task's row shows besides its title, in a view (§22, §24): the source of both the row and its height signature
/// (`TaskCollection.signatures`), so the two never disagree.
struct RowDetails {
    /// The list mark's list, in views that mix lists.
    var mark: ListModel?
    /// In a month group of Completed or Trash: the day, after the mark.
    var day: CalendarDate?
    /// The When's words, where the view shows it.
    var when: String?
    /// The notes hint (none once a checked row has settled).
    var summary: NotesSummary?
    var deadline: CalendarDate?

    /// Line 2 has something: the notes glyph alone doesn't count, it stays on line 1 (ROW-DENSITY.md §6.4).
    var twoLine: Bool { mark != nil || when != nil || deadline != nil || (summary?.total ?? 0) > 0 }
}

extension AppModel {
    /// A task's row details in `source`.
    /// - The dates: none on done or trashed rows (§24, §22), except while a check made here settles, so the row keeps
    ///   its height until it moves. In Upcoming both dates read as dates, and the group's own day isn't repeated
    ///   (`DateLabel.upcomingWhen`); in Today a When on or before today isn't shown; in lists every When is, "Today" too
    ///   (the user, 2026-11-08: "no keep \"Today\"").
    /// - The mark (§22 "The list mark"): in Upcoming, Completed and Trash, and on Today's Completed rows; not under a
    ///   deleted list's row (§28), nor under a label that names the list.
    /// `when`: the task's When as a drop will write it (Upcoming's drag lays the row out on the day it's over), in place
    /// of its own.
    func rowDetails(_ t: TaskModel, source: Source, indent: Bool, groupDay: CalendarDate?, day: CalendarDate?,
                    when: CalendarDate? = nil) -> RowDetails {
        let trashed = isTrashed(t)
        let settled = t.isDone && !completing.contains(t.id)
        let dates = !settled && !trashed
        var d = RowDetails()
        if dates, let w = when ?? t.when {
            switch source {
            case .upcoming: d.when = DateLabel.upcomingWhen(w, today: today, groupDay: groupDay)
            case .today: d.when = w <= today ? nil : DateLabel.whenChip(w, today: today)
            default: d.when = w == groupDay ? nil : DateLabel.whenChip(w, today: today)
            }
        }
        if dates { d.deadline = t.deadline }
        if !settled {
            let s = t.notesSummary
            if s.total > 0 || s.hasNotes { d.summary = s }
        }
        if !indent {
            switch source {
            case .upcoming, .completed, .trash: d.mark = list(t.list)
            case .today: d.mark = settled ? list(t.list) : nil
            default: break
            }
            if d.mark != nil { d.day = day }
        }
        return d
    }
}

/// A row's line 2 (ROW-DENSITY.md §6.4): 13pt `ink-tertiary`, 20pt tall (more with a larger text size). The mark, the day (Completed and Trash
/// months), the When, the count or the notes glyph, 9 apart; the deadline capsule at the right edge. Short of room, the
/// mark's short name fades first, then the When goes; the tile, the count and the deadline never go.
struct DetailLine: View {
    let details: RowDetails
    var groupDay: CalendarDate? = nil
    var upcoming = false
    @Environment(\.palette) private var p

    var body: some View {
        DetailLayout {
            if let l = details.mark {
                ListMarkTile(list: l).layoutValue(key: DetailRole.self, value: .fixed)
                ListMarkName(list: l).layoutValue(key: DetailRole.self, value: .name)
            }
            if let day = details.day {
                Text(DateLabel.monthDay(day)).font(Typo.quiet).monospacedDigit().foregroundStyle(p.inkTertiary)
                    .fixedSize().layoutValue(key: DetailRole.self, value: .fixed)
            }
            if let w = details.when { QuietWhen(text: w).layoutValue(key: DetailRole.self, value: .when) }
            if let s = details.summary { NotesHint(summary: s).fixedSize().layoutValue(key: DetailRole.self, value: .fixed) }
            if let dl = details.deadline {
                DeadlineChip(date: dl, groupDay: groupDay, upcoming: upcoming, compact: true)
                    .layoutValue(key: DetailRole.self, value: .trailing)
            }
        }
        // 20pt at the default size; it grows with Dynamic Type, as the row does.
        .frame(minHeight: Metric.detailLine)
    }
}

/// A part of line 2, for `DetailLayout`.
enum DetailRole: LayoutValueKey {
    case fixed, name, when, trailing
    static let defaultValue = DetailRole.fixed
}

/// Line 2's layout: the parts from the leading edge, 9 apart (the mark's tile and name 6), the trailing one at the
/// right edge. Short of room: the name is cut (it fades), and goes under 30pt; then the When goes.
struct DetailLayout: Layout {
    var gap: CGFloat = 9
    var markGap: CGFloat = 6
    var nameMin: CGFloat = 30

    private struct Plan { var widths: [CGFloat]; var shown: [Bool] }

    private func plan(_ width: CGFloat, _ subviews: Subviews) -> Plan {
        var widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        var shown = Array(repeating: true, count: subviews.count)
        func roles(_ r: DetailRole) -> [Int] { subviews.indices.filter { subviews[$0][DetailRole.self] == r } }
        func total() -> CGFloat {
            var x: CGFloat = 0
            var prev: DetailRole?
            for i in subviews.indices where shown[i] {
                let r = subviews[i][DetailRole.self]
                if let prev { x += prev == .fixed && r == .name ? markGap : gap }
                x += widths[i]
                prev = r
            }
            return x
        }
        var over = total() - width
        guard over > 0 else { return Plan(widths: widths, shown: shown) }
        for i in roles(.name) {
            let cut = widths[i] - over
            if cut >= min(nameMin, widths[i]) { widths[i] = cut; return Plan(widths: widths, shown: shown) }
            shown[i] = false
        }
        over = total() - width
        guard over > 0 else { return Plan(widths: widths, shown: shown) }
        for i in roles(.when) { shown[i] = false }
        return Plan(widths: widths, shown: shown)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
        let p = plan(width, subviews)
        let h = subviews.indices.filter { p.shown[$0] }.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
        let natural = p.widths.enumerated().filter { p.shown[$0.offset] }.map(\.element).reduce(0, +)
        return CGSize(width: width.isFinite ? width : natural, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(bounds.width, subviews)
        var x = bounds.minX
        var prev: DetailRole?
        for i in subviews.indices {
            let r = subviews[i][DetailRole.self]
            guard p.shown[i] else {
                // Gone: placed out of sight (a layout can't remove a child).
                subviews[i].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.midY), anchor: .leading, proposal: .zero)
                continue
            }
            if r == .trailing {
                subviews[i].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(width: p.widths[i], height: nil))
                continue
            }
            if let prev { x += prev == .fixed && r == .name ? markGap : gap }
            subviews[i].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: p.widths[i], height: nil))
            x += p.widths[i]
            prev = r
        }
    }
}

/// The list mark's tile (§22): the sidebar's small tile, 16×13, its colour and monogram.
struct ListMarkTile: View {
    let list: ListModel
    @Environment(\.palette) private var p
    var body: some View {
        ListTile(content: .mono(list.monogram), hue: p.tile(slot: list.colorSlot), scale: Metric.markTileW / Metric.tileW)
    }
}

/// The list mark's short name (`ListName.short`), 13pt `ink-tertiary`; cut off, it fades. VoiceOver reads the full name.
struct ListMarkName: View {
    let list: ListModel
    @Environment(\.palette) private var p
    var body: some View {
        let full = list.name.isEmpty ? "Untitled" : list.name
        let short = list.shortName.isEmpty ? "Untitled" : list.shortName
        Text(short)
            .font(Typo.quiet)
            .foregroundStyle(p.inkTertiary)
            .fadeTruncation(Metric.titleFade, text: short)
            .accessibilityLabel(full)
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

/// A heading (§23): its name, 15 semibold ink at the checkbox's edge, on a hairline; the chevron at the right, always
/// shown (there's no hover). Collapsed, its open tasks' count follows the name. A tap on the name does nothing (the
/// phone has no heading details to select it for): Rename is in its long-press menu. The chevron takes its own tap.
/// Its notes are the next line (`HeadingNotesRow`).
struct HeadingRow: View {
    let heading: TaskModel
    let count: Int
    /// The air above its hairline: in a list it's an edge row of its own (`Line.edge`), so the row starts at the rule.
    var top: CGFloat = HeadingRow.air
    static let air: CGFloat = 11
    /// On the collection view: the renaming state the cell was configured with, so the field shows only once the
    /// collection view reconfigures the row, after easing it whole into view (TaskCollection+Editing.swift). Nil: the
    /// draft's.
    var editingOverride: Bool? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @FocusState private var focus: DetailField?

    private var collapsed: Bool { app.collapsed.contains(heading.id) }
    private var renaming: Bool {
        if let editingOverride { return editingOverride }
        if case let .rename(h, _)? = app.draft?.kind { return h == heading.id } else { return false }
    }
    /// Its name is one line: pasted line breaks become spaces. Its name for the moment the field outlives the draft
    /// (until it's reconfigured).
    private var text: Binding<String> {
        Binding(get: { app.draft?.title ?? heading.title }, set: { new in
            let text = TitleText.oneLine(new)
            app.draft?.title = text
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            if renaming { nameField } else { name }
            chevron
        }
        .hairline(renaming ? .clear : p.lineSeparator, leading: Metric.rowPad, trailing: Metric.rowPad)
        .padding(.top, top)
        .padding(.bottom, 4)
        .onChange(of: focus) { old, new in
            // The caret left the field (a tap elsewhere, the keyboard put away): it's written, once.
            if old != nil, new == nil, renaming { app.endDraft() }
        }
    }

    private var name: some View {
        HStack(spacing: 8) {
            Text(heading.title).font(Typo.heading).foregroundStyle(p.ink).lineLimit(1)
            if collapsed {
                Text("\(count)").font(Typo.chip).monospacedDigit().foregroundStyle(p.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Metric.rowPad)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heading.title)
        .accessibilityValue(collapsed ? "Collapsed, \(count) open" : "")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("heading")
    }

    /// Renaming: the field in place, in the heading's font, with the new-task row's look. It's in the name's own line
    /// box (a hidden name), so the row is as tall renaming as at rest. From the XL text size up a text field's line is
    /// 1.7–2 pt taller than a Text's, and the row grew as Rename began, under the closing menu: its platter, made for the
    /// row as it was, showed the taller row 1 pt up within its cut (the row's fill, from `air` down), so the box's top
    /// edge was cut to a hairline for the ~0.6 s the menu took to close (T37, the user's film: "rename section top
    /// border getting clipped"). The rows below no longer move 2 pt as it starts and ends either.
    private var nameField: some View {
        Text(heading.title.isEmpty ? " " : heading.title)
            .font(Typo.heading)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                TextField("New Heading", text: text, prompt: Text("New Heading").foregroundStyle(p.inkTertiary))
                    .font(Typo.heading)
                    .foregroundStyle(p.ink)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { app.submitDraft() }
                    .accessibilityIdentifier("headingName")
            }
            .padding(.leading, Metric.rowPad)
            .padding(.vertical, 9)
            .background(p.base, in: RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
            .onAppear { DispatchQueue.main.async { focus = .title } }
    }

    /// Down when open, right when collapsed, turning in 200 ms ease-out.
    private var chevron: some View {
        Button { if PressGate.allows { app.toggleCollapse(heading.id) } } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.inkTertiary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .motion(.easeOut(duration: 0.2), value: collapsed)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Expand \(heading.title)" : "Collapse \(heading.title)")
        .accessibilityIdentifier("chevron")
    }
}

/// A heading's notes, the line under it, at its name's edge and a step quieter: rendered at rest (a box toggles in one
/// op, a tap elsewhere edits them), the notes editor while editing. Their own line, so collapsing folds them into the
/// heading with its tasks, and the rows below close up on the same curve (§23).
struct HeadingNotesRow: View {
    let heading: TaskModel
    /// On the collection view: the editing state the cell was configured with, so its height changes only when the
    /// collection view reconfigures it, inside an animation (TaskCollection+Editing.swift). Nil: the draft's.
    var editingOverride: Bool? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    private var editing: Bool {
        if let editingOverride { return editingOverride }
        return draftsThem
    }
    /// The draft is these notes.
    private var draftsThem: Bool {
        if case let .notes(h, _)? = app.draft?.kind { return h == heading.id } else { return false }
    }

    var body: some View {
        Group {
            if editing {
                // Typed into in place, in the rest view's line box (InPlaceNotes.swift). The draft's text; its notes for
                // the moment the editor outlives the draft (until it's reconfigured). The caret leaving them (a tap
                // elsewhere, the keyboard put away) writes them, once.
                InPlaceNotesEditor(text: app.draft?.title ?? heading.notes, identifier: "headingNotes") { app.draft?.title = $0 }
                    onEnd: { if draftsThem { app.endDraft() } }
            } else {
                // In a deleted list they only read (§28). Each line in the editor's line box, so nothing moves as
                // editing starts or ends.
                MarkdownText(text: heading.notes, font: Typo.notes, ink: p.inkSecondary, lineBox: true,
                             onToggle: app.isTrashed(heading) ? nil : { new, checking in
                                 app.setNotes(heading.id, new, name: checking ? "Check Item" : "Uncheck Item")
                             })
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { app.editHeadingNotes(heading.id) }
            }
        }
        .padding(.horizontal, Metric.rowPad)
        .padding(.top, 3)
        .padding(.bottom, 8)
    }
}

/// "Completed 4": the disclosure at a list's end.
struct CompletedToggleRow: View {
    /// A list's id, or `AppModel.todayDone`.
    let key: String
    let count: Int
    let open: Bool
    /// The air above it: in a list or Today it's an edge row of its own (`Line.edge`).
    var top: CGFloat = CompletedToggleRow.air
    static let air: CGFloat = 8
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
        .padding(.top, top)
        .accessibilityLabel(open ? "Hide completed tasks" : "Show \(count) completed tasks")
    }
}

/// A deleted list in Trash: one row on the day it was deleted, its tile on the checkbox's column, "11 tasks", and a
/// chevron that shows what it holds. A tap opens the list, read-only; the chevron, its own 44×44 at the right, expands
/// it in place (§28: the Mac's click shows the list, its chevron or Space expands it).
struct DeletedListRow: View {
    let list: ListModel
    let open: Bool
    /// In a month group: the day it was deleted, after its count ("2 tasks · Oct 22").
    var day: CalendarDate? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Button { app.openDeletedList(list.id) } label: {
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
                Button { toggle() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.inkTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 1)
            .frame(minHeight: Metric.rowHeight)
        }
        .buttonStyle(RowStyle())
        // One element: a tap opens it, and the rotor has the rest (§28).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(list.name), deleted list, \(app.deletedListCount(list.id))")
        .accessibilityHint("Opens the list")
        .accessibilityAction { app.openDeletedList(list.id) }
        .accessibilityAction(named: "Open") { app.openDeletedList(list.id) }
        .accessibilityAction(named: open ? "Collapse" : "Expand") { toggle() }
        .accessibilityAction(named: "Restore List") { app.restoreList(list.id) }
    }
    private func toggle() {
        animate(Motion.layout) {
            if open { app.expandedTrash.remove(list.id) } else { app.expandedTrash.insert(list.id) }
        }
    }
}

/// A deleted list's banner, above its large title (§28; the sheet's trash banner): when it was deleted, why it's
/// read-only, and Restore. Two lines, as the Mac's is in a narrow pane.
struct DeletedListBanner: View {
    let list: ListModel
    /// When it was deleted, if not the list's own: kept while the banner fades out after a restore (TaskCollection+Screens).
    var deletedAt: Int? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(p.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deleted " + ((deletedAt ?? list.archivedAt).map { DateLabel.monthDay(app.localDay($0)) } ?? ""))
                    .font(Typo.body).foregroundStyle(p.ink)
                Text("Read-only until you restore it.").font(Typo.meta).foregroundStyle(p.inkSecondary)
            }
            Spacer(minLength: 8)
            Button("Restore") { app.restoreList(list.id) }
                .buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 30))
        }
        .padding(12)
        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deletedListBanner")
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
    /// A title is one line: pasted line breaks become spaces.
    private var text: Binding<String> { Binding(get: { app.draft?.title ?? "" }, set: { app.draft?.title = TitleText.oneLine($0) }) }

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
