import XCTest
@testable import TasksCore

/// The CLI's nudge to the app (feedback item 14, spec §5 "Realtime"): its name, and when the app syncs after a burst.
final class SyncNudgeTests: XCTestCase {
    func testReleaseUsesTheBaseName() {
        XCTAssertEqual(SyncNudge.name(server: URL(string: "https://tasks.example.workers.dev"), debug: false), "com.elguindi.Tasks.changed")
        XCTAssertEqual(SyncNudge.name(server: nil, debug: false), "com.elguindi.Tasks.changed")
    }

    func testDebugNamesFollowTheServer() {
        let a = SyncNudge.name(server: URL(string: "http://127.0.0.1:8794"), debug: true)
        XCTAssertTrue(a.hasPrefix("com.elguindi.Tasks.changed.dev."), a)
        // The same server however it's written: the CLI's TASKS_URL and the app's -serverURL may differ in form.
        XCTAssertEqual(a, SyncNudge.name(server: URL(string: "HTTP://127.0.0.1:8794/"), debug: true))
        XCTAssertEqual(a, SyncNudge.name(server: URL(string: "http://127.0.0.1:8794/v1/sync"), debug: true))
        XCTAssertNotEqual(a, SyncNudge.name(server: URL(string: "http://127.0.0.1:8792"), debug: true))
        XCTAssertNotEqual(a, SyncNudge.name(server: URL(string: "http://localhost:8794"), debug: true))
        XCTAssertEqual(SyncNudge.name(server: URL(string: "https://a.dev"), debug: true),
                       SyncNudge.name(server: URL(string: "https://a.dev:443"), debug: true))
        XCTAssertEqual(SyncNudge.hash("abc").count, 8)
    }

    func testOneNudgeSyncsAfterTheQuietTime() {
        var d = SyncNudge.Debounce(quiet: 0.5, cap: 5)
        XCTAssertEqual(d.nudge(at: 10), 10.5)
    }

    func testABurstIsOneSyncUnlessItOutlastsTheCap() {
        var d = SyncNudge.Debounce(quiet: 0.5, cap: 5)
        // 20 commands 0.15 s apart: each pushes the sync back; it runs once, 0.5 s after the last.
        var fire = 0.0
        for i in 0..<20 { fire = d.nudge(at: 100 + Double(i) * 0.15) }
        XCTAssertEqual(fire, 100 + 19 * 0.15 + 0.5, accuracy: 1e-9)
        d.fired()
        // A burst longer than the cap still syncs by then.
        var last = 0.0
        for i in 0..<60 { last = d.nudge(at: 200 + Double(i) * 0.2) }
        XCTAssertEqual(last, 205, accuracy: 1e-9)
        d.fired()
        XCTAssertEqual(d.nudge(at: 300), 300.5, "after it fired, a new burst")
    }
}
