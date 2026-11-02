import AppKit
import SwiftUI
import TasksCore

/// The detail pane (§4, §6, §7; the prototype's dc:112–166, css:252–289). It shows the selection: one task (or the
/// new task being added), several ("3 tasks selected" with the rows that apply to all), a deleted list's row in Trash
/// (the list itself, §28), or none. Its open and close are v1's, done by `MainLayout`.
struct DetailPane: View {
    let store: Store
    @Bindable var window: WindowState
    /// Alone in the window (the narrow window's drill-in): no focus look (v2 feedback 3).
    var single = false
    @State private var refs = DetailRefs()
    @Environment(\.tk) private var tk

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        let items = selectedItems
        let focused = window.focus == .detail
        VStack(spacing: 0) {
            DetailHeader(store: store, window: window, items: items, focused: focused, single: single, refs: refs, actions: actions)
            GeometryReader { g in
                content(items, actions: actions, size: g.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .paneChrome(focused: focused, single: single)
        .background(PanePressMonitor(handler: { press($0, actions: actions) }, keyEquivalent: { keyEquivalent($0, actions: actions) }))
        .background(
            KeySink(register: { window.detailKeySink = $0 },
                    onKey: { key($0, actions: actions) },
                    onFocus: { if window.focus != .detail { window.focus = .detail } },
                    // Opened on a deleted list with Return or a double-click: the pane has the keys (§28 Opening).
                    onAttach: { sink in
                        if window.focus == .detail, WindowActions(store: store, window: window).selectedDeletedList != nil {
                            DispatchQueue.main.async { sink.takeKeys() }
                        }
                    })
                .frame(width: 0, height: 0)
        )
        .onAppear { takeTitleRequest() }
        .onChange(of: window.titleFocusRequest) { _, _ in takeTitleRequest() }
        .onChange(of: items.isEmpty) { _, empty in if empty { window.detailChipFrames = [:] } }
        .onDisappear { window.detailChipFrames = [:] }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task details")
    }

    /// The selection minus trashed tasks (in Trash, and a deleted list opened from it, only trashed ones: deleted, or
    /// in a deleted list, §22, §28); the draft when it's what's selected (dc:1611, 1930).
    private var selectedItems: [DetailItem] {
        if let d = window.draft, window.selection == [d.id] { return [DetailItem(d)] }
        let p = store.projection
        let trash = window.inTrash(p)
        return window.selection.sorted().compactMap { id -> DetailItem? in
            // Headings aren't tasks: they have no details of their own (§23).
            guard id != window.draft?.id, let m = p.taskModel(id), (m.deleted || !p.isActive(list: m.list)) == trash, !m.isHeading
            else { return nil }
            return DetailItem(m)
        }
    }

    /// The selected headings, when nothing else is selected.
    private var selectedHeadings: [TaskModel] {
        let p = store.projection
        return window.selection.sorted().compactMap { p.taskModel($0) }.filter { $0.isHeading && !$0.deleted }
    }

    /// "A heading with 3 open tasks under it." (dc:141, dc:3649–3657).
    private func headingLine(_ h: TaskModel) -> String {
        let p = store.projection
        let n = p.section(of: h.id).dropFirst().filter { p.task($0)?.completedAt == nil }.count
        return n == 0 ? "A heading with no open tasks under it." : "A heading with \(n) open task\(n == 1 ? "" : "s") under it."
    }

    @ViewBuilder
    private func content(_ items: [DetailItem], actions: WindowActions, size: CGSize) -> some View {
        if items.isEmpty, let id = actions.selectedDeletedList {
            DeletedListInDetail(store: store, window: window, id: id)
                .id(id)
        } else if items.count == 1 {
            SingleDetail(store: store, window: window, item: items[0], refs: refs, actions: actions, viewport: size.height)
                .id(items[0].id)
        } else if items.count > 1 {
            // "3 tasks selected" (15/20 semibold, indented 26, where a title's text starts), then the rows that apply
            // to all, from the content's left edge as under one task (css:260–261).
            VStack(alignment: .leading, spacing: 0) {
                Text("\(items.count) tasks selected")
                    .font(Font(TK.Font.detailTitle))
                    .foregroundStyle(tk.ink.swiftUI)
                    .frame(height: 20)
                    .padding(.leading, 26)
                DetailProps(store: store, window: window, items: items, actions: actions)
                    .padding(.top, 12)
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else {
            // 40% down the body (dc:126, css:298–301). With only headings selected, the heading (§23).
            let heads = selectedHeadings
            VStack(spacing: 6) {
                Text(heads.count > 1 ? "\(heads.count) headings selected"
                     : heads.first.map { $0.title.isEmpty ? "New Heading" : $0.title } ?? "No task selected")
                    .font(Font(TK.Font.bodyMedium))
                    .foregroundStyle(tk.inkSecondary.swiftUI)
                    .lineLimit(1)
                    .frame(height: 16)
                Text(heads.count == 1 ? headingLine(heads[0]) : heads.count > 1 ? "Headings have no notes or dates here."
                     : window.route == .trash ? "Select a task or a list to see it here." : "Select a task to see its notes and dates.")
                    .font(Font(TK.Font.small))
                    .foregroundStyle(tk.inkTertiary.swiftUI)
                    .multilineTextAlignment(.center)
                    .lineSpacing(16 - NSLayoutManager().defaultLineHeight(for: TK.Font.small))
                    .frame(maxWidth: 280, minHeight: 16)
            }
            .padding(.horizontal, 24)
            .frame(width: size.width)
            .offset(y: (size.height * 0.4).rounded(.down))
            .frame(width: size.width, height: size.height, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    // MARK: Focusing the title (a new task, ⌘N again, §6; editing a task from the list, §7)

    private func takeTitleRequest() {
        guard let r = window.titleFocusRequest else { return }
        refs.focusTitle(r.selection, of: r.id)
        DispatchQueue.main.async { if window.titleFocusRequest?.token == r.token { window.titleFocusRequest = nil } }
    }

    // MARK: Presses (§4 Pane focus, §6 The pointer while adding, dc:1307–1320)

    /// Every press in the pane focuses it. One outside the title and the notes ends their editing (they commit as they
    /// resign), except under an untitled new task: there, anything but the × leaves the caret in the title.
    private func press(_ e: NSEvent, actions a: WindowActions) -> NSEvent? {
        guard window.overlays.picker == nil else { return e }
        let inTitle = refs.title?.contains(e) == true
        let inNotes = refs.notes?.view.map { v in
            v.window != nil && !v.inert && v.visibleRect.contains(v.convert(e.locationInWindow, from: nil))
        } == true
        if let d = window.draft, window.selection == [d.id], a.untitledDraft {
            if refs.closeFrame.contains(windowPoint(e)) { return e }
            if window.focus != .detail { window.focus = .detail }
            if inTitle { return e }
            if refs.title?.field.isEditing != true { refs.focusTitle(.end) }
            return nil
        }
        if window.focus != .detail { window.focus = .detail }
        if inTitle || inNotes { return e }
        window.detailKeySink?.takeKeys()
        return e
    }

    /// Keys the pane takes before the menu bar's key equivalents.
    private func keyEquivalent(_ e: NSEvent, actions a: WindowActions) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods == .command else { return false }
        // ⌘Return in the title: commit, keys to the list (§6, §7). AppKit binds no command to it, so the field editor
        // would only beep.
        if e.keyCode == 36 || e.keyCode == 76, let t = refs.title, t.isEditingTitle {
            t.key(.commandReturn)
            return true
        }
        // ⌘A with the pane focused and no field editing: every open task in the view (dc:1399), not the menu bar's
        // Select All (there's no text to select).
        if e.charactersIgnoringModifiers == "a", let sink = window.detailKeySink, e.window?.firstResponder === sink {
            a.selectAll()
            return true
        }
        return false
    }

    private func windowPoint(_ e: NSEvent) -> CGPoint {
        let h = e.window?.contentView?.bounds.height ?? 0
        return CGPoint(x: e.locationInWindow.x, y: h - e.locationInWindow.y)
    }

    // MARK: Keys with no field editing (§21 Keys, dc:1402–1430)

    private func key(_ e: NSEvent, actions a: WindowActions) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let cmd = mods.contains(.command), shift = mods.contains(.shift)
        let plain = mods.isEmpty
        let k = e.keyCode
        if k == 53 && plain {
            // Esc: hide the pane; the list gets the keys.
            a.closeDetail()
            if window.focus == .detail { a.focus(.list) }
            return true
        }
        if k == 48 && !cmd {
            // Tab → sidebar, ⇧Tab → list.
            a.focus(shift ? .list : .sidebar)
            return true
        }
        if (k == 125 || k == 126) && !mods.contains(.option) && !mods.contains(.control) {
            // ↓ ↑ (⇧ extends, ⌘ to the end) act on the list and move focus there.
            a.focus(.list)
            let down = k == 125
            a.moveSelection(cmd ? (down ? .last : .first) : .by(down ? 1 : -1), extend: shift)
            return true
        }
        if (k == 115 || k == 119) && !cmd {
            // Home, End.
            a.moveSelection(k == 115 ? .first : .last, extend: shift)
            return true
        }
        if k == 116 || k == 121 {
            // Page Up, Page Down scroll the list a page: a deleted list's here, else the list pane's.
            (window.detailList?.taskList ?? window.taskList)?.keyDown(with: e)
            return true
        }
        if (k == 36 || k == 76) && plain {
            // Return edits the selected task as Settings ▸ Edit tasks says: its title here, or renamed in its row (the
            // list takes the keys). A deleted list's row in Trash is already shown here (§28).
            let ids = a.targetIDs
            if let id = a.selectedDeletedList {
                a.openDeletedList(id)
            } else if ids.count == 1 {
                a.editTask(ids[0], caret: .all)
            } else if ids.isEmpty {
                a.focus(.list)
                a.moveSelection(.by(1), extend: false)
            }
            return true
        }
        if k == 49 && plain {
            // Space completes or uncompletes, once per press (v2 feedback 18); on a deleted list's row it expands it in
            // Trash (§28).
            if !e.isARepeat { if let id = a.selectedDeletedList { a.toggleTrashExpanded([id]) } else { a.toggleComplete() } }
            return true
        }
        if k == 0 && cmd && !shift {
            // ⌘A: every open task in the view.
            a.selectAll()
            return true
        }
        if !cmd, !mods.contains(.control), !mods.contains(.option), let ch = e.charactersIgnoringModifiers, ch.count == 1,
           ch.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            // Type-select in the list.
            a.typeSelect(ch, inSidebar: false)
            return true
        }
        return false
    }
}

// MARK: - Header (dc:113–123, css:145–154)

/// 34 tall, centered on the window's y = 25 line: the list's small tile and name in `ink-secondary` regular, then
/// trash (Delete ⌘⌫) and × (Hide Details ⌘D). With nothing selected only the ×.
private struct DetailHeader: View {
    let store: Store
    let window: WindowState
    let items: [DetailItem]
    let focused: Bool
    let single: Bool
    let refs: DetailRefs
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let ids = items.map(\.id)
        let first = items.first
        let sameList = first.map { f in items.allSatisfy { $0.list == f.list } } ?? false
        let list = sameList ? first.flatMap { store.projection.listModel($0.list) } : nil
        let inert = items.count == 1 && items[0].isDraft && items[0].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let deletedList = items.isEmpty ? actions.selectedDeletedList : nil
        HStack(spacing: 8) {
            if deletedList != nil {
                // A deleted list: the Trash glyph and "Trash", where it is (§28).
                GlyphView(glyph: .trash, size: 14, color: tk.inkSecondary.swiftUI)
                Text("Trash").font(Font(TK.Font.body)).foregroundStyle(tk.inkSecondary.swiftUI).lineLimit(1).frame(height: 16)
            } else if let first {
                TileView(monogram: list?.monogram ?? "…", hue: list.map { tk.tile(slot: $0.colorSlot) } ?? tk.tile(.ink), size: .small)
                Text(list != nil ? actions.listName(first.list) : "Several lists")
                    .font(Font(TK.Font.body))
                    .foregroundStyle(tk.inkSecondary.swiftUI)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 16)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if let id = deletedList {
                    HeaderIconButton(glyph: .putBack, tip: "\(TrashVerb.list.title) List", keys: "⌘⌫", overlays: window.overlays) {
                        actions.restoreList(id)
                    }
                } else if !items.isEmpty && actions.inTrash {
                    // In Trash, Put Back replaces Delete (§22, dc:120); for a task whose list is in Trash it pops "Put back
                    // in" (§28).
                    let verb = TrashVerb.task
                    let into = ids.contains(where: actions.homeIsDeleted)
                    HeaderIconButton(glyph: .putBack, tip: into ? "\(verb.title) in…" : items.count > 1 ? "\(verb.title) \(items.count) Tasks" : verb.title,
                                     keys: "⌘⌫", overlays: window.overlays) { actions.takeOutOfTrash(ids) }
                } else if !items.isEmpty {
                    HeaderIconButton(glyph: .trash, tip: items.count > 1 ? "Delete \(items.count) Tasks" : "Delete", keys: "⌘⌫",
                                     overlays: window.overlays) { actions.delete(ids) }
                        // Under an untitled new task: 45% and deaf, switching at once (css:286).
                        .opacity(inert ? 0.45 : 1)
                        .allowsHitTesting(!inert)
                }
                HeaderIconButton(glyph: .xmark, tip: "Hide Details", keys: "⌘D", overlays: window.overlays) { actions.closeDetail() }
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { refs.closeFrame = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { _, f in refs.closeFrame = f }
                    })
            }
            .opacity(focused || single ? 1 : 0.55)
            .paneLookAnimation(focused: focused, single: single)
        }
        .padding(.leading, TK.M.headerInset)
        .padding(.trailing, 8)
        .frame(height: TK.M.header)
    }
}

// MARK: - A deleted list

/// A deleted list's row selected in Trash, or opened from it (§28 Opening, the user 2026-11-01): the list pane's own
/// view, on the list's window state (`WindowState.detailListState`), so it's the list exactly as it opens in the list
/// pane: the banner with Restore, the large title with its tile and "In Trash", the notes, the headings (which fold)
/// and the rows, all read-only. The pane's 340pt minimum is wider than the list pane's own 220pt one, so it fits as a
/// narrow list does: the banner's words take two lines, the notes wrap, and a long title fades at the row's end.
private struct DeletedListInDetail: View {
    let store: Store
    let window: WindowState
    let id: EntityID
    @Environment(\.tk) private var tk

    var body: some View {
        let list = window.detailListState(id)
        TaskListRepresentable(store: store, window: list, palette: tk)
            .onDisappear { if window.detailList === list { window.detailList = nil } }
    }
}

// MARK: - One task

/// The title row, the rows, the separator, the notes (the flexible part) and the footer, in a column that scrolls
/// when the notes outgrow it (css:256–283). Under an untitled new task everything below the title is at 45% and
/// ignores the pointer, fading back on `icon` once there's a character (css:284–286).
private struct SingleDetail: View {
    let store: Store
    let window: WindowState
    let item: DetailItem
    let refs: DetailRefs
    let actions: WindowActions
    let viewport: CGFloat
    @State private var liveTitle: String?
    @State private var notesTick = 0
    /// The notes' length while they're being edited, for the footer's count.
    @State private var notesLength: Int?
    @Environment(\.tk) private var tk

    var body: some View {
        let inert = item.isDraft && item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Trash reads but doesn't edit, nor does a deleted list opened from it: the title, the rows and the notes are
        // deaf to the pointer (§22, §28, css:429–430).
        let readOnly = actions.inTrash
        ScrollView(.vertical) {
            DetailColumn(minHeight: max(0, viewport - 8 - 18), flexIndex: 3, flexMin: 12 + 120) {
                titleRow(inert: inert, readOnly: readOnly)
                // Everything under the title starts at the checkbox's left edge and spans the content width, as the
                // title row does (v2 feedback 6).
                DetailProps(store: store, window: window, items: [item], actions: actions)
                    .padding(.top, 12)
                    .dimmed(inert)
                    .allowsHitTesting(!readOnly)
                Rectangle()
                    .fill(tk.lineSeparator.swiftUI)
                    .frame(height: 1)
                    .padding(.top, 10)
                    .dimmed(inert)
                NotesField(store: store, window: window, refs: refs, id: item.id, notes: item.notes, inert: inert || readOnly,
                           palette: tk, layoutTick: notesTick, onLayoutChange: { notesTick &+= 1 },
                           onLength: { if notesLength != $0 { notesLength = $0 } })
                    .padding(.top, 12)
                    .dimmed(inert)
                    .allowsHitTesting(!readOnly)
                Text(meta)
                    .font(Font(TK.Font.caption))
                    .foregroundStyle(tk.inkTertiary.swiftUI)
                    .lineLimit(1)
                    .frame(height: 14)
                    .padding(.top, 14)
                    .dimmed(inert)
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func titleRow(inert: Bool, readOnly: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // The same ring as the task's row (§24, dc:2868); none in the Trash or on a new task.
            let cue = readOnly || item.isDraft || item.completedAt != nil ? CheckLayer.Cue()
                : CheckLayer.Cue(when: item.when, deadline: item.deadline, today: store.projection.dayModel.day.date,
                                 inToday: window.route == .today)
            DetailCheckbox(id: item.id, on: item.completedAt != nil, placeholder: item.isDraft, inert: inert, cue: cue, palette: tk) {
                actions.toggleComplete([item.id])
            }
            .frame(width: DetailCheckView.side, height: DetailCheckView.side)
            .padding(-(DetailCheckView.side - TK.M.check) / 2)
            .padding(.top, 2)
            .opacity(readOnly ? 0.6 : 1)
            .allowsHitTesting(!readOnly)
            TitleField(store: store, window: window, refs: refs, id: item.id, text: item.title, measure: liveTitle ?? item.title,
                       palette: tk, onLiveText: { liveTitle = $0 })
                .allowsHitTesting(!readOnly)
        }
    }

    /// "Created Oct 26 · Completed Oct 30" (dc:1964); in the Trash "Created Aug 20 · Deleted Oct 28" (dc:2437), and for
    /// a task that went with its list "Deleted with School, Nov 1" (§28). The notes' length from 18,000 characters:
    /// " · 19,412 / 20,000" (design/MARKDOWN.md §8, dc:2624).
    private var meta: String {
        func day(_ ms: Int) -> String { DateLabel.monthDay(CalendarDate(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))) }
        var s = "Created " + day(item.createdAt)
        let p = store.projection
        if actions.inTrash, let t = p.task(item.id), t.deleted {
            s += " · Deleted " + day(ViewItems.deletedAt(t))
        } else if actions.inTrash, let t = p.task(item.id), let l = p.list(t.list), let at = l.archivedAt {
            s += " · Deleted with " + actions.listName(l.id) + ", " + day(at)
        } else if let done = item.completedAt {
            s += " · Completed " + day(done)
        }
        let n = notesLength ?? item.notes.utf16.count
        if n >= NotesStyle.nearLength {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            s += " · " + (f.string(from: n as NSNumber) ?? "\(n)") + " / " + (f.string(from: NotesStyle.maxLength as NSNumber) ?? "20,000")
        }
        return s
    }
}

private extension View {
    /// 45% and deaf to the pointer, fading on `icon` (css:285–286).
    func dimmed(_ inert: Bool) -> some View {
        opacity(inert ? 0.45 : 1)
            .animation(TK.Motion.icon, value: inert)
            .allowsHitTesting(!inert)
    }
}

/// A column whose one flexible child (the notes) takes the height the others leave, at least `flexMin`; the column is
/// at least `minHeight` (the pane's body is a flex column with the notes at `flex: 1`, css:256, 274).
private struct DetailColumn: Layout {
    let minHeight: CGFloat
    let flexIndex: Int
    let flexMin: CGFloat

    private func heights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        var hs = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard flexIndex < hs.count else { return hs }
        hs[flexIndex] = max(hs[flexIndex], flexMin)
        let total = hs.reduce(0, +)
        if total < minHeight { hs[flexIndex] += minHeight - total }
        return hs
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 384
        return CGSize(width: w, height: heights(width: w, subviews: subviews).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let hs = heights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: hs[i]))
            y += hs[i]
        }
    }
}

// MARK: - The press monitor

/// Sees every press in the pane before AppKit dispatches it (a local event monitor), so the pane can take focus and end
/// or keep an edit whatever was pressed, AppKit field or SwiftUI view. Returning nil swallows the press. It also gets
/// key presses before the menu bar's key equivalents.
private struct PanePressMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> NSEvent?
    let keyEquivalent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView()
        v.handler = handler
        v.keyEquivalent = keyEquivalent
        return v
    }

    func updateNSView(_ v: MonitorView, context: Context) {
        v.handler = handler
        v.keyEquivalent = keyEquivalent
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent) -> NSEvent?)?
        var keyEquivalent: ((NSEvent) -> Bool)?
        nonisolated(unsafe) private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] e in
                let event = UnsafeSendableBox(e)
                return MainActor.assumeIsolated { () -> UnsafeSendableBox<NSEvent?> in
                    let e = event.value
                    guard let self, let w = self.window, e.window === w else { return UnsafeSendableBox(e) }
                    if e.type == .keyDown {
                        // Before the menu bar's key equivalents.
                        return UnsafeSendableBox(self.keyEquivalent?(e) == true ? nil : e)
                    }
                    guard self.bounds.contains(self.convert(e.locationInWindow, from: nil)) else { return UnsafeSendableBox(e) }
                    return UnsafeSendableBox(self.handler?(e) ?? e)
                }.value
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
