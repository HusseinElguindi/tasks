import XCTest

/// XCTest's `waitForExistence(timeout:)` and `waitForNonExistence(timeout:)` first look about 1 s after they're
/// called, even when the element is already there: in the log each "Waiting 3.0s for …" is followed by its first
/// "Checking existence" 1.03 s later. Across the suite that was over 6 minutes spent on things that were already true.
/// These mean the same (true as soon as the element is there, or gone; false if it isn't by the timeout), but look at
/// once and then every 0.1 s.
extension XCUIElement {
    func appears(timeout: TimeInterval) -> Bool { eventually(timeout) { self.exists } }
    func vanishes(timeout: TimeInterval) -> Bool { eventually(timeout) { !self.exists } }
}

/// True as soon as `condition` holds, looking at once and then every 0.1 s; false if it still doesn't at `timeout`.
func eventually(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while true {
        if condition() { return true }
        if Date() >= end { return false }
        usleep(100_000)
    }
}

extension XCUIApplication {
    /// Until the app is idle: its event loop quiet and, unless `idleAnimationWaitEnabled` is off (FlowTests.menuOpen),
    /// its animations finished. This is the wait XCTest makes before and after each tap or press ("Wait for … to
    /// idle"); here on its own, in place of a fixed `sleep(1)` after a step whose motion should be over before the
    /// next look. Not for something the app does on a timer (a notice's life, a delayed settle): wait on that itself.
    /// `_waitForQuiescenceAsPreEvent:` is XCUIApplication's own (private); if an Xcode drops it, this sleeps 1 s, as
    /// the tests did before.
    func settle() {
        let sel = NSSelectorFromString("_waitForQuiescenceAsPreEvent:")
        guard responds(to: sel) else { sleep(1); return }
        typealias Wait = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method(for: sel), to: Wait.self)(self, sel, false)
    }
}
