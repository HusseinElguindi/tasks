import SwiftUI
import TasksCore
import UIKit

// A heading folding or opening (§23): its notes and tasks slide up under its foot as they fade (150 ms ease-out), or
// back down (220 ms ease-in), the rows below closing up on the same curve. Step 2 of the migration.
//
// Hooks the core calls: `plan` as items change, `prepare` and `animate` around the snapshot's apply, `didApply` when
// it has ended; `slack` and `didScroll`; the layout's `decorate`, `initial` and `final`; a cell's `cellDidApply` and `reuse`.

@MainActor
final class CollectionFold {
    /// A fold: the heading's item, the items that go or come with it.
    struct Plan {
        var heading: String
        var items: Set<String>
        var collapse: Bool
        /// Only notes come or go (Add Notes, notes emptied): on the draft's curve, not the fold's.
        var notesOnly = false
    }

    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {}

    /// The fold that turns `old` into `new`, if one does.
    func plan(from old: [String], to new: [String]) -> Plan? { nil }

    /// Before the apply: the fold's distances and masks.
    func prepare(_ plan: Plan?, old: [String], animated: Bool) {}

    /// Runs `apply` on the fold's own curve; false leaves it to the core's spring.
    func animate(_ plan: Plan, _ apply: @escaping () -> Void) -> Bool { false }

    func didApply() {}

    /// Room under the last row while a collapse near the end closes up (the core adds it to the bottom inset).
    var slack: CGFloat { 0 }
    func didScroll() {}

    func decorate(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes { a }
    func initial(at ip: IndexPath, _ a: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? { a }
    func final(at ip: IndexPath, _ a: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? { a }
    func cellDidApply(_ cell: TaskCell, _ a: UICollectionViewLayoutAttributes) {}
    func reuse(_ cell: TaskCell) {}
}
