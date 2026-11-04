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

// A stand-in until the menus land: only select mode's (CollectionSelect.menu). The menus area's own method replaces it,
// with the same first line.
extension TaskCollectionController {
    func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard ips.count == 1, let id = dataSource.itemIdentifier(for: ips[0]) else { return nil }
        if let m = select.menu(for: id) { return m }
        return nil
    }
}
