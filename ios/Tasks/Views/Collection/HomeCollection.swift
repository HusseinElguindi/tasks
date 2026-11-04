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
// Lists reorder by drag (§14), on our own gap, as the spikes found works (memory: uicollectionview-spike-findings):
// the drop delegate answers `.unspecified`, so the collection view never moves a cell itself; the dragged row is hidden
// by its content's alpha, the others move by transforms to open a gap at our slot, and our own lifted copy follows the
// finger, held to the first and last slot. The slots are the lists' run only, from just under "Lists" to the end of
// the lists, so Today and the views never move. The drop is `AppModel.dropList`, given the run as `.onMove` gives it
// (edges included, as nil). A drop at the row's own place is refused, so the copy flies home and nothing is written.

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
            if id.hasPrefix("l:") { SourceRow(source: .list(String(id.dropFirst(2))), sidebar: sidebar) }
        }
    }
}

// MARK: - The controller

@MainActor
final class HomeCollectionController: UIViewController, UICollectionViewDelegate, UICollectionViewDragDelegate,
    UICollectionViewDropDelegate {
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
        cv.dragDelegate = self
        cv.dropDelegate = self
        cv.dragInteractionEnabled = true
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
    }

    func stop() {
        copyView?.removeFromSuperview()
        copyView = nil
    }

    // MARK: Cells

    private func configure(_ cell: HomeCell, _ id: String) {
        cell.itemID = id
        cell.owner = self
        cell.backgroundConfiguration = .clear()
        // Nothing here holds the controller: the cells are its view's.
        let app = app, sidebar = sidebar
        cell.contentConfiguration = UIHostingConfiguration {
            HomeLine(id: id, sidebar: sidebar).modifier(CellTheme(app: app))
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

    /// A drag, or its copy's landing, holds updates back: they're applied at its end (`settle`).
    private var holds: Bool { drag != nil || landing != nil }

    func update(_ items: [String], animated: Bool) {
        wanted = items
        guard !holds else { return }
        apply(items, animated: animated)
    }

    /// The items, at once, or on Motion.layout's spring (a list added, deleted or restored, the sync line).
    private func apply(_ items: [String], animated: Bool) {
        guard items != current else { return }
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

    // MARK: Drag: our own gap

    private struct DragState {
        var id: String
        /// The dragged row's height: the gap's.
        var height: CGFloat
        /// The finger's distance below the row's top at lift.
        var grab: CGFloat
        /// The slot among the other items (nil: no gap, the finger is off the list).
        var slot: Int?
    }

    private var drag: DragState?
    /// The dropped row, kept hidden while the copy flies into its place.
    private var landing: String?
    private weak var dragSession: UIDragSession?
    private weak var dropSession: UIDropSession?
    /// Our lifted copy: `fill-lift`, radius 8, a shadow, the row's snapshot.
    private var copyView: UIView?

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

    fileprivate var gapOn: Bool { holds }

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

    /// The copy follows the finger, kept within 6pt of the first and last slot; over the list, the gap follows the
    /// copy, at the slot whose top is nearest the copy's.
    private func follow() {
        guard var d = drag, let session = dragSession else { return }
        cv.layoutIfNeeded()
        let tops = slotTops(d)
        var copyTop = session.location(in: cv).y - d.grab
        if let lo = tops.map(\.y).min(), let hi = tops.map(\.y).max() { copyTop = min(max(copyTop, lo - 6), hi + 6) }
        if let v = copyView, landing == nil { UIView.performWithoutAnimation { v.frame.origin.y = copyTop } }
        guard dropSession != nil else { return }
        let s = tops.min { abs($0.y - copyTop) < abs($1.y - copyTop) }?.slot
        guard s != d.slot else { return }
        d.slot = s
        drag = d
        moveGap(animated: true)
    }

    /// Each shown cell's transform for the gap, set directly (an invalidated layout would measure every hosting cell
    /// again), on Motion.layout's spring. A cell that comes into view takes its place in `HomeCell.apply`.
    private func moveGap(animated: Bool) {
        layout.pad = drag?.height ?? 0
        let body = {
            for case let c as HomeCell in self.cv.subviews where !c.isHidden { c.placeForGap() }
        }
        CATransaction.begin()
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(springDuration: 0.25, bounce: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: body)
        } else {
            UIView.performWithoutAnimation(body)
        }
        CATransaction.commit()
    }

    func collectionView(_ cv: UICollectionView, itemsForBeginning session: UIDragSession, at ip: IndexPath) -> [UIDragItem] {
        guard !holds, let id = dataSource.itemIdentifier(for: ip), id.hasPrefix("l:"), let f = layout.modelFrame(ip.item) else { return [] }
        let p = session.location(in: cv)
        let item = UIDragItem(itemProvider: NSItemProvider())
        // The system's copy is invisible once lifted: ours is drawn instead.
        item.previewProvider = {
            let p = UIDragPreviewParameters()
            p.backgroundColor = .clear
            p.shadowPath = UIBezierPath()
            return UIDragPreview(view: UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)), parameters: p)
        }
        item.localObject = id
        drag = DragState(id: id, height: f.height, grab: p.y - f.minY, slot: ip.item)
        return [item]
    }

    func collectionView(_ cv: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

    func collectionView(_ cv: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        guard let d = drag else { return }
        dragSession = session
        makeCopy(d)
        // The dragged row leaves its place (the gap stays where it was).
        moveGap(animated: false)
    }

    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        dragSession = nil
        // A refused drop went home at the drop session's end already; this is a fallback (a drag that never entered).
        goHome()
        settle()
    }

    func collectionView(_ cv: UICollectionView, dragPreviewParametersForItemAt ip: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = cv.cellForItem(at: ip) else { return nil }
        let p = UIDragPreviewParameters()
        p.visiblePath = UIBezierPath(roundedRect: cell.bounds.insetBy(dx: Metric.rowInset, dy: 0), cornerRadius: Metric.rowRadius)
        p.backgroundColor = UIColor(palette.base)
        return p
    }

    /// The drag ended with no drop (refused at the row's own place, or the finger off the list): the copy flies home,
    /// the gap there closes, and the row shows under it. At the finger's lift, not after UIKit's set-down of the
    /// refused drop (about a second, memory: uicollectionview-spike-findings).
    private func goHome() {
        guard let d = drag else { return }
        let home = current.firstIndex(of: d.id).flatMap { layout.modelFrame($0) }
        drag = nil
        landing = d.id
        moveGap(animated: true)
        land(at: home)
    }

    // MARK: Drop

    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil && drag != nil
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath dest: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil, drag != nil else { return UICollectionViewDropProposal(operation: .forbidden) }
        dropSession = session
        follow()
        // At its own place the drop is refused, so it goes back as a cancel and writes nothing.
        let own = drag.map { $0.slot == current.firstIndex(of: $0.id) } == true
        return UICollectionViewDropProposal(operation: own ? .cancel : .move, intent: .unspecified)
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidExit session: UIDropSession) {
        dropSession = nil
        guard drag?.slot != nil else { return }
        drag?.slot = nil
        moveGap(animated: true)
    }

    func collectionView(_ cv: UICollectionView, performDropWith c: UICollectionViewDropCoordinator) {
        dropSession = nil
        guard let item = c.items.first, let d = drag, let src = current.firstIndex(of: d.id),
              let top = current.firstIndex(of: "e:top"), let end = current.firstIndex(of: "e:end") else { return }
        // The lists' run, as `.onMove` gives it: the edges (nil), the lists.
        let run = Array(current[top...end])
        let from = src - top
        // The slot among the others is an index in the run without the dragged row (the run starts at the same place).
        let at = (d.slot ?? src) - top
        let to = at < from ? at : at + 1
        let ids: [EntityID?] = run.map { $0.hasPrefix("l:") ? String($0.dropFirst(2)) : nil }
        if app.dropList(IndexSet(integer: from), to, in: ids) {
            UIImpactFeedbackGenerator(style: .light, view: cv).impactOccurred()
        }
        wanted = HomeCollection.items(app)
        landing = d.id
        drag = nil
        // The new order, at once: every row's drawn place is the same (the gap was the dropped row's place).
        UIView.performWithoutAnimation {
            apply(wanted, animated: false)
            moveGap(animated: false)
        }
        guard let ip = dataSource.indexPath(for: d.id) else {
            landing = nil
            moveGap(animated: false)
            settle()
            return
        }
        c.drop(item.dragItem, toItemAt: ip)
        land(at: layout.modelFrame(ip.item))
    }

    func collectionView(_ cv: UICollectionView, dropSessionDidEnd session: UIDropSession) {
        dropSession = nil
        // The finger lifted with no drop performed: the drop was refused, or the finger was off the list.
        goHome()
    }

    // MARK: The lifted copy

    private func makeCopy(_ d: DragState) {
        guard let i = current.firstIndex(of: d.id), let cell = cv.cellForItem(at: IndexPath(item: i, section: 0)),
              let snap = cell.snapshotView(afterScreenUpdates: false) else { return }
        let inset = Metric.rowInset
        let v = UIView(frame: cell.frame.insetBy(dx: inset, dy: 0))
        v.backgroundColor = UIColor(palette.lift)
        v.layer.cornerRadius = 8
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.35
        v.layer.shadowRadius = 10
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
        let clip = UIView(frame: v.bounds)
        clip.clipsToBounds = true
        clip.layer.cornerRadius = 8
        snap.frame.origin = CGPoint(x: -inset, y: 0)
        clip.addSubview(snap)
        v.addSubview(clip)
        v.layer.zPosition = 1000
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true
        cv.addSubview(v)
        copyView = v
    }

    /// The copy sets down at `frame` (`DragCopy.setDown`), and the row shows under it.
    private func land(at frame: CGRect?) {
        let done: () -> Void = { [weak self] in
            guard let self else { return }
            self.landing = nil
            self.moveGap(animated: false)
            self.settle()
        }
        guard let v = copyView else { done(); return }
        copyView = nil
        DragCopy.setDown(v, at: frame?.minY, landed: done)
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
    /// UIKit's drag state of this cell (`dragStateDidChange`).
    private var uikitDrag: UICollectionViewCell.DragState = .none

    /// While UIKit has this cell in a drag, its alpha stays 1: UIKit draws the dragged cell at half alpha, a ghost of
    /// the row in our gap. Our drag hides the row by its content's alpha instead (`placeForGap`), which UIKit leaves.
    override var alpha: CGFloat {
        get { super.alpha }
        set { super.alpha = uikitDrag == .none ? newValue : 1 }
    }

    override func dragStateDidChange(_ s: UICollectionViewCell.DragState) {
        uikitDrag = s
        super.dragStateDidChange(s)
    }

    /// Its place for the drag's gap (`HomeCollectionController.gapShift`): hidden, or moved by a transform.
    func placeForGap() {
        let shift = MainActor.assumeIsolated { itemID.flatMap { owner?.gapShift($0) } }
        transform = CGAffineTransform(translationX: 0, y: shift?.dy ?? 0)
        if let shift { contentView.alpha = shift.hide ? 0 : 1 } else if contentView.alpha == 0 { contentView.alpha = 1 }
    }

    override func apply(_ a: UICollectionViewLayoutAttributes) {
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
}
