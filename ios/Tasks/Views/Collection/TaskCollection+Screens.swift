import SwiftUI
import TasksCore

// Each item's row, for every screen: a list, Today and Undated (their group labels), Upcoming (its days and months),
// Completed, Trash and a deleted list (read-only). The rows are the app's own SwiftUI views, hosted in the cells
// (UIHostingConfiguration); they look their task or heading up live, so a row redraws for its own changes without a
// reconfigure.
//
// Air: there are no edge items, so a heading, a group label and the Completed row draw their own air above them.

/// One cell's row.
struct CollectionLine: View {
    let id: String
    let source: Source
    let rows: CollectionRows
    /// The row's height signature when it was configured (`TaskCollection.signatures`).
    var state: String? = nil
    weak var owner: TaskCollectionController?
    @Environment(AppModel.self) private var app

    /// The row being typed into here: taps on it are its own.
    private var edited: Bool {
        guard let d = app.draft, d.source == source else { return false }
        if id == "draft" { return true }
        if d.editsListNotes { return id == "header" }
        if let h = d.editedHeading { return id == (d.editsNotes ? "n:" : "h:") + h }
        return false
    }

    var body: some View {
        content.endsAddingOnTap(!edited)
    }

    @ViewBuilder private var content: some View {
        switch id {
        case "header": CollectionHeader(source: source, editingOverride: state.map { $0.hasPrefix(TaskCollection.editingMark) })
        case "banner": BannerLine(source: source)
        default:
            if let line = rows.line(id) { row(line) }
        }
    }

    @ViewBuilder private func row(_ line: Line) -> some View {
        switch line {
        case let .group(_, title, sub, quiet):
            // Lit while a drag in Upcoming is over its day (CollectionDrag.hover).
            GroupLabel(title: title, sub: sub, quiet: quiet, hot: owner?.drag.hover.key == id, top: GroupLabel.air)
                .allowsHitTesting(false)
        case let .heading(h, count, _):
            // The state it was configured with (its signature): the field shows only as it's resized.
            HeadingRow(heading: h, count: count, top: HeadingRow.air,
                       editingOverride: state.map { $0.hasPrefix(TaskCollection.editingMark) } ?? false)
        case let .headingNotes(h):
            // The state it was configured with (its signature): its height changes only as it's resized.
            HeadingNotesRow(heading: h, editingOverride: state.map { $0.hasPrefix(TaskCollection.editingMark) } ?? false)
        case let .task(t, indent, groupDay, day):
            // On the phone the row whose details are open keeps the selected fill, then fades out as they close.
            // In select mode, the joined fill (CollectionSelect).
            let pick = owner?.select.pick(t.id) ?? .init()
            let row = TaskRow(task: t, source: source, indent: indent, groupDay: groupDay, day: day,
                              selected: app.flashed.contains(t.id) || (app.isSplit ? app.selectedTask == t.id : app.detailTask == t.id),
                              picked: pick.picked, joinTop: pick.joinTop, joinBottom: pick.joinBottom)
            // A deleted list's rows are deaf, as on the Mac (§28).
            if app.deletedList(source) != nil {
                row.disabled(true)
            } else {
                row.modifier(SwipeActionsForVoiceOver(task: t, source: source, enabled: !app.isSelecting(source),
                                                      move: owner.map { o in { o.drag.voiceOverMove(id, by: $0) } },
                                                      canMove: owner.map { o in { o.drag.voiceOverCanMove(id, by: $0) } }))
            }
        case let .completedToggle(key, count, open):
            CompletedToggleRow(key: key, count: count, open: open, top: CompletedToggleRow.air)
        case let .deletedList(l, _, open, day):
            DeletedListRow(list: l, open: open, day: day)
                // Its swipe's Restore, as List gives VoiceOver (none in select mode).
                .accessibilityActions {
                    if !app.isSelecting(source) { Button("Restore") { app.restoreList(l.id) } }
                }
        case .draft:
            if let token = app.draft?.token { DraftRow(token: token).id(token) }
        case let .empty(title, message, symbol):
            EmptyState(title: title, message: message, symbol: symbol)
        case .allDone:
            AllDoneSun(rise: rows.sunRise)
        case .edge:
            EmptyView()
        }
    }
}

/// A row's swipe actions as VoiceOver's actions, named and ordered as List gives them for `TaskSwipes` (When, Delete,
/// Complete or Not Done; in Trash, Put Back), on the row's container. On this path the swipes themselves are UIKit's
/// (`CollectionSwipes`), not SwiftUI's, so VoiceOver gets them from here. Where rows reorder (not Upcoming, Completed or
/// Trash), also Move Up and Move Down: the drag's drop at the slot before or after (`CollectionDrag.voiceOverMove`).
private struct SwipeActionsForVoiceOver: ViewModifier {
    let task: TaskModel
    let source: Source
    let enabled: Bool
    var move: ((Int) -> Bool)?
    /// Whether a move that way has a slot (asked as the row is drawn; one that has gone since says so).
    var canMove: ((Int) -> Bool)?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if enabled, let move, source != .upcoming, app.dragRuns([], source) != nil {
                if canMove?(-1) ?? true { Button("Move Up") { _ = move(-1) } }
                if canMove?(1) ?? true { Button("Move Down") { _ = move(1) } }
            }
            if enabled {
                if source == .trash {
                    if app.canPutBack(task) { Button("Put Back") { app.putBack(task.id) } }
                } else {
                    // VoiceOver lists them last first.
                    Button(task.isDone ? "Not Done" : "Complete") { app.toggle(task.id) }
                    Button("Delete") { app.delete(task.id) }
                    Button("When") { app.dateTarget = DateTarget(taskID: task.id, kind: .when) }
                }
            }
        }
    }
}

/// A deleted list's banner (§28), 4 under the bar and 10 in from the sides (the cell's margins).
/// Restored, its item goes and the cell fades out with the rows closing up: it keeps drawing the list as it was until
/// then (the list and the day it was deleted, which the restore clears), not a blank or "Deleted" with no day.
private struct BannerLine: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @State private var kept: (list: ListModel, at: Int)?

    var body: some View {
        let live = app.deletedList(source)
        Group {
            if let live {
                DeletedListBanner(list: live)
            } else if let kept {
                DeletedListBanner(list: kept.list, deletedAt: kept.at)
            }
        }
        .padding(.top, 4)
        .onChange(of: live?.archivedAt, initial: true) { _, at in
            if let live, let at { kept = (live, at) }
        }
    }
}

/// The large title, Today's date or a deleted list's "In Trash" after it, and a list's notes under it.
struct CollectionHeader: View {
    let source: Source
    /// The editing state it was configured with (its signature), as `HeadingNotesRow.editingOverride`.
    var editingOverride: Bool? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    private var editingNotes: Bool {
        editingOverride ?? (app.draft?.source == source && app.draft?.editsListNotes == true)
    }

    private var subtitle: String? {
        if app.deletedList(source) != nil { return "In Trash" }
        return source == .today ? DateLabel.long(app.today, today: app.today) : nil
    }

    var body: some View {
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
                    // A list's notes are a step quieter (§23). A tap on them edits them; a checklist box toggles in one
                    // op (IX:1540–1543). A deleted list's only read.
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
                ListNotesEditor(live: true).padding(.top, 2)
            }
        }
        .padding(.leading, Metric.rowPad)
        .padding(.trailing, 8)
        .padding(.top, app.isSplit ? 14 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
