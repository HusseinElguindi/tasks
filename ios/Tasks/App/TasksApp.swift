import SwiftUI

@main
struct TasksApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .themed(store)
                .task { await LaunchArguments.apply(to: store) }
        }
    }
}

/// Deep links for screenshots and demos:
///   -screen home | today | upcoming | undated | completed | trash | list:<id> | detail:<taskID> | when:<taskID>
///           | deadline:<taskID> | settings | newtask | notice | swipe
///   -appearance system|light|dark   -style classic|glass
///   -expand <listID> (opens a deleted list in Trash)   -completed <listID> (opens a list's Completed)
///   -hold YES (keeps notices and just-checked rows on screen, for screenshots)
enum LaunchArguments {
    @MainActor static func apply(to store: Store) async {
        let d = UserDefaults.standard
        if let a = d.string(forKey: "appearance"), let v = Appearance(rawValue: a) { store.appearance = v }
        if let s = d.string(forKey: "style"), let v = InterfaceStyle(rawValue: s) { store.style = v }
        if let e = d.string(forKey: "expand") { store.expandedTrash.insert(e) }
        if let c = d.string(forKey: "completed") { store.showCompleted.insert(c) }
        if d.bool(forKey: "hold") { store.holdTransient = true }
        guard let screen = d.string(forKey: "screen") else { return }

        func list(of taskID: String) -> Source { .list(store.task(taskID)?.listID ?? "inbox") }
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "home": break
        case "today", "upcoming", "undated", "completed", "trash":
            store.open(Source(id: parts[0])!)
        case "list":
            store.open(.list(arg))
        case "detail":
            store.open(list(of: arg))
            try? await Task.sleep(for: .seconds(0.6))
            if store.isSplit { store.selectedTask = arg } else { store.detailTask = arg }

        case "when", "deadline":
            store.open(list(of: arg))
            if store.isSplit { store.selectedTask = arg }
            try? await Task.sleep(for: .seconds(0.6))
            store.dateTarget = DateTarget(taskID: arg, kind: parts[0] == "when" ? .when : .deadline)
        case "settings":
            try? await Task.sleep(for: .seconds(0.4))
            store.showSettings = true
        case "newtask":
            store.open(.list(arg.isEmpty ? "school" : arg))
            try? await Task.sleep(for: .seconds(0.5))
            store.startDraft(.list(arg.isEmpty ? "school" : arg))
            store.draft?.title = "Book a study room for Thursday"
        case "notice":
            store.open(.today)
            try? await Task.sleep(for: .seconds(0.5))
            store.toggle(arg.isEmpty ? "s2" : arg)
        default: break
        }
    }
}
