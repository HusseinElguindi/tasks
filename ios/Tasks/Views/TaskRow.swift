import SwiftUI

/// A task on the row grid: checkbox, title, the quiet When after it, the list's name where the view mixes lists, and
/// the deadline capsule at the end.
struct TaskRow: View {
    let task: TaskItem
    let source: Source
    var indent = false
    var selected = false
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p

    private var trashed: Bool { source == .trash }
    private var done: Bool { task.isDone }
    private var settled: Bool { done && !store.completing.contains(task.id) }

    var body: some View {
        Button { open() } label: {
            HStack(spacing: 0) {
                Checkbox(checked: done, cue: store.cue(task, in: source), readOnly: trashed) {
                    store.toggle(task.id)
                }
                .padding(.leading, Metric.rowPad - 11)   // the 44pt hit area centres the 22pt ring
                .padding(.trailing, Metric.titleGap - 11)

                TitleSlot {
                    HStack(spacing: 8) {
                        Text(task.title.isEmpty ? "New Task" : task.title)
                            .font(Typo.row)
                            .foregroundStyle(titleColor)
                            .strikethrough(settled, color: p.inkQuiet)
                            .lineLimit(1)
                        if !task.notes.isEmpty && !settled {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(p.inkQuiet)
                                .accessibilityLabel("Has notes")
                        }
                    }
                    if let w = task.when, showWhen(w) { QuietWhen(date: w) }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if let name = whereName {
                    Text(name)
                        .font(Typo.quiet)
                        .foregroundStyle(p.inkTertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                        .padding(.trailing, task.deadline == nil ? 0 : 8)
                }
                if let d = task.deadline, !settled { DeadlineChip(date: d) }
            }
            .padding(.trailing, 12)
            .padding(.leading, indent ? 30 : 0)
            .frame(minHeight: Metric.rowHeight)
        }
        .buttonStyle(RowStyle(selected: selected))
        .opacity(store.completing.contains(task.id) ? 0.75 : 1)
        .accessibilityElement(children: .contain)
    }

    private var titleColor: Color {
        if settled { return p.inkTertiary }
        if trashed { return p.inkSecondary }
        return task.title.isEmpty ? p.inkTertiary : p.ink
    }

    private func showWhen(_ w: Date) -> Bool {
        if settled || trashed { return false }
        switch source {
        case .today, .upcoming: return false
        default: return true
        }
    }

    /// Views that mix lists by day show where each task lives; Today and Undated group by list already.
    private var whereName: String? {
        switch source {
        case .upcoming, .completed, .trash: indent ? nil : store.list(task.listID)?.name
        default: nil
        }
    }

    private func open() {
        if store.isSplit { store.selectedTask = task.id } else { store.detailTask = task.id }
    }
}

/// The heading row: 15 semibold ink at the checkbox's edge with a hairline under it.
struct HeadingRow: View {
    let heading: Heading
    let count: Int
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 8) {
            Text(heading.title).font(Typo.heading).foregroundStyle(p.ink).lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 { Text("\(count)").font(Typo.chip).monospacedDigit().foregroundStyle(p.inkTertiary) }
        }
        .padding(.horizontal, Metric.rowPad)
        .padding(.top, 20)
        .padding(.bottom, 9)
        .hairline(p.lineSeparator, leading: Metric.rowPad, trailing: Metric.rowPad)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "Completed 4": the disclosure at a list's end.
struct CompletedToggleRow: View {
    let listID: String
    let count: Int
    let open: Bool
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Button {
            animate(Motion.layout) {
                if open { store.showCompleted.remove(listID) } else { store.showCompleted.insert(listID) }
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
    let list: TaskList
    let count: Int
    let open: Bool
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 0) {
                ListTile(content: .mono(list.mono), hue: p.tile(list.hue))
                    .frame(width: 44)
                    .padding(.leading, Metric.rowPad - 11)
                    .padding(.trailing, Metric.titleGap - 11)
                Text(list.name).font(Typo.rowMedium).foregroundStyle(p.inkSecondary).lineLimit(1)
                Text(count == 1 ? "1 task" : "\(count) tasks")
                    .font(Typo.quiet).foregroundStyle(p.inkTertiary).padding(.leading, 8)
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
        .accessibilityLabel("\(list.name), deleted list, \(count) tasks")
        .accessibilityHint(open ? "Hides its tasks" : "Shows its tasks")
    }
    private func toggle() {
        animate(Motion.layout) {
            if open { store.expandedTrash.remove(list.id) } else { store.expandedTrash.insert(list.id) }
        }
    }
}

/// The row a new task is typed into: the row's own fill with a 1.5pt accent ring and a quiet placeholder box.
struct DraftRow: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool
    let token: UUID

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Checkbox(checked: false, placeholder: true)
                .padding(.leading, Metric.rowPad - 11)
                .padding(.trailing, Metric.titleGap - 11)
            TextField("New Task", text: Binding(get: { store.draft?.title ?? "" }, set: { store.draft?.title = $0 }),
                      prompt: Text("New Task").foregroundStyle(p.inkTertiary))
                .font(Typo.row)
                .foregroundStyle(p.ink)
                .focused($focused)
                .submitLabel(.next)
                .onSubmit { store.commitDraft() }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 12)
        .frame(minHeight: Metric.rowHeight)
        .background(p.base, in: RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) { _, now in
            guard !now, store.draft?.token == token else { return }
            // Leaving the row: a title commits, an empty one cancels.
            if (store.draft?.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty { store.cancelDraft() }
            else { store.commitDraft(); store.cancelDraft() }
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
            Text(message).font(Typo.body).foregroundStyle(p.inkTertiary).multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// The title and the quiet When after it, as the Mac lays them out when narrow: the title keeps up to 120pt; the When
/// drops before the title goes under that.
struct TitleSlot: Layout {
    var minTitle: CGFloat = 120
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
        let th = subviews[0].sizeThatFits(ProposedViewSize(width: p.title, height: nil)).height
        let total = p.title + (p.when.map { $0.width + gap } ?? 0)
        return CGSize(width: total, height: max(th, p.when?.height ?? 0))
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
