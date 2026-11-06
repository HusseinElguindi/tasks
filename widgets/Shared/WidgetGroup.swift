import Foundation
import TasksCore

/// Where the app and its widgets meet: a folder in the App Group's container (WIDGETS.md §3.2), TasksCore's
/// `WidgetFolder`. The app is the feed's only writer; the widgets only read it. `Tasks` for Release builds and
/// `Tasks Dev` for Debug ones, as the app's own data folders are, so a Debug build's widget never shows Release data
/// or the other way round. Decided here, by the app's and the extension's own build, not by the package's.
enum WidgetGroup {
    #if os(macOS)
    /// The Mac's group is prefixed with the signing team's id, which is what lets macOS grant it to the unsandboxed app
    /// and the sandboxed extension with no prompt and no profile (WIDGETS.md §3.5; app/Signing.xcconfig).
    static let id = "F4AMC8FYKT.com.elguindi.Tasks"
    #else
    static let id = "group.com.elguindi.Tasks"
    #endif

    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif

    /// The folder, or nil when the group's container isn't there (a build without the entitlement).
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            .map { WidgetFolder.url(in: $0, debug: isDebug) }
    }

    /// The feed the widgets draw from: `<group>/Tasks/widget-feed.json`.
    static var feedURL: URL? { folder.map(WidgetFeed.url(in:)) }

    /// The widgets' kinds.
    enum Kind {
        static let today = "com.elguindi.Tasks.today"
        /// The List widget (configurable by list).
        static let list = "com.elguindi.Tasks.list"
        /// The lock screen's Today (inline and rectangular; iPhone).
        static let todayLock = "com.elguindi.Tasks.today-lock"
        /// The lock screen's circular New Task and Today (iPhone).
        static let newTask = "com.elguindi.Tasks.new-task"
        static let todayCircle = "com.elguindi.Tasks.today-circle"
        /// The controls (Control Center, the lock screen, the Action button; iPhone).
        static let newTaskControl = "com.elguindi.Tasks.control.new-task"
        static let todayControl = "com.elguindi.Tasks.control.today"
    }
}
