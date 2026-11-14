import XCTest

/// `WrapSettle` (Tasks/Window/WrapSettle.swift): while a pane's width animates, the text in it wraps once, at the width
/// it's going to, as the slide starts (the user, 2026-11-08, about the list pane; 2026-11-14: "we need to do the same
/// on detail"). The view's width is the pane's less what's around it, so it's going to its own width plus what the
/// pane gains.
@MainActor
final class WrapSettleTests: XCTestCase {
    /// A view 36 narrower than its pane (the detail pane's notes), told the pane's first width.
    private func settled(pane: CGFloat = 420) -> (WrapSettle, () -> Int) {
        let s = WrapSettle()
        var ended = 0
        s.onEnd = { ended += 1 }
        XCTAssertFalse(s.pane(PaneSettle(width: pane), animated: true, wrap: pane - 36, inWindow: true), "the first width: nothing to settle")
        XCTAssertNil(s.to)
        return (s, { ended })
    }

    func testAnAnimatedChangeWrapsAtTheWidthTheViewIsGoingTo() {
        let (s, ended) = settled()
        XCTAssertTrue(s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: true))
        XCTAssertEqual(s.span?.from, 384)
        XCTAssertEqual(s.to, 826, "the view gains what the pane gains")
        // The widths on the way don't end it; the one it was going to does.
        XCTAssertFalse(s.arrived(500))
        XCTAssertFalse(s.arrived(825.6), "near isn't there: the last half point of a spring could move a word")
        XCTAssertEqual(s.to, 826)
        XCTAssertTrue(s.arrived(826))
        XCTAssertNil(s.to)
        XCTAssertEqual(ended(), 1)
    }

    func testWhatIsUnderTheTextMovesWithTheWidth() {
        let (s, _) = settled()
        _ = s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: true)
        XCTAssertEqual(s.progress(at: 384), 0)
        XCTAssertEqual(s.progress(at: 605), 0.5)
        XCTAssertEqual(s.progress(at: 826), 1)
        XCTAssertEqual(s.progress(at: 0), 0, "a width from outside the slide (SwiftUI asking what fits) is clamped")
        XCTAssertEqual(s.progress(at: .infinity), 1)
    }

    func testALiveChangeIsFollowedAndEndsASettle() {
        let (s, ended) = settled()
        // A divider dragged, the window resized: not animated.
        XCTAssertFalse(s.pane(PaneSettle(width: 500), animated: false, wrap: 384, inWindow: true))
        XCTAssertNil(s.to)
        XCTAssertEqual(ended(), 0)
        _ = s.pane(PaneSettle(width: 862), animated: true, wrap: 464, inWindow: true)
        XCTAssertEqual(s.to, 826)
        XCTAssertFalse(s.pane(PaneSettle(width: 700), animated: false, wrap: 826, inWindow: true))
        XCTAssertNil(s.to, "the drag takes over")
        XCTAssertEqual(ended(), 1)
    }

    func testTheSameWidthAgainChangesNothing() {
        let (s, ended) = settled()
        _ = s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: true)
        // Another update mid-slide (typing, a sync) carries the same settle, animated or not.
        XCTAssertFalse(s.pane(PaneSettle(width: 862), animated: false, wrap: 826, inWindow: true))
        XCTAssertEqual(s.to, 826)
        XCTAssertEqual(ended(), 0)
    }

    func testTurningBackMidSlideGoesBackToTheWidthItCameFrom() {
        let (s, _) = settled()
        _ = s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: true)
        // Unzoomed before the zoom finished: the text is wrapped at 826, and goes back by what the pane loses.
        XCTAssertTrue(s.pane(PaneSettle(width: 420), animated: true, wrap: 826, inWindow: true))
        XCTAssertEqual(s.span?.from, 826)
        XCTAssertEqual(s.to, 384)
    }

    func testAViewOffScreenOrWithNoPaneDoesNotSettle() {
        let (s, _) = settled()
        XCTAssertFalse(s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: false))
        XCTAssertNil(s.to)
        XCTAssertFalse(s.pane(nil, animated: true, wrap: 384, inWindow: true))
        XCTAssertNil(s.to)
    }

    func testALeavingPaneKeepsItsWrapWhateverWidthsItTakes() {
        let (s, ended) = settled(pane: 862)
        // A zoomed detail pane closing: its frame narrows as it slides off, and its text stays as it is.
        XCTAssertFalse(s.pane(PaneSettle(width: 420, leaving: true), animated: true, wrap: 826, inWindow: true), "no re-wrap")
        XCTAssertEqual(s.to, 826)
        XCTAssertFalse(s.arrived(826))
        XCTAssertFalse(s.arrived(600))
        XCTAssertEqual(s.to, 826)
        XCTAssertEqual(s.progress(at: 600), 1, "and nothing under it moves")
        // Opened again before it left, beside the list now: it settles from the wrap it kept.
        XCTAssertTrue(s.pane(PaneSettle(width: 420), animated: true, wrap: 826, inWindow: true))
        XCTAssertEqual(s.to, 384)
        XCTAssertEqual(ended(), 0)
    }

    func testEndingTwiceTellsTheViewOnce() {
        let (s, ended) = settled()
        _ = s.pane(PaneSettle(width: 862), animated: true, wrap: 384, inWindow: true)
        s.end()
        s.end()
        XCTAssertEqual(ended(), 1)
    }
}
