import Foundation
import TasksCore

/// When the app's periodic sync runs (spec §5 Realtime), and how often the widgets' feed is written while no window is
/// open (design/WIDGETS.md §3.4). Pure, so its cases are tested without timers or windows (SyncScheduleTests).
///
/// - A window visible: every tick (30 s), as before.
/// - No window visible (⌘W, the app hidden) and Settings ▸ Sync with no window open on (the default): every 60 s, so a
///   change made on another device reaches the desktop widgets within about a minute. Off: no periodic sync at all
///   until a window shows, as before 2026-11-06. The CLI's nudge syncs either way (`SyncNudgeListener`).
/// - The feed: 1 s after the last change, and at most once per 20 s while a window is visible (the desktop widgets are
///   mostly under it, and each write re-renders them; coord title-design T8) or per 2 minutes with none, so a burst of
///   changes (an agent's) costs the widgets few of WidgetKit's budgeted background reloads. Hiding, closing or leaving
///   the window writes what's waiting at once (`WidgetFeedWriter.flush`). `WidgetFeedPace` (TasksCore) has the rule.
enum SyncSchedule {
    /// The periodic timer's tick.
    static let tick: TimeInterval = 30
    /// The sync interval while no window is visible.
    static let windowless: TimeInterval = 60
    /// How long the feed writer waits after the last change before writing.
    static let feedQuiet: TimeInterval = 1
    /// While a window is visible, the least time between two feed writes.
    static let feedGap: TimeInterval = 20
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
    /// since launch). `waitingSince`: the first change still waiting (nil: this one).
    static func feedDelay(windowVisible: Bool, now: TimeInterval, lastWrite: TimeInterval?,
                          waitingSince: TimeInterval? = nil) -> TimeInterval {
        WidgetFeedPace.delay(now: now, lastWrite: lastWrite, waitingSince: waitingSince, quiet: feedQuiet,
                             gap: windowVisible ? feedGap : windowlessFeedGap)
    }
}
