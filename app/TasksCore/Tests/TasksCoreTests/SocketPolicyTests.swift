import XCTest
@testable import TasksCore

/// The poke socket's rules (design/PUSH-SYNC.md §3, `SocketPolicy`): the reconnect backoff and its jitter, what a 401
/// or an old server does, and how often the periodic sync runs with the socket up or down.
final class SocketPolicyTests: XCTestCase {
    /// The waits after `n` drops in a row, with no jitter (random 0.5 is the delay itself).
    private func waits(_ n: Int) -> [Double] {
        var p = SocketPolicy()
        return (0..<n).map { i in
            guard case .retry(let after) = p.closed(.dropped, at: Double(i), random: 0.5) else { XCTFail(); return -1 }
            return after
        }
    }

    func testTheBackoffDoublesFromASecondToFiveMinutes() {
        XCTAssertEqual(waits(12), [1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300, 300])
    }

    func testTheBackoffNeverOverflows() {
        XCTAssertEqual(waits(200).last, 300)
    }

    func testJitterIsWithinTwentyPercentEitherWay() {
        XCTAssertEqual(SocketPolicy.jittered(10, random: 0), 8, accuracy: 1e-9)
        XCTAssertEqual(SocketPolicy.jittered(10, random: 0.5), 10, accuracy: 1e-9)
        XCTAssertLessThan(SocketPolicy.jittered(10, random: 0.999_999), 12)
        XCTAssertEqual(SocketPolicy.jittered(300, random: 0), 240, accuracy: 1e-9)
        XCTAssertEqual(SocketPolicy.jittered(10, random: -3), 8, accuracy: 1e-9, "out-of-range randoms are clamped")
        XCTAssertEqual(SocketPolicy.jittered(10, random: 7), 12, accuracy: 1e-9)

        // Seeded: every wait in its band, and spread across it (a deploy's reconnect wave is smeared out).
        var rng = SeededRandom(seed: 23)
        for failures in 0..<10 {
            let base = min(pow(2, Double(failures)), 300)
            var seen: [Double] = []
            for _ in 0..<200 {
                var p = SocketPolicy()
                for i in 0..<failures { _ = p.closed(.dropped, at: Double(i), random: 0.5) }
                guard case .retry(let after) = p.closed(.dropped, at: 100, random: Double.random(in: 0..<1, using: &rng)) else {
                    return XCTFail()
                }
                XCTAssertGreaterThanOrEqual(after, base * 0.8 - 1e-9)
                XCTAssertLessThan(after, base * 1.2)
                seen.append(after)
            }
            XCTAssertGreaterThan(seen.max()! - seen.min()!, base * 0.3, "spread over the band")
        }
    }

    func testAConnectionThatLastedAMinuteResetsTheBackoff() {
        var p = SocketPolicy()
        for i in 0..<3 { _ = p.closed(.dropped, at: Double(i), random: 0.5) }
        XCTAssertEqual(p.failures, 3)
        // Up for 59 s: still unstable, the backoff keeps doubling.
        p.opened(at: 100)
        XCTAssertEqual(p.closed(.dropped, at: 159, random: 0.5), .retry(after: 8))
        // Up for a minute: back to a second.
        p.opened(at: 200)
        XCTAssertEqual(p.closed(.dropped, at: 260, random: 0.5), .retry(after: 1))
        XCTAssertEqual(p.closed(.dropped, at: 261, random: 0.5), .retry(after: 2), "and doubling again from there")
        XCTAssertNil(p.openedAt)
    }

    func testResetGoesBackToTheFirstDelay() {
        var p = SocketPolicy()
        for i in 0..<6 { _ = p.closed(.dropped, at: Double(i), random: 0.5) }
        p.reset()
        XCTAssertEqual(p.closed(.dropped, at: 10, random: 0.5), .retry(after: 1))
    }

    func testABadTokenStops() {
        var p = SocketPolicy()
        XCTAssertEqual(p.closed(.badToken, at: 0, random: 0.5), .stop)
        p.opened(at: 10)
        XCTAssertEqual(p.closed(.badToken, at: 100, random: 0.5), .stop, "even after a long connection")
    }

    func testAnOldServerIsTriedAgainInAnHour() {
        var p = SocketPolicy()
        XCTAssertEqual(p.closed(.oldServer, at: 0, random: 0.5), .retry(after: 3600))
        XCTAssertEqual(p.closed(.oldServer, at: 1, random: 0.5), .retry(after: 3600), "an hour each time, not doubling")
        guard case .retry(let low) = p.closed(.oldServer, at: 2, random: 0) else { return XCTFail() }
        XCTAssertEqual(low, 2880, accuracy: 1e-9)
        XCTAssertEqual(p.failures, 0, "an old server isn't a drop")
    }

    func testTheUpgradeStatusSaysWhy() {
        XCTAssertEqual(SocketPolicy.Close(status: 401), .badToken)
        XCTAssertEqual(SocketPolicy.Close(status: 404), .oldServer)
        XCTAssertEqual(SocketPolicy.Close(status: 405), .oldServer)
        XCTAssertEqual(SocketPolicy.Close(status: 426), .oldServer)
        XCTAssertEqual(SocketPolicy.Close(status: 500), .dropped)
        XCTAssertEqual(SocketPolicy.Close(status: 502), .dropped, "a Cloudflare edge error")
        XCTAssertEqual(SocketPolicy.Close(status: nil), .dropped, "no response: the network")
    }

    // MARK: The periodic sync

    func testPollIntervals() {
        XCTAssertEqual(SocketPolicy.pollInterval(.front, socketConnected: false), 30, "today's pace")
        XCTAssertEqual(SocketPolicy.pollInterval(.windowless, socketConnected: false), 60, "today's pace")
        XCTAssertEqual(SocketPolicy.pollInterval(.front, socketConnected: true), 300)
        XCTAssertEqual(SocketPolicy.pollInterval(.windowless, socketConnected: true), 600)
        XCTAssertNil(SocketPolicy.pollInterval(.away, socketConnected: false))
        XCTAssertNil(SocketPolicy.pollInterval(.away, socketConnected: true))
        XCTAssertTrue(SocketPolicy.holds(.front))
        XCTAssertTrue(SocketPolicy.holds(.windowless))
        XCTAssertFalse(SocketPolicy.holds(.away), "nothing would poll, so no socket either")
    }

    /// 30 s ticks over 20 minutes, a little drift, and which of them sync.
    private func polls(_ presence: SocketPolicy.Presence, connected: (Double) -> Bool) -> [Double] {
        var last: Double?
        var out: [Double] = []
        for i in 1...40 {
            let now = Double(i) * 30 + Double(i % 3) * 0.2
            if SocketPolicy.pollDue(presence, socketConnected: connected(now), now: now, lastPoll: last) {
                last = now
                out.append(now.rounded())
            }
        }
        return out
    }

    func testWithTheSocketUpThePeriodicSyncIsASafetyNet() {
        XCTAssertEqual(polls(.front) { _ in true }, [30, 330, 630, 930])
        XCTAssertEqual(polls(.windowless) { _ in true }, [30, 630])
        XCTAssertEqual(polls(.away) { _ in true }, [])
    }

    func testWithTheSocketDownItsTodaysPace() {
        XCTAssertEqual(polls(.front) { _ in false }, (1...40).map { Double($0) * 30 })
        XCTAssertEqual(polls(.windowless) { _ in false }, stride(from: 30.0, through: 1200, by: 60).map { $0 })
    }

    func testTheSocketDroppingGoesBackToThirtySecondsAtOnce() {
        // Up until 7 min, down after: the first tick past 30 s since the last poll syncs.
        XCTAssertEqual(polls(.front) { $0 < 420 }, [30, 330] + (14...40).map { Double($0) * 30 })
    }
}

/// `SyncConfig.eventsURL`: the WebSocket URL for the server's base URL.
final class EventsURLTests: XCTestCase {
    func testHTTPBecomesWSAndHTTPSBecomesWSS() {
        XCTAssertEqual(SyncConfig(url: URL(string: "http://127.0.0.1:8797")!, token: "t").eventsURL.absoluteString,
                       "ws://127.0.0.1:8797/v1/events")
        XCTAssertEqual(SyncConfig(url: URL(string: "https://tasks.example.workers.dev")!, token: "t").eventsURL.absoluteString,
                       "wss://tasks.example.workers.dev/v1/events")
        XCTAssertEqual(SyncConfig(url: URL(string: "HTTPS://tasks.example.workers.dev/")!, token: "t").eventsURL.absoluteString,
                       "wss://tasks.example.workers.dev/v1/events")
    }
}
