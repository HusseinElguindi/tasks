import XCTest
@testable import TasksCore

/// Settings ▸ Sync ▸ Live updates in every state, on both devices, and the live cloud's 5 s rule
/// (design/SYNC-STATUS.md §2–3).
final class LiveStatusTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }

    func row(_ state: SyncSocket.State, offline: Bool = false, dropped: Double? = nil, last: Double? = nil,
             _ device: LiveStatus.Device = .mac(syncWithoutWindow: true), pace: Double = 30) -> LiveStatus {
        LiveStatus(.init(state: state, offline: offline, droppedAt: dropped.map { now.addingTimeInterval(-$0) },
                         lastChangeAt: last.map { now.addingTimeInterval(-$0) }),
                   device: device, pace: pace, now: now, calendar: cal)
    }

    func time(_ ago: Double) -> String { now.addingTimeInterval(-ago).formatted(date: .omitted, time: .shortened) }

    func testLive() {
        let r = row(.connected, last: 120)
        XCTAssertEqual(r.kind, .live)
        XCTAssertEqual(r.dot, .live)
        XCTAssertEqual(r.word, "Live")
        XCTAssertEqual(r.detail, "Changes from your other devices arrive within seconds. Last one 2 min ago.")
        XCTAssertEqual(r.spoken, "Live. Changes from your other devices arrive within seconds. Last one 2 minutes ago.")
        XCTAssertEqual(row(.connected).detail, "Changes from your other devices arrive within seconds.",
                       "no change heard yet: no last one")
        XCTAssertEqual(row(.connected, last: 5).detail, "Changes from your other devices arrive within seconds. Last one just now.")
        XCTAssertEqual(row(.connected, last: 120, .mac(syncWithoutWindow: false)).detail,
                       "Changes from your other devices arrive within seconds, until you close the last window.")
        XCTAssertEqual(row(.connected, last: 120, .iPhone).detail,
                       "Changes from your other devices arrive within seconds while Tasks is open. Last one 2 min ago.")
    }

    func testConnecting() {
        let r = row(.connecting)
        XCTAssertEqual(r.dot, .ring)
        XCTAssertEqual(r.word, "Connecting…")
        XCTAssertEqual(r.detail, "Checking every 30 s until it connects.")
        XCTAssertEqual(r.spoken, "Connecting. Checking every 30 seconds until it connects.")
        XCTAssertEqual(row(.connecting, pace: 60).detail, "Checking every minute until it connects.", "a windowless Mac")
    }

    func testReconnecting() {
        let until = now.addingTimeInterval(7.2)
        let mac = row(.waiting(until: until, why: .dropped), dropped: 180)
        XCTAssertEqual(mac.kind, .reconnecting(at: until))
        XCTAssertEqual(mac.dot, .ring)
        XCTAssertEqual(mac.word, "Reconnecting in 8 s")
        XCTAssertEqual(mac.detail, "Lost the connection at \(time(180)). Checking every 30 s meanwhile.")
        XCTAssertEqual(mac.spoken, "Reconnecting in 8 seconds. Lost the connection at \(time(180)). Checking every 30 seconds meanwhile.")
        let phone = row(.waiting(until: until, why: .dropped), dropped: 180, .iPhone)
        XCTAssertEqual(phone.word, "Reconnecting")
        XCTAssertEqual(phone.detail, "Lost the connection at \(time(180)). Trying again in 8 s; checking every 30 s meanwhile.")
        // A long backoff counts in minutes; a failed try that never connected says so.
        let long = row(.waiting(until: now.addingTimeInterval(200), why: .dropped))
        XCTAssertEqual(long.word, "Reconnecting in 4 min")
        XCTAssertEqual(long.detail, "Couldn't connect. Checking every 30 s meanwhile.")
        XCTAssertEqual(row(.waiting(until: now.addingTimeInterval(-1), why: .dropped)).word, "Reconnecting in 1 s")
    }

    func testOfflineWinsOverTryingAndWaiting() {
        for state: SyncSocket.State in [.connecting, .waiting(until: now + 4, why: .dropped), .waiting(until: now + 3600, why: .oldServer)] {
            let r = row(state, offline: true, dropped: 60)
            XCTAssertEqual(r.kind, .offline, "\(state)")
            XCTAssertEqual(r.dot, .quiet)
            XCTAssertEqual(r.word, "Offline")
            XCTAssertEqual(r.detail, "No network. Reconnects as soon as it's back.")
        }
        XCTAssertEqual(row(.connected, offline: true).kind, .live, "connected is connected")
        XCTAssertEqual(row(.stopped, offline: true).kind, .rejected)
    }

    func testNotAvailable() {
        let at = now.addingTimeInterval(3400)
        let r = row(.waiting(until: at, why: .oldServer))
        XCTAssertEqual(r.kind, .notAvailable(retryAt: at))
        XCTAssertEqual(r.dot, .quiet)
        XCTAssertEqual(r.word, "Not available")
        let when = LiveStatus.at(at, now: now, calendar: cal)
        XCTAssertEqual(r.detail, "This server doesn't have them yet. Checking every 30 s; trying again \(when).")
    }

    func testRejectedAndOff() {
        let r = row(.stopped)
        XCTAssertEqual(r.dot, .attention)
        XCTAssertEqual(r.word, "Token rejected")
        XCTAssertEqual(r.detail, "The server didn't accept the token. Save it again above.")
        XCTAssertEqual(row(.stopped, .iPhone).word, "Rejected")
        XCTAssertEqual(row(.stopped, .iPhone).spoken, "Token rejected. The server didn't accept the token. Save it again above.")
        let off = row(.off, .mac(syncWithoutWindow: false))
        XCTAssertEqual(off.dot, .quietRing)
        XCTAssertEqual(off.word, "Off")
        XCTAssertEqual(off.detail, "Only while a window is open. Turn on Sync with no window open to keep them.")
        XCTAssertEqual(row(.off, .iPhone).detail, "Only while Tasks is open. In the background, Background refresh takes over.")
    }

    func testWords() {
        XCTAssertEqual(LiveStatus.pace(30), "every 30 s")
        XCTAssertEqual(LiveStatus.pace(60), "every minute")
        XCTAssertEqual(LiveStatus.pace(300), "every 5 min")
        XCTAssertEqual(LiveStatus.pace(30, spoken: true), "every 30 seconds")
        XCTAssertEqual(LiveStatus.pace(for: .front), 30)
        XCTAssertEqual(LiveStatus.pace(for: .windowless), 60)
        XCTAssertEqual(LiveStatus.countdown(to: now + 59.5, now: now), "1 min", "60 s reads as a minute")
        XCTAssertEqual(LiveStatus.countdown(to: now + 58.5, now: now), "59 s")
        XCTAssertEqual(LiveStatus.countdown(to: now + 1, now: now, spoken: true), "1 second")
        XCTAssertEqual(LiveStatus.countdown(to: now + 61, now: now, spoken: true), "2 minutes")
        XCTAssertEqual(LiveStatus.tipLine(live: true, pace: 30), "Live")
        XCTAssertEqual(LiveStatus.tipLine(live: false, pace: 30), "Checking every 30 s")
        XCTAssertEqual(LiveStatus.tipLine(live: false, pace: 30, spoken: true), "Checking every 30 seconds")
        XCTAssertEqual(LiveStatus.symbol(live: true), "bolt.horizontal.icloud")
        XCTAssertEqual(LiveStatus.symbol(live: false), "icloud")
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let t = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(LiveStatus.at(noon + 600, now: noon, calendar: cal), "at " + t(noon + 600))
        XCTAssertEqual(LiveStatus.at(noon - 86400, now: noon, calendar: cal), "yesterday at " + t(noon))
        XCTAssertEqual(LiveStatus.at(noon + 86400, now: noon, calendar: cal), "tomorrow at " + t(noon))
        XCTAssertEqual(LiveStatus.ago(noon - 7200, now: noon, calendar: cal), "at " + t(noon - 7200))
        XCTAssertEqual(LiveStatus.ago(noon - 86400, now: noon, calendar: cal), "yesterday at " + t(noon))
        XCTAssertEqual(LiveStatus.ago(noon - 60, now: noon, spoken: true, calendar: cal), "1 minute ago")
    }

    /// The bolt only once connected; the plain cloud only after 5 s down; a reconnect inside them doesn't flip it.
    func testTheLiveCloudWaitsFiveSecondsBeforeGoingPlain() {
        var g = LiveGlyph()
        XCTAssertFalse(g.live, "the plain cloud at launch")
        XCTAssertNil(g.update(connected: false, now: 0), "nothing to wait for")
        XCTAssertNil(g.update(connected: true, now: 1))
        XCTAssertTrue(g.live)
        XCTAssertEqual(g.update(connected: false, now: 10), 15, "down: check again at 15")
        XCTAssertTrue(g.live)
        XCTAssertEqual(g.update(connected: false, now: 14), 15, "still counting from 10")
        XCTAssertTrue(g.live)
        XCTAssertNil(g.update(connected: true, now: 14.5), "back before 5 s: never flipped")
        XCTAssertTrue(g.live)
        XCTAssertEqual(g.update(connected: false, now: 20), 25)
        XCTAssertNil(g.update(connected: false, now: 25))
        XCTAssertFalse(g.live, "5 s down: the plain cloud")
    }

    /// The iPhone in the background: the count stops, and coming back starts it again.
    func testPausingForgetsTheDownTime() {
        var g = LiveGlyph()
        g.update(connected: true, now: 0)
        XCTAssertEqual(g.update(connected: false, now: 1), 6)
        g.pause()
        XCTAssertTrue(g.live, "kept")
        XCTAssertEqual(g.update(connected: false, now: 600), 605, "an hour later: 5 s from now, not from then")
        XCTAssertTrue(g.live)
        XCTAssertNil(g.update(connected: true, now: 601.5))
        XCTAssertTrue(g.live, "reconnected inside them: never flipped")
    }
}
