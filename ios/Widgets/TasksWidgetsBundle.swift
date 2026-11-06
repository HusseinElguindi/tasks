import SwiftUI
import WidgetKit

/// The iPhone's widget extension (WIDGETS.md §3.1). The widgets are in widgets/Shared, shared with the Mac later; what
/// only the iPhone gets (the lock-screen accessories, the controls: pieces 5 on) goes here.
@main
struct TasksWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}
