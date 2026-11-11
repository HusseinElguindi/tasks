import XCTest

/// `PaneLayout` and `PaneFrames` (Tasks/Window/PaneLayout.swift): which panes exist, and where each is drawn. The
/// stuck detail pane (T50) was a pane left on screen after its close, because SwiftUI's removal transition decided
/// what was drawn while a Bool said it was closed. Here a closing pane stays in the layout, off to the side and clear,
/// until `unmount` takes it out, and a reopen in between keeps it.
final class PaneLayoutTests: XCTestCase {
    func testTheListIsAlwaysThereAndNeverCloses() {
        var l = PaneLayout()
        XCTAssertEqual(l.panes.map(\.id), [.list])
        XCTAssertTrue(l.isOpen(.list))
        XCTAssertNil(l.close(.list))
        XCTAssertEqual(l.panes.map(\.id), [.list])
    }

    func testOpeningAddsTheDetailPaneAfterTheList() {
        var l = PaneLayout()
        XCTAssertTrue(l.open(.detail, kind: .detail, after: .list))
        XCTAssertEqual(l.panes.map(\.id), [.list, .detail])
        XCTAssertTrue(l.isOpen(.detail))
        XCTAssertFalse(l.open(.detail, kind: .detail, after: .list), "already open: no change")
    }

    func testAClosingPaneIsClosedButStillDrawnUntilUnmounted() {
        var l = PaneLayout()
        l.open(.detail, kind: .detail, after: .list)
        let token = try! XCTUnwrap(l.close(.detail))
        XCTAssertFalse(l.isOpen(.detail), "× and Esc see it closed at once")
        XCTAssertTrue(l.isMounted(.detail), "it slides away before it goes")
        XCTAssertNil(l.close(.detail), "closing twice hands out no second token")
        XCTAssertTrue(l.unmount(.detail, token: token))
        XCTAssertFalse(l.isMounted(.detail))
        XCTAssertEqual(l.panes.map(\.id), [.list])
    }

    /// The stuck pane's trigger: + then Esc, closing the pane as it opens; and ⌘D twice, quickly.
    func testReopeningWhileClosingKeepsThePaneAndVoidsItsUnmount() {
        var l = PaneLayout()
        l.open(.detail, kind: .detail, after: .list)
        let token = try! XCTUnwrap(l.close(.detail))
        XCTAssertTrue(l.open(.detail, kind: .detail, after: .list))
        XCTAssertTrue(l.isOpen(.detail))
        XCTAssertFalse(l.unmount(.detail, token: token), "the first close's unmount comes too late and does nothing")
        XCTAssertTrue(l.isOpen(.detail))
        // Closed again: only the new token takes it out.
        let second = try! XCTUnwrap(l.close(.detail))
        XCTAssertNotEqual(second, token)
        XCTAssertFalse(l.unmount(.detail, token: token))
        XCTAssertTrue(l.unmount(.detail, token: second))
        XCTAssertFalse(l.isMounted(.detail))
    }

    // MARK: Frames: today's four cases (§4, §29) at 1300 × 800, sidebar 230, detail 420, gutter 8.

    private func frames(_ l: PaneLayout, narrow: Bool = false, zoomed: Bool = false) -> PaneFrames {
        PaneFrames(layout: l, width: 1300, height: 800, lead: 230, detailWidth: 420, gutter: 8, narrow: narrow, zoomed: zoomed)
    }

    private var open: PaneLayout {
        var l = PaneLayout()
        l.open(.detail, kind: .detail, after: .list)
        return l
    }

    func testTheListAlone() {
        let f = frames(PaneLayout())
        XCTAssertEqual(f.list.rect, CGRect(x: 230, y: 8, width: 1062, height: 784))
        XCTAssertEqual(f.list.opacity, 1)
        XCTAssertNil(f.detail)
    }

    func testTheDetailPaneBesideTheList() {
        let f = frames(open)
        XCTAssertEqual(f.list.rect, CGRect(x: 230, y: 8, width: 634, height: 784))
        XCTAssertEqual(f.detail?.rect, CGRect(x: 872, y: 8, width: 420, height: 784))
        XCTAssertEqual(f.detail?.opacity, 1)
        XCTAssertEqual(f.detail?.interactive, true)
        XCTAssertEqual(f.detailSlide, 420, "it comes in from the panes' trailing edge, as .move(edge: .trailing) did")
    }

    func testAClosingDetailPaneSlidesOffClearAndDeafWhileTheListWidens() {
        var l = open
        _ = l.close(.detail)
        let f = frames(l)
        XCTAssertEqual(f.list.rect.width, 1062)
        XCTAssertEqual(f.detail?.rect, CGRect(x: 1292, y: 8, width: 420, height: 784))
        XCTAssertEqual(f.detail?.opacity, 0)
        XCTAssertEqual(f.detail?.interactive, false)
    }

    func testZoomedTheDetailPaneHasTheListsRoomAndTheListKeepsItsWidthUnderIt() {
        let f = frames(open, zoomed: true)
        XCTAssertEqual(f.list.rect, CGRect(x: 230, y: 8, width: 634, height: 784))
        XCTAssertEqual(f.list.opacity, 0)
        XCTAssertFalse(f.list.interactive)
        XCTAssertEqual(f.detail?.rect, CGRect(x: 230, y: 8, width: 1062, height: 784))
    }

    func testNarrowTheDetailPaneTakesTheListsPlace() {
        let f = frames(open, narrow: true)
        XCTAssertEqual(f.list.opacity, 0)
        XCTAssertFalse(f.list.interactive)
        XCTAssertEqual(f.detail?.rect, CGRect(x: 230, y: 8, width: 1062, height: 784))
        XCTAssertEqual(f.detailSlide, 1062)
        // A narrow window has nothing to zoom over: zoomed changes nothing.
        XCTAssertEqual(frames(open, narrow: true, zoomed: true), f)
    }
}
