import QuartzCore
import SwiftUI
import TasksCore
import UIKit

// Drag to reorder (§14, §23) and Upcoming's drag onto a day (§22), on our own press and pan (T24, in place of UIKit's
// drag and drop sessions; memory: uicollectionview-spike-findings).
//
// - The press (`PressDrag`, on the collection view): held 0.35 s within 10 pt, the row lifts; from there the finger
//   drags it. No UIKit drag or drop session is ever made. UIKit's sessions outlived each drop by 0.6-0.9 s (its drop
//   animation, a refused drop's set-down), and a press whose lift fell in that window got UIKit's lift haptic, then
//   nothing (T23, on the phone): with no session, a press right after a drop lifts as any other.
// - The hold and the menu: the row's long-press menu stays UIKit's (the controller's context-menu delegate), on its own
//   clock: it opens about 0.8 s into a still hold. The lift (0.35 s) comes first, our copy on the row's exact frame, a
//   haptic of ours. Still until 0.8 s, and the menu opens: the copy fades under its preview (`menuOpened`). Moved more
//   than 10 pt from where it lifted, it's a drag (`begin`): the gap opens, and the menu is cut for this touch
//   (`DragMenu.cut`). The row's own button lets the touch go at the lift (`DragMenu.release`), so no release opens it.
// - Scrolls and swipes: before the lift, a move past 10 pt fails the press, and the list's pan or a row's swipe (pans
//   both) takes the touch as before. Once lifted, no pan begins: the list scrolls only by our edge autoscroll
//   (`EdgeScroll`), near its top and bottom.
// - Our own gap. The collection view never moves a cell itself: the dragged row is hidden in place (its content's
//   alpha), and the gap opens at our own slot: the rows after the dragged one move up by its height, the rows from the
//   slot on move down by it, as transforms set on the shown cells (`moveGap`), on Motion.layout's spring. Never by
//   invalidating the layout: that re-measures every hosting cell (13.6 ms a move) and drops self-sized heights back to
//   their estimates.
// - Slots (`slotTops`): never above the header, never between a heading and its notes, never past the Completed row; a
//   heading only before another heading or at the end. In Today and Undated, only in the dragged row's run
//   (`AppModel.dragRuns`: its list's group), so the gap and the copy stay in its group.
// - Our own lifted copy (`fill-lift`, the row's radius 12 with continuous corners, `shadow-lift`, the row's snapshot)
//   follows the finger in x and y, keeping the grab offset, as the Mac's does, every frame (a display link, so it
//   follows the list's autoscroll under a still finger too); only its y is held, 6 pt past the first and last slot (the
//   Mac's rule inside a group), and the slot is chosen by y alone. A heading's section folds into the copy as the drag
//   begins (CollectionFold's collapse), and its copy shows the open count in an accent badge.
// - Haptics (`DragFeel`): an impact at the lift, a selection tick each time the gap moves to a new slot (in Upcoming
//   also when another day lights), the light impact of a drop that writes.
// - Upcoming: the gap opens where the drop puts it (`dropOnDay`'s rules, then list order in the day), and the day's
//   label is lit (`hover`, read by +Screens' group label).
// - A drop is the finger's lift, anywhere (over the floating bar, or off the list): at the last slot shown, as on the
//   Mac (§14: "as in a Mac list"). It sets the copy down as the Mac's does (`DragCopy.setDown`): lift and all, it flies
//   into the row's exact frame (160 ms, `Motion.flight`'s curve), the row shows under it in that frame, and the copy
//   fades out over it (150 ms ease-out). One at the row's own place is refused and flies home the same way; nothing is
//   written. A touch taken from us mid-drag (the system's) goes home too.
// - VoiceOver: its double-tap-and-hold passes the touch through, so the same press drags; "Move Up" and "Move Down"
//   (`voiceOverMove`, a task row's accessibility actions in +Screens) drop it at the slot before or after its own.
// - Drops write through AppModel.drop (dropOnDay in Upcoming), Reorder.swift.
//
// Hooks: `install` adds the press to the collection view, `stop`; `holdsUpdates` (while a drag, its landing or a lifted
// heading is on, the core keeps the latest items in `wanted`); `layoutPad` (the layout reaches a row's height past a
// rect, for cells the gap moves into it); a cell's `configured`, `cellDidApply` and `reuse`; `menuOpened` (the
// controller's willDisplayContextMenu).

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
        /// In Today and Undated, the items of the dragged row's run (`AppModel.dragRuns`: its list's group, the label
        /// first; the last group also has the Completed row and its done tasks). Nil elsewhere: one run.
        var run: Set<String>?
    }

    unowned let owner: TaskCollectionController
    let hover = DragHover()

    /// The drag under way: the finger has moved since the lift, and the gap is open.
    private(set) var state: State?
    /// The row lifted at the hold, before the finger has moved: its menu may still open (`menuOpened`).
    private var held: State?
    /// The finger's place at the lift, in the window: a move past `PressDrag.slop` from it begins the drag.
    private var liftPoint: CGPoint = .zero
    /// The dropped (or refused) row, kept hidden while the copy flies into its place.
    private var landing: String?
    /// The copy setting down (a new lift ends its set-down at once), and a count that tells its end from a later one's.
    private var landingCopy: UIView?
    private var landings = 0
    /// A heading whose section is folded into its drag.
    private var lifted: String?
    private var copy: UIView?
    private var press: PressDrag?
    private let feel = DragFeel()
    private var edge = EdgeScroll()
    /// Ticks from the lift to the release: the copy and the slot follow the finger, and the list's edge autoscroll.
    private var link: CADisplayLink?
    /// Items whose cells the gap has moved or hidden, put back when it closes.
    private var placed: Set<String> = []

    init(owner: TaskCollectionController) { self.owner = owner }

    func install() {
        let p = PressDrag(target: self, action: #selector(pressed(_:)))
        p.canLift = { [weak self] at in self?.item(at: at) != nil }
        p.touched = { [weak self] in self?.touched() }
        owner.cv.addGestureRecognizer(p)
        press = p
    }

    func stop() {
        stopLink()
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

    /// Its place for the gap: hidden by its content, or moved by a transform.
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

    /// Each frame from the lift: the copy follows the finger in x and y, keeping the grab offset; its y is held within
    /// 6 pt of the first and last slot (the Mac's rule in a group; x is free, as the Mac's pointer is). Once the drag
    /// has begun, the list scrolls at its edges (`EdgeScroll`), and the gap follows the copy's y: the slot whose top is
    /// nearest the copy's (Upcoming: `upcomingTarget`). Each new slot, or newly lit day, ticks.
    private func follow() {
        guard let base = state ?? held, let g = press else { return }
        let t0 = Perf.begin(.follow)
        defer { Perf.end(.follow, t0) }
        let cv = owner.cv!
        if state != nil { edge.scroll(cv, finger: g.location(in: cv), foot: owner.bottomClearance) }
        // Sizing that rows scrolled into view still owe is settled first, so the slots' tops have no holes.
        Perf.measure(.layout) { cv.layoutIfNeeded() }
        var d = state ?? base
        let tops = slotTops(d)
        let finger = g.location(in: cv)
        var copyTop = finger.y - d.grab.y
        if let lo = tops.map(\.y).min(), let hi = tops.map(\.y).max() { copyTop = min(max(copyTop, lo - 6), hi + 6) }
        if let v = copy {
            UIView.performWithoutAnimation { v.frame.origin = CGPoint(x: finger.x - d.grab.x + Metric.rowInset, y: copyTop) }
        }
        guard state != nil else { return }
        // Wherever the finger is (over the floating bar at the bottom, or off the list), the gap stays at the slot
        // nearest the copy, held to the list: letting go drops at the last slot shown (INTERACTIONS §14, "as in a Mac
        // list").
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

    private func startLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: Tick { [weak self] in self?.follow() }, selector: #selector(Tick.fire))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        edge.stop()
    }

    // MARK: The press

    private func canLift(_ id: String) -> Bool {
        let app = owner.app, source = owner.source
        // Not in select mode (`CollectionSelect.blocksDrag`: one row at a time), nor while adding here, nor
        // where rows don't move (Completed, Trash, a deleted list).
        guard !owner.select.blocksDrag, app.draft?.source != source, app.dragRuns([], source) != nil else { return false }
        return owner.rows.line(id)?.canDrag == true && (id.hasPrefix("t:") || id.hasPrefix("h:"))
    }

    /// The row a press at `p` (in the list) would lift, if it may.
    private func item(at p: CGPoint) -> (id: String, ip: IndexPath)? {
        guard state == nil, held == nil, let ip = owner.cv.indexPathForItem(at: p),
              let id = owner.dataSource.itemIdentifier(for: ip), canLift(id) else { return nil }
        return (id, ip)
    }

    /// A finger is down: the haptics are made ready, so the lift's isn't late.
    private func touched() {
        feel.prepare(in: owner.cv)
        #if DEBUG || PERF_PROBE
        DragProbe.shared.pressed(owner.cv)
        #endif
    }

    @objc private func pressed(_ g: PressDrag) {
        switch g.state {
        case .began: lift(g)
        case .changed: moved(g)
        case .ended: release(drop: true)
        case .cancelled, .failed: release(drop: false)
        default: break
        }
    }

    /// The hold: our copy lifts in place, on the row's exact frame, with a haptic, and follows the finger from here.
    private func lift(_ g: PressDrag) {
        // A set-down still under way ends now, so the rows are where they'll stay.
        endLanding()
        let cv = owner.cv!
        let p = g.location(in: cv)
        guard let (id, ip) = item(at: p), let f = owner.layout.modelFrame(ip.item) else { return }
        let d = State(id: id, height: f.height, grab: CGPoint(x: p.x - f.minX, y: p.y - f.minY), slot: ip.item, ticked: ip.item, run: run(of: id))
        makeCopy(d)
        guard let v = copy else { return }
        held = d
        liftPoint = g.location(in: nil)
        if let cell = cv.cellForItem(at: ip) { DragMenu.release(cell) }
        feel.lifted(in: cv)
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("lift", in: cv)
        DragProbe.shared.finger = { [weak g, weak cv] in
            guard let g, let cv, g.numberOfTouches > 0 else { return nil }
            return g.location(in: cv)
        }
        if let cell = cv.cellForItem(at: ip) {
            DragProbe.shared.held(v, on: cell)
            DragProbe.shared.lift(cv) { [weak self] in self?.owner.dataSource.indexPath(for: id).flatMap { self?.owner.cv.cellForItem(at: $0) } }
        }
        #endif
        startLink()
    }

    /// The finger moved: once past `PressDrag.slop` from where it lifted, the drag begins.
    private func moved(_ g: PressDrag) {
        guard let d = held else { return }
        let w = g.location(in: nil)
        guard hypot(w.x - liftPoint.x, w.y - liftPoint.y) > PressDrag.slop else { return }
        begin(d)
    }

    /// The drag begins: the row's menu won't open for this touch, the dragged row leaves its place (the gap stays where
    /// it was), and a heading's section folds into it (§23).
    private func begin(_ lift: State) {
        held = nil
        guard let at = owner.current.firstIndex(of: lift.id) else { release(drop: false); return }
        var d = lift
        // The rows may have changed since the lift (a sync): the gap starts at its place now.
        d.slot = at
        d.ticked = at
        state = d
        DragMenu.cut(owner.cv, keeping: press)
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("begin", in: owner.cv)
        FrameProbe.dragBegan()
        #endif
        if d.id.hasPrefix("h:") {
            // The gap is the heading's own row.
            lifted = d.id
            let all = owner.current
            let items = shown(all)
            let slot = items.firstIndex(of: d.id)
            state?.slot = slot
            state?.ticked = slot
            owner.apply(items, fold: CollectionFold.Plan(heading: d.id, items: Set(CollectionFold.section(of: d.id, in: all)), collapse: true),
                        animation: .easeOut(duration: 0.15))
        }
        moveGap(animated: false)
    }

    /// The finger lifted (`drop`), or the touch was taken from us: a drag drops at its slot (or goes home, refused or
    /// taken); a lift that never moved sets down on its row.
    private func release(drop: Bool) {
        if let d = held {
            held = nil
            stopLink()
            #if DEBUG || PERF_PROBE
            DragProbe.shared.call("holdDown", in: owner.cv)
            #endif
            land(at: owner.modelFrame(d.id), id: d.id)
            return
        }
        guard state != nil else { stopLink(); return }
        // At the finger's last place.
        follow()
        stopLink()
        if drop, let d = state, moves(d) { self.drop(d) } else { goHome() }
        unfold()
        settle()
    }

    /// The row's menu opened (a still hold, about 0.8 s in): the copy fades where it is, over the row (150 ms), under
    /// the menu's own preview of the row. Removed at once, the row showed bare for a frame or two before the preview.
    func menuOpened() {
        if held != nil, let v = copy {
            held = nil
            copy = nil
            stopLink()
            #if DEBUG || PERF_PROBE
            DragProbe.shared.call("holdMenu", in: owner.cv)
            #endif
            DragCopy.setDown(v, at: nil) {}
        } else if state != nil {
            // A drag cuts the menu as it begins (`DragMenu.cut`); one that opened anyway goes.
            owner.cv.contextMenuInteraction?.dismissMenu()
        }
    }

    /// VoiceOver's "Move Up" and "Move Down" on a task's row (not in Upcoming, where a drag sets the day): dropped at the
    /// slot before or after its own, as a drag would drop it there. Whether it moved.
    func voiceOverMove(_ id: String, by step: Int) -> Bool {
        guard state == nil, held == nil, landing == nil, canLift(id), let at = owner.current.firstIndex(of: id),
              let f = owner.layout.modelFrame(at), id.hasPrefix("t:"), owner.source != .upcoming else { return false }
        var d = State(id: id, height: f.height, grab: .zero, slot: at, ticked: at, run: run(of: id))
        let slots = slotTops(d).map(\.slot)
        guard let next = step < 0 ? slots.last(where: { $0 < at }) : slots.first(where: { $0 > at }) else { return false }
        d.slot = next
        state = d
        _ = write(d)
        landing = nil
        moveGap(animated: false)
        settle()
        return true
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

    /// The drag ended with no drop (refused: let go at the row's own place; or the touch was taken): the copy flies home
    /// as the gap there closes, and sets down there as a drop does; a lifted heading's section opens.
    private func goHome() {
        guard let d = state else { return }
        let home = owner.current.firstIndex(of: d.id).flatMap { owner.layout.modelFrame($0) }
        state = nil
        landing = d.id
        hover.key = nil
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("home", in: owner.cv)
        #endif
        moveGap(animated: true)
        land(at: home, id: d.id)
        unfold()
    }

    // MARK: The copy

    private func makeCopy(_ d: State) {
        let cv = owner.cv!
        guard let i = owner.current.firstIndex(of: d.id), let cell = cv.cellForItem(at: IndexPath(item: i, section: 0)),
              let snap = cell.snapshotView(afterScreenUpdates: false) else { return }
        let p = owner.palette, inset = Metric.rowInset
        let v = UIView(frame: cell.frame.insetBy(dx: inset, dy: 0))
        v.isUserInteractionEnabled = false
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

    /// The copy sets down on the row's `frame` (`DragCopy.setDown`), and the row `id` shows under it.
    private func land(at frame: CGRect?, id: String) {
        guard let v = copy else { landed(); return }
        copy = nil
        landings += 1
        let n = landings
        landingCopy = v
        let origin = frame.map { CGPoint(x: $0.minX + Metric.rowInset, y: $0.minY) }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.released(v, home: origin)
        #endif
        DragCopy.setDown(v, at: origin) { [weak self] in
            guard let self, self.landings == n else { return }
            #if DEBUG || PERF_PROBE
            if let ip = self.owner.dataSource.indexPath(for: id) { DragProbe.shared.landed(v, on: self.owner.cv.cellForItem(at: ip)) }
            #endif
            self.landingCopy = nil
            self.landed()
        }
    }

    /// A new lift while a copy still sets down: it ends now (its row shows, what was held back is applied).
    private func endLanding() {
        guard let v = landingCopy else { return }
        landingCopy = nil
        landings += 1
        v.layer.removeAllAnimations()
        v.removeFromSuperview()
        landed()
    }

    /// The landed row shows; anything held back meanwhile is applied.
    private func landed() {
        landing = nil
        moveGap(animated: false)
        settle()
    }

    // MARK: Dropping

    /// The finger lifted over a new slot: written, and the copy sets down in the row's new place.
    private func drop(_ d: State) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("drop", in: owner.cv)
        #endif
        let f = write(d)
        land(at: f, id: d.id)
    }

    /// The drop at the gap: written (AppModel.drop: dropOnDay in Upcoming), and the new order applied at once, the
    /// dropped row hidden under the copy. Its frame, where the copy sets down (nil: it has gone).
    private func write(_ d: State) -> CGRect? {
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
}

/// Our press-and-drag on a list (the task lists' and Home's), in place of UIKit's drag interaction. One finger held
/// `hold` (0.35 s) within `slop` (10 pt) of where it landed begins it (the lift); from there each move is a change,
/// and the finger's lift ends it. UIKit lifted at about 0.41 s (its click driver's, shared with the menu; its own
/// recognizer waits 0.325 s within 10 pt): ours lifts a little sooner, never later, and fails the same way, so a scroll
/// or a row's swipe that moves 10 pt before the lift wins as before. Its delegate is itself: it runs alongside UIKit's
/// own on the list (the row's long-press menu, which opens about 0.8 s into a still hold; the scroll indicator's), never
/// a pan's (the list's scroll, a row's swipe), which it stops once it has begun; it isn't simultaneous with anything in
/// the rows (their buttons' taps fail as it begins, so letting go opens nothing). Only a pan can prevent it.
@MainActor
final class PressDrag: UIGestureRecognizer, UIGestureRecognizerDelegate {
    static let hold: TimeInterval = 0.35
    static let slop: CGFloat = 10
    /// May a press at this point (in the view) lift? Asked at the hold's end.
    var canLift: (CGPoint) -> Bool = { _ in false }
    /// A finger has landed.
    var touched: () -> Void = {}
    private var timer: Timer?
    private var start: CGPoint = .zero
    private weak var finger: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard finger == nil else {
            // Another finger: before the lift it's no press (two fingers select, `SwipeSelect`); after it, ignored.
            if state == .possible { state = .failed } else { touches.forEach { ignore($0, for: event) } }
            return
        }
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        finger = t
        start = t.location(in: nil)
        touched()
        let timer = Timer(timeInterval: Self.hold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.held() }
        }
        // In the tracking mode too: the list's run loop runs in it while a finger is down.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func held() {
        timer = nil
        guard state == .possible, let v = view else { return }
        state = canLift(location(in: v)) ? .began : .failed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = finger, touches.contains(t) else { return }
        if state == .possible {
            let p = t.location(in: nil)
            if hypot(p.x - start.x, p.y - start.y) > Self.slop { state = .failed }
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = finger, touches.contains(t) else { return }
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = finger, touches.contains(t) else { return }
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        timer?.invalidate()
        timer = nil
        finger = nil
        super.reset()
    }

    override func canBePrevented(by p: UIGestureRecognizer) -> Bool { p is UIPanGestureRecognizer }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other.view === view && !(other is UIPanGestureRecognizer)
    }
}

/// A drag's edge autoscroll (the task lists' and Home's), in place of UIKit's: with the finger near the list's top (its
/// top inset, under the bar) or its foot (the floating bar's top), the list scrolls that way, faster the deeper the
/// finger is: from 40 pt/s at 60 pt from the edge to 1200 pt/s at 20 pt past the top edge or 40 pt past the foot (over
/// the bar), with the square of the depth (UIKit's grows the same way). It never scrolls past the content's ends.
struct EdgeScroll {
    static let reach: CGFloat = 60
    private var last: CFTimeInterval = 0

    mutating func stop() { last = 0 }

    /// One frame's scroll, for the finger at `p` (in the list's content); `foot` is how far the list's clear bottom is
    /// from its frame's (the floating bar's clearance).
    @MainActor mutating func scroll(_ cv: UIScrollView, finger p: CGPoint, foot: CGFloat) {
        let now = CACurrentMediaTime()
        let dt = last > 0 ? min(now - last, 1.0 / 30) : 1.0 / 60
        last = now
        let y = p.y - cv.contentOffset.y
        let top = cv.adjustedContentInset.top, bottom = cv.bounds.height - foot
        let up = (top + Self.reach - y) / (Self.reach + 20), down = (y - (bottom - Self.reach)) / (Self.reach + 40)
        let k = min(1, max(up, down))
        guard k > 0 else { return }
        let v = (40 + 1160 * k * k) * (up > 0 ? -1 : 1)
        let lo = -cv.adjustedContentInset.top, hi = max(lo, cv.contentSize.height + cv.adjustedContentInset.bottom - cv.bounds.height)
        let to = min(max(cv.contentOffset.y + v * dt, lo), hi)
        guard abs(to - cv.contentOffset.y) > 0.01 else { return }
        cv.contentOffset.y = to
    }
}

/// What else the press's touch drives, once it's ours (the task lists' and Home's). A recognizer whose `isEnabled` goes
/// off and on again is cancelled (or fails) at once, and is itself for the next touch.
@MainActor
enum DragMenu {
    /// The row's menu still to come at the hold's end (UIKit's click presentation, about 0.8 s in) doesn't open, once a
    /// drag has begun: the list's own recognizers still following this touch, but for our press and the pans (none
    /// runs once ours has begun), are cancelled; the menu's are among them. UIKit cancels its menu itself once the finger
    /// has gone far enough, but not for a slow drag: one of 12 pt in 0.3 s still opened the menu over the drag (T24,
    /// measured). (Taking the list's context-menu interaction off and putting it back cut it too, but the list's
    /// menus never opened again.)
    static func cut(_ cv: UICollectionView, keeping press: UIGestureRecognizer?) {
        for g in cv.gestureRecognizers ?? [] where g !== press && !(g is UIPanGestureRecognizer) && (g.state == .began || g.state == .changed) {
            g.isEnabled = false
            g.isEnabled = true
        }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call("menuCut", in: cv)
        #endif
    }

    /// The lifted row's own recognizers (its SwiftUI button's) let the touch go as it lifts, so letting go opens
    /// nothing: they run alongside UIKit's in a hosting view, and only the row's menu, when it has one, used to take the
    /// touch from them.
    static func release(_ cell: UIView) {
        var views = [cell]
        while let v = views.popLast() {
            for g in v.gestureRecognizers ?? [] where g.isEnabled {
                g.isEnabled = false
                g.isEnabled = true
            }
            views += v.subviews
        }
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

    /// The lifted row's shape (the copy, its clip and shadow): the row's tapped fill, radius 12 with continuous corners
    /// (TaskRow's `RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous)`). The path is UIKit's rounded
    /// rect, which is drawn with continuous corners itself.
    static func shape(_ r: CGRect) -> UIBezierPath { UIBezierPath(roundedRect: r, cornerRadius: Metric.rowRadius) }

    /// A layer rounded as the row's fill.
    static func round(_ l: CALayer) {
        l.cornerRadius = Metric.rowRadius
        l.cornerCurve = .continuous
    }
}

/// A drag's haptics (SwiftUI List's reorder and the Mac's feel): an impact at the lift; a selection tick each time the
/// gap moves to a new slot (or, in Upcoming, another day lights); a light impact when a drop writes. The generators are
/// made and prepared as a finger lands, so the lift's isn't late.
@MainActor
final class DragFeel {
    private var lift: UIImpactFeedbackGenerator?
    private var tick: UISelectionFeedbackGenerator?
    private var thud: UIImpactFeedbackGenerator?

    func prepare(in view: UIView) {
        if lift == nil {
            lift = UIImpactFeedbackGenerator(style: .medium, view: view)
            tick = UISelectionFeedbackGenerator(view: view)
            thud = UIImpactFeedbackGenerator(style: .light, view: view)
        }
        lift?.prepare()
        tick?.prepare()
        thud?.prepare()
    }

    func lifted(in view: UIView) {
        prepare(in: view)
        lift?.impactOccurred()
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
        lift = nil
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

// MARK: - The menu, and the probe's hooks

extension TaskCollectionController {
    func collectionView(_ cv: UICollectionView, willDisplayContextMenu c: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        probe("menu")
        drag.menuOpened()
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
/// `-dragProbe YES` (FlowTests): what the last press did, as the collection view's accessibility value (identifier
/// "dragProbe"), read once it's over: "pd=180 step=12.0 still=0 ticks=3 drops=1 dx=80.0 land=0.0,0.0 uk=0
/// held=0.0,0.0 scroll=0.0 ev=press>lift>begin>menuCut>drop" (ms from the last copy's release to this press's touch;
/// the copy's largest step and still run (with -dragTrace); the haptic ticks and drops; the copy's sideways offset
/// from the row's place as the finger lifted; the copy's last frame against the row cell's; whether a UIKit drag or
/// drop session was ever seen on the list (`hasActiveDrag`/`hasActiveDrop`); the copy at the hold against the row's
/// cell; how far the list scrolled since the press; the press's calls in order: press, lift, begin, menuCut, drop,
/// home, holdDown (let go where it lifted), holdMenu (the row's menu opened), menu, and the list's gesture recognizers
/// that began or ended, "gr-…").
/// `-dragTrace YES` (DragFilmTests, the phone): from each lift to 0.5 s after its set-down, every frame, to
/// tmp/drag-trace.log in the app's container: "F <epoch s> copy=x,y,w,h a= sh= sc= cm=<model y> row=x,y ra= fg=<the
/// press's finger x,y in the list> off=<the list's content offset y> tc=<the window's last touch x,y in the list>
/// g=<item>:<model ty>:<shown ty>[h],…" (each shown cell the gap moves or hides: its transform as set, and as drawn
/// now; h: hidden). Marks: "M <epoch s> …" (the calls, "slot <new> was <old> at <copy top>", the copy's release and
/// landing), from each touch-down on the list. With `-dragTraceUIKit YES` (DragFilmTests) also any view UIKit shows
/// outside the app's root view (a menu's previews): a walk of every window's views, each frame, too slow to measure
/// frame times with.
@MainActor
final class DragProbe {
    static let shared = DragProbe()
    private let probing = UserDefaults.standard.bool(forKey: "dragProbe")
    private let tracing = UserDefaults.standard.bool(forKey: "dragTrace")
    private let tracingUIKit = UserDefaults.standard.bool(forKey: "dragTraceUIKit")
    /// The press under way: its finger in the list, each frame.
    var finger: (() -> CGPoint?)?

    private init() {
        // Written out as the app leaves the foreground (the phone's logs are copied then: T22's last lift was lost).
        for n in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DragProbe.shared.flush() }
            }
        }
    }

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

    /// Our copy lifted at the hold against the row's cell ("0.0,0.0": in place).
    private var held: String?
    /// A UIKit drag or drop session was seen on the list since the press (there should be none: T24).
    private var uikit = false
    /// From the last copy's release to this press's touch-down, ms.
    private var sinceRelease: Double?
    /// A finger landed on the list: a new press.
    func pressed(_ list: UIView) {
        held = nil
        uikit = false
        calls = []
        sinceRelease = releasedAt.map { (CACurrentMediaTime() - $0) * 1000 }
        view = list
        offset0 = (list as? UIScrollView)?.contentOffset.y
        watch(list)
        call("press", in: list)
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
    func held(_ copy: UIView, on cell: UIView) {
        held = "\(f(copy.frame.minX - (cell.frame.minX + Metric.rowInset))),\(f(copy.frame.minY - cell.frame.minY))"
        publish()
    }

    /// The press's calls since its touch-down, in order (a repeated one once).
    private var calls: [String] = []
    private var releasedAt: CFTimeInterval?
    func call(_ s: String, in v: UIView) {
        view = v
        sampleUIKit()
        if calls.last != s { calls.append(s) }
        mark("call " + s)
        publish()
    }

    /// Whether UIKit has a drag or drop session on the list now.
    private func sampleUIKit() {
        if let cv = view as? UICollectionView, cv.hasActiveDrag || cv.hasActiveDrop { uikit = true }
    }

    func released(_ copy: UIView, home: CGPoint?) {
        following = false
        releasedAt = CACurrentMediaTime()
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
        view.accessibilityValue = "pd=\(sinceRelease.map { String(format: "%.0f", $0) } ?? "-") step=\(f(step)) still=\(still) ticks=\(ticks) drops=\(drops) dx=\(dx.map(f) ?? "-") land=\(land.map { "\(f($0.x)),\(f($0.y))" } ?? "-") uk=\(uikit ? 1 : 0) held=\(held ?? "-") scroll=\(scrolled) ev=\(calls.joined(separator: ">"))"
    }

    // MARK: The copy against the finger (with -dragTrace YES, published with -dragProbe YES)

    /// From the lift to the finger's lift: the copy's largest step between two frames (pt), and the most frames in a row
    /// it stood still while the finger moved (T22, UIKit's drag: on Home it stood still for 11 frames, then jumped 104
    /// pt, following only UIKit's drop updates; and it jumped 35-77 pt to the finger as the drag began).
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

    /// From the lift: the row, and what UIKit shows; once per launch, the list's gesture recognizers (whether each is a
    /// pan) and interactions, with a long press's duration and allowable movement.
    private var listed = false
    func lift(_ list: UIView, row: @escaping () -> UIView?) {
        view = list
        mark("row at lift")
        if !listed, tracing {
            listed = true
            for g in list.gestureRecognizers ?? [] {
                let lp = (g as? UILongPressGestureRecognizer).map { " min=\($0.minimumPressDuration) move=\($0.allowableMovement)" } ?? ""
                mark("gr \(type(of: g)) name=\(g.name ?? "-") on=\(g.isEnabled) pan=\(g is UIPanGestureRecognizer)\(lp) delegate=\(g.delegate.map { "\(type(of: $0))" } ?? "-")")
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
        // Between drags (no trace running), at once.
        if link == nil { flush() }
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
            sampleUIKit()
            if let p = finger?() {
                out += " fg=\(f(p.x)),\(f(p.y))"
                // In the window's terms (the copy moves with the list's autoscroll as the finger does).
                if let c = copy, c.superview != nil {
                    follow(copy: (c.layer.presentation() ?? c.layer).frame.minY - cv.contentOffset.y, finger: p.y - cv.contentOffset.y)
                }
            }
            out += " off=\(f(cv.contentOffset.y))"
            // The finger as the window's last touch.
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
