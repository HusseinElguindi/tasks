import SwiftUI
import WidgetKit

/// The iPhone's widget extension (WIDGETS.md §3.1). The home-screen widgets are in widgets/Shared, shared with the Mac
/// later; what only the iPhone gets (the lock screen's widgets, the controls) is here. All read-only: they open the
/// app.
@main
struct TasksWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ListWidget()
        TodayLockWidget()
        NewTaskLockWidget()
        TodayCircleWidget()
        NewTaskControl()
        TodayControl()
    }
}
