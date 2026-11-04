import SwiftUI
import TasksCore
import UIKit

// Drag to reorder (§14, §23) and Upcoming's drag onto a day (§22): our own gap (drop intent `.unspecified`, transforms
// on the other cells), our own lifted copy held to the slots, Today's and Undated's per-run clamp, a heading's fold into
// its copy with the count badge. Drops write through AppModel.drop / dropOnDay. Step 5 of the migration.
//
// Hooks: `install` (set the collection view's drag and drop delegates; the controller conforms in an extension in this
// file), `stop`; `holdsUpdates` (true while a drag is on: the core keeps the latest items in `wanted` and doesn't
// apply them); `layoutPad` (how far outside a rect the layout reaches for cells a gap moves in); a cell's `configured`,
// `cellDidApply` and `reuse`.

@MainActor
final class CollectionDrag {
    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {}
    func stop() {}

    var holdsUpdates: Bool { false }
    var layoutPad: CGFloat { 0 }

    func configured(_ cell: TaskCell) {}
    func cellDidApply(_ cell: TaskCell, _ a: UICollectionViewLayoutAttributes) {}
    func reuse(_ cell: TaskCell) {}
}
