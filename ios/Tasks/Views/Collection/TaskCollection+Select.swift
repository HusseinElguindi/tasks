import SwiftUI
import TasksCore
import UIKit

// Select mode (§3): the joined fill (`Picks`), the two-finger swipe (`SwipeSelect`, on this collection view), and the
// SelectBar and ⌘A / Esc, which stay in ListScreen and RootView. Step 7 of the migration.
//
// Hooks: `install` and `stop`. A cell's row reads what it needs from here through `CollectionLine.owner`.

@MainActor
final class CollectionSelect {
    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {}
    func stop() {}

    // Stand-ins for cv-select's hooks (the interface agreed through sc), so +Swipes builds before it merges.
    /// Select mode: no swipe actions.
    var blocksSwipes: Bool { owner.app.isSelecting(owner.source) }
    /// Select mode's menu for an item: nil when it isn't select's call, `.some(nil)` for none.
    func menu(for id: String) -> UIContextMenuConfiguration?? { owner.app.isSelecting(owner.source) ? .some(nil) : nil }
}
