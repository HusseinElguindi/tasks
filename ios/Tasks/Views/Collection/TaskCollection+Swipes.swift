import SwiftUI
import TasksCore
import UIKit

// Swipe actions (TaskSwipes on the List path: Complete, When and Delete; Put Back in Trash; a deleted list's Restore)
// and long-press menus (HeadingMenu, TaskMenu, the deleted list's, the selection's). Step 3 of the migration.
//
// Hooks: `actions` is the list layout's swipe provider, both edges. Menus go in an extension of
// TaskCollectionController in this file: `collectionView(_:contextMenuConfigurationForItemsAt:point:)` and its
// preview and dismissal delegate methods (the controller is the collection view's delegate).

@MainActor
final class CollectionSwipes {
    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {}

    /// The swipe actions for the item at `ip`, on its leading or trailing edge; nil for none.
    func actions(_ ip: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? { nil }
}
