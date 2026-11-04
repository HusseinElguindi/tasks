import SwiftUI
import TasksCore
import UIKit

// A heading folding or opening (§23): its notes and tasks slide up under its foot as they fade (150 ms ease-out), or
// back down from it (220 ms ease-in), the rows below closing up on the same curve, rigidly with them. Measured exact in
// the spike (ios-spike 25fabe4; memory uicollectionview-spike-findings), because:
// - the curves are UIKit's own: the collection view doesn't take SwiftUI's. They're critically damped springs of the
//   fold's durations (`UIView.animate(springDuration:bounce: 0)`): for a diffable apply UIKit makes springs whatever
//   curve the block asks for, and with `withDuration:` it cut its 0.5 s springs off at our duration, 82% of the way
//   (a 26–35 pt snap at a collapse's end, filmed; the cells' layer animations logged);
// - an appearing row's offset is a transform: the collection view puts a self-sizing cell's first frame back at its
//   final place;
// - the update is one CATransaction (the core's `apply`);
// - a mask at the heading's foot keeps the sliding rows from drawing above it, and headings draw over the rows;
// - a collapse near the end has slack under it, so the scroll offset isn't clamped mid-fold (it snapped 43 pt).
// Notes that come or go alone (Add Notes, notes emptied) fold from or into their heading the same way, on the draft's
// curve (Motion.layout's spring, the core's).
//
// Hooks the core calls: `plan` as items change, `prepare` and `animate` around the snapshot's apply, `didApply` when
// it has ended; `didScroll`; the layout's `decorate`, `initial` and `final`; a cell's `cellDidApply` and `reuse`.

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
    /// The headings folded as of the last update.
    private var collapsed: Set<EntityID> = []
    /// The fold being applied, the items before it, the folding rows' frames before it and their height.
    private var active: Plan?
    private var oldIDs: [String] = []
    private var oldFrames: [String: CGRect] = [:]
    private var distance: CGFloat = 0
    /// Room under the last row while a collapse near the end closes up, so the offset stays (given back as the list
    /// scrolls up).
    private(set) var slack: CGFloat = 0

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() { collapsed = owner.app.collapsed }

    /// The items under a heading's item: its notes and tasks, down to the next heading or the Completed row.
    static func section(of heading: String, in items: [String]) -> [String] {
        guard let i = items.firstIndex(of: heading) else { return [] }
        return Array(items[(i + 1)...].prefix { !$0.hasPrefix("h:") && !$0.hasPrefix("c:") })
    }

    /// The fold that turns `old` into `new`, if one does: a heading folding or opening, or a heading's notes coming
    /// or going.
    func plan(from old: [String], to new: [String]) -> Plan? {
        let was = collapsed, now = owner.app.collapsed
        collapsed = now
        guard !old.isEmpty, old != new else { return nil }
        if let h = was.symmetricDifference(now).first, new.contains("h:" + h) {
            let collapse = now.contains(h)
            let items = Set(Self.section(of: "h:" + h, in: collapse ? old : new))
            return items.isEmpty ? nil : Plan(heading: "h:" + h, items: items, collapse: collapse)
        }
        let gone = Set(old).subtracting(new), came = Set(new).subtracting(old)
        if let n = gone.union(came).first(where: { $0.hasPrefix("n:") }), new.contains("h:" + n.dropFirst(2)) {
            return Plan(heading: "h:" + n.dropFirst(2), items: [n], collapse: gone.contains(n), notesOnly: true)
        }
        return nil
    }

    /// Before the apply: the folding rows' frames and height, their masks, and the slack under a collapse.
    func prepare(_ plan: Plan?, old: [String], animated: Bool) {
        active = nil
        guard let plan, animated else { return }
        oldIDs = old
        oldFrames = [:]
        distance = 0
        let cv = owner.cv!, layout = owner.layout!
        if plan.collapse {
            for (i, id) in old.enumerated() where plan.items.contains(id) {
                guard let f = layout.modelFrame(i) else { continue }
                oldFrames[id] = f
                distance += f.height
            }
            // Scrolled near the end, the shorter list would clamp the offset at once: room under it, for now.
            let inset = cv.adjustedContentInset
            let end = cv.contentSize.height - distance + inset.bottom - cv.bounds.height
            if cv.contentOffset.y > end {
                slack += cv.contentOffset.y - end
                owner.updateBottomInset()
            }
        }
        active = plan
        // Masks at the heading's foot, before the animation, so their move animates with the cells.
        if plan.collapse, let clip = clipLine(for: plan.items.first ?? "") {
            for case let c as TaskCell in cv.subviews where plan.items.contains(c.itemID ?? "") { c.installMask(clip) }
        }
    }

    /// Runs `apply` on the fold's curve; false leaves notes alone to the core's spring.
    func animate(_ plan: Plan, _ apply: @escaping () -> Void) -> Bool {
        guard !plan.notesOnly else { return false }
        UIView.animate(springDuration: plan.collapse ? 0.15 : 0.22, bounce: 0, animations: apply)
        return true
    }

    func didApply() {
        guard active != nil else { return }
        active = nil
        oldFrames = [:]
        for case let c as TaskCell in owner.cv.subviews { c.mask = nil }
    }

    /// The slack goes as the list scrolls back up into it.
    func didScroll() {
        guard slack > 0, active == nil, let cv = owner.cv else { return }
        let inset = cv.adjustedContentInset
        let over = cv.contentOffset.y - (cv.contentSize.height + inset.bottom - slack - cv.bounds.height)
        let next = max(0, min(slack, over))
        guard next != slack else { return }
        slack = next
        owner.updateBottomInset()
    }

    // MARK: The layout's hooks

    /// Headings draw over the rows that slide under them.
    func decorate(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard a.representedElementCategory == .cell, owner.dataSource.itemIdentifier(for: a.indexPath)?.hasPrefix("h:") == true else { return a }
        let c = a.copy() as! UICollectionViewLayoutAttributes
        c.zIndex = 2
        return c
    }

    /// The heading's frame after the update.
    private func headingFrame(_ f: Plan) -> CGRect? {
        owner.dataSource.indexPath(for: f.heading).flatMap { owner.layout.base($0)?.frame }
    }

    /// The line a folding row is masked at: its heading's foot.
    func clipLine(for id: String) -> CGFloat? {
        guard let f = active, f.items.contains(id) else { return nil }
        return headingFrame(f)?.maxY
    }

    /// An opening's rows start under the heading's foot, moved up by the section's height, clear.
    func initial(at ip: IndexPath, _ a: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? {
        guard let f = active, !f.collapse, let id = owner.dataSource.itemIdentifier(for: ip), f.items.contains(id),
              let h = headingFrame(f), let end = owner.layout.base(ip) else { return a }
        let c = end.copy() as! UICollectionViewLayoutAttributes
        let bottom = f.items.compactMap { owner.dataSource.indexPath(for: $0).flatMap { owner.layout.base($0)?.frame.maxY } }.max() ?? h.maxY
        c.transform = CGAffineTransform(translationX: 0, y: -(bottom - h.maxY))
        c.alpha = 0
        c.zIndex = -1
        return c
    }

    /// A collapse's rows end moved up by the section's height, clear.
    func final(at ip: IndexPath, _ a: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? {
        guard let f = active, f.collapse, ip.item < oldIDs.count, f.items.contains(oldIDs[ip.item]),
              let start = oldFrames[oldIDs[ip.item]], let a else { return a }
        let c = a.copy() as! UICollectionViewLayoutAttributes
        c.frame = start
        c.frame.origin.y = start.minY - distance
        c.alpha = 0
        c.zIndex = -1
        return c
    }

    // MARK: Cells

    func cellDidApply(_ cell: TaskCell, _ a: UICollectionViewLayoutAttributes) {
        guard let id = cell.itemID, let clip = clipLine(for: id) else { return }
        cell.placeMask(clip, a)
    }

    func reuse(_ cell: TaskCell) { cell.mask = nil }
}

extension TaskCell {
    private static func maskRect(_ y: CGFloat, _ width: CGFloat) -> CGRect { CGRect(x: -200, y: y, width: width + 400, height: 5000) }

    /// A mask whose top is the clip line, in the cell's coordinates; set without animation.
    func installMask(_ clip: CGFloat) {
        UIView.performWithoutAnimation {
            let m = mask ?? UIView()
            m.backgroundColor = .black
            m.frame = Self.maskRect(clip - frame.minY, frame.width)
            mask = m
        }
    }

    /// The mask for the attributes the cell takes (where its top is drawn: its untransformed top, moved by its
    /// transform), animated with them when it's there already.
    func placeMask(_ clip: CGFloat, _ a: UICollectionViewLayoutAttributes) {
        let top = a.center.y - a.size.height / 2 + a.transform.ty
        if let mask {
            mask.frame = Self.maskRect(clip - top, a.frame.width)
        } else {
            UIView.performWithoutAnimation {
                let m = UIView()
                m.backgroundColor = .black
                m.frame = Self.maskRect(clip - top, a.frame.width)
                mask = m
            }
        }
    }
}
