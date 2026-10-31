#if DEBUG
import Foundation
import TasksCore

/// Debug aid for v2 feedback 16: `-demoLongNames YES` (with `-demoData YES`) adds lists and tasks with very long
/// names, so every trailing label can be checked at the panes' minimum widths: the list names after titles in Today's
/// Completed group, Upcoming, Completed (with a month row's date) and Trash; date chips beside long titles; a long
/// heading; and a 200-character list name for the sidebar, the band, the large title and the menus.
@MainActor
enum DemoLongNames {
    static let course = "SE 463 — Software Project Management, Requirements, and Analysis"
    static let longest = String(String(repeating: "A list name that keeps going well past any width a pane could give it ", count: 3).prefix(200))

    static func add(_ store: Store, doneAt: (Int) -> Int) {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let today = store.projection.day.date
        let se = store.createList(name: course)
        let long = store.createList(name: longest)
        func t(_ list: EntityID, _ title: String, when: Int? = nil, deadline: Int? = nil, notes: String = "", done: Int? = nil,
               del: Bool = false) {
            guard let id = store.createTask(title: title, notes: notes, in: list, when: when.map { today.adding(days: $0) },
                                            deadline: deadline.map { today.adding(days: $0) }) else { return }
            if let done { store.perform([Op(id: store.newID(), at: now, type: .taskUpdate, target: id, set: Patch(completedAt: .some(doneAt(done))))]) }
            if del { store.perform([Op(id: store.newID(), at: now - 3_600_000, type: .taskUpdate, target: id, set: Patch(deleted: true))]) }
        }
        // Today's Completed group: short titles with notes, the long list name after them (the screenshot).
        t(se, "Field Notes", when: 0, notes: "x", done: 0)
        t(se, "Study Site A observations", when: 0, notes: "x", done: 0)
        t(se, "Quiz 1", when: 0, notes: "- [x] a\n- [ ] b", done: 0)
        t(long, "Reading response", when: 0, done: 0)
        // Open rows: long titles with both chips and the hint; Upcoming and Undated rows.
        t(se, "Write the requirements elicitation report for the stakeholder interview round", when: 0, deadline: 1, notes: "- [ ] a\n- [x] b")
        t(se, "Prepare the risk register", when: 3, deadline: 5)
        t(long, "Compare the two estimation models and pick one for the project plan", when: 6, deadline: 9)
        t(se, "Draft the project charter")
        // Completed: this week and earlier this month (a month row reads "List · Oct 22").
        t(se, "Submit the team contract", done: 2)
        t(long, "Read the chapter on stakeholder analysis and write the one-page summary", done: 12)
        // Trash.
        t(se, "Old project proposal draft with a long title that runs on", del: true)
        // A long heading.
        store.createHeading(title: "Requirements engineering and the elicitation interviews with every stakeholder group", in: se)
        t(se, "Interview the client")
        // Enough rows that the list scrolls at the window's minimum height (the band's title).
        for i in 1...12 { t(se, "Stakeholder interview \(i)") }
    }
}
#endif
