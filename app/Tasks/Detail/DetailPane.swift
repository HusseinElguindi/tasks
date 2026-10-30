import SwiftUI
import TasksCore

// STUB: replaced by the detail pane build.
struct DetailPane: View {
    let store: Store
    @Bindable var window: WindowState

    var body: some View {
        Color.clear.paneChrome(focused: window.focus == .detail)
    }
}
