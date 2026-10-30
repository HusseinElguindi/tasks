#if DEBUG
import AppKit
import Foundation
import TasksCore

/// Debug aid for the end-to-end check (spec §10): a real app instance performs actions through the same Store
/// calls the UI makes, syncs, writes its state, and quits.
///
///     Tasks -dataDirectory /tmp/a -serverURL http://127.0.0.1:8791 -syncToken … \
///           -debugActions '[{"createTask":"Milk","list":"Inbox"},{"archive":"Errands"}]' -debugDumpTo /tmp/a.json
///
/// Tasks and lists are named by title. Never compiled into release builds.
@MainActor
enum DebugAutomation {
    static func runIfRequested(_ store: Store) {
        // Read verbatim: UserDefaults' argument domain drops values that look like (non-plist) JSON.
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: "-" + name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let actions = arg("debugActions")
        let dump = arg("debugDumpTo")
        guard actions != nil || dump != nil else { return }
        Task { @MainActor in
            if let json = actions, let data = json.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for action in list { perform(action, store) }
            }
            store.cancelScheduledSync()
            if store.config != nil {
                await store.sync()
                store.cancelScheduledSync()
            }
            store.persistNow()
            if let dump { write(store, to: dump) }
            NSApp.terminate(nil)
        }
    }

    private static func task(_ title: Any?, _ store: Store) -> EntityID? {
        guard let title = title as? String else { return nil }
        let p = store.projection
        return p.allTaskIDs.sorted().first { p.task($0)?.title == title && p.task($0)?.deleted == false }
    }

    private static func list(_ name: Any?, _ store: Store) -> EntityID? {
        guard let name = name as? String else { return nil }
        let p = store.projection
        return p.allListIDs.sorted().first { p.list($0)?.name == name }
    }

    private static func date(_ value: Any?, _ store: Store) -> CalendarDate? {
        guard let s = value as? String else { return nil }
        return s == "today" ? store.projection.day.date : CalendarDate(s)
    }

    private static func perform(_ a: [String: Any], _ store: Store) {
        if let name = a["createList"] as? String {
            store.createList(name: name)
        } else if let title = a["createTask"] as? String {
            store.createTask(title: title, in: list(a["list"], store), when: date(a["when"], store), deadline: date(a["deadline"], store))
        } else if let id = task(a["complete"], store) {
            store.toggleComplete([id])
        } else if let id = task(a["rename"], store), let to = a["to"] as? String {
            store.setTitle(id, to)
        } else if let id = task(a["delete"], store) {
            store.delete([id])
        } else if let id = task(a["move"], store), let to = list(a["to"], store) {
            store.move([id], to: to)
        } else if let id = task(a["reorder"], store), let l = list(a["list"], store) {
            if let after = task(a["after"], store) {
                store.reorder([id], in: l, at: .after(after))
            } else if let before = task(a["before"], store) {
                store.reorder([id], in: l, at: .before(before))
            } else {
                store.reorder([id], in: l, at: .top)
            }
        } else if let l = list(a["archive"], store) {
            store.archive(list: l)
        } else if let l = list(a["unarchive"], store) {
            store.unarchive(list: l)
        } else if let l = list(a["reorderList"], store) {
            if let after = list(a["after"], store) { store.reorderLists([l], at: .after(after)) } else { store.reorderLists([l], at: .top) }
        } else {
            NSLog("debugActions: can't perform %@", a.description)
        }
    }

    /// The confirmed + visible state, deterministic (sorted keys), plus what's still pending.
    private static func write(_ store: Store, to path: String) {
        let p = store.projection
        var visible = AppState()
        for id in p.allTaskIDs { visible.tasks[id] = p.task(id) }
        for id in p.allListIDs { visible.lists[id] = p.list(id) }
        struct Dump: Encodable {
            var cursor: Int
            var pending: Int
            var syncState: String
            var recovering: Bool
            var visible: AppState
            var today: [String]
            var lists: [String]
        }
        let today = p.activeLists.ids.flatMap { l in p.todayTasks(in: l).ids.compactMap { p.task($0)?.title } }
        let lists = p.activeLists.ids.compactMap { p.list($0)?.name }
        let dump = Dump(cursor: store.cursor, pending: p.pending.count, syncState: "\(store.syncState)",
                        recovering: store.recovery != nil, visible: visible, today: today, lists: lists)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try? encoder.encode(dump).write(to: URL(fileURLWithPath: path))
    }
}
#endif
