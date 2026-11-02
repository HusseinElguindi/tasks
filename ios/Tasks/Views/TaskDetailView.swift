import SwiftUI

/// A task's details: checkbox and title, List / When / Deadline, then its notes. A sheet on the phone, the third pane
/// on iPad and the Mac.
struct TaskDetailView: View {
    let taskID: String
    var inline = false
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    enum Field { case title, notes }

    var body: some View {
        @Bindable var store = store
        Group {
            if let t = store.task(taskID) {
                content(t)
            } else {
                NothingSelected()
            }
        }
        .background(inline ? Color.clear : p.base)
        .sheet(item: inline ? .constant(nil) : $store.dateTarget) { target in
            DatePickerSheet(target: target).themed(store).datePickerPresentation()
        }
    }

    private func content(_ t: TaskItem) -> some View {
        let trashed = t.isTrashed || (store.list(t.listID)?.deletedAt != nil)
        return VStack(spacing: 0) {
            topBar(t, trashed: trashed)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if trashed { trashBanner(t) }
                    HStack(alignment: .top, spacing: 0) {
                        Checkbox(checked: t.isDone, cue: store.cue(t, in: .list(t.listID)), readOnly: trashed, size: 24) {
                            store.toggle(t.id)
                        }
                        .padding(.leading, -10)
                        .padding(.top, -10)
                        .padding(.trailing, 2)
                        TextField("New Task", text: binding(\.title), prompt: Text("New Task").foregroundStyle(p.inkTertiary), axis: .vertical)
                            .font(Typo.detailTitle)
                            .foregroundStyle(t.isDone ? p.inkSecondary : p.ink)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                            .disabled(trashed)
                            .onSubmit { focus = nil }
                    }
                    .padding(.top, 6)

                    VStack(spacing: 0) {
                        listRow(t, trashed: trashed)
                        dateRow(t, kind: .when, trashed: trashed)
                        dateRow(t, kind: .deadline, trashed: trashed)
                    }
                    .padding(.top, 14)

                    Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.top, 12).padding(.bottom, 14)

                    NotesEditor(text: binding(\.notes), readOnly: trashed, focus: $focus)

                    Text(meta(t))
                        .font(Typo.meta)
                        .foregroundStyle(p.inkTertiary)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Bar

    private func topBar(_ t: TaskItem, trashed: Bool) -> some View {
        HStack(spacing: 8) {
            if let l = store.list(t.listID) {
                ListTile(content: .mono(l.mono), hue: p.tile(l.hue), scale: 0.85)
                Text(l.name).font(Typo.body).foregroundStyle(p.inkSecondary).lineLimit(1)
            }
            Spacer()
            if trashed {
                if !t.deletedWithList {
                    BarIcon(symbol: "arrow.uturn.backward", label: "Restore") { store.restore(t.id) }
                }
            } else {
                BarIcon(symbol: "trash", label: "Delete") {
                    if !inline { dismiss() }
                    store.delete(t.id)
                }
            }
            if inline {
                BarIcon(symbol: "xmark", label: "Hide Details") { store.selectedTask = nil }
            } else {
                Button("Done") { focus = nil; dismiss() }
                    .buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .frame(height: inline ? 46 : 60)
        .padding(.top, inline ? 0 : 6)
    }

    private func trashBanner(_ t: TaskItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(p.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deleted \(Day.monthDay(t.deletedAt ?? store.list(t.listID)?.deletedAt ?? Date()))").font(Typo.body).foregroundStyle(p.ink)
                Text(t.deletedWithList || t.deletedAt == nil ? "Deleted with \(store.list(t.listID)?.name ?? "its list"). Restore the list to bring it back." : "Read-only until you restore it.")
                    .font(Typo.meta).foregroundStyle(p.inkSecondary)
            }
            Spacer(minLength: 8)
            if t.deletedAt != nil && !t.deletedWithList {
                Button("Restore") { store.restore(t.id) }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 30))
            } else if let l = store.list(t.listID), l.deletedAt != nil {
                Button("Restore List") { store.restoreList(l.id) }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 30))
            }
        }
        .padding(12)
        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 14)
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

    private func listRow(_ t: TaskItem, trashed: Bool) -> some View {
        HStack(spacing: 0) {
            propLabel("tray", "List")
            Menu {
                ForEach(store.liveLists) { l in
                    Button { store.move(t.id, to: l.id) } label: {
                        if l.id == t.listID { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let l = store.list(t.listID) {
                        ListTile(content: .mono(l.mono), hue: p.tile(l.hue), scale: 0.85)
                        Text(l.name).font(Typo.body).foregroundStyle(p.ink)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.inkTertiary)
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .padding(.leading, -8)
            .disabled(trashed)
            Spacer()
        }
        .frame(minHeight: 44)
    }

    private func dateRow(_ t: TaskItem, kind: DateKind, trashed: Bool) -> some View {
        let date = kind == .when ? t.when : t.deadline
        let active = store.dateTarget?.taskID == t.id && store.dateTarget?.kind == kind
        return HStack(spacing: 0) {
            propLabel(kind == .when ? "calendar" : "flag", kind == .when ? "When" : "Deadline")
            Button { store.dateTarget = DateTarget(taskID: t.id, kind: kind) } label: {
                DateChip(date: date, kind: kind, active: active)
            }
            .buttonStyle(.plain)
            .disabled(trashed)
            .accessibilityLabel(kind == .when ? "When" : "Deadline")
            .accessibilityValue(date.map(Day.full) ?? "None")
            if let date {
                Text(relWords(date, kind))
                    .font(Typo.quiet)
                    .foregroundStyle(relColor(date, kind))
                    .padding(.leading, 10)
                    .lineLimit(1)
                if !trashed {
                    Button { store.setDate(t.id, kind, nil) } label: {
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

    private func relWords(_ d: Date, _ kind: DateKind) -> String {
        if kind == .deadline { let x = Day.deadlineLabel(d); return Day.diff(d) > 7 ? Day.relative(d) : x }
        return Day.diff(d) <= 1 ? "" : Day.relative(d)
    }
    private func relColor(_ d: Date, _ kind: DateKind) -> Color {
        guard kind == .deadline else { return p.inkTertiary }
        switch Day.tone(d) { case .late: return p.danger; case .due: return p.attention; default: return p.inkTertiary }
    }

    private func meta(_ t: TaskItem) -> String {
        var parts = ["Created \(Day.monthDay(t.created))"]
        if let c = t.completedAt { parts.append("Completed \(Day.monthDay(c))") }
        if let d = t.deletedAt { parts.append("Deleted \(Day.monthDay(d))") }
        return parts.joined(separator: " · ")
    }

    private func binding(_ key: WritableKeyPath<TaskItem, String>) -> Binding<String> {
        Binding(get: { store.task(taskID)?[keyPath: key] ?? "" },
                set: { v in if let i = store.index(taskID) { store.tasks[i][keyPath: key] = v } })
    }
}

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

/// The notes: rendered Markdown at rest (bold, italics, links, code, square checklists), the plain text while editing.
struct NotesEditor: View {
    @Binding var text: String
    var readOnly = false
    var focus: FocusState<TaskDetailView.Field?>.Binding
    @Environment(\.palette) private var p

    private var editing: Bool { focus.wrappedValue == .notes }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(Typo.detailNotes)
                .lineSpacing(6)
                .foregroundStyle(p.ink)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused(focus, equals: .notes)
                .frame(minHeight: 180, alignment: .topLeading)
                .padding(.horizontal, -5)
                .padding(.top, -8)
                .opacity(editing ? 1 : 0)
                .disabled(readOnly)
            if !editing {
                Group {
                    if text.isEmpty {
                        Text("Notes").font(Typo.detailNotes).foregroundStyle(p.inkTertiary)
                    } else {
                        MarkdownNotes(text: $text, readOnly: readOnly)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { if !readOnly { focus.wrappedValue = .notes } }
            }
        }
    }
}

struct MarkdownNotes: View {
    @Binding var text: String
    var readOnly = false
    @Environment(\.palette) private var p

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                if let (checked, rest) = checklist(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Button { toggle(i) } label: {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(checked ? p.accent : p.inkQuiet)
                        }
                        .buttonStyle(.plain)
                        .disabled(readOnly)
                        .accessibilityLabel(checked ? "Checked" : "Unchecked")
                        rich(rest)
                            .foregroundStyle(checked ? p.inkTertiary : p.ink)
                            .strikethrough(checked, color: p.inkQuiet)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•").foregroundStyle(p.inkTertiary).frame(width: 16)
                        rich(String(line.dropFirst(2)))
                    }
                } else if line.isEmpty {
                    Color.clear.frame(height: 6)
                } else {
                    rich(line)
                }
            }
        }
        .font(Typo.detailNotes)
        .lineSpacing(6)
        .foregroundStyle(p.ink)
        .tint(p.accentText)
    }

    private func rich(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }

    private func checklist(_ line: String) -> (Bool, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- [ ] ") { return (false, String(t.dropFirst(6))) }
        if t.lowercased().hasPrefix("- [x] ") { return (true, String(t.dropFirst(6))) }
        return nil
    }

    private func toggle(_ i: Int) {
        var lines = text.components(separatedBy: "\n")
        guard i < lines.count else { return }
        if lines[i].contains("- [ ] ") { lines[i] = lines[i].replacingOccurrences(of: "- [ ] ", with: "- [x] ") }
        else { lines[i] = lines[i].replacingOccurrences(of: "- [x] ", with: "- [ ] ").replacingOccurrences(of: "- [X] ", with: "- [ ] ") }
        text = lines.joined(separator: "\n")
    }
}
