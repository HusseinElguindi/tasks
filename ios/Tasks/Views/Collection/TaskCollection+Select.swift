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
    /// STAND-IN (cv-drag, until cv-select's +Select merges): true in select mode, where nothing lifts.
    var blocksDrag: Bool { owner.app.isSelecting(owner.source) }
}
