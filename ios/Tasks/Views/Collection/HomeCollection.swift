import SwiftUI
import TasksCore
import UIKit

// Home on a UICollectionView (the migration's step 8, in place of SwiftUI List). The app's own SwiftUI rows, each in a
// UIHostingConfiguration cell: the header, Today, Upcoming and Undated, "Lists", the lists
// between their two edges, Completed and Trash, and the sync line. Under the last row, the floating controls' clearance
// (iPad's sidebar: 60) is the bottom inset, not a row.
//
// Items are strings: "header", "s:" and a view's id ("s:today" …), "lists" (the label), "e:top" and "e:end" (the
// edges above and below the lists, `HomeItem`), "l:" and a list's id, and "sync".
//
// Lists reorder by drag (§14), on our own press and gap, as the task lists' (TaskCollection+Drag.swift, T24): no UIKit
// drag or drop session. Our press (`PressDrag`) lifts a list at 0.35 s, our copy on the row's exact frame; still until
// about 0.8 s, the list's menu (UIKit's) opens and the copy fades; moved past 10 pt, the drag begins (the menu is cut,
// `DragMenu.cut`). The collection view never moves a cell itself: the dragged row is hidden by its content's alpha, the
// others move by transforms to open a gap at our slot, and our copy follows the finger in x and y every frame (its y
// held 6 pt past the first and last slot; the slot is chosen by y), with the edge autoscroll (`EdgeScroll`). The slots
// are the lists' run only, from just under "Lists" to the end of the lists, so Today and the views never move. The drop,
// at the finger's lift anywhere, is `AppModel.dropList`, given the run as `.onMove` gives it (edges included, as nil).
// One at the row's own place is refused, so the copy flies home and nothing is written. The haptics (`DragFeel`) and
// the set-down (`DragCopy.setDown`) are the task lists'. VoiceOver: the press passes through its double-tap-and-hold,
// and a list's row has Move Up and Move Down (`voiceOverMove`).

struct HomeCollection: UIViewControllerRepresentable {
    let items: [String]
    let sidebar: Bool
    /// The title has scrolled under the bar.
    let folded: Binding<Bool>
    @Environment(AppModel.self) private var app

    func makeUIViewController(context: Context) -> HomeCollectionController {
        HomeCollectionController(app: app, sidebar: sidebar)
    }

    func updateUIViewController(_ c: HomeCollectionController, context: Context) {
        let folded = folded
        c.onFold = { if folded.wrappedValue != $0 { folded.wrappedValue = $0 } }
        let t = context.transaction
        c.update(items, animated: !t.disablesAnimations && t.animation != nil)
    }

    static func dismantleUIViewController(_ c: HomeCollectionController, coordinator: ()) { c.stop() }

    /// Home's items (above), from the app's lists and sync state.
    @MainActor static func items(_ app: AppModel) -> [String] {
        var ids = ["header", "s:today", "s:upcoming", "s:undated", "lists"]
        ids += HomeItem.items(app.activeLists).map { item in item.listID.map { "l:" + $0 } ?? item.id }
        ids += ["s:completed", "s:trash"]
        if app.syncSummary != nil { ids.append("sync") }
        return ids
    }
}

/// An item's SwiftUI row (HomeView.swift's views). Each reads the app itself, so it stays live (Today's count, a
/// list's name, the sync line's words).
struct HomeLine: View {
    let id: String
    let sidebar: Bool
    /// VoiceOver's Move Up and Move Down, on a list's row (the drag's drop at the slot before or after).
    var move: ((Int) -> Bool)? = nil
    @Environment(AppModel.self) private var app

    var body: some View {
        switch id {
        case "header": HomeHeader(sidebar: sidebar)
        case "s:today": SourceRow(source: .today, count: app.todayCount(), sidebar: sidebar)
        case "s:upcoming": SourceRow(source: .upcoming, sidebar: sidebar)
        case "s:undated": SourceRow(source: .undated, sidebar: sidebar)
        case "s:completed": SourceRow(source: .completed, sidebar: sidebar)
        case "s:trash": SourceRow(source: .trash, sidebar: sidebar)
        case "lists": GroupLabel(title: "Lists", bottom: 0)
        // The air under "Lists" and under the last list: the lists' run's edges (Reorder.swift, "Edges").
        case "e:top": Color.clear.frame(height: 6).accessibilityHidden(true)
        case "e:end": Color.clear.frame(height: 14).accessibilityHidden(true)
        case "sync": if let s = app.syncSummary { SyncLine(text: s) }
        default:
            // No count: only Today has one (the user, 2026-10-31; IX:37–39).
            if id.hasPrefix("l:") {
                SourceRow(source: .list(String(id.dropFirst(2))), sidebar: sidebar)
                    .accessibilityActions {
                        if let move {
                            Button("Move Up") { _ = move(-1) }
                            Button("Move Down") { _ = move(1) }
                        }
                    }
            }
        }
    }
}

// MARK: - The controller

@MainActor
final class HomeCollectionController: UIViewController, UICollectionViewDelegate {
    let app: AppModel
    let sidebar: Bool
    private var cv: UICollectionView!
    private var layout: HomeLayout!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    /// The items applied, and the latest asked for (held back while a drag or its landing is on).
    private var current: [String] = []
    private var wanted: [String] = []
    var onFold: (Bool) -> Void = { _ in }

    init(app: AppModel, sidebar: Bool) {
        self.app = app
        self.sidebar = sidebar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var dark: Bool { app.appearance == .system ? traitCollection.userInterfaceStyle == .dark : app.appearance == .dark }
    private var palette: Palette { Palette.make(dark: dark) }

    override func loadView() {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        // No swipe actions on Home.
        let layout = HomeLayout { _, env in NSCollectionLayoutSection.list(using: config, layoutEnvironment: env) }
        self.layout = layout
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.allowsSelection = false
        cv.delegate = self
        // It pulls down even when the rows fit, to refresh.
        cv.alwaysBounceVertical = true
        // A row's press shows the moment a finger lands.
        cv.delaysContentTouches = false
        // The rows' heights don't change while shown; a new text size reconfigures them all (below).
        cv.selfSizingInvalidation = .disabled
        // Clear of the floating bar and the + on the phone (whose bottom safe area this ignores, as ListScreen's
        // does); in iPad's sidebar, 60 over the HomeBar's inset.
        cv.contentInset.bottom = sidebar ? 60 : Metric.bottomClearance
        self.cv = cv

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task { @MainActor in
                await self?.app.syncNow()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        cv.refreshControl = refresh

        let reg = UICollectionView.CellRegistration<HomeCell, String> { [weak self] cell, _, id in self?.configure(cell, id) }
        dataSource = UICollectionViewDiffableDataSource(collectionView: cv) { cv, ip, id in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: id)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.reconfigureAll() }
        view = cv
        installDrag()
    }

    func stop() {
        stopLink()
        copyView?.removeFromSuperview()
        copyView = nil
        held = nil
        feel.end()
    }

    // MARK: Cells

    private func configure(_ cell: HomeCell, _ id: String) {
        let t0 = Perf.begin(.configure)
        defer { Perf.end(.configure, t0) }
        cell.itemID = id
        cell.owner = self
        cell.backgroundConfiguration = .clear()
        // Nothing here holds the controller: the cells are its view's.
        let app = app, sidebar = sidebar
        let move: ((Int) -> Bool)? = id.hasPrefix("l:") ? { [weak self] in self?.voiceOverMove(id, by: $0) ?? false } : nil
        cell.contentConfiguration = UIHostingConfiguration {
            HomeLine(id: id, sidebar: sidebar, move: move).modifier(CellTheme(app: app))
        }
        .margins(.horizontal, Metric.rowInset)
        .margins(.vertical, 0)
        .minSize(width: nil, height: 0)
        // A configuration can bring a new content view: a row hidden for the gap stays hidden.
        cell.placeForGap()
    }

    private func reconfigureAll() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Applying

    /// A lift, its drag, or its copy's landing holds updates back: they're applied at its end (`settle`). From the lift,
    /// so a sync doesn't move rows under the still copy (T28).
    private var holds: Bool { held != nil || drag != nil || landing != nil }

    func update(_ items: [String], animated: Bool) {
        wanted = items
        guard !holds else { return }
        apply(items, animated: animated)
    }

    /// The items, at once, or on Motion.layout's spring (a list added, deleted or restored, the sync line).
    private func apply(_ items: [String], animated: Bool) {
        guard items != current else { return }
        let t0 = Perf.begin(.apply)
        defer { Perf.end(.apply, t0) }
        let old = current
        current = items
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(items)
        CATransaction.begin()
        defer { CATransaction.commit() }
        guard animated, !old.isEmpty, !UIAccessibility.isReduceMotionEnabled else {
            dataSource.apply(snap, animatingDifferences: false)
            return
        }
        // SwiftUI may run this update inside performWithoutAnimation: it animates regardless.
        let was = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(was) }
        UIView.animate(springDuration: 0.25, bounce: 0) { self.dataSource.apply(snap, animatingDifferences: true) }
    }

    /// The updates held back during a drag, once it and its landing are over.
    private func settle() {
        guard !holds else { return }
        apply(wanted, animated: true)
    }

    // MARK: Scrolling

    /// The bar's name fades in once the large one has gone under it (HomeView's `folded`).
    func scrollViewDidScroll(_ s: UIScrollView) {
        onFold(s.contentOffset.y + s.adjustedContentInset.top > 40)
    }

    // MARK: Menus

    /// A list's long-press menu: Rename, then Delete List.
    func collectionView(_ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        probe(drag == nil ? "menuAsk" : "menuAsk-dragSet")
        guard drag == nil, ips.count == 1, let id = dataSource.itemIdentifier(for: ips[0]), id.hasPrefix("l:") else { return nil }
        let listID = String(id.dropFirst(2))
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { [weak self] _ in
            self?.listMenu(listID)
        }
    }

    /// An action that presents something (Rename's alert) waits for the menu to finish closing.
    private var afterMenu: (() -> Void)?

    private func listMenu(_ id: EntityID) -> UIMenu {
        let app = app
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.afterMenu = { app.listEditor = .init(listID: id, name: app.list(id)?.name ?? "") }
        }
        // The row leaves while the menu closes.
        let delete = UIAction(title: "Delete List", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            app.deleteList(id)
        }
        return UIMenu(children: [rename, UIMenu(options: .displayInline, children: [delete])])
    }

    func collectionView(_ cv: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        let finish: () -> Void = { [weak self] in
            guard let self, let a = self.afterMenu else { return }
            self.afterMenu = nil
            a()
        }
        if let animator { animator.addCompletion(finish) } else { finish() }
    }

    /// The row's rounded fill, inside the list's insets, lifts for the menu.
    private func preview(_ configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let id = configuration.identifier as? String, let ip = dataSource.indexPath(for: id),
              let cell = cv.cellForItem(at: ip) else { return nil }
        let p = UIPreviewParameters()
        p.visiblePath = UIBezierPath(roundedRect: cell.bounds.insetBy(dx: Metric.rowInset, dy: 0), cornerRadius: Metric.rowRadius)
        p.backgroundColor = UIColor(palette.base)
        return UITargetedPreview(view: cell, parameters: p)
    }

    func collectionView(_ cv: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt ip: IndexPath) -> UITargetedPreview? { preview(configuration) }
    func collectionView(_ cv: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt ip: IndexPath) -> UITargetedPreview? { preview(configuration) }

    // MARK: Drag: our own press and gap

    private struct DragState {
        var id: String
        /// The dragged row's height: the gap's.
        var height: CGFloat
        /// The finger's offset from the row's top-left corner at lift (the copy keeps it, in x and y).
        var grab: CGPoint
        /// The slot among the other items (nil: none to take).
        var slot: Int?
        /// The last slot the gap was open at: a new one ticks.
        var ticked: Int?
    }

    /// The drag under way: the finger has moved since the lift, and the gap is open.
    private var drag: DragState?
    /// The list lifted at the hold, before the finger has moved: its menu may still open.
    private var held: DragState?
    /// The finger's place at the lift, in the window.
    private var liftPoint: CGPoint = .zero
    /// The dropped row, kept hidden while the copy flies into its place.
    private var landing: String?
    /// The copy setting down, and a count that tells its end from a later one's.
    private var landingCopy: UIView?
    private var landings = 0
    /// Our lifted copy (`DragCopy.make`, the task lists').
    private var copyView: UIView?
    private var press: PressDrag?
    private let feel = DragFeel()
    private var edge = EdgeScroll()
    private var gap = DragGap()
    /// Ticks from the lift to the release, so the copy follows the finger every frame, and the edge autoscroll.
    private var link: CADisplayLink?

    private func installDrag() {
        let p = PressDrag(target: self, action: #selector(pressed(_:)))
        p.canLift = { [weak self] at in self?.list(at: at) != nil }
        p.touched = { [weak self] in
            guard let self else { return }
            self.feel.prepare(in: self.cv)
            #if DEBUG || PERF_PROBE
            DragProbe.shared.pressed(self.cv)
            #endif
        }
        cv.addGestureRecognizer(p)
        press = p
    }

    /// A cell's place while a drag is on: hidden (the dragged row), or moved by `dy`. Nil: no drag.
    fileprivate func gapShift(_ id: String) -> (hide: Bool, dy: CGFloat)? {
        if id == landing { return (true, 0) }
        guard let d = drag, let from = current.firstIndex(of: d.id), let i = current.firstIndex(of: id) else { return nil }
        if i == from { return (true, 0) }
        let o = i > from ? i - 1 : i
        var dy: CGFloat = i > from ? -d.height : 0
        if let s = d.slot, o >= s { dy += d.height }
        return (false, dy)
    }

    fileprivate var gapOn: Bool { drag != nil || landing != nil }

    /// The slots a list may take, with the y the gap would open at (in the items without the dragged row): after the
    /// top edge, after each other list.
    private func slotTops(_ d: DragState) -> [(slot: Int, y: CGFloat)] {
        guard let from = current.firstIndex(of: d.id) else { return [] }
        let others = current.filter { $0 != d.id }
        guard let top = others.firstIndex(of: "e:top"), let end = others.firstIndex(of: "e:end"), top < end else { return [] }
        return (top + 1...end).compactMap { s in slotY(d, s, others: others, from: from).map { (s, $0) } }
    }

    /// The gap's top at slot `s`: under the row before it.
    private func slotY(_ d: DragState, _ s: Int, others: [String], from: Int) -> CGFloat? {
        guard s >= 1, s <= others.count, let i = current.firstIndex(of: others[s - 1]), let f = layout.modelFrame(i) else { return nil }
        return f.maxY - (i > from ? d.height : 0)
    }

    /// Each frame from the lift: the copy follows the finger in x and y, keeping the grab offset, its y kept within 6pt
    /// of the first and last slot; once the drag has begun, the list scrolls at its edges, and the gap follows the
    /// copy's y, at the slot whose top is nearest the copy's. A new slot ticks. As the task lists' (CollectionDrag.follow).
    private func follow() {
        guard let base = drag ?? held, let g = press else { return }
        let t0 = Perf.begin(.follow)
        defer { Perf.end(.follow, t0) }
        if drag != nil { edge.scroll(cv, finger: g.location(in: cv), foot: cv.contentInset.bottom) }
        Perf.measure(.layout) { cv.layoutIfNeeded() }
        var d = drag ?? base
        let tops = slotTops(d)
        let finger = g.location(in: cv)
        var copyTop = finger.y - d.grab.y
        if let lo = tops.map(\.y).min(), let hi = tops.map(\.y).max() { copyTop = min(max(copyTop, lo - 6), hi + 6) }
        if let v = copyView {
            UIView.performWithoutAnimation { v.frame.origin = CGPoint(x: finger.x - d.grab.x + Metric.rowInset, y: copyTop) }
        }
        guard drag != nil else { return }
        // Wherever the finger is (over the floating bar, or off the list), the gap stays at the slot nearest the copy:
        // letting go drops at the last slot shown, as the task lists' (CollectionDrag.follow).
        let s = tops.min { abs($0.y - copyTop) < abs($1.y - copyTop) }?.slot
        if let s, s != d.ticked {
            d.ticked = s
            drag = d
            feel.moved()
        }
        guard s != d.slot else { return }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.slot(s, was: d.slot, copyTop: copyTop)
        #endif
        d.slot = s
        drag = d
        moveGap(animated: true)
    }

    /// Each shown cell's transform for the gap, set directly (an invalidated layout would measure every hosting cell
    /// again), on Motion.layout's spring. A cell that comes into view takes its place in `HomeCell.apply`.
    private func moveGap(animated: Bool) {
        let t0 = Perf.begin(.moveGap)
        defer { Perf.end(.moveGap, t0) }
        let pad = drag?.height ?? 0
        let grew = pad > layout.pad
        layout.pad = pad
        if grew { DragGap.reach(cv) }
        let body = {
            for case let c as HomeCell in self.cv.subviews where !c.isHidden { c.placeForGap() }
        }
        CATransaction.begin()
        if animated, !UIAccessibility.isReduceMotionEnabled {
            gap.moved()
            UIView.animate(springDuration: DragGap.spring, bounce: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: body)
        } else {
            UIView.performWithoutAnimation(body)
        }
        CATransaction.commit()
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

    /// The list a press at `p` (in the list) would lift: only lists move, one at a time.
    private func list(at p: CGPoint) -> (id: String, ip: IndexPath)? {
        guard drag == nil, held == nil, let ip = cv.indexPathForItem(at: p), let id = dataSource.itemIdentifier(for: ip),
              id.hasPrefix("l:") else { return nil }
        return (id, ip)
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

    /// The hold: our copy lifts in place, on the row's exact frame, with a haptic, and follows the finger from here. As
    /// the task lists' (CollectionDrag.lift).
    private func lift(_ g: PressDrag) {
        endLanding()
        let p = g.location(in: cv)
        guard let (id, ip) = list(at: p), let f = layout.modelFrame(ip.item) else { return }
        let d = DragState(id: id, height: f.height, grab: CGPoint(x: p.x - f.minX, y: p.y - f.minY), slot: ip.item, ticked: ip.item)
        makeCopy(d)
        guard let v = copyView else { return }
        held = d
        liftPoint = g.location(in: nil)
        if let cell = cv.cellForItem(at: ip) { DragMenu.release(cell) }
        feel.lifted(in: cv)
        #if DEBUG || PERF_PROBE
        probe("lift")
        DragProbe.shared.finger = { [weak g, weak cv] in
            guard let g, let cv, g.numberOfTouches > 0 else { return nil }
            return g.location(in: cv)
        }
        if let cell = cv.cellForItem(at: ip) {
            DragProbe.shared.held(v, on: cell)
            DragProbe.shared.lift(cv) { [weak self] in self?.dataSource.indexPath(for: id).flatMap { self?.cv.cellForItem(at: $0) } }
        }
        #endif
        startLink()
    }

    /// Past `PressDrag.slop` from where it lifted, the drag begins: the list's menu won't open for this touch, and the
    /// dragged row leaves its place (the gap stays where it was).
    private func moved(_ g: PressDrag) {
        guard let d = held else { return }
        let w = g.location(in: nil)
        guard hypot(w.x - liftPoint.x, w.y - liftPoint.y) > PressDrag.slop else { return }
        held = nil
        guard let at = current.firstIndex(of: d.id) else { release(drop: false); return }
        var b = d
        b.slot = at
        b.ticked = at
        drag = b
        DragMenu.cut(cv, keeping: press)
        #if DEBUG || PERF_PROBE
        probe("begin")
        FrameProbe.dragBegan()
        #endif
        moveGap(animated: false)
    }

    /// The finger lifted (`drop`), or the touch was taken from us: a drag drops at its slot (or goes home); a lift that
    /// never moved sets down on its row.
    private func release(drop: Bool) {
        if let d = held {
            held = nil
            stopLink()
            probe("holdDown")
            land(at: current.firstIndex(of: d.id).flatMap { layout.modelFrame($0) }, id: d.id)
            return
        }
        guard drag != nil else { stopLink(); settle(); return }
        follow()
        stopLink()
        if drop, let d = drag, moves(d) {
            probe("drop")
            land(at: write(d), id: d.id)
        } else {
            goHome()
        }
        settle()
    }

    /// The list's menu opened (a still hold): the copy fades where it is (150 ms), under the menu's own preview.
    private func menuOpened() {
        if held != nil, let v = copyView {
            held = nil
            copyView = nil
            stopLink()
            probe("holdMenu")
            DragCopy.setDown(v, at: nil) {}
            settle()
        } else if drag != nil {
            cv.contextMenuInteraction?.dismissMenu()
        }
    }

    func collectionView(_ cv: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        probe("menu")
        menuOpened()
    }

    /// The drag ended with no drop (refused: let go at the row's own place; or the touch was taken): the copy flies
    /// home, the gap there closes, and the row shows under it.
    private func goHome() {
        guard let d = drag else { return }
        let home = current.firstIndex(of: d.id).flatMap { layout.modelFrame($0) }
        drag = nil
        landing = d.id
        probe("home")
        moveGap(animated: true)
        land(at: home, id: d.id)
    }

    /// The gap is at a new place: a drop there writes.
    private func moves(_ d: DragState) -> Bool {
        guard let s = d.slot, let i = current.firstIndex(of: d.id) else { return false }
        return s != i
    }

    /// VoiceOver's "Move Up" and "Move Down" on a list: dropped at the slot before or after its own, as a drag would.
    fileprivate func voiceOverMove(_ id: String, by step: Int) -> Bool {
        guard drag == nil, held == nil, landing == nil, let at = current.firstIndex(of: id), let f = layout.modelFrame(at) else { return false }
        var d = DragState(id: id, height: f.height, grab: .zero, slot: at, ticked: at)
        let slots = slotTops(d).map(\.slot)
        guard let next = step < 0 ? slots.last(where: { $0 < at }) : slots.first(where: { $0 > at }) else { return false }
        d.slot = next
        drag = d
        _ = write(d)
        landing = nil
        moveGap(animated: false)
        settle()
        return true
    }

    /// The drop at the gap: written (AppModel.dropList), the new order applied at once, the dropped row hidden under
    /// the copy. Its frame, where the copy sets down (nil: it has gone).
    private func write(_ d: DragState) -> CGRect? {
        guard let src = current.firstIndex(of: d.id), let top = current.firstIndex(of: "e:top"),
              let end = current.firstIndex(of: "e:end") else {
            drag = nil
            return nil
        }
        // The lists' run, as `.onMove` gives it: the edges (nil), the lists.
        let run = Array(current[top...end])
        let from = src - top
        // The slot among the others is an index in the run without the dragged row (the run starts at the same place).
        let at = (d.slot ?? src) - top
        let to = at < from ? at : at + 1
        let ids: [EntityID?] = run.map { $0.hasPrefix("l:") ? String($0.dropFirst(2)) : nil }
        if app.dropList(IndexSet(integer: from), to, in: ids) { feel.dropped() }
        wanted = HomeCollection.items(app)
        landing = d.id
        drag = nil
        // The new order, at once: every row's drawn place is the same (the gap was the dropped row's place).
        UIView.performWithoutAnimation {
            apply(wanted, animated: false)
            moveGap(animated: false)
        }
        guard let ip = dataSource.indexPath(for: d.id) else { return nil }
        return layout.modelFrame(ip.item)
    }

    /// Debug only: the call, in DragProbe's log (`-dragProbe`).
    private func probe(_ s: String) {
        #if DEBUG || PERF_PROBE
        DragProbe.shared.call(s, in: cv)
        #endif
    }

    // MARK: The lifted copy

    private func makeCopy(_ d: DragState) {
        guard let i = current.firstIndex(of: d.id), let cell = cv.cellForItem(at: IndexPath(item: i, section: 0)),
              let v = DragCopy.make(of: cell, palette: palette) else { return }
        cv.addSubview(v)
        copyView = v
        #if DEBUG || PERF_PROBE
        let id = d.id
        DragProbe.shared.trace(copy: v) { [weak self] in
            guard let self, let ip = self.dataSource.indexPath(for: id) else { return nil }
            return self.cv.cellForItem(at: ip)
        }
        #endif
    }

    /// The copy sets down on the row's `frame` (`DragCopy.setDown`), and the row `id` shows under it.
    private func land(at frame: CGRect?, id: String) {
        let done: () -> Void = { [weak self] in
            guard let self else { return }
            self.landing = nil
            self.moveGap(animated: false)
            self.settle()
        }
        guard let v = copyView else { done(); return }
        copyView = nil
        landings += 1
        let n = landings
        landingCopy = v
        let origin = frame.map { CGPoint(x: $0.minX + Metric.rowInset, y: $0.minY) }
        #if DEBUG || PERF_PROBE
        DragProbe.shared.released(v, home: origin)
        #endif
        DragCopy.setDown(v, at: origin, gap: gap.left) { [weak self] in
            guard let self, self.landings == n else { return }
            #if DEBUG || PERF_PROBE
            if let ip = self.dataSource.indexPath(for: id) { DragProbe.shared.landed(v, on: self.cv.cellForItem(at: ip)) }
            #endif
            self.landingCopy = nil
            done()
        }
    }

    /// A new lift while a copy still sets down: it ends now.
    private func endLanding() {
        guard let v = landingCopy else { return }
        landingCopy = nil
        landings += 1
        v.layer.removeAllAnimations()
        v.removeFromSuperview()
        landing = nil
        moveGap(animated: false)
        settle()
    }
}

// MARK: - The layout

/// The list layout, reaching past the shown rect by the gap's height during a drag, so a row the gap moves into view
/// is there to move.
final class HomeLayout: UICollectionViewCompositionalLayout {
    var pad: CGFloat = 0

    /// An item's frame as the list lays it out (no gap).
    func modelFrame(_ item: Int) -> CGRect? { super.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let pad = MainActor.assumeIsolated { self.pad }
        return super.layoutAttributesForElements(in: rect.insetBy(dx: 0, dy: -pad))
    }
}

// MARK: - Cells

final class HomeCell: UICollectionViewListCell {
    var itemID: String?
    weak var owner: HomeCollectionController?

    /// Its place for the drag's gap (`HomeCollectionController.gapShift`): hidden, or moved by a transform.
    func placeForGap() {
        let shift = MainActor.assumeIsolated { itemID.flatMap { owner?.gapShift($0) } }
        transform = CGAffineTransform(translationX: 0, y: shift?.dy ?? 0)
        if let shift { contentView.alpha = shift.hide ? 0 : 1 } else if contentView.alpha == 0 { contentView.alpha = 1 }
    }

    override func apply(_ a: UICollectionViewLayoutAttributes) {
        let t0 = MainActor.assumeIsolated { Perf.begin(.cellApply) }
        defer { MainActor.assumeIsolated { Perf.end(.cellApply, t0) } }
        super.apply(a)
        // Laid out again (or into view) mid-drag, it takes its place in the gap again.
        let gap = MainActor.assumeIsolated { owner?.gapOn ?? false }
        if gap, a.transform == .identity { placeForGap() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        contentView.alpha = 1
    }

    override func layoutSubviews() {
        let t0 = MainActor.assumeIsolated { Perf.begin(.cellLayout) }
        defer { MainActor.assumeIsolated { Perf.end(.cellLayout, t0) } }
        super.layoutSubviews()
    }

    override func preferredLayoutAttributesFitting(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let t0 = MainActor.assumeIsolated { Perf.begin(.cellSize) }
        defer { MainActor.assumeIsolated { Perf.end(.cellSize, t0) } }
        return super.preferredLayoutAttributesFitting(a)
    }
}
