import SwiftUI
import TasksCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tk) private var tk
    @Environment(\.undoManager) private var undoManager
    @Environment(\.paneInterfaceStyle) private var style
    @State private var window = WindowState()
    /// A widget's link that came before the store or this window's lists were up.
    @State private var pendingLink: DeepLink?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if style == .glass { GlassGround() } else { tk.ground.swiftUI }
            if let store = model.store {
                MainLayout(store: store, window: window)
                    .focusedSceneValue(\.store, store)
                    .onAppear {
                        #if DEBUG
                        DemoData.seedIfRequested(store)
                        DemoData.applyDebugRoute(store, window)
                        DebugSnapshot.runIfRequested()
                        DebugSettingsSnapshot.runIfRequested(model)
                        DebugThemeCheck.runIfRequested()
                        DebugAutomation.runIfRequested(store)
                        DebugTiming.runIfRequested(store, window)
                        DebugKeyLog.installIfRequested()
                        DebugScript.runIfRequested(window, model: model) {
                            let titles = window.selection.compactMap { store.projection.task($0)?.title }.sorted()
                            return "selection=\(titles) focus=\(window.focus) detail=\(window.detailOpen) zoom=\(window.zoomed) draft=\(window.draft.map { "'\($0.title)'" } ?? "-") widths=\(Int(window.sidebarWidth))/\(Int(window.detailWidth)) rename=\(window.rename.map { "\($0.kind)" } ?? "-") detailEditing=\(window.detailEditing.map { "\($0)" } ?? "-") editor=\((window.nsWindow?.firstResponder as? NSTextView).map { "'\($0.string)'" } ?? "-")"
                        }
                        #endif
                    }
            }
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.windowState, window)
        .background(WindowConfigurator(ground: tk.ground, window: window))
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { window.undoManager = undoManager }
        // A widget's link (`tasks://…`, DeepLink): an open window takes it rather than a new one opening for it; with
        // none open, SwiftUI opens one and hands it the link.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard let link = DeepLink(url) else { return }
            pendingLink = link
            followPendingLink()
        }
        .onChange(of: model.store != nil) { followPendingLink() }
        .onChange(of: model.paneHighlight, initial: true) { _, new in
            window.paneHighlight = new
            window.detailList?.paneHighlight = new
        }
        .onChange(of: undoManager) { _, new in window.undoManager = new }
    }

    /// Follows the waiting link once the store is open, a turn later so a window that just opened has its lists.
    private func followPendingLink() {
        guard pendingLink != nil, model.store != nil else { return }
        DispatchQueue.main.async {
            guard let link = pendingLink, let store = model.store else { return }
            pendingLink = nil
            NSApp.activate()
            window.nsWindow?.makeKeyAndOrderFront(nil)
            WindowActions(store: store, window: window).follow(link)
        }
    }
}

/// The window (§4): the sidebar on the ground, then the list pane and the detail pane with 8pt gutters. Hiding the
/// sidebar slides the panes over it (it stays put underneath) while the traffic lights and the toggle stay where they
/// are, on the y = 25 line with every pane's title and buttons. Under ~900pt the detail pane replaces the list
/// (A3's drill-in). The sidebar's edge and the gap before the detail pane are dividers (`PaneGeometry`). A zoomed
/// detail pane (§29) takes the list's room as well, sliding over it; the sidebar stays as it is.
struct MainLayout: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.tk) private var tk
    @Environment(\.paneInterfaceStyle) private var style
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GeometryReader { geo in
            let g = PaneGeometry(width: geo.size.width, window: window)
            let sync = window.sync(store)
            // Offline and stopped beside the toggle while the sidebar is hidden or its header has scrolled away (§26).
            let inBand = !window.sidebarVisible || window.sidebarHeaderHidden
            let collapsedInset = inBand && sync.showsInBand ? TK.M.headerInsetCloud : TK.M.headerInsetCollapsed
            let narrow = g.narrow
            let paneHeight = max(0, geo.size.height - 2 * TK.M.gutter)
            let zoomed = window.zoomed && !narrow
            ZStack(alignment: .topLeading) {
                SidebarRepresentable(store: store, window: window, palette: tk)
                    .frame(width: g.sidebar)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // In Glass the panes would show it through their fills: it fades as they slide over it.
                    .opacity(style == .glass && !window.sidebarVisible ? 0 : 1)
                // The panes as `window.panes` has them, each placed by its frame (`PaneFrames`). Nothing leaves with a
                // removal transition: a closing pane slides off and fades in place, and is taken out a moment later with
                // no transition, so it can't stay on screen after it closed (T50).
                let frames = PaneFrames(layout: window.panes, width: geo.size.width, height: geo.size.height, lead: g.lead,
                                        detailWidth: g.detail, gutter: TK.M.gutter, narrow: narrow, zoomed: window.zoomed)
                ZStack(alignment: .topLeading) {
                    ForEach(window.panes.panes) { pane in
                        switch pane.kind {
                        case .list:
                            // The band's title makes room for the cloud on the sidebar's curve. Its width settles where
                            // the frame says (beside the detail pane, under a zoom, or alone), so its notes wrap once as
                            // the detail pane or the sidebar slides, not on every frame.
                            ListPane(store: store, window: window, leadingInset: window.sidebarVisible ? TK.M.headerInset : collapsedInset,
                                     settleWidth: frames.list.rect.width)
                                .animation(TK.Motion.sidebar, value: collapsedInset)
                                .placed(frames.list)
                        case .detail:
                            if let f = frames.detail {
                                // v1's open and close (§4): in from the trailing edge, fading, on `natural`.
                                DetailPane(store: store, window: window, single: narrow || zoomed,
                                           leadingInset: zoomed && !window.sidebarVisible ? collapsedInset : TK.M.headerInset)
                                    .animation(TK.Motion.sidebar, value: collapsedInset)
                                    // The list pane, which shows notices, is covered: they show here (§29).
                                    .overlay(alignment: .bottomTrailing) {
                                        if zoomed {
                                            NoticeView(overlays: window.overlays, actions: WindowActions(store: store, window: window)).padding(12)
                                        }
                                    }
                                    .placed(f)
                                    .transition(.asymmetric(insertion: .offset(x: frames.detailSlide).combined(with: .opacity),
                                                            removal: .identity))
                            }
                        }
                    }
                }
                .animation(TK.Motion.natural, value: window.detailOpen)
                .animation(TK.Motion.natural, value: window.zoomed)
                if window.sidebarVisible {
                    PaneDividerRepresentable(kind: .sidebar, window: window, geometry: g)
                        .frame(width: TK.M.dividerHit, height: paneHeight)
                        .offset(x: g.sidebar - TK.M.dividerHit / 2, y: TK.M.gutter)
                }
                if g.detailBeside(window) {
                    // Exactly the gutter: the detail pane takes any press inside its frame (`PanePressMonitor`).
                    PaneDividerRepresentable(kind: .detail, window: window, geometry: g)
                        .frame(width: TK.M.gutter, height: paneHeight)
                        .offset(x: geo.size.width - 2 * TK.M.gutter - g.detail, y: TK.M.gutter)
                }
                // The window's controls, above everything (Rex): the toggle's 28pt circle at (93, 11).
                ToolbarToggle(window: window, actions: WindowActions(store: store, window: window))
                    .offset(x: 93, y: 11)
                SyncCloud(indicator: sync, overlays: window.overlays, round: true, inBand: inBand,
                          anchor: { CGRect(x: 125, y: 11, width: 28, height: 28) }, openSettings: { openSettings() })
                    .offset(x: 125, y: 11)
                OverlayLayer(store: store, window: window, size: geo.size)
                DragOverlayRepresentable(window: window, palette: tk)
                    .allowsHitTesting(false)
            }
            .onAppear { window.openSettings = { openSettings() } }
            // Closing the window writes what's being typed, as a press elsewhere would. The detail pane's fields do
            // that themselves as they leave the window; the renames in place live in this window's state, which
            // goes with it (docs/MAC-EDIT-DURABILITY.md).
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
                if let w = n.object as? NSWindow, w === window.nsWindow { WindowActions(store: store, window: window).endEdits() }
            }
            // A window narrowed past ~900pt has the detail pane in the list's place: a zoom has nothing left to do.
            .onChange(of: g.narrow, initial: true) { _, n in
                if window.narrow != n { window.narrow = n }
                if n, window.zoomed { window.zoomed = false }
            }
        }
    }
}

/// The sidebar toggle beside the traffic lights: `ink-secondary`, a `fill-track` circle and `ink` on hover (`icon`),
/// `press` at once (css:91–95).
struct ToolbarToggle: View {
    @Bindable var window: WindowState
    let actions: WindowActions
    @Environment(\.tk) private var tk
    @State private var hovered = false

    var body: some View {
        Button { actions.toggleSidebar() } label: {
            GlyphView(glyph: .sidebarLeft, size: 16, color: (hovered ? tk.ink : tk.inkSecondary).swiftUI)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(CircleToolbarStyle(hovered: hovered))
        .tipped(window.sidebarVisible ? "Hide Sidebar" : "Show Sidebar", keys: "⌃⌘S", overlays: window.overlays, hovered: $hovered)
        .accessibilityLabel(window.sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct CircleToolbarStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle().fill((configuration.isPressed ? tk.press : hovered ? tk.fillTrack : .clear).swiftUI)
                    .animation(configuration.isPressed ? nil : TK.Motion.icon, value: hovered)
            }
    }
}

extension View {
    /// A pane at its frame in the panes' layer (`PaneFrames`): sized, moved there by layout (so its AppKit views move
    /// with it), faded, and out of presses and VoiceOver when it's hidden or closing.
    func placed(_ f: PaneFrames.Frame) -> some View {
        frame(width: f.rect.width, height: f.rect.height)
            .opacity(f.opacity)
            .allowsHitTesting(f.interactive)
            .accessibilityHidden(!f.interactive)
            .padding(.leading, f.rect.minX)
            .padding(.top, f.rect.minY)
    }
}
