import AppIntents
import SwiftUI
import WidgetKit

// The controls (WIDGETS.md §1.1, MVP 5): New Task and Today, for Control Center, the lock screen's two bottom buttons
// and the Action button. Each only opens the app there, through its `tasks://` link (DeepLink.swift), so they're
// buttons with the system's open-URL intent: no intent of our own and no entitlement.

struct NewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetGroup.Kind.newTaskControl) {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.new(list: nil).url)) {
                Label("New Task", systemImage: "plus.circle")
            }
        }
        .displayName("New Task")
        .description("Opens Tasks on a new task.")
    }
}

struct TodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetGroup.Kind.todayControl) {
            ControlWidgetButton(action: OpenURLIntent(DeepLink.today.url)) {
                Label("Today", systemImage: "sun.max")
            }
        }
        .displayName("Today")
        .description("Opens Today in Tasks.")
    }
}
