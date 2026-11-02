import SwiftUI
import TasksCore

/// One list, or one of the views, on the row grid. The large title scrolls with the rows; the bar's title fades in once
/// it has gone under the bar.
struct ListScreen: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @State private var folded = false

    var body: some View {
        let lines = app.lines(source)
        List {
            header
                .listRow()
            ForEach(lines) { line in
                row(line)
                    .listRow()
            }
            Color.clear.frame(height: app.isSplit ? 24 : Metric.bottomClearance)
                .listRow()
        }
        .listStyle(.plain)
        .refreshable { await app.syncNow() }
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background { if !app.isSplit { AppBackground() } }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 40
        } action: { _, now in
            withAnimation(.easeOut(duration: 0.15)) { folded = now }
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
            if case let .list(id) = source {
                ToolbarItem(placement: .primaryAction) { ListMenu(listID: id) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
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
            if case let .list(id) = source, let notes = app.list(id)?.notes, !notes.isEmpty {
                // A list's notes are a step quieter (§23), in the same Markdown as a task's.
                MarkdownText(text: notes, font: Typo.notes, ink: p.inkSecondary, lineSpacing: 5)
                    .padding(.top, 2)
            }
            if source == .trash {
                Text("Deleted tasks and lists stay here, read-only, until you restore them.")
                    .font(Typo.notes).lineSpacing(5).foregroundStyle(p.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, Metric.rowPad)
        .padding(.trailing, 8)
        .padding(.top, app.isSplit ? 14 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String? {
        switch source {
        case .today: DateLabel.long(app.today, today: app.today)
        case let .list(id): app.openCount(id) > 0 ? "\(app.openCount(id))" : nil
        default: nil
        }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ line: Line) -> some View {
        switch line {
        case let .group(_, title, sub, quiet):
            GroupLabel(title: title, sub: sub, quiet: quiet)
        case let .heading(h, count):
            HeadingRow(heading: h, count: count)
        case let .task(t, indent, groupDay):
            TaskRow(task: t, source: source, indent: indent, groupDay: groupDay, selected: app.isSplit && app.selectedTask == t.id)
                .transition(.opacity)
                .modifier(TaskSwipes(task: t, source: source))
                .contextMenu { TaskMenu(task: t, source: source) }
        case let .completedToggle(key, count, open):
            CompletedToggleRow(key: key, count: count, open: open)
        case let .deletedList(l, count, open):
            DeletedListRow(list: l, count: count, open: open)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { app.restoreList(l.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
                .contextMenu {
                    Button { app.restoreList(l.id) } label: { Label("Restore List", systemImage: "arrow.uturn.backward") }
                }
        case .draft:
            if let token = app.draft?.token { DraftRow(token: token).id(token) }
        case let .empty(title, message, symbol):
            EmptyState(title: title, message: message, symbol: symbol)
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
                if app.canRestore(task) {
                    Button { app.restore(task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
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
        if source == .trash {
            if app.canRestore(task) {
                Button { app.restore(task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
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
                    Button(l.name) { app.move(task.id, to: l.id) }.disabled(l.id == task.list)
                }
            } label: { Label("Move to", systemImage: "arrow.right.square") }
            Divider()
            Button(role: .destructive) { app.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// A list's menu in the bar: Rename, show or hide completed, Delete List (at once, with Undo).
struct ListMenu: View {
    let listID: EntityID
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            Button { app.listEditor = .init(listID: listID, name: app.list(listID)?.name ?? "") } label: {
                Label("Rename", systemImage: "pencil")
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
