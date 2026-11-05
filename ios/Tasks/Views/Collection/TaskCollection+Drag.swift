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
// - Our own lifted copy (`fill-lift`, the row's radius 12 with continuous corners, `shadow-lift`, the row's snapshot)
//   follows the finger in x and y, keeping the grab offset, as the Mac's does; only its y is held, 6 pt past the first
//   and last slot (the Mac's rule inside a group), and the slot is chosen by y alone. It lifts at the hold, as UIKit
//   lifts (the drag items asked), on the row's exact frame (`lift`); if no drag follows (the row's menu opens, or UIKit
//   puts the lift down: the cell's drag state back to none) it goes again (`holdEnded`). Nothing of UIKit's shows,
//   from the hold on: its lift preview and drag preview draw nothing (a lift preview of the row was shrunk by UIKit,
//   as the drag began, into the drag preview at the finger: a second copy sliding there). The hold itself (0.41 s to
//   the lift, 0.82 s to the menu) is UIKit's: its click-presentation driver, shared with the menu, has no public
//   setting. A heading's section folds into the copy as the drag begins (CollectionFold's collapse), and its copy
//   shows the open count in an accent badge.
// - Haptics (`DragFeel`): UIKit's own at the lift (none of ours), a selection tick each time the gap moves to a new
//   slot (in Upcoming also when another day lights), the light impact of a drop that writes.
// - Upcoming: the gap opens where the drop puts it (`dropOnDay`'s rules, then list order in the day), and the day's
//   label is lit (`hover`, read by +Screens' group label).
// - A drop sets the copy down as the Mac's does (`DragCopy.setDown`): lift and all, it flies into the row's exact frame
//   (160 ms, `Motion.flight`'s curve), the row shows under it in that frame, and the copy fades out over it (150 ms
//   ease-out). UIKit's own drop animation is made invisible (`DragCopy.invisibleDrop`): `drop(_:toItemAt:)` grew a
//   picture of the destination cell (the hidden row: only the preview's fill) from the finger out to the row, over our
//   copy, which read as a fade outwards from the centre. One that's refused (let go at its own slot) flies home the same
//   way as the finger lifts (`dropSessionDidEnd`); let go anywhere else (over the floating bar, or off the list), it
//   drops at the last slot shown, as on the Mac (§14: "as in a Mac list"): UIKit's own set-down of a refused drop runs about a second after
//   that (its cancel preview is invisible too), and the drag session ends only then.
// - A fast flick: UIKit's lift starts a drag session only 0.2-0.4 s later, and a finger let go in between ends
//   it with no drop. Let go within about 0.13 s of the lift's start, UIKit never begins it (no call at all: the row
//   stays, nothing to do). Later, it begins, then either ends with no drop session ever reaching the list (asking
//   first for its set-down's preview, or not), or reaches the list and then doesn't perform a `.move` it was given.
//   Its session knows where the finger lifted, so the drop at that slot is ours (`letGo`, `dropEnded`), set down the
//   same way: at once, not after UIKit's second-long set-down. The gap follows the copy wherever the finger is.
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
        /// The finger's offset from the row's top-left corner at lift (the copy keeps it, in x and y).
        var grab: CGPoint
        /// The slot among the other items (nil: none to take).
        var slot: Int?
        /// The last slot the gap was open at: a new one ticks.
        var ticked: Int?
        /// A drop session has reached the list. Before that, UIKit asking for its set-down means the finger has lifted
        /// (a fast flick let go before UIKit's first hit test), and the drop is ours (`letGo`).
        var entered = false
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
    /// The row whose copy was lifted at the hold, before any drag has begun (`lift`).
    private var heldCopy: String?
    private let feel = DragFeel()
    private var catchUp = DragCatchUp()
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
        feel.end()
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
        let t0 = Perf.begin(.moveGap)
        defer { Perf.end(.moveGap, t0) }
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

    /// The copy follows the finger in x and y, keeping the grab offset; its y is held within 6 pt of the first and
    /// last slot (the Mac's rule in a group; x is free, as the Mac's pointer is). Over the list, the gap follows the
    /// copy's y: the slot whose top is nearest the copy's (Upcoming: `upcomingTarget`). Each new slot, or newly lit
    /// day, ticks.
    private func follow() {
        guard state != nil, let session = dragSession else { return }
        let t0 = Perf.begin(.follow)
        defer { Perf.end(.follow, t0) }
        let cv = owner.cv!
        // Sizing that rows scrolled into view still owe is settled first, so the slots' tops have no holes.
        Perf.measure(.layout) { cv.layoutIfNeeded() }
        guard var d = state else { return }
        let tops = slotTops(d)
        let finger = session.location(in: cv)
        var copyTop = finger.y - d.grab.y
        if let lo = tops.map(\.y).min(), let hi = tops.map(\.y).max() { copyTop = min(max(copyTop, lo - 6), hi + 6) }
        if let v = copy, landing == nil {
            // As a drag begins, the copy glides to the finger (DragCatchUp). The gap follows the finger's place, not the
            // glide: a flick let go during it drops where the finger let go.
            let p = catchUp.place(CGPoint(x: finger.x - d.grab.x + Metric.rowInset, y: copyTop), from: v.frame.origin)
            UIView.performWithoutAnimation { v.frame.origin = p }
        }
        // Wherever the finger is (over the floating bar at the bottom, or off the list), the gap stays at the slot
        // nearest the copy, held to the list: letting go drops at the last slot shown (INTERACTIONS §14, "as in a Mac
        // list"). A flick down ended over the bar, where the drop session exits: closing the gap sent the row home.
        var s = tops.min { abs($0.y - copyTop) < abs($1.y - copyTop) }?.slot
        var lit = false
        if owner.source == .upcoming {
            let target = upcomingTarget(d, copyTop)
            s = target.slot
            if hover.key != target.hot {
                hover.key = target.hot
                lit = target.hot != nil
            }
        }
        if let s, s != d.ticked {
            d.ticked = s
            state = d
            feel.moved()
        } else if lit {
            feel.moved()
        }
        guard s != d.slot else { return }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.slot(s, was: d.slot, copyTop: copyTop)
        #endif
        d.slot = s
        state = d
        moveGap(animated: true)
    }


    /// The gap is at a new place: a drop there writes.
    private func moves(_ d: State) -> Bool {
        guard let s = d.slot, let i = owner.current.firstIndex(of: d.id) else { return false }
        return s != i
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
        pending = State(id: id, height: f.height, grab: CGPoint(x: p.x - f.minX, y: p.y - f.minY), slot: ip.item, run: run(of: id))
        lift(pending!)
        return [item]
    }

    /// The hold: our copy lifts in place, on the row's exact frame, as UIKit lifts (its own lift preview is
    /// invisible, `previewParameters`), and follows the finger from there once the drag begins. With no drag
    /// after it, it goes again (`holdEnded`).
    private func lift(_ d: State) {
        dropHeld(fade: false)
        makeCopy(d)
        if copy != nil { heldCopy = d.id }
        #if DEBUG || PERF_PROBE
        if let v = copy, let ip = owner.dataSource.indexPath(for: d.id), let cell = owner.cv.cellForItem(at: ip) {
            DragProbe.shared.held(v, on: cell)
        }
        #endif
    }

    /// The hold ended with no drag: the row's menu opened (its own preview rises over the copy as it fades), or UIKit
    /// put the lift down. The copy fades where it is, over the row (150 ms): removed at once, the row showed bare for a
    /// frame or two before the menu's preview. A drag from the open menu lifts a copy again (`willBegin`).
    func holdEnded(menu: Bool) {
        guard state == nil, dragSession == nil, heldCopy != nil else { return }
        dropHeld(fade: true, menu: menu)
    }

    private func dropHeld(fade: Bool, menu: Bool = false) {
        guard heldCopy != nil, let v = copy else { heldCopy = nil; return }
        heldCopy = nil
        copy = nil
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call(menu ? "holdMenu" : fade ? "holdDown" : "holdDrop", in: owner.cv)
        #endif
        if fade { DragCopy.setDown(v, at: nil) {} } else { v.removeFromSuperview() }
    }

    /// UIKit's drag state of a row's cell (`TaskCell.dragStateDidChange`): back to none with no drag begun, the hold is
    /// over.
    func cellDragState(_ cell: TaskCell, _ s: UICollectionViewCell.DragState) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("cell-\(s == .none ? "none" : s == .lifting ? "lifting" : "dragging")", in: owner.cv)
        #endif
        if s == .none, cell.itemID == heldCopy { holdEnded(menu: false) }
    }

    /// UIKit's lift preview draws nothing: our copy lifts instead (`lift`). A lift preview of the row, drawn as our copy
    /// is, was UIKit's own picture: at the drag's start UIKit shrank it, over 0.4 s, into the drag preview (ours, a
    /// clear point at the finger), a second copy of the row sliding to the finger. Once the drag is on, UIKit asks again
    /// for its cancel (a refused drop's set-down): nothing it draws then shows either, our copy has gone home.
    func previewParameters(at ip: IndexPath) -> UIDragPreviewParameters? {
        if dragSession != nil, state?.entered == false {
            // Asked for its set-down before any drop session reached the list: the finger has lifted (a flick let go
            // before UIKit's first hit test), and UIKit's session ends only after its set-down, a second on.
            DispatchQueue.main.async { [weak self] in self?.letGo() }
        }
        return DragCopy.invisibleParameters
    }

    func willBegin(_ session: UIDragSession) {
        guard var d = pending, d.id == session.localContext as? String, let at = owner.current.firstIndex(of: d.id) else { return }
        pending = nil
        // The rows may have changed since the lift (a menu was open meanwhile): the gap starts at its place now.
        d.slot = at
        d.ticked = at
        state = d
        dragSession = session
        // The lift's haptic is UIKit's; the ticks and the drop's are ours, ready from here.
        feel.begin(in: owner.cv)
        catchUp.begin()
        #if DEBUG || PERF_PROBE
        DragProbe.shared.session = session
        DragProbe.shared.mark("willBegin start", in: owner.cv)
        #endif
        // The copy lifted at the hold, or (a drag from the row's open menu) a new one.
        if heldCopy != d.id || copy == nil { dropHeld(fade: false); makeCopy(d) }
        heldCopy = nil
        if d.id.hasPrefix("h:") {
            // A heading's section folds into it at lift (§23); the gap is the heading's own row.
            lifted = d.id
            let all = owner.current
            let items = shown(all)
            let slot = items.firstIndex(of: d.id)
            state?.slot = slot
            state?.ticked = slot
            owner.apply(items, fold: CollectionFold.Plan(heading: d.id, items: Set(CollectionFold.section(of: d.id, in: all)), collapse: true),
                        animation: .easeOut(duration: 0.15))
        }
        // The dragged row leaves its place (the gap stays where it was).
        moveGap(animated: false)
        let link = CADisplayLink(target: Tick { [weak self] in self?.follow() }, selector: #selector(Tick.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
        #if DEBUG || PERF_PROBE
        DragProbe.shared.mark("willBegin end", in: owner.cv)
        #endif
    }

    /// The finger lifted with no drop session ever reaching the list (a fast flick, let go before UIKit's first hit
    /// test; UIKit's session knows where): the drop at the finger's slot is ours, or it goes home, at once.
    private func letGo() {
        guard dragSession != nil, let d = state, !d.entered else { return }
        // At the finger, where it let go.
        catchUp.end()
        follow()
        if let d = state, moves(d) { drop(d) } else { goHome() }
    }

    func dragEnded() {
        pending = nil
        // A flick UIKit ended without asking for a set-down first.
        letGo()
        link?.invalidate()
        link = nil
        dragSession = nil
        feel.end()
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

    /// The drag ended with no drop (refused: let go at the row's own place): the copy flies home
    /// as the gap there closes, and sets down there as a drop does; a lifted heading's section opens.
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
        DragCopy.round(v.layer)
        // `shadow-lift`: a 0.5 pt ring, and 0 8 24 (INTERACTIONS-v2, Shadows), cast by the copy's own shape.
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor(p.shadowLiftRing).cgColor
        v.layer.shadowColor = UIColor(p.shadowLift).cgColor
        v.layer.shadowOpacity = 1
        v.layer.shadowRadius = 12
        v.layer.shadowOffset = CGSize(width: 0, height: 8)
        v.layer.shadowPath = DragCopy.shape(v.bounds).cgPath
        let clip = UIView(frame: v.bounds)
        clip.clipsToBounds = true
        DragCopy.round(clip.layer)
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
        #if DEBUG || PERF_PROBE
        let id = d.id
        DragProbe.shared.trace(copy: v) { [weak self] in
            guard let self, let ip = self.owner.dataSource.indexPath(for: id) else { return nil }
            return self.owner.cv.cellForItem(at: ip)
        }
        #endif
    }

    /// The copy sets down on the row's `frame` (`DragCopy.setDown`), and the row shows under it.
    private func land(at frame: CGRect?) {
        guard let v = copy else { landed(); return }
        copy = nil
        let origin = frame.map { CGPoint(x: $0.minX + Metric.rowInset, y: $0.minY) }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.released(v, home: origin)
        #endif
        DragCopy.setDown(v, at: origin) { [weak self] in
            #if DEBUG || PERF_PROBE
            if let self, let id = self.landing, let ip = self.owner.dataSource.indexPath(for: id) {
                DragProbe.shared.landed(v, on: self.owner.cv.cellForItem(at: ip))
            }
            #endif
            self?.landed()
        }
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
        let t0 = Perf.begin(.update)
        defer { Perf.end(.update, t0) }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.updated()
        #endif
        dropSession = session
        state?.entered = true
        follow()
        // At its own place (where it started, or a day it can't take) the drop is refused, so it goes back as a
        // cancel (a heading's performed no-move drop would still write an order).
        return UICollectionViewDropProposal(operation: state.map(moves) == true ? .move : .cancel, intent: .unspecified)
    }

    /// The finger left the list's drop area (over the floating bar, or off the list): the gap stays at the last slot
    /// shown, and follows the copy still (`follow`).
    func didExit(_ session: UIDropSession) {
        dropSession = nil
    }

    func perform(_ c: UICollectionViewDropCoordinator) {
        guard let item = c.items.first, let d = state, owner.current.contains(d.id) else { return }
        let f = write(d)
        // UIKit's drop goes nowhere to be seen: our copy sets down instead.
        _ = c.drop(item.dragItem, to: DragCopy.invisibleDrop(at: f.map { CGPoint(x: $0.midX, y: $0.midY) } ?? copy?.center ?? .zero, in: owner.cv))
        land(at: f)
    }

    /// A drop UIKit didn't perform, though the finger lifted over a new slot: ours, set down the same way.
    private func drop(_ d: State) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("ourDrop", in: owner.cv)
        #endif
        let f = write(d)
        land(at: f)
    }

    /// The drop at the gap: written (AppModel.drop: dropOnDay in Upcoming), and the new order applied at once, the
    /// dropped row hidden under the copy. Its frame, where the copy sets down (nil: it has gone).
    private func write(_ d: State) -> CGRect? {
        dropSession = nil
        hover.key = nil
        let app = owner.app, source = owner.source, current = owner.current
        guard let src = current.firstIndex(of: d.id) else {
            state = nil
            return nil
        }
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
        if app.drop(IndexSet(integer: from), to, in: lines, source: source) { feel.dropped() }
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
        guard let ip = owner.dataSource.indexPath(for: d.id) else { return nil }
        return owner.layout.modelFrame(ip.item)
    }

    func dropEnded() {
        dropSession = nil
        // The finger lifted with no drop performed. Over a new slot, UIKit didn't get to it (a flick let go as its drop
        // session began): the drop is ours. Otherwise it was refused (let go at its own slot): home.
        if let d = state, moves(d) { drop(d) } else { goHome() }
    }
}

/// A drag's lifted copy, set down (the task lists' and Home's).
@MainActor
enum DragCopy {
    /// The Mac's set-down (INTERACTIONS-v2 §14 "Drop on the list", its DragOverlayView `flyCopy` then `settleCopy`):
    /// the copy, lift and all (fill, ring, shadow), flies to `origin`, the row's own top-left, in x and y (160 ms,
    /// cubic-bezier(0.2, 0.8, 0.2, 1)). There `landed` shows the row under it, in the same transaction, and the copy
    /// fades out over it (150 ms ease-out), so the lift dissolves into the row: the row's pixels never move or fade.
    /// With no origin (the row has gone), or with Reduce Motion, it doesn't fly: it fades where it is (at the origin).
    static func setDown(_ v: UIView, at origin: CGPoint?, landed: @escaping () -> Void) {
        let settle = {
            CATransaction.begin()
            landed()
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                v.alpha = 0
            } completion: { _ in v.removeFromSuperview() }
            CATransaction.commit()
        }
        guard let origin, !UIAccessibility.isReduceMotionEnabled else {
            if let origin { v.frame.origin = origin }
            settle()
            return
        }
        let fly = UIViewPropertyAnimator(duration: 0.16, controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.2, y: 1)) {
            v.frame.origin = origin
        }
        fly.addCompletion { _ in settle() }
        fly.startAnimation()
    }

    /// The lifted row's shape (the copy, its clip and shadow, the lift preview): the row's tapped fill, radius 12 with
    /// continuous corners (TaskRow's `RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous)`). The path
    /// is UIKit's rounded rect, which is drawn with continuous corners itself.
    static func shape(_ r: CGRect) -> UIBezierPath { UIBezierPath(roundedRect: r, cornerRadius: Metric.rowRadius) }

    /// A layer rounded as the row's fill.
    static func round(_ l: CALayer) {
        l.cornerRadius = Metric.rowRadius
        l.cornerCurve = .continuous
    }

    /// Preview parameters that draw nothing: a clear fill and no shadow, in a point.
    static var invisibleParameters: UIDragPreviewParameters {
        let p = UIDragPreviewParameters()
        p.backgroundColor = .clear
        p.shadowPath = UIBezierPath()
        p.visiblePath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        return p
    }

    /// UIKit's drop animation, made to draw nothing: the drag's own preview (ours is a clear point, `itemsForBeginning`)
    /// goes to `center`. `drop(_:toItemAt:)` instead animates a picture of the destination cell, made with the drag's
    /// preview parameters, from the finger out to the cell, above the app's own views: with the row hidden under our
    /// copy, that was the preview's fill growing from the finger outwards, over the copy setting down.
    static func invisibleDrop(at center: CGPoint, in container: UIView) -> UIDragPreviewTarget {
        UIDragPreviewTarget(container: container, center: center)
    }
}

/// The copy's way to the finger as a drag begins (the task lists' and Home's). From the lift until UIKit's drag session
/// begins (about 0.3 s, UIKit's), the copy waits where it lifted while the finger has gone on (UIKit takes the touch
/// after 10-16 pt): followed at once, it jumped 35-77 pt in one frame (T22, measured), which read as a stutter over the
/// first rows. It glides there instead: the copy's distance from the finger's place, at the drag's first follow,
/// fades out over 0.15 s (ease-out), while it follows the finger's moves exactly. Its clock counts at most a frame
/// (1/60 s) between follows, so UIKit's long frames as its drag begins (40-130 ms) don't skip the glide. Not with
/// Reduce Motion.
struct DragCatchUp {
    static let duration: CFTimeInterval = 0.15
    private var on = false
    /// The glide's time so far, and the last follow's.
    private var elapsed: CFTimeInterval = -1
    private var last: CFTimeInterval = 0
    private var offset: CGPoint = .zero

    mutating func begin() { on = true; elapsed = -1 }
    mutating func end() { on = false }

    /// Where the copy is drawn, for the origin `want` the finger asks for, from where it is (`now`).
    @MainActor mutating func place(_ want: CGPoint, from now: CGPoint) -> CGPoint {
        guard on, !UIAccessibility.isReduceMotionEnabled else { return want }
        let t = CACurrentMediaTime()
        if elapsed < 0 {
            elapsed = 0
            offset = CGPoint(x: now.x - want.x, y: now.y - want.y)
        } else {
            elapsed += min(t - last, 1.0 / 60)
        }
        last = t
        let x = elapsed / Self.duration
        guard x < 1 else { on = false; return want }
        // The first follow is drawn where it is (x 0), the next ones closer: (1 - x)^3 of the distance left.
        let k = pow(1 - x, 3)
        return CGPoint(x: want.x + offset.x * k, y: want.y + offset.y * k)
    }
}

/// A drag's haptics (SwiftUI List's reorder and the Mac's feel): UIKit plays its own at the lift, and none of ours does;
/// a selection tick each time the gap moves to a new slot (or, in Upcoming, another day lights); a light impact when a
/// drop writes. The generators are made and prepared as the drag begins, so the first tick isn't late.
@MainActor
final class DragFeel {
    private var tick: UISelectionFeedbackGenerator?
    private var thud: UIImpactFeedbackGenerator?

    func begin(in view: UIView) {
        tick = UISelectionFeedbackGenerator(view: view)
        tick?.prepare()
        thud = UIImpactFeedbackGenerator(style: .light, view: view)
        thud?.prepare()
        #if DEBUG || PERF_PROBE
        DragProbe.shared.begin(view)
        #endif
    }

    func moved() {
        tick?.selectionChanged()
        tick?.prepare()
        #if DEBUG || PERF_PROBE
        DragProbe.shared.ticks += 1
        #endif
    }

    func dropped() {
        thud?.impactOccurred()
        #if DEBUG || PERF_PROBE
        DragProbe.shared.drops += 1
        #endif
    }

    func end() {
        tick = nil
        thud = nil
    }
}

/// A display link's target (it holds its target strongly, and calls an Objective-C selector). The task lists' drag
/// and Home's.
@MainActor
final class Tick: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}

// MARK: - The delegates

extension TaskCollectionController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_ cv: UICollectionView, itemsForBeginning session: UIDragSession, at ip: IndexPath) -> [UIDragItem] {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.pressed(cv)
        #endif
        let items = drag.itemsForBeginning(session, at: ip)
        probe(items.isEmpty ? "items0" : "items")
        #if DEBUG || PERF_PROBE
        if !items.isEmpty, let id = dataSource.itemIdentifier(for: ip) {
            DragProbe.shared.lift(cv) { [weak self] in self?.dataSource.indexPath(for: id).flatMap { self?.cv.cellForItem(at: $0) } }
        }
        #endif
        return items
    }

    func collectionView(_ cv: UICollectionView, dragPreviewParametersForItemAt ip: IndexPath) -> UIDragPreviewParameters? {
        probe("params")
        let p = drag.previewParameters(at: ip)
        #if DEBUG || PERF_PROBE
        if let p { DragProbe.shared.liftPreview(p) }
        #endif
        return p
    }

    func collectionView(_ cv: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        probe("begin")
        mark("begin at \(session.location(in: cv))")
        drag.willBegin(session)
    }
    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        probe("dragEnd")
        mark("dragEnd at \(session.location(in: cv))")
        drag.dragEnded()
    }

    func collectionView(_ cv: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool {
        let can = drag.canHandle(session)
        probe(can ? "can1" : "can0")
        return can
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath dest: IndexPath?) -> UICollectionViewDropProposal {
        let p = drag.didUpdate(session)
        probe(["upd-cancel", "upd-forbidden", "upd-copy", "upd-move"][max(0, min(3, Int(p.operation.rawValue)))])
        return p
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidEnter session: UIDropSession) { probe("enter") }
    func collectionView(_ cv: UICollectionView, dropSessionDidExit session: UIDropSession) { probe("exit"); drag.didExit(session) }
    func collectionView(_ cv: UICollectionView, performDropWith c: UICollectionViewDropCoordinator) { probe("perform"); drag.perform(c) }
    func collectionView(_ cv: UICollectionView, dropSessionDidEnd session: UIDropSession) {
        probe("dropEnd")
        mark("dropEnd at \(session.location(in: cv))")
        drag.dropEnded()
    }

    func collectionView(_ cv: UICollectionView, willDisplayContextMenu c: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        probe("menu")
        drag.holdEnded(menu: true)
    }

    func mark(_ s: String) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.mark(s, in: cv)
        #endif
    }

    /// Debug only: the call, in DragProbe's log (`-dragProbe`).
    func probe(_ s: String) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call(s, in: cv)
        #endif
    }
}

#if DEBUG || PERF_PROBE
/// Debug builds and the phone's measuring build (`PERF_PROBE`, ios/Tools/perf/README.md) only.
/// `-dragProbe YES` (FlowTests): what the last drag did, as the collection view's accessibility value
/// (identifier "dragProbe"), read once it's over: "ticks=3 drops=1 dx=80.0 land=0.0,0.0 ev=items>…" (the haptic ticks
/// and drops; the copy's sideways offset from the row's place as the finger lifted; the copy's last frame against the
/// row cell's; the drag and drop delegate calls since the lift, "ourDrop" a flick's drop of ours).
/// `-dragTrace YES` (DragFilmTests, the phone): from each lift to 0.5 s after its set-down, every frame, to
/// tmp/drag-trace.log in the app's container: "F <epoch s> copy=x,y,w,h a= sh= sc= cm=<model y> row=x,y ra= fg=<the
/// drag session's finger x,y in the list> u=<drop updates since the last frame> tc=<the app's own touch x,y in the
/// list, until the drag begins> g=<item>:<model ty>:<shown ty>[h],…"
/// (each shown cell the gap moves or hides: its transform as set, and as drawn now; h: hidden). Marks: "M <epoch s>
/// …" (delegate calls, "slot <new> was <old> at <copy top>", the copy's release and landing). With `-dragTraceUIKit
/// YES` (DragFilmTests) also any view UIKit shows outside the app's root view (its drag and drop previews): a walk of
/// every window's views, each frame, too slow to measure frame times with.
@MainActor
final class DragProbe {
    static let shared = DragProbe()
    private let probing = UserDefaults.standard.bool(forKey: "dragProbe")
    private let tracing = UserDefaults.standard.bool(forKey: "dragTrace")
    private let tracingUIKit = UserDefaults.standard.bool(forKey: "dragTraceUIKit")
    /// The drag session under way (its finger, each frame).
    weak var session: (any UIDragSession)?
    /// Drop session updates since the last frame.
    private var updates = 0

    /// A drop session update reached the list.
    func updated() { updates += 1 }

    /// The gap moved to a new slot.
    func slot(_ s: Int?, was: Int?, copyTop: CGFloat) {
        mark("slot \(s.map(String.init) ?? "-") was \(was.map(String.init) ?? "-") at \(f(copyTop))")
    }

    var ticks = 0 { didSet { publish() } }
    var drops = 0 { didSet { publish() } }
    private var dx: CGFloat?
    private var land: CGPoint?
    private weak var view: UIView?

    func begin(_ v: UIView) {
        ticks = 0
        drops = 0
        dx = nil
        land = nil
        following = true
        lastCopy = nil
        step = 0
        still = 0
        stillRun = 0
        view = v
        publish()
        mark("lift")
    }

    /// The visible size of the lift preview UIKit was last given ("1x1": nothing of it shows), and our copy lifted at
    /// the hold against the row's cell ("0.0,0.0": in place).
    private var liftShape: String?
    private var held: String?
    /// A long press asks for drag items: a new lift.
    func pressed(_ list: UIView) {
        held = nil
        liftShape = nil
        calls = []
        view = list
        offset0 = (list as? UIScrollView)?.contentOffset.y
        watch(list)
    }

    /// How far the list scrolled since the press (a pan that won over the drag scrolls it).
    private var offset0: CGFloat?
    /// The list's gesture recognizers, each watched once: one that begins, ends or is cancelled is logged ("gr-…").
    private var watched: Set<ObjectIdentifier> = []
    private func watch(_ list: UIView) {
        for g in list.gestureRecognizers ?? [] where !watched.contains(ObjectIdentifier(g)) {
            watched.insert(ObjectIdentifier(g))
            g.addTarget(self, action: #selector(recognizer(_:)))
        }
    }
    @objc private func recognizer(_ g: UIGestureRecognizer) {
        let st: String
        switch g.state {
        case .began: st = "began"
        case .ended: st = "ended"
        case .cancelled: st = "cancelled"
        case .failed: st = "failed"
        default: return
        }
        guard let v = view else { return }
        let n = String(describing: type(of: g)).replacingOccurrences(of: "GestureRecognizer", with: "")
        call("gr-\(n)-\(st)", in: v)
    }
    func liftPreview(_ p: UIDragPreviewParameters) {
        let b = p.visiblePath?.bounds ?? .null
        liftShape = b.isNull ? "whole" : "\(Int(b.width))x\(Int(b.height))"
        publish()
    }
    func held(_ copy: UIView, on cell: UIView) {
        held = "\(f(copy.frame.minX - (cell.frame.minX + Metric.rowInset))),\(f(copy.frame.minY - cell.frame.minY))"
        publish()
    }

    /// The drag and drop delegate calls since the last lift's `items`, in order (a repeated one once): "ev=items>begin>
    /// can1>upd>perform>dropEnd>dragEnd" ("can" with its answer, "upd" with the proposal's operation when it changes).
    private var calls: [String] = []
    func call(_ s: String, in v: UIView) {
        if s == "items", calls.contains("items") { calls = [] }
        view = v
        if calls.last != s { calls.append(s) }
        mark("call " + s)
        publish()
    }

    func released(_ copy: UIView, home: CGPoint?) {
        following = false
        if let home { dx = copy.frame.minX - home.x }
        mark("release copy=\(f(copy.frame.minX)),\(f(copy.frame.minY)) home=\(home.map { "\(f($0.x)),\(f($0.y))" } ?? "-")")
        publish()
    }

    /// The copy at its set-down's end against the row's cell, which then shows under it.
    func landed(_ copy: UIView, on cell: UIView?) {
        if let cell { land = CGPoint(x: copy.frame.minX - (cell.frame.minX + Metric.rowInset), y: copy.frame.minY - cell.frame.minY) }
        mark("landed copy=\(f(copy.frame.minX)),\(f(copy.frame.minY)) cell=\(cell.map { "\(f($0.frame.minX)),\(f($0.frame.minY))" } ?? "-")")
        publish()
        until = CACurrentMediaTime() + 0.5 + 0.15
    }

    private var scrolled: String {
        guard let y0 = offset0, let y = (view as? UIScrollView)?.contentOffset.y else { return "-" }
        return f(y - y0)
    }

    private func publish() {
        guard probing, let view else { return }
        view.accessibilityIdentifier = "dragProbe"
        view.accessibilityValue = "step=\(f(step)) still=\(still) ticks=\(ticks) drops=\(drops) dx=\(dx.map(f) ?? "-") land=\(land.map { "\(f($0.x)),\(f($0.y))" } ?? "-") lp=\(liftShape ?? "-") held=\(held ?? "-") scroll=\(scrolled) ev=\(calls.joined(separator: ">"))"
    }

    // MARK: The copy against the finger (with -dragTrace YES, published with -dragProbe YES)

    /// From the drag's begin to the finger's lift: the copy's largest step between two frames (pt), and the most frames
    /// in a row it stood still while the drag session's finger moved (T22: on Home it stood still for 11 frames, then
    /// jumped 104 pt, following only UIKit's drop updates; and it jumped 35-77 pt to the finger as the drag began).
    private var following = false
    private var lastCopy: (copy: CGFloat, finger: CGFloat)?
    private var step: CGFloat = 0
    private var still = 0
    private var stillRun = 0

    private func follow(copy y: CGFloat, finger fy: CGFloat) {
        defer { lastCopy = (y, fy) }
        guard following, let l = lastCopy else { return }
        step = max(step, abs(y - l.copy))
        if abs(y - l.copy) < 0.05, abs(fy - l.finger) > 0.5 { stillRun += 1 } else if abs(y - l.copy) >= 0.05 { stillRun = 0 }
        if stillRun > still {
            still = stillRun
            publish()
        }
    }

    // MARK: The trace

    private weak var copy: UIView?
    private var row: () -> UIView? = { nil }
    private var link: CADisplayLink?
    private var until = CFTimeInterval.infinity
    private var lines: [String] = []
    private var lastUI = ""
    private lazy var file: FileHandle? = Trace.open("drag-trace.log")
    private let disk = DispatchQueue(label: "dragProbe.disk", qos: .utility)
    /// FrameProbe's, so the two logs line up.
    private let epoch = FrameProbe.epoch

    func trace(copy v: UIView?, row: @escaping () -> UIView?) {
        guard tracing else { return }
        copy = v
        self.row = row
        until = .infinity
        guard link == nil else { return }
        let l = CADisplayLink(target: Tick { [weak self] in self?.frame() }, selector: #selector(Tick.fire))
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// From the lift (the drag items asked), before any copy: the row, and what UIKit shows; once per launch, the
    /// list's gesture recognizers and interactions, with a long press's duration and allowable movement.
    private var listed = false
    func lift(_ list: UIView, row: @escaping () -> UIView?) {
        view = list
        mark("lift-items")
        if !listed, tracing {
            listed = true
            for g in list.gestureRecognizers ?? [] {
                let lp = (g as? UILongPressGestureRecognizer).map { " min=\($0.minimumPressDuration) move=\($0.allowableMovement)" } ?? ""
                mark("gr \(type(of: g)) name=\(g.name ?? "-") on=\(g.isEnabled)\(lp) delegate=\(g.delegate.map { "\(type(of: $0))" } ?? "-")")
            }
            for i in list.interactions { mark("interaction \(type(of: i))") }
        }
        // The copy lifted already (CollectionDrag.lift, before this) stays traced.
        trace(copy: copy, row: row)
    }

    func mark(_ s: String, in v: UIView) {
        if view == nil { view = v }
        mark(s)
    }

    private func mark(_ s: String) {
        guard tracing else { return }
        lines.append(String(format: "M %.4f ", CACurrentMediaTime() + epoch) + s)
    }

    private func frame() {
        let t0 = Perf.begin(.probe)
        defer { Perf.end(.probe, t0) }
        let now = CACurrentMediaTime()
        var out = String(format: "F %.4f", now + epoch)
        if let c = copy, c.superview != nil {
            let p = c.layer.presentation() ?? c.layer
            let sc = sqrt(p.transform.m11 * p.transform.m11 + p.transform.m12 * p.transform.m12)
            out += " copy=\(f(p.frame.minX)),\(f(p.frame.minY)),\(f(p.frame.width)),\(f(p.frame.height)) a=\(f2(p.opacity)) sh=\(f2(p.shadowOpacity)) sc=\(f2(Float(sc))) cm=\(f(c.frame.minY))"
        }
        if let cell = row() {
            let p = cell.layer.presentation() ?? cell.layer
            let ca = (cell as? UICollectionViewCell).map { $0.contentView.layer.presentation()?.opacity ?? $0.contentView.layer.opacity } ?? 1
            out += " row=\(f(p.frame.minX)),\(f(p.frame.minY)) ra=\(f2(ca))"
        }
        if let cv = view as? UICollectionView {
            if let s = session {
                let p = s.location(in: cv)
                out += " fg=\(f(p.x)),\(f(p.y))"
                if let c = copy, c.superview != nil { follow(copy: (c.layer.presentation() ?? c.layer).frame.minY, finger: p.y) }
            }
            out += " u=\(updates)"
            // The finger as the app's own touch, until UIKit hands it to the system as the drag begins.
            if let t = FrameProbe.touch {
                let q = t.window.convert(t.point, to: cv)
                out += " tc=\(f(q.x)),\(f(q.y))"
            }
            // The gap: each shown cell moved or hidden, its transform as set and as drawn.
            var g: [String] = []
            for case let c as UICollectionViewCell in cv.subviews where !c.isHidden {
                let model = c.transform.ty
                let shown = (c.layer.presentation() ?? c.layer).affineTransform().ty
                let hidden = c.contentView.alpha < 0.01
                guard model != 0 || shown != 0 || hidden, let ip = cv.indexPath(for: c) else { continue }
                g.append("\(ip.item):\(f(model)):\(f(shown))\(hidden ? "h" : "")")
            }
            if !g.isEmpty { out += " g=" + g.joined(separator: ",") }
        }
        updates = 0
        // UIKit's previews: whatever is shown in the scene's windows outside the app's root view, and any preview,
        // platter or portal view anywhere in them (its frame in the window, opacity, scale).
        if tracingUIKit, let scene = copy?.window?.windowScene ?? view?.window?.windowScene {
            var ui: [String] = []
            for w in scene.windows where !w.isHidden {
                let root = w.rootViewController?.view
                for v in w.subviews where v !== root && !v.isHidden && v.alpha > 0.01 {
                    ui.append("\(type(of: w)):\(type(of: v))[\(Self.leaves(v))]")
                }
                if let root { let l = Self.leaves(root, in: w); if !l.isEmpty { ui.append("\(type(of: w)):root[\(l)]") } }
            }
            let sig = ui.joined(separator: " ")
            if sig != lastUI { lastUI = sig; lines.append(String(format: "M %.4f ", now + epoch) + "uikit " + (sig.isEmpty ? "none" : sig)) }
        }
        lines.append(out)
        if lines.count > 60 { flush() }
        if now > until {
            link?.invalidate()
            link = nil
            flush()
        }
    }

    /// The visible views under `v`, by class, as UIKit's lift, drag and drop previews are made of (with `window`: their
    /// presented frame in it, and scale).
    private static func leaves(_ v: UIView, in window: UIView? = nil) -> String {
        var names: [String] = []
        func walk(_ v: UIView, _ depth: Int) {
            guard depth < 40, !v.isHidden, v.alpha > 0.01 else { return }
            let n = String(describing: type(of: v))
            if n.contains("Preview") || n.contains("Platter") || n.contains("Portal") || n.contains("Drag") || n.contains("Snapshot")
                || n.contains("Lift") || n.contains("ContextMenu") {
                let p = v.layer.presentation() ?? v.layer
                var s = n + "@\(f(v.frame.width))x\(f(v.frame.height))a\(f2(p.opacity))"
                if let w = window, let sv = v.superview {
                    let r = sv.convert(p.frame, to: w)
                    s += "(\(f(r.minX)),\(f(r.minY)) \(f(r.width))x\(f(r.height)) sc\(f2(Float(p.transform.m11))))"
                }
                names.append(s)
            }
            v.subviews.forEach { walk($0, depth + 1) }
        }
        walk(v, 0)
        return names.joined(separator: ",")
    }

    private func flush() {
        guard !lines.isEmpty, let file else { return }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        lines.removeAll(keepingCapacity: true)
        let h = Trace.Handle(file)
        disk.async { h.write(data) }
    }
}

private func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
private func f2(_ v: Float) -> String { String(format: "%.2f", v) }
#endif
