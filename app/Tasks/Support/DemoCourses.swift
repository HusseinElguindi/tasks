#if DEBUG
import Foundation
import TasksCore

/// Debug aid for row density (design/ROW-DENSITY.md): `-demoData YES -demoCourses YES` fills an empty data folder with
/// the screenshots' data instead of the prototype's seed: an Inbox and five courses with long names, tasks with a When,
/// a Deadline or both, notes and checklists, in Today, Upcoming (the mock-ups' 18 rows, a week later: their today was
/// Sat, Nov 7), Completed and Trash. Dates are relative to today.
@MainActor
enum DemoCourses {
    static func seed(_ store: Store, doneAt: (Int) -> Int) {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let today = store.projection.day.date
        let inbox = store.defaultListID
        let cs = store.createList(name: "CS 489")
        let ece = store.createList(name: "ECE 358 — Computer Networks")
        let se463 = store.createList(name: "SE 463 — Software Project Management, Requirements, and Analysis")
        let earth = store.createList(name: "EARTH 121 — Introductory Earth Sciences")
        let se490 = store.createList(name: "SE 490 — Design Project 1")
        let notes = "Part of the course outline. Submit on LEARN by 11:59 PM."
        // The mock-ups' days were Nov 7 + n; here they're today + (n − 7).
        func t(_ list: EntityID?, _ title: String, when: Int? = nil, deadline: Int? = nil, notes: String = "",
               done: Int? = nil, del: Int? = nil) {
            func day(_ n: Int) -> CalendarDate { today.adding(days: n) }
            guard let id = store.createTask(title: title, notes: notes, in: list, when: when.map(day), deadline: deadline.map(day))
            else { return }
            if let done {
                store.perform([Op(id: store.newID(), at: now, type: .taskUpdate, target: id, set: Patch(completedAt: .some(doneAt(done))))])
            }
            if let del {
                store.perform([Op(id: store.newID(), at: doneAt(del), type: .taskUpdate, target: id, set: Patch(deleted: true))])
            }
        }
        func up(_ list: EntityID?, _ title: String, when: Int? = nil, dl: Int? = nil, notes: String = "") {
            t(list, title, when: when.map { $0 - 7 }, deadline: dl.map { $0 - 7 }, notes: notes)
        }
        // Today: open, and its Completed group.
        t(cs, "Assignment 3 — Transformers and attention", when: 0, deadline: 0, notes: notes)
        t(se463, "Deliverable 3 — peer review", when: 0, deadline: 1, notes: "- [x] Read the rubric\n- [ ] Review two teams")
        t(inbox, "Reply to the co-op coordinator", when: 0)
        t(earth, "Quiz 2", when: 0, notes: notes, done: 0)
        t(ece, "Lab 2 report", when: 0, notes: notes, done: 0)
        // Upcoming: the mock-ups' rows (C-Days.dc.html), in their order.
        up(inbox, "Renew iOS signing on the Ex-Mac (press ⌘B in Xcode)", when: 11, dl: 17)
        up(earth, "Field Notes Journals 6–10", when: 11, dl: 34, notes: notes)
        up(cs, "Assignment 4 — Finetuning, Alignment & LM APIs", when: 13, dl: 27, notes: notes)
        up(earth, "Discussion 3 — replies", when: 13, dl: 16, notes: notes)
        up(inbox, "Figure out Bitwarden payment method", when: 14, dl: 20, notes: "- [ ] Update the card")
        up(inbox, "elguindi.com: check owner reply, else place backorder", when: 18, dl: 45, notes: notes)
        up(inbox, "View next term's schedule and appointments", when: 18, notes: "- [ ] Schedule\n- [ ] Advisor\n- [ ] Dentist")
        up(se463, "Deliverable 4", dl: 18, notes: notes)
        up(earth, "Study Site Assessment — Part C", when: 23, dl: 27, notes: notes)
        up(earth, "Quiz 3", when: 23, dl: 38, notes: notes)
        up(inbox, "Check up on OSAP extension", when: 27, notes: notes)
        up(se463, "Assignment 1 — Ambiguity Exercise (optional)", dl: 27, notes: notes)
        up(se490, "Final presentation", dl: 30, notes: notes)
        up(ece, "Lab 3 (Router simulation)", dl: 34, notes: notes)
        up(se463, "Deliverable 5", dl: 39, notes: notes)
        up(cs, "Final exam", dl: 42, notes: notes)
        up(ece, "Final exam", dl: 46, notes: notes)
        up(se463, "Final exam", dl: 48, notes: notes)
        // Undated.
        t(se490, "Book a room for the team meeting")
        // Completed: this week and the month before (a month row reads "CS 489 · Oct 30").
        t(se463, "Deliverable 2", notes: notes, done: 1)
        t(inbox, "Pay the phone bill", done: 3)
        t(cs, "Assignment 2 — Word embeddings", notes: notes, done: 9)
        t(earth, "Field Notes Journals 1–5", notes: notes, done: 20)
        t(se463, "Assignment 0 — Team contract", notes: notes, done: 24)
        // Trash: this week and the month before.
        t(ece, "Lab 1 prelab (duplicate)", del: 0)
        t(inbox, "Old reading list", notes: "Moved to notes.", del: 2)
        t(earth, "Field trip waiver", notes: notes, del: 11)
        t(se490, "Proposal draft v1", notes: notes, del: 15)
    }
}
#endif
