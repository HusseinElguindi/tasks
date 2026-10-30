import SwiftUI
import TasksCore

/// ⌘N's editor row: title, then Tab to notes, then chips for the list (preselected), When (Today when started from
/// Today) and Deadline. In Today it sits at the top; in a list at the bottom of the open tasks, where the task
/// lands. Return adds and keeps the row open for the next one; Esc closes it.
struct QuickAddRow: View {
    let store: Store
    @Bindable var window: WindowState
    /// The open list, or nil in Today (the draft's list, else the default list).
    let listID: EntityID?
    @Environment(\.pane) private var pane
    @FocusState private var field: Field?
    @State private var listPicker = false
    @State private var whenPicker = false
    @State private var deadlinePicker = false

    enum Field { case title, notes }


    var body: some View {
        if let draft = window.quickAdd {
            let target = draft.list ?? listID ?? store.defaultListID
            let today = store.projection.day.date
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    PaneCheckbox(isDone: false, style: .placeholder)
                    TextField("", text: binding(\.title), prompt: Text("New task").foregroundStyle(pane.inkSecondary))
                        .textFieldStyle(.plain)
                        .font(PaneFont.body)
                        .focused($field, equals: .title)
                        .onSubmit(add)
                }
                .frame(minHeight: 18)
                TextField("", text: binding(\.notes), prompt: Text("Notes").foregroundStyle(pane.inkSecondary))
                    .textFieldStyle(.plain)
                    .font(PaneFont.body)
                    .focused($field, equals: .notes)
                    .onSubmit(add)
                    .padding(.leading, 26)
                HStack(spacing: 6) {
                    Button { listPicker = true } label: {
                        if let target, let list = store.projection.listModel(target) {
                            HStack(spacing: 4) {
                                PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot), size: 12)
                                Text(list.name.isEmpty ? "Untitled" : list.name)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(pane.accentText)
                            .padding(.horizontal, 7)
                            .frame(height: PaneSize.chip)
                            .background(pane.accentTint, in: Capsule())
                        } else {
                            PaneChip(text: "No list — create or unarchive one", kind: .late)
                        }
                    }
                    .buttonStyle(PanePressStyle())
                    .popover(isPresented: $listPicker, arrowEdge: .bottom) { listMenu(target) }
                    Button { whenPicker = true } label: {
                        if let when = draft.when {
                            PaneChip(text: DateText.short(when, today: today), systemImage: "calendar")
                        } else {
                            PaneChip(text: "When", systemImage: "calendar", kind: .ghost)
                        }
                    }
                    .buttonStyle(PanePressStyle())
                    .popover(isPresented: $whenPicker, arrowEdge: .bottom) {
                        DatePopover(title: "When", date: draft.when, other: draft.deadline, today: today) { picked in
                            window.quickAdd?.when = picked
                            whenPicker = false
                        }
                    }
                    Button { deadlinePicker = true } label: {
                        if let deadline = draft.deadline {
                            PaneChip(text: DateText.short(deadline, today: today), systemImage: "flag")
                        } else {
                            PaneChip(text: "Deadline", systemImage: "flag", kind: .ghost)
                        }
                    }
                    .buttonStyle(PanePressStyle())
                    .popover(isPresented: $deadlinePicker, arrowEdge: .bottom) {
                        DatePopover(title: "Deadline", date: draft.deadline, other: draft.when, today: today) { picked in
                            window.quickAdd?.deadline = picked
                            deadlinePicker = false
                        }
                    }
                    Spacer(minLength: 8)
                    PaneKeyHint(text: "↩ Add")
                    PaneKeyHint(text: "⇥ Next field").padding(.leading, 4)
                    PaneKeyHint(text: "esc Cancel").padding(.leading, 4)
                }
                .padding(.leading, 26)
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
            .background(pane.selected, in: RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous))
            .overlay {
                // The ring shows only while one of the editor's fields has focus.
                RoundedRectangle(cornerRadius: PaneRadius.row, style: .continuous)
                    .strokeBorder(pane.focusRing, lineWidth: 2)
                    .opacity(field == nil ? 0 : 1)
                    .animation(PaneMotion.snappy, value: field == nil)
            }
            .padding(.vertical, 4)
            .onExitCommand { window.quickAdd = nil }
            // A List row appears before it is in the window, where a focus request made right away is dropped.
            .onAppear { DispatchQueue.main.async { field = .title } }
            .onChange(of: draft.focusToken) { _, _ in field = .title }
        }
    }

    private func binding(_ key: WritableKeyPath<QuickAddDraft, String>) -> Binding<String> {
        Binding(get: { window.quickAdd?[keyPath: key] ?? "" }, set: { window.quickAdd?[keyPath: key] = $0 })
    }

    private func add() {
        guard let draft = window.quickAdd else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            window.quickAdd = nil
            return
        }
        let list = draft.list ?? listID ?? store.defaultListID
        guard store.createTask(title: title, notes: draft.notes, in: list, when: draft.when, deadline: draft.deadline,
                               undoManager: window.undoManager) != nil else { return }
        window.quickAdd?.title = ""
        window.quickAdd?.notes = ""
        field = .title
    }

    private func listMenu(_ current: EntityID?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneGroupLabel(text: "Add to list").padding(EdgeInsets(top: 4, leading: 8, bottom: 6, trailing: 8))
            ForEach(Array(store.projection.activeLists.ids.enumerated()), id: \.element) { index, id in
                if let list = store.projection.listModel(id) {
                    PaneMenuItem(isHot: id == current, shortcut: index < 9 ? "⌘\(index + 1)" : nil) {
                        window.quickAdd?.list = id
                        listPicker = false
                    } label: {
                        PaneListMark(monogram: list.monogram, color: pane.listColor(slot: list.colorSlot), size: 16)
                        Text(list.name.isEmpty ? "Untitled" : list.name)
                    }
                    .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : KeyEquivalent("0"),
                                      modifiers: index < 9 ? .command : [.command, .option, .control, .shift])
                }
            }
            PaneMenuSeparator()
            Text("Defaults to the first list in the sidebar.")
                .font(PaneFont.subheadline)
                .foregroundStyle(pane.inkSecondary)
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 4, trailing: 8))
        }
        .padding(6)
        .frame(width: 220)
    }
}
