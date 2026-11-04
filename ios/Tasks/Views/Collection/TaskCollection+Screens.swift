import SwiftUI
import TasksCore

// Each item's row, as ListScreen's `row(_:)` draws it on the List path, for every screen: a list, Today and Undated
// (their group labels), Upcoming (its days and months), Completed, Trash and a deleted list (read-only). The rows are
// the app's own SwiftUI views, hosted in the cells (UIHostingConfiguration); they look their task or heading up live,
// so a row redraws for its own changes without a reconfigure.
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
        case "header": CollectionHeader(source: source)
        case "banner":
            if let l = app.deletedList(source) { DeletedListBanner(list: l).padding(.top, 4) }
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
            HeadingRow(heading: h, count: count, top: HeadingRow.air)
        case let .headingNotes(h):
            HeadingNotesRow(heading: h)
        case let .task(t, indent, groupDay, day):
            // On the phone the row whose details are open keeps the selected fill, then fades out as they close.
            let row = TaskRow(task: t, source: source, indent: indent, groupDay: groupDay, day: day,
                              selected: app.flashed.contains(t.id) || (app.isSplit ? app.selectedTask == t.id : app.detailTask == t.id))
            // A deleted list's rows are deaf, as on the Mac (§28).
            if app.deletedList(source) != nil { row.disabled(true) } else { row }
        case let .completedToggle(key, count, open):
            CompletedToggleRow(key: key, count: count, open: open, top: CompletedToggleRow.air)
        case let .deletedList(l, _, open, day):
            DeletedListRow(list: l, open: open, day: day)
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

/// The large title, Today's date or a deleted list's "In Trash" after it, and a list's notes under it (ListScreen's
/// `header` on the List path).
struct CollectionHeader: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    private var editingNotes: Bool { app.draft?.source == source && app.draft?.editsListNotes == true }

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
                ListNotesEditor().padding(.top, 2)
            }
        }
        .padding(.leading, Metric.rowPad)
        .padding(.trailing, 8)
        .padding(.top, app.isSplit ? 14 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
