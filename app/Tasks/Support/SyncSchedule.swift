import Foundation

/// When the app's periodic sync runs (spec §5 Realtime), and how often the widgets' feed is written while no window is
/// open (design/WIDGETS.md §3.4). Pure, so its cases are tested without timers or windows (SyncScheduleTests).
///
/// - A window visible: every tick (30 s), as before.
/// - No window visible (⌘W, the app hidden) and Settings ▸ Sync with no window open on (the default): every 60 s, so a
///   change made on another device reaches the desktop widgets within about a minute. Off: no periodic sync at all
///   until a window shows, as before 2026-11-06. The CLI's nudge syncs either way (`SyncNudgeListener`).
/// - The feed: 1 s after the last change while a window is visible; with none, at most once per 2 minutes, so a burst of
///   changes (an agent's) costs the widgets few of WidgetKit's budgeted background reloads.
enum SyncSchedule {
    /// The periodic timer's tick.
    static let tick: TimeInterval = 30
    /// The sync interval while no window is visible.
    static let windowless: TimeInterval = 60
    /// How long the feed writer waits after the last change before writing.
    static let feedQuiet: TimeInterval = 1
    /// While no window is visible, the least time between two feed writes.
    static let windowlessFeedGap: TimeInterval = 120

    /// Whether a tick at `now` syncs. `lastTick`: when a tick last synced (nil: none yet).
    static func tickSyncs(windowVisible: Bool, syncWithoutWindow: Bool, now: TimeInterval,
                          lastTick: TimeInterval?) -> Bool {
        if windowVisible { return true }
        guard syncWithoutWindow else { return false }
        guard let lastTick else { return true }
        // A second's slack: ticks 30 s apart drift a little, and every other one should sync.
        return now - lastTick >= windowless - 1
    }

    /// How long the feed writer waits after a change at `now` before writing. `lastWrite`: the last write (nil: none
    /// since launch).
    static func feedDelay(windowVisible: Bool, now: TimeInterval, lastWrite: TimeInterval?) -> TimeInterval {
        guard !windowVisible, let lastWrite else { return feedQuiet }
        return max(feedQuiet, lastWrite + windowlessFeedGap - now)
    }
}
