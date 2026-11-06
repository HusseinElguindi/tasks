import SwiftUI
import WidgetKit

/// The Mac's widget extension (design/WIDGETS.md §3.1), for the desktop and Notification Center: Today (small, medium,
/// large) and a List (medium, large, chosen in Edit Widget), from widgets/Shared, as on the iPhone. Read-only: they
/// open the app. The New Task and Today controls (Control Center, the menu bar) are the iPhone's, compiled as they are.
@main
struct TasksWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ListWidget()
        NewTaskControl()
        TodayControl()
    }
}
