import SwiftUI
import TasksCore
import UIKit

// The iPhone's lists on a UICollectionView, in place of SwiftUI List (the migration on branch ios-cv; its plan is
// coord's migration-plan.md). List can't draw §23's fold, our own drag gap or an edit's height on the design's curves
// (memory: swiftui-list-motion-limits); a collection view can (the spikes on ios-spike and ios-spike-drag).
//
// The core is this file: the representable ListScreen uses, the controller with its data source, the snapshot apply,
// the cell registration, scrolling, the keyboard inset and the floating controls' clearance. Each area has a file of
// its own, with its state in a class of its own that the controller holds, and hooks the core calls:
//   TaskCollection+Fold.swift      CollectionFold      a heading folding or opening (§23)
//   TaskCollection+Editing.swift   CollectionEditing   rows whose height changes as they're typed into
//   TaskCollection+Swipes.swift    CollectionSwipes    swipe actions and long-press menus
//   TaskCollection+Drag.swift      CollectionDrag      drag to reorder: our own press, gap and lifted copy (§14, §22)
//   TaskCollection+Select.swift    CollectionSelect    select mode (§3)
//   TaskCollection+Screens.swift   CollectionLine      each line's SwiftUI row, per screen
//
// Items are strings, from the app's `Line`s (`items`): "banner" (a deleted list's), "header", then a line's id ("g:",
// "t:", "c:", "dl:", "draft", "empty", "allDone"), except that a heading is "h:<id>" and its notes are always an item of
// their own, "n:<id>" (`Line.heading(notes:)` and `Line.headingNotes` both). Edge lines are left out: their air is
// drawn in the row below them (a heading's, a label's, Completed's own `top`).

/// What the cells read as they draw: each item's line, kept after it goes so a row keeps its content while it leaves.
///
/// One observed box per item, written only when that item's line changed (`Line.cellKey`): a row redraws for its own
/// changes only. (Redrawing every row on every update made the list cells re-lay themselves out mid-fold, which
/// snapped the fold.) The controller's update runs inside the representable's update, where SwiftUI observes what's
/// read: so it only ever writes a box, never reads one, or each write would update it again, forever.
@MainActor
final class CollectionRows {
    @Observable final class Box {
        var line: Line
        init(_ line: Line) { self.line = line }
    }

    @Observable final class Stamp { var value = 0 }

    private var boxes: [String: Box] = [:]
    private var keys: [String: String] = [:]
    private let stamp = Stamp()
    private var count = 0

    /// Stamped each time the applied items change (observed): what depends on a row's neighbours reads it, as select
    /// mode's joined fill does. Rows that don't, don't redraw then.
    var version: Int { stamp.value }

    /// The applied items changed (written only, never read, in the update).
    func itemsChanged() {
        count += 1
        stamp.value = count
    }

    /// An item's line (observed: the row redraws when it changes).
    func line(_ id: String) -> Line? { boxes[id]?.line }

    /// New lines over the old: the old stay, for rows that are leaving.
    func merge(_ new: [String: Line]) {
        for (id, line) in new {
            let key = line.cellKey
            if let box = boxes[id] {
                guard keys[id] != key else { continue }
                box.line = line
            } else {
                boxes[id] = Box(line)
            }
            keys[id] = key
        }
    }

    /// Drops the lines of items no longer shown.
    func keep(_ ids: Set<String>) {
        guard boxes.keys.contains(where: { !ids.contains($0) }) else { return }
        boxes = boxes.filter { ids.contains($0.key) }
        keys = keys.filter { ids.contains($0.key) }
    }

    /// Today's all-done sun (ListScreen's `sunRise`).
    var sunRise: Binding<Bool> = .constant(false)
}

extension Line {
    /// What a row draws from its line beyond its task's, heading's or list's own fields (which the row observes):
    /// equal keys draw the same.
    var cellKey: String {
        func d(_ c: CalendarDate?) -> String { c.map { String(describing: $0) } ?? "-" }
        switch self {
        case let .group(key, title, sub, quiet): return "g|\(key)|\(title)|\(sub ?? "-")|\(quiet)"
        case let .heading(h, count, notes): return "h|\(ObjectIdentifier(h).hashValue)|\(count)|\(notes)"
        case let .headingNotes(h): return "n|\(ObjectIdentifier(h).hashValue)"
        case let .task(t, indent, groupDay, day): return "t|\(ObjectIdentifier(t).hashValue)|\(indent)|\(d(groupDay))|\(d(day))"
        case let .completedToggle(key, count, open): return "c|\(key)|\(count)|\(open)"
        case let .deletedList(l, count, open, day): return "dl|\(ObjectIdentifier(l).hashValue)|\(count)|\(open)|\(d(day))"
        case .draft: return "draft"
        case let .empty(title, message, symbol): return "e|\(title)|\(message)|\(symbol)"
        case .allDone: return "allDone"
        case let .edge(key, height): return "edge|\(key)|\(height)"
        }
    }
}

/// ListScreen's handle on the collection, for what ScrollViewReader does for List.
@MainActor
final class CollectionProxy {
    weak var controller: TaskCollectionController?

    /// Scrolls the item into view: the least that shows it, or `center`ed.
    func scrollTo(_ id: String, center: Bool = false) { controller?.scroll(to: id, center: center) }
}

struct TaskCollection: UIViewControllerRepresentable {
    let source: Source
    let lines: [Line]
    /// Each resizable row's height signature (`TaskCollection.signatures`, read in ListScreen's body).
    let sizes: [String: String]
    let proxy: CollectionProxy
    /// The large title has gone under the bar.
    let folded: Binding<Bool>
    let sunRise: Binding<Bool>
    @Environment(AppModel.self) private var app

    func makeUIViewController(context: Context) -> TaskCollectionController {
        TaskCollectionController(app: app, source: source)
    }

    func updateUIViewController(_ c: TaskCollectionController, context: Context) {
        proxy.controller = c
        let folded = folded
        c.onFold = { if folded.wrappedValue != $0 { folded.wrappedValue = $0 } }
        c.rows.sunRise = sunRise
        let t = context.transaction
        c.update(lines, sizes: sizes, animation: t.disablesAnimations ? nil : t.animation)
    }

    static func dismantleUIViewController(_ c: TaskCollectionController, coordinator: ()) { c.stop() }

    /// The items of a screen's lines (above), and the line each draws.
    @MainActor static func items(_ lines: [Line], banner: Bool) -> (ids: [String], lines: [String: Line]) {
        var ids: [String] = banner ? ["banner", "header"] : ["header"]
        var map: [String: Line] = [:]
        var seen = Set(ids)
        func add(_ id: String, _ line: Line) {
            guard seen.insert(id).inserted else { return }
            ids.append(id)
            map[id] = line
        }
        for line in lines {
            switch line {
            case .edge: continue
            case let .heading(h, count, notes):
                add("h:" + h.id, .heading(h, openCount: count, notes: false))
                if notes { add("n:" + h.id, .headingNotes(h)) }
            case let .headingNotes(h): add("n:" + h.id, line)
            default: add(line.id, line)
            }
        }
        return (ids, map)
    }
}

// MARK: - The controller

@MainActor
final class TaskCollectionController: UIViewController, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    let app: AppModel
    let source: Source
    let rows = CollectionRows()
    private(set) var cv: UICollectionView!
    private(set) var layout: CollectionLayout!
    private(set) var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    /// The items applied, and the latest asked for (applied unless an area holds updates back, as a drag does).
    private(set) var current: [String] = []
    private(set) var wanted: [String] = []
    /// Items the last apply inserted.
    private(set) var justInserted: Set<String> = []
    /// Each resizable row's height signature as last configured (`CollectionEditing`).
    var sizes: [String: String] = [:]
    var onFold: (Bool) -> Void = { _ in }

    // The areas (the files above). Each holds its own state.
    private(set) lazy var fold = CollectionFold(owner: self)
    private(set) lazy var editor = CollectionEditing(owner: self)
    private(set) lazy var swipes = CollectionSwipes(owner: self)
    private(set) lazy var drag = CollectionDrag(owner: self)
    private(set) lazy var select = CollectionSelect(owner: self)

    init(app: AppModel, source: Source) {
        self.app = app
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    var dark: Bool { app.appearance == .system ? traitCollection.userInterfaceStyle == .dark : app.appearance == .dark }
    var palette: Palette { Palette.make(dark: dark) }
    /// Space under the last row, clear of the floating bar and the +.
    var bottomClearance: CGFloat { app.isSplit ? 24 : Metric.bottomClearance }

    override func loadView() {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipes.actions(ip, leading: true) }
        config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in self?.swipes.actions(ip, leading: false) }
        let layout = CollectionLayout { _, env in NSCollectionLayoutSection.list(using: config, layoutEnvironment: env) }
        layout.owner = self
        self.layout = layout
        let cv = TaskCollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.allowsSelection = false
        cv.delegate = self
        cv.keyboardDismissMode = .onDrag
        // It pulls down even when the rows fit: to refresh, and to put the keyboard away.
        cv.alwaysBounceVertical = true
        // A row's press shows the moment a finger lands.
        cv.delaysContentTouches = false
        // A row's height changes only when it's reconfigured, inside an animation (`CollectionEditing.resize`):
        // self-sizing on its own snaps, and races the updates' animations.
        cv.selfSizingInvalidation = .disabled
        self.cv = cv
        updateBottomInset()

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task { @MainActor in
                await self?.app.syncNow()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        cv.refreshControl = refresh

        // While adding, a tap outside the row being typed into ends adding. On a row it goes no further (the row's
        // `endsAddingOnTap`); this catches the rest, the list's empty space.
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        cv.addGestureRecognizer(tap)

        let reg = UICollectionView.CellRegistration<TaskCell, String> { [weak self] cell, _, id in self?.configure(cell, id) }
        dataSource = UICollectionViewDiffableDataSource(collectionView: cv) { cv, ip, id in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: id)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.reconfigureAll() }
        view = cv
        fold.install()
        editor.install()
        swipes.install()
        drag.install()
        select.install()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        drag.stop()
        select.stop()
    }

    // MARK: Cells

    private func configure(_ cell: TaskCell, _ id: String) {
        let t0 = Perf.begin(.configure)
        defer { Perf.end(.configure, t0) }
        cell.itemID = id
        cell.owner = self
        cell.backgroundConfiguration = .clear()
        // Nothing here holds the controller: the cells are its view's.
        let app = app, source = source, rows = rows, state = sizes[id]
        weak let owner = self
        cell.contentConfiguration = UIHostingConfiguration {
            CollectionLine(id: id, source: source, rows: rows, state: state, owner: owner).modifier(CellTheme(app: app))
                // One identity per task, so a reused cell starts fresh: its box sees no "change" and gives no haptic.
                .id(id)
        }
        .margins(.horizontal, Metric.rowInset)
        .margins(.vertical, 0)
        .minSize(width: nil, height: 0)
        drag.configured(cell)
    }

    /// Every shown row configured again, e.g. for a new text size.
    func reconfigureAll() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
    }

    fileprivate func cellDidApply(_ cell: TaskCell, _ a: UICollectionViewLayoutAttributes) {
        fold.cellDidApply(cell, a)
        drag.cellDidApply(cell, a)
    }

    fileprivate func cellWillReuse(_ cell: TaskCell) {
        fold.reuse(cell)
        drag.reuse(cell)
    }

    // MARK: Applying

    func update(_ lines: [Line], sizes new: [String: String], animation: Animation?) {
        let made = TaskCollection.items(lines, banner: app.deletedList(source) != nil)
        // A row that goes keeps drawing its line while it leaves.
        rows.merge(made.lines)
        // New cells are configured with the new signatures; those already shown keep theirs until they're resized.
        let before = sizes
        sizes = before.merging(new.filter { !current.contains($0.key) }) { _, n in n }
        wanted = made.ids
        let fold = fold.plan(from: current, to: made.ids)
        let holding = drag.holdsUpdates
        if !holding { apply(made.ids, fold: fold, animation: animation) } else if let fold { heldFold = fold }
        let changed = new.keys.filter { new[$0] != before[$0] && before[$0] != nil && current.contains($0) && !justInserted.contains($0) }
        sizes = new
        if holding {
            // Resized once the drag lets updates through (`applyHeld`), from the signature it was drawn with.
            for k in changed where heldSizes[k] == nil { heldSizes[k] = before[k] }
        } else if !changed.isEmpty {
            editor.resize(changed.sorted(), from: before)
        }
        // Rows inserted by this update were configured with their new signatures; from the next one on, they resize.
        justInserted = []
    }

    /// What `update` held back while the drag held updates: the rows whose height changed meanwhile (with the
    /// signature each was drawn with), and the fold planned meanwhile (a heading collapsed or expanded).
    private var heldSizes: [String: String] = [:]
    private var heldFold: CollectionFold.Plan?

    /// Once the drag holds updates no more (its `settle`): the latest items, at once, or folding on the fold's curves
    /// when a fold was planned meanwhile and is still to be drawn; then the rows whose height changed meanwhile are
    /// resized (they kept the height they were drawn with: T27).
    func applyHeld(_ items: [String]) {
        let plan = heldFold.flatMap { p -> CollectionFold.Plan? in
            let was = !p.items.isDisjoint(with: current), now = !p.items.isDisjoint(with: items)
            return (p.collapse ? was && !now : !was && now) && current.contains(p.heading) && items.contains(p.heading) ? p : nil
        }
        heldFold = nil
        if items != current { apply(items, fold: plan, animation: plan == nil ? nil : .default) }
        let held = heldSizes
        heldSizes = [:]
        if !held.isEmpty { editor.resize(held.keys.sorted(), from: held) }
    }

    /// The items, at once (`animation` nil, or Reduce Motion), or animated: a fold on its own curves
    /// (`CollectionFold.animate`), anything else on Motion.layout's spring. `done` runs once the update has ended.
    func apply(_ items: [String], fold: CollectionFold.Plan? = nil, animation: Animation?, done: (() -> Void)? = nil) {
        guard items != current else { done?(); return }
        let t0 = Perf.begin(.apply)
        defer { Perf.end(.apply, t0) }
        let old = current
        current = items
        justInserted = Set(items).subtracting(old)
        rows.itemsChanged()
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(items)
        let finish: () -> Void = { [weak self] in
            self?.didApply()
            done?()
        }
        // One transaction, so every animation of the update is committed together (a hosting cell's first draw can
        // commit the inserted cells' animations a few ms before the moved ones').
        CATransaction.begin()
        defer { CATransaction.commit() }
        guard animation != nil, !old.isEmpty, !UIAccessibility.isReduceMotionEnabled else {
            self.fold.prepare(fold, old: old, animated: false)
            dataSource.apply(snap, animatingDifferences: false)
            finish()
            return
        }
        // SwiftUI may run this update inside performWithoutAnimation: it animates regardless.
        let was = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(was) }
        self.fold.prepare(fold, old: old, animated: true)
        if let fold, self.fold.animate(fold, snap, done: finish) {
            return
        }
        // The inherited curve and duration (SwiftUI's, around this update) are overridden: see TaskCollection+Fold.swift.
        UIView.animate(springDuration: 0.25, bounce: 0, initialSpringVelocity: 0, delay: 0,
                       options: [.overrideInheritedCurve, .overrideInheritedDuration]) {
            self.dataSource.apply(snap, animatingDifferences: true) { finish() }
        }
    }

    private func didApply() {
        fold.didApply()
        // Lines of rows that have gone, once they're off screen.
        rows.keep(Set(current))
    }

    /// An item's frame in the layout, with no transform of a drag's gap.
    func modelFrame(_ id: String) -> CGRect? {
        dataSource.indexPath(for: id).flatMap { layout.modelFrame($0.item) }
    }

    // MARK: Scrolling

    func scroll(to id: String, center: Bool) {
        guard let ip = dataSource.indexPath(for: id) else { return }
        cv.layoutIfNeeded()
        guard let f = layout.modelFrame(ip.item) else { return }
        let inset = cv.adjustedContentInset
        let top = cv.contentOffset.y + inset.top, bottom = cv.contentOffset.y + cv.bounds.height - inset.bottom
        var y = cv.contentOffset.y
        if center {
            y = f.midY - (inset.top + (cv.bounds.height - inset.top - inset.bottom) / 2)
        } else if f.minY < top {
            y -= top - f.minY
        } else if f.maxY > bottom {
            y += min(f.maxY - bottom, f.minY - top)
        } else {
            return
        }
        let lo = -inset.top, hi = max(lo, cv.contentSize.height + inset.bottom - cv.bounds.height)
        y = min(max(y, lo), hi)
        guard abs(y - cv.contentOffset.y) > 0.5 else { return }
        if UIAccessibility.isReduceMotionEnabled {
            cv.contentOffset.y = y
        } else {
            UIView.animate(springDuration: 0.25, bounce: 0) { self.cv.contentOffset.y = y }
        }
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        onFold(s.contentOffset.y + s.adjustedContentInset.top > 40)
        fold.didScroll()
    }

    /// A swipe on the list puts the keyboard away (`keyboardDismissMode`), which ends adding. A hosted row's focus
    /// doesn't always hear of it, so the drag ends adding itself.
    func scrollViewWillBeginDragging(_ s: UIScrollView) {
        if app.draft?.source == source { app.endDraft() }
    }

    /// What's under the last row: the floating controls' clearance, or the keyboard's height and some air, plus a
    /// fold's slack (`CollectionFold.slack`).
    private var keyboardInset: CGFloat = 0
    func updateBottomInset() {
        cv.contentInset.bottom = max(bottomClearance, keyboardInset) + fold.slack
    }

    // MARK: Taps while adding

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard app.draft?.source == source else { return }
        if let id = editor.item, let ip = dataSource.indexPath(for: id), let cell = cv.cellForItem(at: ip),
           cell.frame.contains(g.location(in: cv)) { return }
        app.endDraft()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard g is UITapGestureRecognizer else { return true }
        return app.draft?.source == source
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: The keyboard

    /// The bottom inset under the keyboard, on the keyboard's own curve (the collection view's size never changes), and
    /// the row being typed into scrolled above it.
    @objc private func keyboard(_ n: Notification) {
        guard let cv, let window = cv.window, let end = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = cv.convert(window.convert(end, from: nil), from: window)
        let under = max(0, cv.bounds.maxY - local.minY - cv.safeAreaInsets.bottom)
        let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 7
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: UInt(curve) << 16)) {
            self.keyboardInset = under > 0 ? under + 24 : 0
            self.updateBottomInset()
            cv.verticalScrollIndicatorInsets.bottom = under
        }
        if under > 0, let id = editor.item {
            DispatchQueue.main.async { [weak self] in self?.scroll(to: id, center: false) }
        }
    }
}

// MARK: - The layout

/// The list layout, with the areas' hooks: a fold's appearing and disappearing rows, and a drag gap's reach.
final class CollectionLayout: UICollectionViewCompositionalLayout {
    weak var owner: TaskCollectionController?

    private func on<T>(_ body: @MainActor (TaskCollectionController) -> T?) -> T? {
        MainActor.assumeIsolated { Unchecked(value: owner.flatMap(body)) }.value
    }

    /// An item's frame in the layout, as the list lays it out (no area's changes).
    func modelFrame(_ item: Int) -> CGRect? { base(IndexPath(item: item, section: 0))?.frame }
    func base(_ ip: IndexPath) -> UICollectionViewLayoutAttributes? { super.layoutAttributesForItem(at: ip) }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let pad = on { max($0.drag.layoutPad, $0.fold.layoutPad) } ?? 0
        return super.layoutAttributesForElements(in: rect.insetBy(dx: 0, dy: -pad))?.map(decorate)
    }

    override func layoutAttributesForItem(at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: ip).map(decorate)
    }

    private func decorate(_ a: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        on { $0.fold.decorate(a) } ?? a
    }

    override func initialLayoutAttributesForAppearingItem(at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        let a = super.initialLayoutAttributesForAppearingItem(at: ip)
        return on { $0.fold.initial(at: ip, a) } ?? a
    }

    override func finalLayoutAttributesForDisappearingItem(at ip: IndexPath) -> UICollectionViewLayoutAttributes? {
        let a = super.finalLayoutAttributesForDisappearingItem(at: ip)
        return on { $0.fold.final(at: ip, a) } ?? a
    }
}

// MARK: - Cells

final class TaskCell: UICollectionViewListCell {
    var itemID: String?
    weak var owner: TaskCollectionController?

    override func apply(_ a: UICollectionViewLayoutAttributes) {
        let t0 = MainActor.assumeIsolated { Perf.begin(.cellApply) }
        defer { MainActor.assumeIsolated { Perf.end(.cellApply, t0) } }
        super.apply(a)
        MainActor.assumeIsolated { owner?.cellDidApply(self, a) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        MainActor.assumeIsolated { owner?.cellWillReuse(self) }
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

/// A layout attributes object handed across `MainActor.assumeIsolated` (the layout's callers are on the main thread).
private struct Unchecked<T>: @unchecked Sendable { let value: T }

/// `Themed` without `preferredColorScheme`, for a cell's content (the scheme comes from the window's traits).
struct CellTheme: ViewModifier {
    let app: AppModel
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = app.appearance == .system ? scheme == .dark : app.appearance == .dark
        let pal = Palette.make(dark: dark)
        content
            .environment(app)
            .environment(\.palette, pal)
            .environment(\.interfaceStyle, app.style)
            .tint(pal.accent)
    }
}

