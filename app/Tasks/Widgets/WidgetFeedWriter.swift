import Foundation
import Observation
import WidgetKit
import TasksCore

// The Mac app's side of the widgets (design/WIDGETS.md §3.2–3.4): it writes the feed the widgets draw from, into the
// group container it shares with the extension (`WidgetGroup`, widgets/Shared). The app is the feed's only writer; the
// widgets never open the store. The iPhone's writer is the same rule (ios/Tasks/Model/Widgets.swift).

/// Writes `widget-feed.json` 1 s after the last visible change, after a sync that applied entries, and when the day
/// changes; then reloads the widgets whose content changed (`WidgetFeed.changes`, `WidgetGroup.kinds`). A feed that
/// would draw the same as the last one isn't written, so the syncs that bring nothing, and edits to notes, cost one
/// comparison. Writes are at least 20 s apart while a window is visible and 2 minutes with none
/// (`SyncSchedule.feedDelay`): each reload re-renders every entry of the widgets' timelines, and with no window the
/// reloads count against WidgetKit's daily budget. Hiding, closing or leaving the window writes what's waiting at once.
@MainActor
final class WidgetFeedWriter {
    private let store: Store
    let url: URL
    /// Reloads the widgets of these kinds after a write (WidgetCenter; tests count the calls).
    private let reload: @MainActor ([String]) -> Void
    /// Whether one of the app's windows is on screen (`AppModel.hasVisibleWindow`; tests set it).
    private let windowVisible: @MainActor () -> Bool
    /// Seconds on a monotonic clock (tests move it).
    private let clock: @MainActor () -> TimeInterval
    private var scheduled: Task<Void, Never>?
    /// When the feed was last written, on `clock`.
    private var lastWriteAt: TimeInterval?
    /// The first change not written yet, on `clock` (`SyncSchedule.feedDelay` writes it within a gap of it).
    private var waitingSince: TimeInterval?
    /// The last feed written (or read at start), to skip writes that change nothing but the time.
    private var last: WidgetFeed?
    /// Writes done (tests).
    private(set) var writes = 0

    /// The group's feed; nil when the group's container isn't there (an unsigned build, or the group refused).
    convenience init?(store: Store, windowVisible: @escaping @MainActor () -> Bool) {
        guard let folder = WidgetGroup.folder else { return nil }
        self.init(store: store, url: WidgetFeed.url(in: folder), windowVisible: windowVisible)
    }

    /// A feed at `url` (tests).
    init(store: Store, url: URL,
         reload: @escaping @MainActor ([String]) -> Void = { kinds in kinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) } },
         windowVisible: @escaping @MainActor () -> Bool = { true },
         clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.url = url
        self.reload = reload
        self.windowVisible = windowVisible
        self.clock = clock
        last = WidgetFeed.read(at: url)
    }

    /// Writes now (at launch), then follows the store. The launch write doesn't start the 2 minutes of `SyncSchedule`, so
    /// what the launch sync brings goes out a second later even with no window (a login launch).
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

    /// Something changed: write in a second, unless more changes come first; no sooner than 20 s after the last write
    /// with a window on screen, 2 minutes with none; and within that gap of the first change waiting.
    func changed() {
        scheduled?.cancel()
        let now = clock()
        if waitingSince == nil { waitingSince = now }
        let delay = SyncSchedule.feedDelay(windowVisible: windowVisible(), now: now, lastWrite: lastWriteAt,
                                           waitingSince: waitingSince)
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Quitting, the window hidden, closed, minimized or left, or a window coming back: a change that's waiting is
    /// written now, so the desktop shows it.
    func flush() {
        guard let s = scheduled else { return }
        s.cancel()
        scheduled = nil
        write()
    }

    func write() {
        scheduled = nil
        waitingSince = nil
        let p = store.projection
        let feed = WidgetFeed.make(from: p, day: p.day)
        let change = feed.changes(since: last)
        guard !change.isEmpty else { return }
        do {
            try feed.write(at: url)
            last = feed
            lastWriteAt = clock()
            writes += 1
            reload(WidgetGroup.kinds(for: change))
        } catch {
            // The widgets keep the last feed; the next change tries again.
        }
    }
}
