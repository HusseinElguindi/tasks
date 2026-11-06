import Foundation
import Observation
import WidgetKit
import TasksCore

// The Mac app's side of the widgets (design/WIDGETS.md §3.2–3.4): it writes the feed the widgets draw from, into the
// group container it shares with the extension (`WidgetGroup`, widgets/Shared). The app is the feed's only writer; the
// widgets never open the store. The iPhone's writer is the same rule (ios/Tasks/Model/Widgets.swift).

/// Writes `widget-feed.json` 1 s after the last visible change, after a sync that applied entries, and when the day
/// changes; then reloads the widgets. A feed that would say the same as the last one isn't written, so the 30 s syncs
/// that bring nothing cost one comparison.
@MainActor
final class WidgetFeedWriter {
    static let delay: Duration = .seconds(1)

    private let store: Store
    let url: URL
    /// Reloads the widgets after a write (WidgetCenter; tests count the calls).
    private let reload: @MainActor () -> Void
    private var scheduled: Task<Void, Never>?
    /// The last feed written (or read at start), to skip writes that change nothing but the time.
    private var last: WidgetFeed?
    /// Writes done (tests).
    private(set) var writes = 0

    /// The group's feed; nil when the group's container isn't there (an unsigned build, or the group refused).
    convenience init?(store: Store) {
        guard let folder = WidgetGroup.folder else { return nil }
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

    /// Quitting: a change waiting for its second is written now, so the desktop shows it.
    func flush() {
        guard let s = scheduled else { return }
        s.cancel()
        scheduled = nil
        write()
    }

    func write() {
        scheduled = nil
        let p = store.projection
        let feed = WidgetFeed.make(from: p, day: p.day)
        if let last, last.schema == feed.schema, last.lists == feed.lists, last.tasks == feed.tasks,
           last.listTops == feed.listTops {
            return
        }
        do {
            try feed.write(at: url)
            last = feed
            writes += 1
            reload()
        } catch {
            // The widgets keep the last feed; the next change tries again.
        }
    }
}
