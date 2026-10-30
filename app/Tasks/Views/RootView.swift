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

/// Rex's layout: the sidebar on the ground, then panes with 8pt gutters. Opening a task splits a detail pane to
/// the right; under about 900pt it replaces the list instead (A3's drill-in).
struct MainLayout: View {
    let store: Store
    @Bindable var window: WindowState
    @Environment(\.pane) private var pane

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if window.sidebarVisible {
                    Sidebar(store: store, window: window)
                        .frame(width: PaneSize.sidebar)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if !window.sidebarVisible {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 76)
                            PaneIconButton("sidebar.left", help: "Show Sidebar") {
                                withAnimation(PaneMotion.natural) { window.sidebarVisible = true }
                            }
                            .foregroundStyle(pane.inkSecondary)
                            Spacer()
                        }
                        .frame(height: 30)
                    }
                    Panes(store: store, window: window, narrow: geo.size.width < 900)
                        .padding(.top, window.sidebarVisible ? 8 : 0)
                        .padding(.leading, window.sidebarVisible ? 0 : 8)
                        .padding([.trailing, .bottom], 8)
                }
            }
        }
    }
}

struct Panes: View {
    let store: Store
    @Bindable var window: WindowState
    let narrow: Bool

    var body: some View {
        HStack(spacing: 8) {
            if narrow, let id = window.detailTaskID {
                DetailPane(store: store, window: window, taskID: id, showsBack: true)
            } else {
                primary
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
        switch window.route {
        case .today:
            TodayPane(store: store, window: window)
        case .list(let id):
            // No .id(listID): switching lists keeps one List and diffs its rows instead of rebuilding the table.
            ListPane(store: store, window: window, listID: id)
        case .archive:
            ArchivePane(store: store, window: window)
                .frame(width: window.archiveSelection == nil ? nil : 380)
            if let id = window.archiveSelection {
                ListPane(store: store, window: window, listID: id)
                    .id(id)
            }
        }
    }
}
