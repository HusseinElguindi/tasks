import XCTest
import WidgetKit
import TasksCore
@testable import Tasks

/// The List widget and the lock screen's widgets as they compute what to show from a feed (widgets/Shared and
/// ios/Widgets/LockWidgets.swift are compiled into this bundle): read-only, no counts, no completed tasks.
@MainActor
final class WidgetListLockTests: XCTestCase {
    private static let day = Day(containing: CalendarDate(year: 2026, month: 11, day: 5)!.startDate().addingTimeInterval(9 * 3600))
    private static var d: CalendarDate { day.date }

    private static let school = WidgetFeed.List(id: "school", name: "School", order: "a0", slot: 0)
    private static let home = WidgetFeed.List(id: "home", name: "Home", order: "a1", slot: 2)

    private func overlay(_ tasks: [TaskItem], tops: [EntityID: [EntityID]] = [:]) -> WidgetOverlay {
        WidgetOverlay(feed: WidgetFeed(written: 0, lists: [Self.school, Self.home], tasks: tasks, listTops: tops))
    }

    // MARK: The List widget

    func testAListShowsItsOpenTasksInOrderWithItsHeadings() throws {
        let d = Self.d
        let tasks = [
            TaskItem(id: "t1", list: "school", order: "a0", title: "Email Prof. Lin", deadline: d.adding(days: -2)),
            TaskItem(id: "t2", list: "school", order: "a1", title: "Return library books", when: d),
            TaskItem(id: "done", list: "school", order: "a2", title: "Done already", completedAt: Self.day.start + 1),
            TaskItem(id: "h1", list: "school", order: "a3", title: "Readings", isHeading: true),
            TaskItem(id: "t3", list: "school", order: "a4", title: "Read chapter 8", when: d.adding(days: 4)),
            TaskItem(id: "h2", list: "school", order: "a5", title: "Empty heading", isHeading: true),
            TaskItem(id: "h3", list: "school", order: "a6", title: "Lab", isHeading: true),
            TaskItem(id: "t4", list: "school", order: "a7", title: "Lab report draft", deadline: d.adding(days: 7)),
            TaskItem(id: "h4", list: "school", order: "a8", title: "Trailing heading", isHeading: true),
        ]
        let s = ListSnapshot(overlay(tasks, tops: ["school": tasks.map(\.id)]), list: "school", day: Self.day)
        XCTAssertEqual(s.list.name, "School")
        XCTAssertEqual(s.list.monogram, "S")
        guard case let .items(items) = s.content else { return XCTFail("the list has tasks") }
        XCTAssertEqual(items.map(\.id), ["task:t1", "task:t2", "label:h1", "task:t3", "label:h3", "task:t4"],
                       "completed tasks are gone, and so are headings with nothing open under them")
        XCTAssertEqual(s.rows.map(\.id), ["t1", "t2", "t3", "t4"], "medium: the tasks alone")
        XCTAssertEqual(s.rows.map(\.when), [nil, "Today", "in 4d", nil], "the When in the app's words")
        XCTAssertEqual(s.rows.map { $0.chip?.text }, ["2d ago", nil, nil, "7d left"])
        XCTAssertEqual(s.rows.map(\.cue), [.late, .planned, .none, .none])
        XCTAssertTrue(s.complete)
        XCTAssertEqual(s.more(2), "2 more")
    }

    func testAFullListTopMayHoldMoreThanTheFeedKnows() {
        let tasks = (0..<WidgetFeed.listTopCount).map {
            TaskItem(id: "t\($0)", list: "home", order: String(format: "a%02d", $0), title: "Task \($0)")
        }
        let s = ListSnapshot(overlay(tasks, tops: ["home": tasks.map(\.id)]), list: "home", day: Self.day)
        XCTAssertFalse(s.complete)
        XCTAssertEqual(s.more(3), "3+ more")
    }

    func testAnEmptyListAndOneInTheTrash() {
        let empty = ListSnapshot(overlay([], tops: ["home": []]), list: "home", day: Self.day)
        XCTAssertEqual(empty.content, .empty)
        let gone = ListSnapshot(overlay([]), list: "deleted-1", name: "Old Projects", day: Self.day)
        XCTAssertEqual(gone.content, .trash, "a list not in the feed is deleted, in the Trash, or gone")
        XCTAssertEqual(gone.list.name, "Old Projects")
    }

    func testANewListWidgetShowsTheSidebarsFirstList() {
        guard case let .list(s) = ListProvider.content(overlay([]), list: nil, at: Date()) else {
            return XCTFail("a list")
        }
        XCTAssertEqual(s.list.id, "school")
        XCTAssertEqual(ListProvider.content(nil, list: nil, at: Date()), .setUp)
        let timeline = ListProvider.timeline(overlay: overlay([]), list: ListEntity(id: "home", name: "Home"), now: Date())
        XCTAssertEqual(timeline.entries.count, 1 + TodayProvider.midnights, "now and the next midnights")
        XCTAssertEqual(timeline.policy, .atEnd)
    }

    func testTheListChoicesAreTheFeedsLiveLists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetListLockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try WidgetFeed(written: 0, lists: [Self.school, Self.home], tasks: [], listTops: [:])
            .write(at: WidgetFeed.url(in: dir))
        XCTAssertEqual(ListQuery.lists(in: dir).map(\.name), ["School", "Home"], "in sidebar order")
        XCTAssertTrue(ListQuery.lists(in: dir.appendingPathComponent("none")).isEmpty, "no feed, no choices")
    }

    // MARK: Today has no completed tasks

    func testTodaysWidgetsShowNoCompletedTasks() {
        let tasks = [
            TaskItem(id: "a", list: "school", order: "a0", title: "Open", when: Self.d),
            TaskItem(id: "b", list: "school", order: "a1", title: "Done", when: Self.d, completedAt: Self.day.start + 1),
        ]
        let s = TodaySnapshot(overlay(tasks), day: Self.day)
        XCTAssertEqual(TodayLargeView.items(s).map(\.id), ["label:school", "task:a"])
        XCTAssertEqual(s.open.map(\.id), ["a"])
        XCTAssertEqual(AllDoneView.words(TodaySnapshot(overlay([tasks[1]]), day: Self.day)), "All done")
        XCTAssertEqual(AllDoneView.words(TodaySnapshot(overlay([]), day: Self.day)), "Nothing today")
    }

    // MARK: The lock screen

    func testTheLockScreenShowsTodaysTasksWithAWordForTheUrgentOnes() {
        let d = Self.d
        let tasks = [
            TaskItem(id: "1", list: "school", order: "a0", title: "Email Prof. Lin about the lab", deadline: d.adding(days: -2)),
            TaskItem(id: "2", list: "school", order: "a1", title: "Problem set 6", deadline: d),
            TaskItem(id: "3", list: "school", order: "a2", title: "Return library books", when: d),
            TaskItem(id: "4", list: "home", order: "a0", title: "Buy milk", when: d),
        ]
        let t = LockToday(.today(TodaySnapshot(overlay(tasks), day: Self.day)))
        XCTAssertNil(t.empty)
        XCTAssertEqual(t.rows.map(\.title).first, "Email Prof. Lin about the lab", "inline: the first open task")
        XCTAssertEqual(t.rows.map(\.word), ["2d ago", "Due", nil, nil])
        XCTAssertEqual(t.spoken(Array(t.rows.prefix(LockToday.rectangularRows))),
                       "Today: Email Prof. Lin about the lab, 2 days overdue. Problem set 6, due today. Return library books")
    }

    func testTheLockScreensEmptyStates() {
        let done = TaskItem(id: "b", list: "school", order: "a1", title: "Done", when: Self.d, completedAt: Self.day.start + 1)
        let allDone = LockToday(.today(TodaySnapshot(overlay([done]), day: Self.day)))
        XCTAssertEqual(allDone.empty, "All done")
        XCTAssertTrue(allDone.allDone)
        XCTAssertEqual(allDone.rows, [], "no completed task shows")
        XCTAssertEqual(LockToday(.today(TodaySnapshot(overlay([]), day: Self.day))).empty, "Nothing today")
        XCTAssertEqual(LockToday(.setUp).empty, "Open Tasks to set up")
    }
}
