import SwiftUI
import TasksCore
import UIKit

// Rows whose height changes as they're typed into: a heading's name and notes, the list's notes under its title, the
// new task's or heading's row. Self-sizing invalidation is off (TaskCollection.swift), so a row is resized only here:
// each resizable row has a height signature (`TaskCollection.signatures`, read in ListScreen's body so SwiftUI
// observes what it reads); when one changes, the row is reconfigured inside Motion.layout's spring, and the rows below
// ease with it. Step 4 of the migration finishes it (the cells drawing the state they were configured with).
//
// A new line typed into notes also moves the caret down: the text view keeps it in view by scrolling the collection
// view, at once (a 17–22 pt jump, filmed). `TaskCollectionView` puts that scroll on the same spring as the row's growth.
//
// Hooks: `install`; `item` (the row being typed into, for the core's taps and keyboard); `resize`; the core's
// collection view is a `TaskCollectionView`.

@MainActor
final class CollectionEditing {
    unowned let owner: TaskCollectionController

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {
        (owner.cv as? TaskCollectionView)?.eases = { [weak self] in self?.item != nil }
    }

    /// The item being typed into on this screen: the new row, a heading's name or notes, or the header (the list's
    /// notes).
    var item: String? {
        guard let d = owner.app.draft, d.source == owner.source else { return nil }
        if d.editsListNotes { return "header" }
        if let h = d.editedHeading { return (d.editsNotes ? "n:" : "h:") + h }
        return "draft"
    }

    /// The rows, reconfigured with their new height inside an animation, so the update lays them out on its curve.
    func resize(_ keys: [String]) {
        guard let ds = owner.dataSource else { return }
        var snap = ds.snapshot()
        let shown = Set(snap.itemIdentifiers)
        let keys = keys.filter(shown.contains)
        guard !keys.isEmpty else { return }
        snap.reconfigureItems(keys)
        guard !UIAccessibility.isReduceMotionEnabled else {
            ds.apply(snap, animatingDifferences: false)
            return
        }
        // SwiftUI runs an update with no animation inside performWithoutAnimation: this one animates regardless.
        let was = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(was) }
        CATransaction.begin()
        UIView.animate(springDuration: 0.25, bounce: 0, initialSpringVelocity: 0, delay: 0,
                       options: [.overrideInheritedCurve, .overrideInheritedDuration]) {
            ds.apply(snap, animatingDifferences: true)
            // A caret that moved to a new line, kept in view on the same curve (`TaskCollectionView`).
            (self.owner.cv as? TaskCollectionView)?.scrollPending()
        }
        CATransaction.commit()
    }
}

extension TaskCollection {
    /// A signature's start while its row is being typed into (no notes or name starts so).
    static let editingMark = "\u{0}e|"

    /// What decides the height of the rows whose height can change: a heading's notes (or their editor and its text), a
    /// heading's name field, the list's notes, the new row's kind, the empty state.
    @MainActor static func signatures(_ app: AppModel, _ source: Source, _ lines: [Line]) -> [String: String] {
        let d = app.draft?.source == source ? app.draft : nil
        let typed = d?.title ?? ""
        var out: [String: String] = [:]
        if case let .list(l) = source {
            out["header"] = d?.editsListNotes == true ? editingMark + typed : (app.list(l)?.notes ?? "")
        }
        for line in lines {
            switch line {
            case let .heading(h, count, notes):
                let renaming = d?.editedHeading == h.id && d?.editsNotes == false
                out["h:" + h.id] = renaming ? editingMark : "\(h.title)|\(count)"
                if notes { out["n:" + h.id] = notesSignature(h, d, typed) }
            case let .headingNotes(h): out["n:" + h.id] = notesSignature(h, d, typed)
            case .draft: out["draft"] = d.map { "\($0.kind)" } ?? ""
            case let .empty(title, message, _): out["empty"] = title + message
            default: break
            }
        }
        return out
    }

    @MainActor private static func notesSignature(_ h: TaskModel, _ d: Draft?, _ typed: String) -> String {
        d?.editedHeading == h.id && d?.editsNotes == true ? editingMark + typed : h.notes
    }
}

/// The core's collection view. While a row is being typed into, a scroll that keeps its caret in view (a text view asks
/// its scroll view, unanimated, as a new line moves the caret down) is on Motion.layout's spring, the one the row grows
/// on (`CollectionEditing.resize`), so the list doesn't jump. It waits for the row's new height: asked for at once, the
/// caret's place is past the content's end, and the offset is cut back to it at once (a 10–21 pt jump, filmed).
final class TaskCollectionView: UICollectionView {
    /// A row on this screen is being typed into.
    var eases: () -> Bool = { false }
    private var pending: CGRect?

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        guard !animated, eases(), !UIAccessibility.isReduceMotionEnabled else {
            super.scrollRectToVisible(rect, animated: animated)
            return
        }
        // The latest ask, made with the row's resize (in its animation), or a moment later if the row doesn't resize.
        let first = pending == nil
        pending = rect
        guard first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.pending != nil else { return }
            UIView.animate(springDuration: 0.25, bounce: 0, initialSpringVelocity: 0, delay: 0,
                           options: [.overrideInheritedCurve, .overrideInheritedDuration, .beginFromCurrentState]) {
                self.scrollPending()
            }
        }
    }

    /// The caret asked for, scrolled into view now (inside the caller's animation), once the rows have their heights.
    func scrollPending() {
        guard let rect = pending else { return }
        pending = nil
        layoutIfNeeded()
        super.scrollRectToVisible(rect, animated: false)
    }
}
