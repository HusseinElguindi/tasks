import SwiftUI
import TasksCore
import UIKit

// Select mode's pieces (batch 2 §3): the "…" menu's Select, the bar at the bottom, the long-press menu for the whole
// selection, and the two-finger swipe. The rules are in Select.swift.

/// Select in a screen's "…" (§0), under Undo and Redo: select mode, with nothing selected.
struct SelectItem: View {
    let source: Source
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { app.startSelecting(source) } label: { Label("Select", systemImage: "checkmark.circle") }
            .disabled(!app.canSelect(source))
    }
}

/// In place of the + (and Home's bar): a Liquid Glass capsule, 56 tall, of equal segments, each a 19pt medium symbol
/// over an 11pt medium word, 3 apart, in `ink` (Delete in `danger`). With nothing selected they're disabled, at 40%.
struct SelectBar: View {
    let source: Source
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let ids = app.selectedIDs(source)
        let tasks = ids.compactMap(app.task)
        HStack(spacing: 0) {
            if source == .trash {
                // Put Back: home, if every task has a live list; else Put back in, for all of them (IX §28).
                if ids.isEmpty || app.allGoHome(ids) {
                    Button { app.putBackTasks(ids) } label: { Segment(symbol: "arrow.uturn.backward", word: "Put Back") }
                } else {
                    Menu { PutBackInItems(ids: ids) } label: { Segment(symbol: "arrow.uturn.backward", word: "Put Back") }
                }
                Menu { PutBackInItems(ids: ids) } label: { Segment(symbol: "tray.and.arrow.up", word: "Put Back in") }
            } else {
                // Not Done when every selected task is done, and in Completed; a mixed selection reads Complete (IX §8).
                let notDone = tasks.isEmpty ? source == .completed : tasks.allSatisfy(\.isDone)
                Button { app.completeTasks(ids) } label: {
                    Segment(symbol: notDone ? "circle" : "checkmark.circle", word: notDone ? "Not Done" : "Complete")
                }
                Button { app.dateTarget = DateTarget(ids: ids, kind: .when) } label: { Segment(symbol: "calendar", word: "When") }
                Menu { MoveItems(ids: ids) } label: { Segment(symbol: "arrow.right.square", word: "Move") }
                Button { app.deleteTasks(ids) } label: { Segment(symbol: "trash", word: "Delete", ink: p.danger) }
            }
        }
        .buttonStyle(.plain)
        .disabled(ids.isEmpty)
        .frame(height: Metric.fab)
        .floatingGlass(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selectBar")
    }
}

/// One of the bar's segments: its symbol over its word, the whole segment its target.
private struct Segment: View {
    let symbol: String
    let word: String
    var ink: Color?
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium)).accessibilityHidden(true)
            Text(word).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(ink ?? p.ink)
        .opacity(enabled ? 1 : 0.4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// A long-press in select mode: the menu for the whole selection (IX §15). Complete 3 Tasks (Mark as Not Done when all
/// are done) · Today · Tomorrow · When… · Deadline… · Move to ▸ · ── · Delete 3 Tasks; in Trash, Put Back (when every
/// task has a live list) · Put Back in ▸.
struct SelectionMenu: View {
    let ids: [EntityID]
    let source: Source
    @Environment(AppModel.self) private var app
    var body: some View {
        let tasks = ids.compactMap(app.task)
        let n = tasks.count
        if source == .trash {
            if app.allGoHome(ids) {
                Button { app.putBackTasks(ids) } label: {
                    Label(n == 1 ? "Put Back" : "Put Back \(n) Tasks", systemImage: "arrow.uturn.backward")
                }
            }
            Menu { PutBackInItems(ids: ids) } label: { Label("Put Back in", systemImage: "tray.and.arrow.up") }
        } else {
            let anyOpen = tasks.contains { !$0.isDone }
            Button { app.completeTasks(ids) } label: {
                Label(anyOpen ? (n == 1 ? "Complete" : "Complete \(n) Tasks") : "Mark as Not Done",
                      systemImage: anyOpen ? "checkmark.circle" : "circle")
            }
            Button { app.setDate(ids, .when, app.today) } label: { Label("Today", systemImage: "sun.max") }
            Button { app.setDate(ids, .when, app.today.adding(days: 1)) } label: { Label("Tomorrow", systemImage: "sunrise") }
            Button { app.dateTarget = DateTarget(ids: ids, kind: .when) } label: { Label("When…", systemImage: "calendar") }
            Button { app.dateTarget = DateTarget(ids: ids, kind: .deadline) } label: { Label("Deadline…", systemImage: "flag") }
            Menu { MoveItems(ids: ids) } label: { Label("Move to", systemImage: "arrow.right.square") }
            Divider()
            Button(role: .destructive) { app.deleteTasks(ids) } label: {
                Label(n == 1 ? "Delete" : "Delete \(n) Tasks", systemImage: "trash")
            }
        }
    }
}

/// Move's lists for a selection: "Move 3 tasks to", then every live list; the list every task is already in is checked
/// and disabled (§3; the Mac's `moveItems`).
struct MoveItems: View {
    let ids: [EntityID]
    @Environment(AppModel.self) private var app
    var body: some View {
        let tasks = ids.compactMap(app.task)
        Section(tasks.count == 1 ? "Move to" : "Move \(tasks.count) tasks to") {
            ForEach(app.activeLists) { l in
                let all = !tasks.isEmpty && tasks.allSatisfy { $0.list == l.id }
                Button { app.moveTasks(ids, to: l.id) } label: {
                    if all { Label(MenuName.fit(l.name), systemImage: "checkmark") } else { Text(MenuName.fit(l.name)) }
                }
                .disabled(all)
            }
        }
    }
}

// MARK: - The two-finger swipe

/// The two-finger swipe over the rows, as iOS's own (Mail, Files): started on an unselected row it selects every row
/// it crosses, started on a selected one it deselects them, and going back reverses it, back to where it started. It
/// enters select mode if it's off. Within 31pt of the list's top or bottom the list scrolls 10pt every 16 ms (the
/// Mac's drag autoscroll × 1.3), and each change gives a `.selection` haptic.
///
/// A two-touch pan on the list's own scroll view, which then scrolls with one finger only, as Mail's does. It maps the
/// touch to the task rows' frames (`frames`, in the window), kept by each row while it's on screen.
@MainActor
final class SwipeSelect: NSObject, UIGestureRecognizerDelegate {
    /// The task rows on screen, by id, in window coordinates.
    var frames: [EntityID: CGRect] = [:]
    /// Every task row, in the screen's order.
    var order: [EntityID] = []
    /// What covers the list's foot: the floating bar (the phone), or nothing.
    var foot: CGFloat = 0
    /// Whether a swipe may start now (a live list or a view, on screen, nothing over it).
    var canStart: () -> Bool = { false }
    /// Select mode on, if it isn't, as the swipe starts.
    var enter: () -> Void = {}
    var selection: () -> Set<EntityID> = { [] }
    var apply: (Set<EntityID>) -> Void = { _ in }

    private weak var scroll: UIScrollView?
    private var pan: UIPanGestureRecognizer?
    private var start: Int?
    private var last: Int?
    private var selects = true
    private var base: Set<EntityID> = []
    private var finger: CGPoint = .zero
    private var timer: Timer?
    private lazy var haptic = UISelectionFeedbackGenerator()

    func install(on s: UIScrollView) {
        guard scroll !== s else { return }
        if let pan { pan.view?.removeGestureRecognizer(pan) }
        let p = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        p.minimumNumberOfTouches = 2
        p.maximumNumberOfTouches = 2
        p.delegate = self
        s.addGestureRecognizer(p)
        s.panGestureRecognizer.maximumNumberOfTouches = 1
        scroll = s
        pan = p
    }

    /// The task row under a point, by its index in `order`.
    private func row(at p: CGPoint) -> Int? {
        order.firstIndex { id in frames[id].map { $0.minY <= p.y && p.y < $0.maxY } ?? false }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, canStart() else { return false }
        // Mostly vertical, and started on a task row.
        let v = pan.velocity(in: nil)
        return abs(v.y) > abs(v.x) && row(at: pan.location(in: nil)) != nil
    }

    @objc private func moved(_ g: UIPanGestureRecognizer) {
        finger = g.location(in: nil)
        switch g.state {
        case .began:
            guard let i = row(at: finger) else { return }
            enter()
            base = selection()
            start = i
            last = nil
            selects = !base.contains(order[i])
            haptic.prepare()
            update()
        case .changed:
            update()
            autoscroll()
        default:
            timer?.invalidate()
            timer = nil
            start = nil
        }
    }

    /// The rows from where it started to the finger take its state; the rest are as they were before it.
    private func update() {
        guard let s = start, s < order.count else { return }
        // Over a heading or a label, between rows: the last row it was on.
        let i = min(row(at: finger) ?? last ?? s, order.count - 1)
        guard i != last else { return }
        let old = selection()
        var next = base
        for j in min(s, i)...max(s, i) {
            if selects { next.insert(order[j]) } else { next.remove(order[j]) }
        }
        last = i
        guard next != old else { return }
        apply(next)
        haptic.selectionChanged()
    }

    private var direction: CGFloat {
        guard let s = scroll else { return 0 }
        let r = s.convert(s.bounds, to: nil)
        let top = r.minY + s.adjustedContentInset.top
        let bottom = r.maxY - s.adjustedContentInset.bottom - foot
        return finger.y < top + 31 ? -1 : finger.y > bottom - 31 ? 1 : 0
    }

    private func autoscroll() {
        guard direction != 0 else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func step() {
        guard let s = scroll, start != nil, direction != 0 else {
            timer?.invalidate()
            timer = nil
            return
        }
        let lo = -s.adjustedContentInset.top
        let hi = max(lo, s.contentSize.height + s.adjustedContentInset.bottom - s.bounds.height)
        let y = min(max(s.contentOffset.y + 10 * direction, lo), hi)
        guard y != s.contentOffset.y else { return }
        s.contentOffset.y = y
        update()
    }
}

extension View {
    /// Installs the two-finger swipe on the list this row is in (as `pressesShowAtOnce`, on a row that's there when the
    /// list appears: its header).
    func swipeSelects(_ handler: SwipeSelect) -> some View {
        background(SwipeSelectProbe(handler: handler).allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct SwipeSelectProbe: UIViewRepresentable {
    let handler: SwipeSelect
    func makeUIView(context: Context) -> Probe { Probe(handler: handler) }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        let handler: SwipeSelect
        init(handler: SwipeSelect) {
            self.handler = handler
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let s = v, !(s is UIScrollView) { v = s.superview }
            if let scroll = v as? UIScrollView { handler.install(on: scroll) }
        }
    }
}
