import SwiftUI
import TasksCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.pane) private var pane
    @Environment(\.undoManager) private var undoManager
    @State private var window = WindowState()

    var body: some View {
        ZStack {
            pane.ground
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
                            let detail = window.detailTaskID.flatMap { store.projection.task($0)?.title } ?? "-"
                            return "selection=\(titles) detail=\(detail) quickAdd=\(window.quickAdd.map { "'\($0.title)'" } ?? "-")"
                        }
                        #endif
                    }
            }
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.windowState, window)
        .background(WindowConfigurator(ground: NSColor(pane.ground)))
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { window.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in window.undoManager = new }
    }
}

/// Rex's layout: the sidebar on the ground, then panes with 8pt gutters. Collapsing the sidebar slides the panes over
/// it (the sidebar stays put underneath) while the traffic lights and the toggle stay where they are. Opening a task
/// splits a detail pane to the right; under about 900pt it replaces the list instead (A3's drill-in).
struct MainLayout: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane

    /// Room the leftmost pane header leaves for the traffic lights and the toggle when the panes cover the sidebar.
    static let windowControlsInset: CGFloat = 116

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Sidebar(store: store, window: window)
                    .frame(width: PaneSize.sidebar)
                    .frame(maxHeight: .infinity, alignment: .top)
                Panes(store: store, window: window, narrow: geo.size.width < 900,
                      leadingHeaderInset: window.sidebarVisible ? 0 : Self.windowControlsInset)
                    .padding([.top, .trailing, .bottom], 8)
                    .padding(.leading, window.sidebarVisible ? 0 : 8)
                    .background(pane.ground)
                    .padding(.leading, window.sidebarVisible ? PaneSize.sidebar : 0)
                // Window actions right after the traffic lights, above everything, as in Rex.
                PaneIconButton("sidebar.left", help: window.sidebarVisible ? "Hide Sidebar ⌃⌘S" : "Show Sidebar ⌃⌘S") {
                    withAnimation(PaneMotion.sidebar) { window.sidebarVisible.toggle() }
                }
                .environment(\.paneGhostLevel, .secondary)
                // Rex's toggle: centered 107pt in, on the traffic lights' line (y 25).
                .padding(.leading, 96)
                .padding(.top, 14)
            }
        }
    }
}

struct Panes: View {
    let store: Store
    @Bindable var window: WindowState
    let narrow: Bool
    /// Header room for the window controls, given to the leftmost pane only.
    var leadingHeaderInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            if narrow, let id = window.detailTaskID {
                DetailPane(store: store, window: window, taskID: id, showsBack: true)
                    .environment(\.paneHeaderInset, leadingHeaderInset)
            } else {
                primary
                    .environment(\.paneHeaderInset, leadingHeaderInset)
                if let id = window.detailTaskID {
                    DetailPane(store: store, window: window, taskID: id, showsBack: false)
                        .frame(width: 420)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(PaneMotion.natural, value: window.detailTaskID == nil)
        .sheet(isPresented: $window.movePickerPresented) {
            MovePicker(store: store, window: window)
        }
    }

    @ViewBuilder private var primary: some View {
        // Today and lists are the same pane at the same place, so switching updates it instead of rebuilding it.
        if let mode = window.route.taskMode {
            TaskPane(store: store, window: window, mode: mode)
        } else {
            ArchivePane(store: store, window: window)
                .frame(width: window.archiveSelection == nil ? nil : 380)
            if let id = window.archiveSelection {
                TaskPane(store: store, window: window, mode: .list(id))
                    .id(id)
                    .environment(\.paneHeaderInset, 0)
            }
        }
    }
}
