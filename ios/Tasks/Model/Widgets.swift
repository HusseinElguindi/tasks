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

    init?(store: Store, isSample: Bool) {
        guard !isSample, let folder = WidgetGroup.folder else { return nil }
        self.store = store
        url = WidgetFeed.url(in: folder)
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

    private func write() {
        scheduled = nil
        let p = store.projection
        let feed = WidgetFeed.make(from: p, day: p.day)
        if let last, last.lists == feed.lists, last.tasks == feed.tasks, last.listTops == feed.listTops,
           last.schema == feed.schema {
            return
        }
        do {
            try feed.write(at: url)
            last = feed
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // The widgets keep the last feed; the next change tries again.
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

    /// Opens where a widget's link points: Today, Upcoming, a list, a task's details, or a new task. Whatever was
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
            open(.list(t.list))
            revealTask = id
            if isSplit { selectedTask = id; return }
            // The list's push first, then its sheet (as `-screen detail`).
            try? await Task.sleep(for: .seconds(0.6))
            if task(id) != nil, shown == .list(t.list) { detailTask = id }
        case let .new(list):
            let source: Source = list.map { projection.isActive(list: $0) ? .list($0) : .today } ?? .today
            open(source)
            try? await Task.sleep(for: .seconds(0.5))
            if shown == source { startDraft(source) }
        }
    }
}
