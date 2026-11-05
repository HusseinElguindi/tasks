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
// - a collapse near the end has slack under it, so the scroll offset isn't clamped mid-fold (it snapped 43 pt);
// - one fold at a time: an update that comes while a fold is still under way (the chevron tapped twice, a heading let
//   go right after its drag began and folded its section) ends that fold at its end state first (`end`), and only
//   the latest fold's completion cleans up. (Two at once, the first's end took the second's masks and pad mid-way:
//   rows drawn over the heading and each other, a heading gone for 200 ms, T27, filmed.)
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
    /// The fold under way (`animate`): its number, its collapse's pictures and the opening rows it masks.
    private var running: (count: Int, ghost: UIView?, masked: [TaskCell])?
    private var folds = 0

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() { collapsed = owner.app.collapsed }

    #if DEBUG || PERF_PROBE
    private let probe = FoldProbe()
    #endif

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
        end()
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
        // Notes alone fold on the core's update: masks at the heading's foot, before the animation, so their move
        // animates with the cells.
        if plan.notesOnly, plan.collapse, let clip = clipLine(for: plan.items.first ?? "") {
            for case let c as TaskCell in cv.subviews where plan.items.contains(c.itemID ?? "") { c.installMask(clip) }
        }
    }

    /// A fold still under way ends now, at its end state (another update has come): its pictures go, its rows stop
    /// where they're going (their animations removed: their model values are the end's), its masks and pad go. Its
    /// own completion, when it comes, does nothing (`animate`).
    private func end() {
        guard let r = running else { return }
        running = nil
        r.ghost?.removeFromSuperview()
        for case let c as TaskCell in owner.cv.subviews {
            c.layer.removeAllAnimations()
            c.contentView.layer.removeAllAnimations()
        }
        for c in r.masked { c.mask = nil }
        layoutPad = 0
    }

    /// How far past the visible rows the layout makes cells while a fold moves them (rows an opening pushes out of
    /// view slide out rather than vanish).
    private(set) var layoutPad: CGFloat = 0

    /// Applies `snap` and runs the fold on §23's curves; false leaves notes alone to the core's spring.
    ///
    /// The collection view's own update can't take these curves (for a diffable apply UIKit makes springs whatever the
    /// block asks for; cut off at our duration they snapped 26–35 pt at a collapse's end, run to their end they
    /// lingered and opened 55 ms early, filmed). So the snapshot is applied at once, and the rows are moved by plain
    /// view animations, which keep their curves, as the drag gap's are: each row that stays starts where it was
    /// (a transform) and goes to its place; an opening's rows start under the heading's foot, masked there, clear;
    /// a collapse's rows go up under it as pictures, in a clip at the foot, behind the rows.
    func animate(_ plan: Plan, _ snap: NSDiffableDataSourceSnapshot<Int, String>, done: @escaping () -> Void) -> Bool {
        guard !plan.notesOnly else { return false }
        let cv = owner.cv!, layout = owner.layout!, ds = owner.dataSource!
        #if DEBUG || PERF_PROBE
        probe.watch(cv)
        #endif
        let collapse = plan.collapse
        // Every row's top before, and the heading's foot (it doesn't move).
        var before: [String: CGFloat] = [:]
        for (i, id) in oldIDs.enumerated() { if let f = layout.modelFrame(i) { before[id] = f.minY } }
        guard let h = oldIDs.firstIndex(of: plan.heading).flatMap({ layout.modelFrame($0) }) else { return false }
        let foot = h.maxY
        var ghost: UIView?
        if collapse {
            let clip = UIView(frame: CGRect(x: 0, y: foot, width: cv.bounds.width, height: max(1, cv.contentSize.height + cv.bounds.height)))
            clip.clipsToBounds = true
            clip.isUserInteractionEnabled = false
            clip.accessibilityElementsHidden = true
            for case let c as TaskCell in cv.subviews where plan.items.contains(c.itemID ?? "") && !c.isHidden {
                guard let pic = c.snapshotView(afterScreenUpdates: false) else { continue }
                pic.frame = c.frame.offsetBy(dx: 0, dy: -foot)
                clip.addSubview(pic)
            }
            cv.insertSubview(clip, at: 0)
            ghost = clip
        }
        layoutPad = distance
        UIView.performWithoutAnimation {
            ds.apply(snap, animatingDifferences: false)
            cv.layoutIfNeeded()
        }
        // The opening's height, once laid out.
        var height = distance
        if !collapse {
            let bottom = plan.items.compactMap { ds.indexPath(for: $0).flatMap { layout.modelFrame($0.item)?.maxY } }.max() ?? foot
            height = bottom - foot
            layoutPad = height
            cv.layoutIfNeeded()
        }
        var appearing: [(cell: TaskCell, top: CGFloat)] = []
        UIView.performWithoutAnimation {
            for case let c as TaskCell in cv.subviews {
                guard let id = c.itemID, let ip = ds.indexPath(for: id), let f = layout.modelFrame(ip.item) else { continue }
                if !collapse, plan.items.contains(id) {
                    c.transform = CGAffineTransform(translationX: 0, y: -height)
                    c.contentView.alpha = 0
                    c.installMask(foot, top: f.minY - height)
                    appearing.append((c, f.minY))
                } else if let y0 = before[id], y0 != f.minY {
                    c.transform = CGAffineTransform(translationX: 0, y: y0 - f.minY)
                }
            }
        }
        folds += 1
        let n = folds
        running = (n, ghost, appearing.map(\.cell))
        // Only this fold's own end, if no update has ended it first (`end`).
        let finish: () -> Void = { [weak self] in
            guard let self, self.running?.count == n else { return }
            self.running = nil
            ghost?.removeFromSuperview()
            for a in appearing { a.cell.mask = nil }
            self.layoutPad = 0
            done()
        }
        UIView.animate(withDuration: collapse ? 0.15 : 0.22, delay: 0,
                       options: [collapse ? .curveEaseOut : .curveEaseIn, .allowUserInteraction, .overrideInheritedCurve, .overrideInheritedDuration]) {
            for case let c as TaskCell in cv.subviews { c.transform = .identity }
            for a in appearing {
                a.cell.contentView.alpha = 1
                a.cell.mask?.frame.origin.y = foot - a.top
            }
            ghost?.subviews.forEach { $0.frame.origin.y -= self.distance; $0.alpha = 0 }
        } completion: { _ in finish() }
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

    /// The line a folding row is masked at: its heading's foot (notes alone, on the core's update; a fold's own masks
    /// move with its animation).
    func clipLine(for id: String) -> CGFloat? {
        guard let f = active, f.notesOnly, f.items.contains(id) else { return nil }
        return headingFrame(f)?.maxY
    }

    /// An opening's rows start under the heading's foot, moved up by the section's height, clear.
    func initial(at ip: IndexPath, _ a: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? {
        guard let f = active, f.notesOnly, !f.collapse, let id = owner.dataSource.itemIdentifier(for: ip), f.items.contains(id),
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
        guard let f = active, f.notesOnly, f.collapse, ip.item < oldIDs.count, f.items.contains(oldIDs[ip.item]),
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
    func installMask(_ clip: CGFloat) { installMask(clip, top: frame.minY) }

    /// A mask whose top is the clip line, for a cell whose top is drawn at `top`; set without animation.
    func installMask(_ clip: CGFloat, top: CGFloat) {
        UIView.performWithoutAnimation {
            let m = mask ?? UIView()
            m.backgroundColor = .black
            m.frame = Self.maskRect(clip - top, bounds.width)
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

#if DEBUG || PERF_PROBE
/// Debug builds and the phone's measuring build only (`-dragProbe YES`, FlowTests). From each fold's start to 0.4 s
/// after the latest, every frame: the most that two things drawn in the list overlap, in points: the rows (their drawn
/// frames, cut by their masks; a row drawn clear doesn't count) and a collapse's pictures (cut by their clip). The
/// drag probe publishes it as `fo` (the worst since launch). A fold drawn right moves rows rigidly, so it's 0.
@MainActor
final class FoldProbe {
    private static let on = UserDefaults.standard.bool(forKey: "dragProbe")
    private weak var cv: UICollectionView?
    private var link: CADisplayLink?
    private var until: CFTimeInterval = 0

    func watch(_ cv: UICollectionView) {
        guard Self.on else { return }
        self.cv = cv
        until = CACurrentMediaTime() + 0.4
        guard link == nil else { return }
        let l = CADisplayLink(target: Tick { [weak self] in self?.frame() }, selector: #selector(Tick.fire))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func frame() {
        guard let cv, CACurrentMediaTime() < until else {
            link?.invalidate()
            link = nil
            return
        }
        var spans: [(top: CGFloat, bottom: CGFloat)] = []
        func add(_ top: CGFloat, _ bottom: CGFloat) { if bottom - top > 1 { spans.append((top, bottom)) } }
        for v in cv.subviews where !v.isHidden {
            let p = v.layer.presentation() ?? v.layer
            guard p.opacity > 0.05 else { continue }
            if let c = v as? TaskCell {
                guard (c.contentView.layer.presentation() ?? c.contentView.layer).opacity > 0.05 else { continue }
                var top = p.frame.minY, bottom = p.frame.maxY
                if let m = c.mask {
                    let mf = (m.layer.presentation() ?? m.layer).frame
                    top = max(top, p.frame.minY + mf.minY)
                    bottom = min(bottom, p.frame.minY + mf.maxY)
                }
                add(top, bottom)
            } else if v.clipsToBounds, v.accessibilityElementsHidden {
                // A collapse's pictures, in their clip at the heading's foot.
                for pic in v.subviews {
                    let q = pic.layer.presentation() ?? pic.layer
                    guard q.opacity > 0.05 else { continue }
                    add(max(p.frame.minY, p.frame.minY + q.frame.minY), min(p.frame.maxY, p.frame.minY + q.frame.maxY))
                }
            }
        }
        spans.sort { $0.top < $1.top }
        var worst: CGFloat = 0, reach = -CGFloat.infinity
        for s in spans {
            worst = max(worst, reach - s.top)
            reach = max(reach, s.bottom)
        }
        if worst > DragProbe.shared.foldOverlap { DragProbe.shared.foldOverlap = worst }
    }
}
#endif
