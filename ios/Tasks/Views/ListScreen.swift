import SwiftUI

/// One list, or one of the views, on the row grid. The large title scrolls with the rows; the bar's title fades in once
/// it has gone under the bar.
struct ListScreen: View {
    let source: Source
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @State private var folded = false

    var body: some View {
        let lines = store.lines(source)
        List {
            header
                .listRow()
            ForEach(lines) { line in
                row(line)
                    .listRow()
            }
            Color.clear.frame(height: store.isSplit ? 24 : Metric.bottomClearance)
                .listRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background { if !store.isSplit { AppBackground() } }
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.contentInsets.top > 40
        } action: { _, now in
            withAnimation(.easeOut(duration: 0.15)) { folded = now }
        }
        .navigationTitle(store.title(source))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    store.tile(for: source, palette: p, scale: 0.8)
                    Text(store.title(source)).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
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
                store.tile(for: source, palette: p, scale: 1.2)
                Text(store.title(source))
                    .font(Typo.largeTitle)
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub).font(Typo.body).foregroundStyle(p.ink3).lineLimit(1).padding(.top, 4)
                }
            }
            if case let .list(id) = source, let notes = store.list(id)?.notes, !notes.isEmpty {
                Text(notes)
                    .font(Typo.notes)
                    .lineSpacing(5)
                    .foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if source == .trash {
                Text("Deleted tasks and lists stay here, read-only, until you restore them.")
                    .font(Typo.notes).lineSpacing(5).foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, Metric.rowPad)
        .padding(.trailing, 8)
        .padding(.top, store.isSplit ? 14 : 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String? {
        switch source {
        case .today: Day.fmt("EEEE MMM d", Day.today)
        case let .list(id): store.openCount(id) > 0 ? "\(store.openCount(id))" : nil
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
        case let .task(t, indent):
            TaskRow(task: t, source: source, indent: indent, selected: store.isSplit && store.selectedTask == t.id)
                .transition(.opacity)
                .modifier(TaskSwipes(task: t, source: source))
                .contextMenu { TaskMenu(task: t, source: source) }
        case let .completedToggle(count, open):
            if case let .list(id) = source { CompletedToggleRow(listID: id, count: count, open: open) }
        case let .deletedList(l, count, open):
            DeletedListRow(list: l, count: count, open: open)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.restoreList(l.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
                .contextMenu {
                    Button { store.restoreList(l.id) } label: { Label("Restore List", systemImage: "arrow.uturn.backward") }
                }
        case .draft:
            if let token = store.draft?.token { DraftRow(token: token).id(token) }
        case let .empty(title, message, symbol):
            EmptyState(title: title, message: message, symbol: symbol)
        }
    }
}

/// Swipe right completes; swipe left sets the When or deletes. In Trash, swipe right restores.
private struct TaskSwipes: ViewModifier {
    let task: TaskItem
    let source: Source
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        if source == .trash {
            content.swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !task.deletedWithList {
                    Button { store.restore(task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(p.accent)
                }
            }
        } else {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.toggle(task.id) } label: {
                        Label(task.isDone ? "Not Done" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(p.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
                        .tint(p.danger)
                    Button { store.dateTarget = DateTarget(taskID: task.id, kind: .when) } label: {
                        Label("When", systemImage: "calendar")
                    }
                    .tint(p.list(.magenta))
                }
        }
    }
}

/// A task's long-press menu.
struct TaskMenu: View {
    let task: TaskItem
    let source: Source
    @Environment(Store.self) private var store
    var body: some View {
        if source == .trash {
            if !task.deletedWithList {
                Button { store.restore(task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            }
        } else {
            Button { store.toggle(task.id) } label: {
                Label(task.isDone ? "Mark as Not Completed" : "Complete", systemImage: task.isDone ? "circle" : "checkmark.circle")
            }
            Button { store.setDate(task.id, .when, Day.today) } label: { Label("Today", systemImage: "sun.max") }
            Button { store.setDate(task.id, .when, Day.offset(1)) } label: { Label("Tomorrow", systemImage: "sunrise") }
            Button { store.dateTarget = DateTarget(taskID: task.id, kind: .when) } label: { Label("When…", systemImage: "calendar") }
            Button { store.dateTarget = DateTarget(taskID: task.id, kind: .deadline) } label: { Label("Deadline…", systemImage: "flag") }
            Menu {
                ForEach(store.liveLists) { l in
                    Button(l.name) { store.move(task.id, to: l.id) }.disabled(l.id == task.listID)
                }
            } label: { Label("Move to", systemImage: "arrow.right.square") }
            Divider()
            Button(role: .destructive) { store.delete(task.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// A list's menu in the bar: Rename, show or hide completed, Delete List (at once, with Undo).
struct ListMenu: View {
    let listID: String
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Menu {
            Button { store.listEditor = .init(listID: listID, name: store.list(listID)?.name ?? "") } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                animate(Motion.layout) {
                    if store.showCompleted.contains(listID) { store.showCompleted.remove(listID) } else { store.showCompleted.insert(listID) }
                }
            } label: {
                Label(store.showCompleted.contains(listID) ? "Hide Completed" : "Show Completed", systemImage: "checkmark.circle")
            }
            if listID != "inbox" {
                Divider()
                Button(role: .destructive) { store.deleteList(listID) } label: { Label("Delete List", systemImage: "trash") }
            }
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
