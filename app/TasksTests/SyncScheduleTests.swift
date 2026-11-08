import XCTest

/// When the periodic sync runs, and how far apart feed writes are with no window open (Tasks/Support/SyncSchedule.swift;
/// spec §5 Realtime; the user, 2026-11-06).
final class SyncScheduleTests: XCTestCase {
    /// The ticks over five minutes from launch (30 s apart), with a little drift, and which of them sync.
    private func syncs(windowVisible: Bool, syncWithoutWindow: Bool) -> [TimeInterval] {
        var last: TimeInterval?
        var out: [TimeInterval] = []
        for i in 1...10 {
            let now = Double(i) * SyncSchedule.tick + Double(i % 3) * 0.2
            if SyncSchedule.tickSyncs(windowVisible: windowVisible, syncWithoutWindow: syncWithoutWindow, now: now,
                                      lastTick: last) {
                last = now
                out.append(now.rounded())
            }
        }
        return out
    }

    func testAVisibleWindowSyncsEveryThirtySecondsEitherWay() {
        let every = (1...10).map { Double($0) * 30 }
        XCTAssertEqual(syncs(windowVisible: true, syncWithoutWindow: true), every)
        XCTAssertEqual(syncs(windowVisible: true, syncWithoutWindow: false), every, "the setting is about no window")
    }

    func testWithNoWindowItSyncsEveryMinute() {
        XCTAssertEqual(syncs(windowVisible: false, syncWithoutWindow: true), [30, 90, 150, 210, 270])
    }

    func testTurnedOffNoWindowMeansNoPeriodicSync() {
        XCTAssertEqual(syncs(windowVisible: false, syncWithoutWindow: false), [], "as before: only nudges and activation")
    }

    func testAWindowClosingKeepsTheMinuteFromTheLastSync() {
        // Synced at 300 with the window open; ⌘W; the next ticks are 330 (too soon) and 360.
        XCTAssertFalse(SyncSchedule.tickSyncs(windowVisible: false, syncWithoutWindow: true, now: 330, lastTick: 300))
        XCTAssertTrue(SyncSchedule.tickSyncs(windowVisible: false, syncWithoutWindow: true, now: 360.2, lastTick: 300))
        XCTAssertTrue(SyncSchedule.tickSyncs(windowVisible: false, syncWithoutWindow: true, now: 359.5, lastTick: 300),
                      "a tick that drifted early by under a second still counts")
    }

    func testWithAWindowOpenFeedWritesWaitASecondAndAreTwentySecondsApart() {
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: true, now: 100, lastWrite: nil), 1, "the first goes out")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: true, now: 100, lastWrite: 99.5), 19.5, "20 s after the last")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: true, now: 100, lastWrite: 50), 1, "long since: a second")
    }

    /// A change every half second for a minute still goes out once per gap, not when the changes stop.
    func testASteadyStreamOfChangesStillGoesOutOncePerGap() {
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: true, now: 104.5, lastWrite: nil, waitingSince: 85), 0.5,
                       "20 s after the first change waiting, though the last came just now")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: true, now: 110, lastWrite: 90, waitingSince: 91), 1,
                       "the gap and the wait both run out: a second")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: false, now: 100, lastWrite: nil, waitingSince: 100), 1)
    }

    func testWithNoWindowFeedWritesAreTwoMinutesApart() {
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: false, now: 100, lastWrite: nil), 1, "the first goes out")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: false, now: 100, lastWrite: 40), 60, "two minutes after 40")
        XCTAssertEqual(SyncSchedule.feedDelay(windowVisible: false, now: 400, lastWrite: 40), 1, "long since: a second")
    }
}
