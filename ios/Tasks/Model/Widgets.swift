import Foundation
import Observation
import WidgetKit
import TasksCore

// The app's side of the widgets (WIDGETS.md §3.2–3.4): it writes the feed the widgets draw from, and it opens where a
// widget's link points (`tasks://…`, DeepLink.swift). The app is the feed's only writer; the widgets never open the
// store.

/// Writes `widget-feed.json` into the App Group 1 s after the last visible change, after a sync that brought changes,
/// and when the day changes; then reloads the widgets whose content changed (`WidgetFeed.changes`,
/// `WidgetGroup.kinds`), as the Mac's writer does. A feed that would draw the same as the last one isn't written, so
/// the syncs that bring nothing, and edits to notes, cost one comparison. Writes are at least 20 s apart
/// (`WidgetFeedPace`): the home and lock screens' widgets aren't on screen while the app is in front, and each reload
/// re-renders every entry of their timelines. Going to the background writes what's waiting at once (`flush`), and the
/// background refresh writes at once (`writeNow`). Never for the sample data: the widgets must never show it.
@MainActor
final class WidgetFeedWriter {
    /// The quiet after the last change before a write.
    static let quiet: TimeInterval = 1
    /// The least time between two writes (coord title-design T10: the Mac's gap with a window open).
    static let gap: TimeInterval = 20

    private let store: Store
    private let url: URL
    private var scheduled: Task<Void, Never>?
    /// The last feed written (or read at start), to skip writes that change nothing the widgets draw.
    private var last: WidgetFeed?
    /// Reloads the widgets of these kinds after a write (WidgetCenter; tests watch it).
    private let reload: @MainActor ([String]) -> Void
    /// Seconds on a monotonic clock (tests move it).
    private let clock: @MainActor () -> TimeInterval
    /// When the feed was last written, on `clock`.
    private var lastWriteAt: TimeInterval?
    /// The first change not written yet, on `clock` (`WidgetFeedPace` writes it within a gap of it).
    private var waitingSince: TimeInterval?
    /// Writes done (tests).
    private(set) var writes = 0

    /// The App Group's feed; nil for the sample data, or when the group's container isn't there.
    convenience init?(store: Store, isSample: Bool) {
        guard !isSample, let folder = WidgetGroup.folder else { return nil }
        self.init(store: store, url: WidgetFeed.url(in: folder))
    }

    /// A feed at `url` (tests).
    init(store: Store, url: URL,
         reload: @escaping @MainActor ([String]) -> Void = { kinds in
             kinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
         },
         clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.url = url
        self.reload = reload
        self.clock = clock
        last = WidgetFeed.read(at: url)
    }

    /// Writes now (at launch), then follows the store. The launch write doesn't start the 20 s gap, so what the launch
    /// sync brings goes out a second later.
    func start() {
        write()
        lastWriteAt = nil
        observe()
    }

    /// Any local change queues an op (the pending count moves); a sync that applied entries ends with a new sync
    /// state; a new day is the projection's. Each wakes the writer, which compares what it would write.
    private func observe() {
        withObservationTracking {
            _ = store.pendingCount
            _ = store.syncState
            _ = store.projection.day
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.changed()
                self?.observe()
            }
        }
    }

    /// Something changed: write in a second, unless more changes come first; no sooner than 20 s after the last write,
    /// and within 20 s of the first change waiting.
    func changed() {
        scheduled?.cancel()
        let now = clock()
        if waitingSince == nil { waitingSince = now }
        let delay = WidgetFeedPace.delay(now: now, lastWrite: lastWriteAt, waitingSince: waitingSince,
                                         quiet: Self.quiet, gap: Self.gap)
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Going to the background: a change that's waiting is written now, so the home screen shows it.
    func flush() {
        guard let s = scheduled else { return }
        s.cancel()
        scheduled = nil
        write()
    }

    /// Writes at once, whatever is waiting (the background refresh). Returns whether the feed changed (and the widgets
    /// reloaded); false when they'd draw what the last one drew, or it couldn't be written.
    @discardableResult
    func writeNow() -> Bool {
        scheduled?.cancel()
        return write()
    }

    @discardableResult
    private func write() -> Bool {
        scheduled = nil
        waitingSince = nil
        let p = store.projection
        let feed = WidgetFeed.make(from: p, day: p.day)
        let change = feed.changes(since: last)
        guard !change.isEmpty else { return false }
        do {
            try feed.write(at: url)
            last = feed
            lastWriteAt = clock()
            writes += 1
            reload(WidgetGroup.kinds(for: change))
            return true
        } catch {
            // The widgets keep the last feed; the next change tries again.
            return false
        }
    }
}

extension AppModel {
    /// Starts writing the widgets' feed (not for the sample data).
    func startWidgetFeed() {
        guard widgetFeed == nil, let w = WidgetFeedWriter(store: store, isSample: isSample) else { return }
        widgetFeed = w
        w.start()
    }

    /// How long a task tapped in a widget keeps the selected fill once its list is up, before it fades.
    static let widgetTaskHold: Duration = .seconds(1.5)

    /// Opens where a widget's link points: Today, Upcoming, a list, a task in its list, or a new task. Whatever was
    /// open closes first, as a tap elsewhere would close it (a titled draft is written). A list or task that's gone
    /// or in the Trash opens Today.
    func follow(_ link: DeepLink) async {
        endSelecting()
        endDraft()
        detailTask = nil
        dateTarget = nil
        listEditor = nil
        showSettings = false
        switch link {
        case .today: open(.today)
        case .upcoming: open(.upcoming)
        case let .list(id):
            open(projection.isActive(list: id) ? .list(id) : .today)
        case let .task(id):
            guard let t = task(id), !t.isHeading, !isTrashed(t) else { open(.today); return }
            if t.isDone { showCompleted.insert(t.list) } else if let h = projection.heading(of: id) { expand(h) }
            // Its list, scrolled to it, and the row highlighted with the selected fill (the undo's flash), not its
            // details (the user: "maybe dont open the details, but highlight it as before"). iPad selects it.
            open(.list(t.list))
            revealTask = id
            if isSplit { selectedTask = id; return }
            // The list's push and the scroll first (ListScreen's reveal waits 0.35 s), then the fill.
            try? await Task.sleep(for: .seconds(0.6))
            if task(id) != nil, shown == .list(t.list) { flash([id], for: Self.widgetTaskHold) }
        case let .new(list):
            let source: Source = list.map { projection.isActive(list: $0) ? .list($0) : .today } ?? .today
            open(source)
            try? await Task.sleep(for: .seconds(0.5))
            if shown == source { startDraft(source) }
        }
    }
}
