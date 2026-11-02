import SwiftUI
import TasksCore

@main
struct TasksApp: App {
    @State private var app: AppModel?
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if let app {
                    RootView()
                        .themed(app)
                        .task { await LaunchArguments.apply(to: app) }
                } else {
                    // The store loads off the main thread; this is a moment at launch.
                    Color(.systemBackground).ignoresSafeArea()
                }
            }
            .task {
                guard app == nil else { return }
                let opened = await Launch.open()
                app = opened
                opened.startSync()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in app?.store.refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in app?.store.refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in app?.store.refreshDay() }
        }
        .onChange(of: phase) { _, now in
            guard let app else { return }
            switch now {
            case .active: app.cameToFront()
            case .background:
                // No new-task row waits in the background: a title is written (and saved, next), an empty row goes.
                app.endDraft()
                app.inFront = false
                app.store.persistNow()
            default: app.inFront = false
            }
        }
    }
}

/// Opening the data: TasksCore's Store on a folder in Application Support, as the Mac's AppModel does.
enum Launch {
    /// `Tasks` for Release builds, `Tasks Dev` for Debug ones: Debug and Release share the app's container on iOS (one
    /// bundle id), so they keep their data apart the way the Mac's two apps do. `-dataDirectory <path>` (testing)
    /// overrides it; `-sampleData YES` uses a scratch folder of its own, seeded fresh.
    static func dataDirectory() -> URL {
        let d = UserDefaults.standard
        if let path = d.string(forKey: "dataDirectory"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        #if DEBUG
        let folder = "Tasks Dev"
        #else
        let folder = "Tasks"
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
    }

    @MainActor static func open() async -> AppModel {
        if UserDefaults.standard.bool(forKey: "sampleData") {
            let dir = SampleData.directory
            try? FileManager.default.removeItem(at: dir)
            let clock = MovableClock()
            let store = await Store.open(directory: dir, clock: clock.storeClock)
            SampleData.seed(store, clock: clock)
            return AppModel(store: store, isSample: true)
        }
        return AppModel(store: await Store.open(directory: dataDirectory()))
    }
}

/// Deep links for screenshots and demos:
///   -sampleData YES (the sample lists and tasks, in a scratch store of their own; never synced)
///   -serverURL <url> (overrides Settings without saving); Debug only: -syncToken <a local server's throwaway token>
///   -screen home | today | upcoming | undated | completed | trash | list:<id> | detail:<taskID> | when:<taskID>
///           | deadline:<taskID> | settings | newtask | notice
///   -appearance system|light|dark   -style classic|glass
///   -expand <listID> (opens a deleted list in Trash)   -completed <listID> (opens a list's Completed)
///   -hold YES (keeps notices and just-checked rows on screen, for screenshots)
///   Debug only, for UI tests: -remoteTask <taskID> -remoteTitle <text> -remoteNotes <text>; -remoteList <listID> -remoteName <text>
///   (RemoteEdit.swift)
/// A list can be named by its sample short name (`school`, `phys`, `inbox`, `w26`…) or its id.
enum LaunchArguments {
    @MainActor static func apply(to app: AppModel) async {
        let d = UserDefaults.standard
        let p = app.projection
        func listID(_ s: String) -> EntityID { SampleData.listID(s, in: p) }
        // -appearance and -style are read by AppModel from the arguments, which win without being saved.
        if let e = d.string(forKey: "expand") { app.expandedTrash.insert(listID(e)) }
        if let c = d.string(forKey: "completed") { app.showCompleted.insert(listID(c)) }
        if d.bool(forKey: "hold") { app.holdTransient = true }
        #if DEBUG
        RemoteEdit.install(app)
        #endif
        guard let screen = d.string(forKey: "screen") else { return }

        func list(of taskID: EntityID) -> Source { .list(app.task(taskID)?.list ?? p.activeLists.ids.first ?? "") }
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "home": break
        case "today", "upcoming", "undated", "completed", "trash":
            app.open(Source(id: parts[0])!)
        case "list":
            app.open(.list(listID(arg)))
        case "detail":
            app.open(list(of: arg))
            try? await Task.sleep(for: .seconds(0.6))
            if app.isSplit { app.selectedTask = arg } else { app.detailTask = arg }
        case "when", "deadline":
            app.open(list(of: arg))
            if app.isSplit { app.selectedTask = arg }
            try? await Task.sleep(for: .seconds(0.6))
            app.dateTarget = DateTarget(taskID: arg, kind: parts[0] == "when" ? .when : .deadline)
        case "settings":
            try? await Task.sleep(for: .seconds(0.4))
            app.showSettings = true
        case "newtask":
            let id = listID(arg.isEmpty ? "school" : arg)
            app.open(.list(id))
            try? await Task.sleep(for: .seconds(0.5))
            app.startDraft(.list(id))
            app.draft?.title = "Book a study room for Thursday"
        case "notice":
            app.open(.today)
            try? await Task.sleep(for: .seconds(0.5))
            app.toggle(arg.isEmpty ? "s2" : arg)
        default: break
        }
    }
}
