#if DEBUG
import Foundation
import TasksCore

/// UI tests only, Debug builds only: a change "from another device", made when the test posts the Darwin notification
/// `RemoteEdit.notification`, so a test can land one in the middle of an edit without a server. The launch arguments
/// say what changes: `-remoteTask <taskID>`, then `-remoteTitle <text>` and/or `-remoteNotes <text>`; `-remoteList
/// <listID>` with `-remoteName <text>`. It goes through the Store like any change, with no undo step here, as a synced
/// one arrives.
enum RemoteEdit {
    static let notification = "com.elguindi.Tasks.test.remote-edit"
    @MainActor private static weak var app: AppModel?

    @MainActor static func install(_ app: AppModel) {
        let d = UserDefaults.standard
        guard d.string(forKey: "remoteTask") != nil || d.string(forKey: "remoteList") != nil else { return }
        self.app = app
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in RemoteEdit.apply() }
        }, notification as CFString, nil, .deliverImmediately)
    }

    @MainActor private static func apply() {
        let d = UserDefaults.standard
        guard let app else { return }
        if let id = d.string(forKey: "remoteTask") {
            if let title = d.string(forKey: "remoteTitle") { _ = app.store.setTitle(id, title) }
            if let notes = d.string(forKey: "remoteNotes") { _ = app.store.setNotes(id, notes) }
        }
        if let id = d.string(forKey: "remoteList"), let name = d.string(forKey: "remoteName") { _ = app.store.rename(list: id, to: name) }
    }
}
#endif
