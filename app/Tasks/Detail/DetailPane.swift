import AppKit
import SwiftUI
import TasksCore

/// The detail pane (§4, §6, §7; the prototype's dc:112–166, css:252–289). It shows the selection: one task (or the
/// new task being added), several ("3 tasks selected" with the rows that apply to all), or none. Its open and close are
/// v1's, done by `MainLayout`.
struct DetailPane: View {
    let store: Store
    @Bindable var window: WindowState
    @State private var refs = DetailRefs()
    @Environment(\.tk) private var tk

    var body: some View {
        let actions = WindowActions(store: store, window: window)
        let items = selectedItems
        let focused = window.focus == .detail
        VStack(spacing: 0) {
            DetailHeader(store: store, window: window, items: items, focused: focused, refs: refs, actions: actions)
            GeometryReader { g in
                content(items, actions: actions, size: g.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .paneChrome(focused: focused)
        .background(PanePressMonitor(handler: { press($0, actions: actions) }, keyEquivalent: { keyEquivalent($0, actions: actions) }))
        .background(
            KeySink(register: { window.detailKeySink = $0 },
                    onKey: { key($0, actions: actions) },
                    onFocus: { if window.focus != .detail { window.focus = .detail } })
                .frame(width: 0, height: 0)
        )
        .onAppear { takeTitleRequest() }
        .onChange(of: window.titleFocusRequest) { _, _ in takeTitleRequest() }
        .onChange(of: items.isEmpty) { _, empty in if empty { window.detailChipFrames = [:] } }
        .onDisappear { window.detailChipFrames = [:] }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task details")
    }

    /// The selection minus deleted tasks; the draft when it's what's selected (dc:1611, 1930).
    private var selectedItems: [DetailItem] {
        if let d = window.draft, window.selection == [d.id] { return [DetailItem(d)] }
        let p = store.projection
        return window.selection.sorted().compactMap { id -> DetailItem? in
            guard id != window.draft?.id, let m = p.taskModel(id), !m.deleted else { return nil }
            return DetailItem(m)
        }
    }

    @ViewBuilder
    private func content(_ items: [DetailItem], actions: WindowActions, size: CGSize) -> some View {
        if items.count == 1 {
            SingleDetail(store: store, window: window, item: items[0], refs: refs, actions: actions, viewport: size.height)
                .id(items[0].id)
        } else if items.count > 1 {
            // "3 tasks selected" (15/20 semibold, indented 26), then the rows that apply to all (css:260).
            VStack(alignment: .leading, spacing: 0) {
                Text("\(items.count) tasks selected")
                    .font(Font(TK.Font.detailTitle))
                    .foregroundStyle(tk.ink.swiftUI)
                    .frame(height: 20)
                    .padding(.leading, 26)
                DetailProps(store: store, window: window, items: items, actions: actions)
                    .padding(.top, 12)
                    .padding(.leading, 26)
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else {
            // 40% down the body (dc:126, css:298–301).
            VStack(spacing: 6) {
                Text("No task selected")
                    .font(Font(TK.Font.bodyMedium))
                    .foregroundStyle(tk.ink2.swiftUI)
                    .frame(height: 16)
                Text("Select a task to see its notes and dates.")
                    .font(Font(TK.Font.small))
                    .foregroundStyle(tk.ink3.swiftUI)
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

    // MARK: Focusing the title (a new task, ⌘N again, §6)

    private func takeTitleRequest() {
        guard let r = window.titleFocusRequest else { return }
        refs.focusTitle(r.selection)
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
            // Page Up, Page Down scroll the list a page.
            window.taskList?.keyDown(with: e)
            return true
        }
        if (k == 36 || k == 76) && plain {
            // Return renames the selected task in its row (the list takes the keys).
            let ids = a.targetIDs
            if ids.count == 1 {
                a.startRename(ids[0], caret: .all)
            } else if ids.isEmpty {
                a.focus(.list)
                a.moveSelection(.by(1), extend: false)
            }
            return true
        }
        if k == 49 && plain {
            // Space completes or uncompletes.
            a.toggleComplete()
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
    let refs: DetailRefs
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let ids = items.map(\.id)
        let first = items.first
        let sameList = first.map { f in items.allSatisfy { $0.list == f.list } } ?? false
        let list = sameList ? first.flatMap { store.projection.listModel($0.list) } : nil
        let inert = items.count == 1 && items[0].isDraft && items[0].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 8) {
            if let first {
                TileView(monogram: list?.monogram ?? "…", color: list.map { tk.listColor(slot: $0.colorSlot) } ?? tk.ansi[6], size: .small)
                Text(list != nil ? actions.listName(first.list) : "Several lists")
                    .font(Font(TK.Font.body))
                    .foregroundStyle(tk.ink2.swiftUI)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 16)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if !items.isEmpty {
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
            .opacity(focused ? 1 : 0.55)
            .animation(TK.Motion.focus, value: focused)
        }
        .padding(.leading, TK.M.headerInset)
        .padding(.trailing, 8)
        .frame(height: TK.M.header)
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
    @Environment(\.tk) private var tk

    var body: some View {
        let inert = item.isDraft && item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ScrollView(.vertical) {
            DetailColumn(minHeight: max(0, viewport - 8 - 18), flexIndex: 3, flexMin: 12 + 120) {
                titleRow(inert: inert)
                DetailProps(store: store, window: window, items: [item], actions: actions)
                    .padding(.top, 12)
                    .padding(.leading, 26)
                    .dimmed(inert)
                Rectangle()
                    .fill(tk.lineSep.swiftUI)
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.leading, 26)
                    .dimmed(inert)
                NotesField(store: store, window: window, refs: refs, id: item.id, notes: item.notes, inert: inert,
                           palette: tk, layoutTick: notesTick, onLayoutChange: { notesTick &+= 1 })
                    .padding(.top, 12)
                    .padding(.leading, 26)
                    .dimmed(inert)
                Text(meta)
                    .font(Font(TK.Font.caption))
                    .foregroundStyle(tk.ink3.swiftUI)
                    .lineLimit(1)
                    .frame(height: 14)
                    .padding(.top, 14)
                    .padding(.leading, 26)
                    .dimmed(inert)
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func titleRow(inert: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DetailCheckbox(id: item.id, on: item.completedAt != nil, placeholder: item.isDraft, inert: inert, palette: tk) {
                actions.toggleComplete([item.id])
            }
            .frame(width: DetailCheckView.side, height: DetailCheckView.side)
            .padding(-(DetailCheckView.side - TK.M.check) / 2)
            .padding(.top, 2)
            TitleField(store: store, window: window, refs: refs, id: item.id, text: item.title, measure: liveTitle ?? item.title,
                       palette: tk, onLiveText: { liveTitle = $0 })
        }
    }

    /// "Created Oct 26 · Completed Oct 30" (dc:1964).
    private var meta: String {
        func day(_ ms: Int) -> String { DateLabel.monthDay(CalendarDate(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))) }
        return "Created " + day(item.createdAt) + (item.completedAt.map { " · Completed " + day($0) } ?? "")
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
