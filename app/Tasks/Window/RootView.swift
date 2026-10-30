import SwiftUI
import TasksCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tk) private var tk
    @Environment(\.undoManager) private var undoManager
    @State private var window = WindowState()

    var body: some View {
        ZStack(alignment: .topLeading) {
            tk.ground.swiftUI
            if let store = model.store {
                MainLayout(store: store, window: window)
                    .focusedSceneValue(\.store, store)
                    .onAppear {
                        #if DEBUG
                        DemoData.seedIfRequested(store)
                        DemoData.applyDebugRoute(store, window)
                        DebugSnapshot.runIfRequested()
                        DebugAutomation.runIfRequested(store)
                        DebugTiming.runIfRequested(store, window)
                        DebugKeyLog.installIfRequested()
                        DebugScript.runIfRequested(window) {
                            let titles = window.selection.compactMap { store.projection.task($0)?.title }.sorted()
                            return "selection=\(titles) focus=\(window.focus) detail=\(window.detailOpen) draft=\(window.draft.map { "'\($0.title)'" } ?? "-") widths=\(Int(window.sidebarWidth))/\(Int(window.detailWidth))"
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
        .onChange(of: undoManager) { _, new in window.undoManager = new }
    }
}

/// The window (§4): the sidebar on the ground, then the list pane and the detail pane with 8pt gutters. Hiding the
/// sidebar slides the panes over it (it stays put underneath) while the traffic lights and the toggle stay where they
/// are, on the y = 25 line with every pane's title and buttons. Under ~900pt the detail pane replaces the list
/// (A3's drill-in). The sidebar's edge and the gap before the detail pane are dividers (`PaneGeometry`).
struct MainLayout: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.tk) private var tk

    var body: some View {
        GeometryReader { geo in
            let g = PaneGeometry(width: geo.size.width, window: window)
            let narrow = g.narrow
            let paneHeight = max(0, geo.size.height - 2 * TK.M.gutter)
            ZStack(alignment: .topLeading) {
                SidebarRepresentable(store: store, window: window, palette: tk)
                    .frame(width: g.sidebar)
                    .frame(maxHeight: .infinity, alignment: .top)
                HStack(spacing: TK.M.gutter) {
                    if !(narrow && window.detailOpen) {
                        ListPane(store: store, window: window, leadingInset: window.sidebarVisible ? TK.M.headerInset : TK.M.headerInsetCollapsed)
                    }
                    if window.detailOpen {
                        // v1's transition, kept exactly (§4).
                        DetailPane(store: store, window: window, single: narrow)
                            .frame(width: narrow ? nil : g.detail)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(TK.Motion.natural, value: window.detailOpen)
                .padding([.top, .bottom, .trailing], TK.M.gutter)
                .padding(.leading, g.lead)
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
                OverlayLayer(store: store, window: window, size: geo.size)
                DragOverlayRepresentable(window: window, palette: tk)
                    .allowsHitTesting(false)
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
            GlyphView(glyph: .sidebarLeft, size: 16, color: (hovered ? tk.ink : tk.ink2).swiftUI)
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
