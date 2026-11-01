import SwiftUI
import TasksCore

/// The list pane (§4): Today or a list, in one pane at one place so switching updates it in place. Its header is 34pt
/// from the pane's top, so its contents center on the window's y = 25 line; the rows are the AppKit task list.
struct ListPane: View {
    let store: Store
    @Bindable var window: WindowState
    /// 12, or 124 with the sidebar hidden so the title clears the traffic lights and the toggle (§4).
    let leadingInset: CGFloat
    @Environment(\.tk) private var tk

    var body: some View {
        let focused = window.focus == .list
        // Alone in the window (the detail pane closed), the pane has no focus look (v2 feedback 3).
        let single = !window.detailOpen
        let actions = WindowActions(store: store, window: window)
        VStack(spacing: 0) {
            ListPaneHeader(store: store, window: window, focused: focused, single: single, leadingInset: leadingInset, actions: actions)
            TaskListRepresentable(store: store, window: window, palette: tk)
        }
        // Today all done: D's sunrise at the top of the pane, behind the band (COLOR.md §4).
        .background(alignment: .top) { Sunrise(shown: window.allDone) }
        .paneChrome(focused: focused, single: single)
        .overlay(alignment: .bottomTrailing) {
            NoticeView(overlays: window.overlays, actions: actions).padding(12)
        }
    }
}

struct ListPaneHeader: View {
    let store: Store
    @Bindable var window: WindowState
    let focused: Bool
    let single: Bool
    let leadingInset: CGFloat
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let p = store.projection
        let lit = focused || single
        let listID = window.route.listID
        let list = listID.flatMap { p.listModel($0) }
        HStack(spacing: 8) {
            // The band's own tile and title stay hidden while the large title is in view, and fade in (150 ms
            // ease-out) once the list has scrolled 24pt (§23 On scroll); double-clicking the title then renames the
            // list at the top.
            HStack(spacing: 8) {
            if let list {
                TileView(monogram: list.monogram, hue: tk.tile(slot: list.colorSlot), size: .small)
                Text(list.name.isEmpty ? "New List" : list.name)
                    .layoutPriority(1)
                    .font(Font(TK.Font.bodyMedium))
                    .foregroundStyle((lit ? tk.ink : tk.inkSecondary).swiftUI)
                    .lineLimit(1)
                if list.isArchived {
                    Text("Archived").font(Font(TK.Font.body)).foregroundStyle(tk.inkSecondary.swiftUI).lineLimit(1)
                }
            } else if window.route.isView {
                // A view's header is Today's: its tile (B), its name, no subtitle (§22).
                TileView(monogram: nil, hue: window.route.tileHue(tk), glyph: window.route.glyph ?? .sun, size: .small)
                Text(window.route.viewName ?? "")
                    .font(Font(TK.Font.bodyMedium))
                    .foregroundStyle((lit ? tk.ink : tk.inkSecondary).swiftUI)
                    .lineLimit(1)
            } else {
                TileView(monogram: nil, hue: tk.tileToday, size: .small)
                Text("Today")
                    .layoutPriority(1)
                    .font(Font(TK.Font.bodyMedium))
                    .foregroundStyle((lit ? tk.ink : tk.inkSecondary).swiftUI)
                Text(DateLabel.long(p.dayModel.day.date, today: p.dayModel.day.date))
                    .font(Font(TK.Font.body))
                    .foregroundStyle(tk.inkSecondary.swiftUI)
                    .lineLimit(1)
            }
            }
            .opacity(window.titleScrolled ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: window.titleScrolled)
            .allowsHitTesting(window.titleScrolled)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if listID != nil { actions.startTitleRename() } }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                // Completed and Trash have no + (§22).
                if !window.route.noAdd {
                    HeaderIconButton(glyph: .plus, tip: newTip, keys: "⌘N", overlays: window.overlays) { actions.newTask() }
                }
                HeaderIconButton(glyph: .split, tip: window.detailOpen ? "Hide Details" : "Show Details", keys: "⌘D",
                                 on: window.detailOpen, overlays: window.overlays) { actions.toggleDetail() }
            }
            .opacity(lit ? 1 : 0.55)
            .paneLookAnimation(focused: focused, single: single)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 8)
        .frame(height: TK.M.header)
        .background {
            // A press on the header (not its buttons) focuses the list, ending any edit the way a press elsewhere does.
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                    if window.focus != .list || window.draft != nil || window.rename != nil {
                        actions.endEdits()
                        actions.focus(.list)
                    }
                })
        }
    }

    /// In Today and the views the + names its target: "New Task in Inbox" (§6, §22).
    private var newTip: String {
        guard window.route.listID == nil else { return "New Task" }
        let actions = WindowActions(store: store, window: window)
        let p = store.projection
        if let sel = window.selection.first(where: { $0 != window.draft?.id }), let t = p.task(sel), p.isActive(list: t.list) {
            return "New Task in \(actions.listName(t.list))"
        }
        return "New Task in \(store.defaultListID.map(actions.listName) ?? "Inbox")"
    }
}

// MARK: - Pane chrome (§4 Pane focus)

extension View {
    /// `surface-base` and a 1pt inset `line-pane` edge when focused, `surface-dim` and `line-pane-dim` when not; radius
    /// 10 (css:142–144). A pane alone in the window (`single`) shows no focus, whatever has the keys: the unfocused
    /// fill and edge, its header and selected rows as in a focused pane (v2 feedback 3). In Glass the fill lets the
    /// window's glass ground through (`TK.Glass.paneFill`).
    func paneChrome(focused: Bool, single: Bool) -> some View { modifier(PaneChromeModifier(focused: focused, single: single)) }

    /// Focus changes on `focus` (60 ms); becoming or ceasing to be the only pane rides the detail pane's open and
    /// close (`natural`), and wins when both change at once (it's the inner one).
    func paneLookAnimation(focused: Bool, single: Bool) -> some View {
        animation(TK.Motion.natural, value: single).animation(TK.Motion.focus, value: focused)
    }
}

private struct PaneChromeModifier: ViewModifier {
    let focused: Bool
    let single: Bool
    @Environment(\.tk) private var tk
    @Environment(\.paneInterfaceStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TK.M.paneRadius, style: .circular)
        let lit = focused && !single
        content
            .background((lit ? tk.base : tk.dim).swiftUI.opacity(style == .glass ? TK.Glass.paneFill : 1), in: shape)
            .overlay(shape.strokeBorder((lit ? tk.linePane : tk.linePaneDim).swiftUI, lineWidth: 1))
            .clipShape(shape)
            .paneLookAnimation(focused: focused, single: single)
    }
}

// MARK: - Pane-header icon buttons (css:151–154)

/// 26×26, radius 6, a 14pt glyph in `ink-quiet`; hover: `hover` fill and `ink-secondary` on `icon`; press: `press` fill
/// and `ink` at once; on (the split button while the pane is open): `ink-secondary`.
struct HeaderIconButton: View {
    let glyph: Glyph
    let tip: String
    var keys: String = ""
    var on = false
    var disabled = false
    let overlays: Overlays
    let action: () -> Void
    @Environment(\.tk) private var tk
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Color.clear.frame(width: TK.M.headerButton, height: TK.M.headerButton)
        }
        .buttonStyle(HeaderIconStyle(glyph: glyph, hovered: hovered, on: on))
        .disabled(disabled)
        .tipped(tip, keys: keys, overlays: overlays, hovered: $hovered)
        .accessibilityLabel(tip)
    }
}

private struct HeaderIconStyle: ButtonStyle {
    let glyph: Glyph
    let hovered: Bool
    let on: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let color = pressed ? tk.ink : hovered ? tk.inkSecondary : on ? tk.inkSecondary : tk.inkQuiet
        let fill = pressed ? tk.press : hovered ? tk.hover : .clear
        configuration.label
            .background(fill.swiftUI, in: RoundedRectangle(cornerRadius: TK.M.headerButtonRadius))
            .overlay { GlyphView(glyph: glyph, size: TK.M.headerGlyph, color: color.swiftUI) }
            .contentShape(Rectangle())
            .animation(pressed ? nil : TK.Motion.icon, value: hovered)
            .animation(pressed ? nil : TK.Motion.icon, value: pressed)
    }
}

// MARK: - Tooltips (§16)

extension View {
    /// Shows the window's tooltip for this control: the name, then the keys, 600 ms after the pointer arrives.
    func tipped(_ text: String, keys: String = "", overlays: Overlays, hovered: Binding<Bool>) -> some View {
        modifier(TipModifier(text: text, keys: keys, overlays: overlays, hovered: hovered))
    }
}

private struct TipModifier: ViewModifier {
    let text: String
    let keys: String
    let overlays: Overlays
    @Binding var hovered: Bool
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in frame = f }
            })
            .onHover { inside in
                hovered = inside
                if inside {
                    overlays.hoverTip(text, keys: keys, for: frame, windowWidth: NSApp.keyWindow?.frame.width ?? 1200)
                } else {
                    overlays.hideTip()
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in overlays.hideTip() })
            .onDisappear { if hovered { overlays.hideTip() } }
    }
}
