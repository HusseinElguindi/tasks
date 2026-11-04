import QuartzCore
import SwiftUI
import TasksCore
import UIKit

// Drag to reorder (§14, §23) and Upcoming's drag onto a day (§22), ported from the spike (ios-spike-drag 0d20941, its
// "Drag: our own gap"; memory: uicollectionview-spike-findings). Step 5 of the migration.
//
// - Our own gap. The drop delegate answers `.unspecified`, so the collection view never moves a cell itself (and never
//   consults its retarget). The dragged row is hidden in place, and the gap opens at our own slot: the rows after the
//   dragged one move up by its height, the rows from the slot on move down by it, as transforms set on the shown cells
//   (`moveGap`), on Motion.layout's spring. Never by invalidating the layout: that re-measures every hosting cell
//   (13.6 ms a move) and drops self-sized heights back to their estimates.
// - Slots (`slotTops`): never above the header, never between a heading and its notes, never past the Completed row; a
//   heading only before another heading or at the end. In Today and Undated, only in the dragged row's run
//   (`AppModel.dragRuns`: its list's group), so the gap and the copy stay in its group.
// - Our own lifted copy (`fill-lift`, radius 8, `shadow-lift`, the row's snapshot) follows the finger vertically, held
//   6 pt past the first and last slot. The system's preview is invisible once lifted. A heading's section folds into it
//   at lift (CollectionFold's collapse), and its copy shows the open count in an accent badge.
// - Upcoming: the gap opens where the drop puts it (`dropOnDay`'s rules, then list order in the day), and the day's
//   label is lit (`hover`, read by +Screens' group label).
// - A drop sets the copy down in the row's place: it flies there (240 ms, `Motion.flight`'s curve) as its lift eases
//   out, the row shows under it and the copy goes. One that's refused, or ends off the list, flies home as the finger lifts (`dropSessionDidEnd`):
//   UIKit's own set-down of a refused drop runs about a second after that, and the drag session ends only then.
// - The dragged row is hidden through its content's alpha: UIKit owns the dragged cell's own alpha (half, while it's
//   lifting or dragging), so hiding the cell left a ghost in the gap (TaskCell keeps that alpha at 1).
// - Drops write through AppModel.drop (dropOnDay in Upcoming), Reorder.swift.
//
// Hooks: `install` sets the collection view's drag and drop delegates (the controller conforms, below), `stop`;
// `holdsUpdates` (while a drag, its landing or a lifted heading is on, the core keeps the latest items in `wanted`);
// `layoutPad` (the layout reaches a row's height past a rect, for cells the gap moves into it); a cell's `configured`,
// `cellDidApply` and `reuse`.

/// The day label a drag is over in Upcoming, drawn in accent-text (+Screens' group label observes it).
@MainActor
@Observable
final class DragHover {
    var key: String?
}

@MainActor
final class CollectionDrag {
    /// A drag under way.
    struct State {
        var id: String
        /// The dragged row's height: the gap's.
        var height: CGFloat
        /// The finger's distance below the row's top at lift.
        var grab: CGFloat
        /// The slot among the other items (nil: no gap, the finger is off the list).
        var slot: Int?
        /// In Today and Undated, the items of the dragged row's run (`AppModel.dragRuns`: its list's group, the label
        /// first; the last group also has the Completed row and its done tasks). Nil elsewhere: one run.
        var run: Set<String>?
    }

    unowned let owner: TaskCollectionController
    let hover = DragHover()

    private(set) var state: State?
    /// The row lifted for a drag that hasn't begun: a long press asks for its drag items as it lifts, and may then
    /// only open the row's menu, with no drag session at all.
    private var pending: State?
    /// The dropped (or refused) row, kept hidden while the copy flies into its place.
    private var landing: String?
    /// A heading whose section is folded into its drag.
    private var lifted: String?
    private weak var dragSession: UIDragSession?
    private weak var dropSession: UIDropSession?
    private var copy: UIView?
    /// Ticks while a drag is on: the list can scroll under a still finger (the edge autoscroll), and the copy and
    /// the slot follow.
    private var link: CADisplayLink?
    /// Items whose cells the gap has moved or hidden, put back when it closes.
    private var placed: Set<String> = []

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {
        owner.cv.dragDelegate = owner
        owner.cv.dropDelegate = owner
        owner.cv.dragInteractionEnabled = true
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    var holdsUpdates: Bool { state != nil || landing != nil || lifted != nil }
    var layoutPad: CGFloat { state.map { $0.height + 8 } ?? 0 }
    private var gapOn: Bool { state != nil || landing != nil }

    // MARK: Cells

    /// A configuration can bring a new content view: a row hidden for the gap stays hidden.
    func configured(_ cell: TaskCell) { if gapOn { place(cell) } }

    /// A cell that comes into view, or is laid out again, takes its place in the gap.
    func cellDidApply(_ cell: TaskCell, _ a: UICollectionViewLayoutAttributes) {
        if gapOn, a.transform == .identity { place(cell) }
    }

    func reuse(_ cell: TaskCell) {
        cell.contentView.alpha = 1
    }

    // MARK: The gap

    /// A cell's place while a drag is on: hidden (the dragged row), or moved by `dy`.
    private func shift(_ id: String) -> (hide: Bool, dy: CGFloat)? {
        if id == landing { return (true, 0) }
        let current = owner.current
        guard let d = state, let from = current.firstIndex(of: d.id), let i = current.firstIndex(of: id) else { return nil }
        if i == from { return (true, 0) }
        let o = i > from ? i - 1 : i
        var dy: CGFloat = i > from ? -d.height : 0
        if let s = d.slot, o >= s { dy += d.height }
        return (false, dy)
    }

    /// Its place for the gap: hidden by its content (UIKit owns the dragged cell's alpha), or moved by a transform.
    private func place(_ c: TaskCell) {
        guard let id = c.itemID else { return }
        guard let s = shift(id) else {
            if placed.contains(id) {
                c.transform = .identity
                c.contentView.alpha = 1
            }
            return
        }
        placed.insert(id)
        c.transform = CGAffineTransform(translationX: 0, y: s.dy)
        c.contentView.alpha = s.hide ? 0 : 1
    }

    /// Each shown cell's transform, set directly (a cell that comes into view takes its own in `cellDidApply`).
    private func moveGap(animated: Bool) {
        let body = {
            for case let c as TaskCell in self.owner.cv.subviews where !c.isHidden {
                guard let id = c.itemID, self.owner.current.contains(id) else { continue }
                self.place(c)
            }
        }
        CATransaction.begin()
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(springDuration: 0.25, bounce: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: body)
        } else {
            UIView.performWithoutAnimation(body)
        }
        CATransaction.commit()
        if !gapOn { placed = [] }
    }

    /// The run of `id`'s row, in Today and Undated (`State.run`).
    private func run(of id: String) -> Set<String>? {
        let app = owner.app, source = owner.source
        guard source == .today || source == .undated, let runs = app.dragRuns(app.lines(source), source) else { return nil }
        return runs.lazy.map { Set(TaskCollection.items($0.lines, banner: false).ids).subtracting(["header"]) }.first { $0.contains(id) }
    }

    /// The slots the dragged row may take, with the y the gap would open at (in the list without the dragged row).
    private func slotTops(_ d: State) -> [(slot: Int, y: CGFloat)] {
        let current = owner.current
        guard let from = current.firstIndex(of: d.id) else { return [] }
        let others = current.filter { $0 != d.id }
        guard let header = others.firstIndex(of: "header") else { return [] }
        let end = others.firstIndex { $0.hasPrefix("c:") } ?? others.count
        guard end > header else { return [] }
        let heading = d.id.hasPrefix("h:")
        var out: [(Int, CGFloat)] = []
        for s in (header + 1)...end {
            // Today and Undated: only after a row of its own group (its label, the group's top, through its last row).
            if let run = d.run, !run.contains(others[s - 1]) { continue }
            if heading {
                guard s == end || others[s].hasPrefix("h:") else { continue }
            } else if s < others.count, others[s].hasPrefix("n:"), others[s - 1] == "h:" + others[s].dropFirst(2) {
                continue
            }
            if let y = slotY(d, s, others: others, from: from) { out.append((s, y)) }
        }
        return out
    }

    /// The gap's top at slot `s`: under the row before it, where the dropped row lands.
    private func slotY(_ d: State, _ s: Int, others: [String], from: Int) -> CGFloat? {
        guard s >= 1, s <= others.count, let i = owner.current.firstIndex(of: others[s - 1]), let f = owner.layout.modelFrame(i) else { return nil }
        return f.maxY - (i > from ? d.height : 0)
    }

    /// Upcoming (IX §22, the Mac's `dayTarget`): the day is the group whose label is the last one drawn above the
    /// copy's middle (above them all, the first). On a day the task may take (not a month, not past its deadline, not its own
    /// day), the gap opens where the drop puts it, by list order among that day's tasks, and the label lights;
    /// elsewhere the gap stays at its own place (the drop writes nothing and it goes back).
    private func upcomingTarget(_ d: State, _ copyTop: CGFloat) -> (slot: Int, hot: String?) {
        let app = owner.app, current = owner.current
        guard let from = current.firstIndex(of: d.id), let t = app.task(String(d.id.dropFirst(2))) else { return (0, nil) }
        let others = current.filter { $0 != d.id }
        // Where each row is drawn now: without the dragged row, and a row lower from the gap on. (The gap's own day
        // keeps its label above the gap, so the target doesn't flicker at a label: it has the gap's height of give.)
        func top(_ s: Int) -> CGFloat {
            guard let i = current.firstIndex(of: others[s]), let f = owner.layout.modelFrame(i) else { return 0 }
            return f.minY - (i > from ? d.height : 0) + (d.slot.map { s >= $0 } == true ? d.height : 0)
        }
        let mid = copyTop + d.height / 2
        let labels = others.indices.filter { others[$0].hasPrefix("g:") }
        guard let label = labels.last(where: { top($0) <= mid }) ?? labels.first else { return (from, nil) }
        let today = app.today
        guard let day = ViewGroups.upcomingDays(today: today).first(where: { "g:" + ViewGroups.upcoming($0, today: today).id == others[label] }),
              t.deadline.map({ day <= $0 }) ?? true,
              ViewGroups.upDay(when: t.when, deadline: t.deadline) != day else { return (from, nil) }
        let ranks = app.projection.activeLists.ids
        func key(_ m: TaskModel) -> ViewGroups.UpcomingKey {
            ViewGroups.UpcomingKey(id: m.id, day: day, rank: ranks.firstIndex(of: m.list) ?? 0, order: m.order)
        }
        var s = label + 1
        while s < others.count, others[s].hasPrefix("t:"), let m = app.task(String(others[s].dropFirst(2))),
              ViewGroups.upcomingPrecedes(key(m), key(t)) { s += 1 }
        return (s, others[label])
    }

    /// The copy follows the finger, held within 6 pt of the first and last slot; over the list, the gap follows the
    /// copy: the slot whose top is nearest the copy's (Upcoming: `upcomingTarget`).
    private func follow() {
        guard state != nil, let session = dragSession else { return }
        let cv = owner.cv!
        // Sizing that rows scrolled into view still owe is settled first, so the slots' tops have no holes.
        cv.layoutIfNeeded()
        guard var d = state else { return }
        let tops = slotTops(d)
        var copyTop = session.location(in: cv).y - d.grab
        if let lo = tops.map(\.y).min(), let hi = tops.map(\.y).max() { copyTop = min(max(copyTop, lo - 6), hi + 6) }
        if let v = copy, landing == nil { UIView.performWithoutAnimation { v.frame.origin.y = copyTop } }
        guard dropSession != nil else { return }
        var s = tops.min { abs($0.y - copyTop) < abs($1.y - copyTop) }?.slot
        if owner.source == .upcoming {
            let target = upcomingTarget(d, copyTop)
            s = target.slot
            if hover.key != target.hot { hover.key = target.hot }
        }
        guard s != d.slot else { return }
        d.slot = s
        state = d
        moveGap(animated: true)
    }


    // MARK: Lifting

    private func canLift(_ id: String) -> Bool {
        let app = owner.app, source = owner.source
        // Not in select mode (`CollectionSelect.blocksDrag`: one row at a time), nor while adding here, nor
        // where rows don't move (Completed, Trash, a deleted list).
        guard !owner.select.blocksDrag, app.draft?.source != source, app.dragRuns([], source) != nil else { return false }
        return owner.rows.line(id)?.canDrag == true && (id.hasPrefix("t:") || id.hasPrefix("h:"))
    }

    func itemsForBeginning(_ session: UIDragSession, at ip: IndexPath) -> [UIDragItem] {
        guard state == nil, landing == nil, let id = owner.dataSource.itemIdentifier(for: ip), canLift(id),
              let f = owner.layout.modelFrame(ip.item) else { return [] }
        let p = session.location(in: owner.cv)
        let item = UIDragItem(itemProvider: NSItemProvider())
        // The system's copy is invisible once lifted: ours is drawn instead.
        item.previewProvider = {
            let p = UIDragPreviewParameters()
            p.backgroundColor = .clear
            p.shadowPath = UIBezierPath()
            return UIDragPreview(view: UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)), parameters: p)
        }
        item.localObject = id
        session.localContext = id
        pending = State(id: id, height: f.height, grab: p.y - f.minY, slot: ip.item, run: run(of: id))
        return [item]
    }

    /// The lift: the system's lift preview, drawn as our copy is (`fill-lift`, radius 8). It shows from the lift until
    /// the finger moves, over our copy, which then takes over.
    func previewParameters(at ip: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = owner.cv.cellForItem(at: ip) else { return nil }
        let p = UIDragPreviewParameters()
        p.visiblePath = UIBezierPath(roundedRect: cell.bounds.insetBy(dx: Metric.rowInset, dy: 0), cornerRadius: Self.radius)
        p.backgroundColor = UIColor(owner.palette.lift)
        return p
    }

    /// The lifted copy's corner radius.
    private static let radius: CGFloat = 8

    func willBegin(_ session: UIDragSession) {
        guard var d = pending, d.id == session.localContext as? String, let at = owner.current.firstIndex(of: d.id) else { return }
        pending = nil
        // The rows may have changed since the lift (a menu was open meanwhile): the gap starts at its place now.
        d.slot = at
        state = d
        dragSession = session
        makeCopy(d)
        if d.id.hasPrefix("h:") {
            // A heading's section folds into it at lift (§23); the gap is the heading's own row.
            lifted = d.id
            let all = owner.current
            let items = shown(all)
            state?.slot = items.firstIndex(of: d.id)
            owner.apply(items, fold: CollectionFold.Plan(heading: d.id, items: Set(CollectionFold.section(of: d.id, in: all)), collapse: true),
                        animation: .easeOut(duration: 0.15))
        }
        // The dragged row leaves its place (the gap stays where it was).
        moveGap(animated: false)
        let link = CADisplayLink(target: Tick { [weak self] in self?.follow() }, selector: #selector(Tick.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func dragEnded() {
        pending = nil
        link?.invalidate()
        link = nil
        dragSession = nil
        // A refused drop went home at the drop session's end already; this is the fallback.
        goHome()
        unfold()
        settle()
    }

    /// The items without a lifted heading's section.
    private func shown(_ items: [String]) -> [String] {
        guard let h = lifted else { return items }
        let s = Set(CollectionFold.section(of: h, in: items))
        return items.filter { !s.contains($0) }
    }

    /// The app's items now, with their lines given to the cells: the core holds updates back while a drag is on, and
    /// the lines of rows that left (a folded section) have been dropped.
    private func latest() -> [String] {
        let app = owner.app, source = owner.source
        let made = TaskCollection.items(app.lines(source), banner: app.deletedList(source) != nil)
        owner.rows.merge(made.lines)
        return made.ids
    }

    /// A lifted heading's section opens again under it (§23), at the drop's or the cancel's end.
    private func unfold() {
        guard let h = lifted else { return }
        lifted = nil
        let items = latest()
        owner.apply(items, fold: CollectionFold.Plan(heading: h, items: Set(CollectionFold.section(of: h, in: items)), collapse: false),
                    animation: .easeIn(duration: 0.22))
    }

    /// Once nothing's held any more: what the app changed meanwhile, at once (the rows drawn are where they'll be).
    private func settle() {
        guard !holdsUpdates else { return }
        let items = latest()
        if items != owner.current { owner.apply(items, animation: nil) }
    }

    /// The drag ended with no drop (refused at the row's own place, or the finger off the list): the copy flies home
    /// as the gap there closes; the row shows under it, the copy fades; a lifted heading's section opens.
    private func goHome() {
        guard let d = state else { return }
        let home = owner.current.firstIndex(of: d.id).flatMap { owner.layout.modelFrame($0) }
        state = nil
        landing = d.id
        hover.key = nil
        moveGap(animated: true)
        land(at: home)
        unfold()
    }

    // MARK: The copy

    private func makeCopy(_ d: State) {
        let cv = owner.cv!
        guard let i = owner.current.firstIndex(of: d.id), let cell = cv.cellForItem(at: IndexPath(item: i, section: 0)),
              let snap = cell.snapshotView(afterScreenUpdates: false) else { return }
        let p = owner.palette, inset = Metric.rowInset
        let v = UIView(frame: cell.frame.insetBy(dx: inset, dy: 0))
        v.backgroundColor = UIColor(p.lift)
        v.layer.cornerRadius = Self.radius
        // `shadow-lift`: a 0.5 pt ring, and 0 8 24 (INTERACTIONS-v2, Shadows).
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor(p.shadowLiftRing).cgColor
        v.layer.shadowColor = UIColor(p.shadowLift).cgColor
        v.layer.shadowOpacity = 1
        v.layer.shadowRadius = 12
        v.layer.shadowOffset = CGSize(width: 0, height: 8)
        let clip = UIView(frame: v.bounds)
        clip.clipsToBounds = true
        clip.layer.cornerRadius = Self.radius
        snap.frame.origin = CGPoint(x: -inset, y: 0)
        clip.addSubview(snap)
        v.addSubview(clip)
        if d.id.hasPrefix("h:") {
            // A heading's open count, in an accent badge 7 pt past the copy's top-right corner.
            let app = owner.app
            let n = app.projection.section(of: String(d.id.dropFirst(2))).dropFirst().compactMap(app.task).filter { !$0.isDone }.count
            let b = UILabel()
            b.text = "\(n)"
            b.font = .systemFont(ofSize: 11, weight: .semibold)
            b.textColor = UIColor(p.onAccent)
            b.backgroundColor = UIColor(p.accent)
            b.textAlignment = .center
            b.layer.cornerRadius = 9
            b.layer.masksToBounds = true
            b.accessibilityIdentifier = "dragBadge"
            let w = max(18, b.intrinsicContentSize.width + 10)
            b.frame = CGRect(x: v.bounds.width - w + 7, y: -7, width: w, height: 18)
            v.addSubview(b)
        }
        v.layer.zPosition = 1000
        v.accessibilityIdentifier = "dragCopy"
        cv.addSubview(v)
        copy = v
    }

    /// The copy sets down at `frame` (`DragCopy.setDown`), and the row shows under it.
    private func land(at frame: CGRect?) {
        guard let v = copy else { landed(); return }
        copy = nil
        DragCopy.setDown(v, at: frame?.minY) { [weak self] in self?.landed() }
    }

    /// The landed row shows; anything held back meanwhile is applied.
    private func landed() {
        landing = nil
        moveGap(animated: false)
        settle()
    }

    // MARK: Dropping

    func canHandle(_ session: UIDropSession) -> Bool { state != nil && session.localDragSession != nil }

    func didUpdate(_ session: UIDropSession) -> UICollectionViewDropProposal {
        guard state != nil, session.localDragSession != nil else { return UICollectionViewDropProposal(operation: .forbidden) }
        dropSession = session
        follow()
        // At its own place (where it started, or a day it can't take) the drop is refused, so it goes back as a
        // cancel (a heading's performed no-move drop would still write an order).
        let own = state.map { $0.slot == owner.current.firstIndex(of: $0.id) } ?? true
        return UICollectionViewDropProposal(operation: own ? .cancel : .move, intent: .unspecified)
    }

    func didExit(_ session: UIDropSession) {
        dropSession = nil
        hover.key = nil
        if state?.slot != nil {
            state?.slot = nil
            moveGap(animated: true)
        }
    }

    func perform(_ c: UICollectionViewDropCoordinator) {
        dropSession = nil
        hover.key = nil
        let app = owner.app, source = owner.source, current = owner.current
        guard let item = c.items.first, let d = state, let src = current.firstIndex(of: d.id) else { return }
        let slot = d.slot ?? src
        let others = current.filter { $0 != d.id }
        // The drop's lines: the run's, as `.onMove` gives them per ForEach (Today and Undated: the group), or all.
        let scope = d.run.map { run in current.filter(run.contains) } ?? current
        let from = scope.firstIndex(of: d.id) ?? src
        // The slot among the scope's other items: after the same item as the gap.
        let at = d.run == nil ? slot
            : (slot >= 1 && slot <= others.count ? (scope.filter { $0 != d.id }.firstIndex(of: others[slot - 1]) ?? -1) + 1 : from)
        // `.onMove`'s offset in the items before the move: the slot among the others, as an index among them all.
        let to = at < from ? at : at + 1
        let lines = scope.map { owner.rows.line($0) ?? .edge(key: $0, height: 0) }
        if app.drop(IndexSet(integer: from), to, in: lines, source: source) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        landing = d.id
        state = nil
        let items = shown(latest())
        // The new order, at once: every row's drawn place is the same (the gap was the dropped row's place). The
        // transforms go back to none directly; the dropped row stays hidden under the copy.
        UIView.performWithoutAnimation {
            owner.apply(items, animation: nil)
            owner.cv.layoutIfNeeded()
            moveGap(animated: false)
        }
        guard let ip = owner.dataSource.indexPath(for: d.id) else { land(at: nil); return }
        c.drop(item.dragItem, toItemAt: ip)
        land(at: owner.layout.modelFrame(ip.item))
    }

    func dropEnded() {
        dropSession = nil
        // The finger lifted with no drop performed: the drop was refused, or the finger was off the list.
        goHome()
    }
}

/// A drag's lifted copy, set down (the task lists' and Home's).
@MainActor
enum DragCopy {
    /// The copy flies to `y` (240 ms, cubic-bezier(0.2, 0.8, 0.2, 1)) as its lift (the fill, the ring, the shadow)
    /// eases out on the same curve, so it arrives as the row itself. `landed` then shows the row under it, and the copy
    /// goes a frame later, with nothing left to fade. With Reduce Motion it doesn't fly: the lift fades where it lands.
    static func setDown(_ v: UIView, at y: CGFloat?, landed: @escaping () -> Void) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        let duration = reduce ? 0.15 : 0.24
        if let y, reduce { v.frame.origin.y = y }
        // The layer's shadow and ring aren't view-animatable: they ease out in CA animations on the same curve.
        let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        for (key, from, to) in [("shadowOpacity", v.layer.shadowOpacity as Any, Float(0) as Any),
                                ("borderWidth", v.layer.borderWidth as Any, CGFloat(0) as Any)] {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = duration
            a.timingFunction = curve
            v.layer.add(a, forKey: key)
        }
        v.layer.shadowOpacity = 0
        v.layer.borderWidth = 0
        let fly = UIViewPropertyAnimator(duration: duration, controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.2, y: 1)) {
            if let y, !reduce { v.frame.origin.y = y }
            v.backgroundColor = .clear
        }
        fly.addCompletion { _ in
            landed()
            DispatchQueue.main.async { v.removeFromSuperview() }
        }
        fly.startAnimation()
    }
}

/// A display link's target (it holds its target strongly, and calls an Objective-C selector).
@MainActor
private final class Tick: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}

// MARK: - The delegates

extension TaskCollectionController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_ cv: UICollectionView, itemsForBeginning session: UIDragSession, at ip: IndexPath) -> [UIDragItem] {
        drag.itemsForBeginning(session, at: ip)
    }

    func collectionView(_ cv: UICollectionView, dragPreviewParametersForItemAt ip: IndexPath) -> UIDragPreviewParameters? {
        drag.previewParameters(at: ip)
    }

    func collectionView(_ cv: UICollectionView, dragSessionWillBegin session: UIDragSession) { drag.willBegin(session) }
    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) { drag.dragEnded() }

    func collectionView(_ cv: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool { drag.canHandle(session) }

    func collectionView(_ cv: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath dest: IndexPath?) -> UICollectionViewDropProposal {
        drag.didUpdate(session)
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidExit session: UIDropSession) { drag.didExit(session) }
    func collectionView(_ cv: UICollectionView, performDropWith c: UICollectionViewDropCoordinator) { drag.perform(c) }
    func collectionView(_ cv: UICollectionView, dropSessionDidEnd session: UIDropSession) { drag.dropEnded() }
}
