import Foundation
import Observation
import WidgetKit
import TasksCore

// The app's side of the widgets (WIDGETS.md §3.2–3.4): it writes the feed the widgets draw from, and it opens where a
// widget's link points (`tasks://…`, DeepLink.swift). The app is the feed's only writer; the widgets never open the
// store.

/// Writes `widget-feed.json` into the App Group after any visible change (1 s after the last one), after a sync that
/// brought changes, and when the day changes; then reloads the widgets. A feed that would say the same as the last
/// one isn't written. Never for the sample data: the widgets must never show it.
@MainActor
final class WidgetFeedWriter {
    static let delay: Duration = .seconds(1)

    private let store: Store
    private let url: URL
    private var scheduled: Task<Void, Never>?
    /// The last feed written (or read at start), to skip writes that change nothing but the time.
    private var last: WidgetFeed?
    /// Reloads every widget's timeline after a write (tests watch it).
    private let reload: @MainActor () -> Void

    /// The App Group's feed; nil for the sample data, or when the group's container isn't there.
    convenience init?(store: Store, isSample: Bool) {
        guard !isSample, let folder = WidgetGroup.folder else { return nil }
        self.init(store: store, url: WidgetFeed.url(in: folder))
    }

    /// A feed at `url` (tests).
    init(store: Store, url: URL, reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.url = url
        self.reload = reload
        last = WidgetFeed.read(at: url)
    }

    /// Writes now (at launch), then follows the store.
    func start() {
        write()
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

    /// Something changed: write in a second, unless more changes come first.
    func changed() {
        scheduled?.cancel()
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Going to the background: a change waiting for its second is written now, so the home screen shows it.
    func flush() {
        guard let s = scheduled else { return }
        s.cancel()
        scheduled = nil
        write()
    }

    /// Writes at once, whatever is waiting (the background refresh). Returns whether the feed changed (and the widgets
    /// reloaded); false when it says what the last one said, or couldn't be written.
    @discardableResult
    func writeNow() -> Bool {
        scheduled?.cancel()
        return write()
    }

    @discardableResult
    private func write() -> Bool {
        scheduled = nil
        let p = store.projection
        let feed = WidgetFeed.make(from: p, day: p.day)
        if let last, last.lists == feed.lists, last.tasks == feed.tasks, last.listTops == feed.listTops,
           last.schema == feed.schema {
            return false
        }
        do {
            try feed.write(at: url)
            last = feed
            reload()
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
