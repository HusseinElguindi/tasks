#if DEBUG
import Foundation
import TasksCore

/// Debug aid: `-demoData YES` fills an empty data folder with the lists and tasks from the design boards (dates
/// relative to today), for screenshots and manual testing. `-debugRoute today|upcoming|undated|completed|trash|list:<name>`,
/// `-debugOpen <task title>` and `-debugQuickAdd YES` set up the window; `-debugHover` hovers items without a pointer
/// (comma-separated: `today`, `lists`, `archive`, `newList`, `list:<name>`, `group:<list name>`, `task:<title>`).
/// Never compiled into release builds.
@MainActor
enum DemoData {
    /// The prototype's seed (design/prototype-v2/Main.dc.html dc:435–509), dates relative to today, so the app and
    /// the prototype can be compared side by side.
    static func seedIfRequested(_ store: Store) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "demoData"), store.projection.allTaskIDs.isEmpty else { return }
        let today = store.projection.day.date
        let dayMs = 86_400_000
        let startOfToday = Int(today.startDate().timeIntervalSince1970 * 1000)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        func day(_ n: Int) -> CalendarDate { today.adding(days: n) }
        // doneAt(k): k days ago at 15:00, or 20 minutes ago today.
        func doneAt(_ k: Int) -> Int { k == 0 ? max(startOfToday + 60_000, now - 20 * 60_000) : startOfToday - k * dayMs + 15 * 3_600_000 }
        let inbox = store.defaultListID
        let school = store.createList(name: "School")
        let tasksApp = store.createList(name: "Tasks app")
        let home = store.createList(name: "Home")
        let errands = store.createList(name: "Errands")
        let winter = store.createList(name: "Winter 2026")
        let move = store.createList(name: "Apartment move")
        func t(_ list: EntityID?, _ title: String, when: Int? = nil, deadline: Int? = nil, notes: String = "", done: Int? = nil,
               del: Int? = nil) {
            guard let id = store.createTask(title: title, notes: notes, in: list, when: when.map(day), deadline: deadline.map(day)) else { return }
            if let done {
                store.perform([Op(id: store.newID(), at: now, type: .taskUpdate, target: id, set: Patch(completedAt: .some(doneAt(done))))])
            }
            if let del {
                // Deleted an hour before `doneAt(del)`: the Trash orders by the delete op's time (dc:455).
                store.perform([Op(id: store.newID(), at: doneAt(del) - 3_600_000, type: .taskUpdate, target: id, set: Patch(deleted: true))])
            }
        }
        t(school, "ECE 358 lab report", when: -3, deadline: -2)
        t(school, "Email TA about midterm regrade", when: 0)
        t(school, "Review CS 489 lectures 10–14", when: 0, deadline: 3, notes: "Slides 10–14 plus the two retrieval readings.\n\n- Make cards for the **attention** derivation\n- Redo tutorial 6, question 3\n\n[Lecture 12 recording](https://example.com/cs489) · bring `q3.py` to tutorial")
        t(school, "Submit MSE 333 A2", when: 2, deadline: 3)
        t(school, "CS 489 final study plan", when: 10)
        t(school, "Print ECE 358 formula sheet")
        t(school, "Ask about co-op interview slots")
        t(school, "Submit ECE 358 lab 3", done: 2)
        t(school, "Read MSE 333 chapter 6", done: 4)
        t(school, "Register for winter courses", done: 9)
        t(tasksApp, "Write sync log spec", when: 0)
        t(tasksApp, "Redesign the interactions", when: 0, deadline: 1, notes: "Adding, renaming, dates, drag. Prototype first, then *INTERACTIONS-v2.md*.")
        t(tasksApp, "Profile list switching")
        t(tasksApp, "Try the build on the old MacBook", when: 4)
        t(tasksApp, "Ship the overnight build", done: 1)
        t(home, "Book flu shot", deadline: 0)
        t(home, "Pick up prescription", when: -1)
        t(home, "Fix the bathroom fan", when: 7)
        t(home, "Call landlord about the heating")
        t(errands, "Return library books", deadline: 0)
        t(errands, "Buy printer paper", when: 1)
        t(errands, "Renew transit pass", when: 0, done: 0)
        t(inbox, "Look into a standing desk")
        t(inbox, "Reply to Sam about Saturday", when: 1)
        t(inbox, "Read DDIA chapter 5", notes: "Replication. Skim the leaderless part.")
        t(winter, "Study for ECE 222 final", done: 200)
        t(winter, "Return the oscilloscope kit")
        t(move, "Forward mail", done: 50)
        t(move, "Cancel the old internet plan")
        t(move, "Return the moving boxes")
        // For the four views (§22, dc:487–508): dates after today, more undated tasks, a history of completed ones, and
        // the Trash.
        t(school, "Midterm review session", when: 1)
        t(errands, "Pick up winter tires", when: 11)
        t(tasksApp, "Write the release notes", deadline: 4)
        t(errands, "Return the drill to Alex", when: 12, deadline: 9)
        t(home, "Renew passport", when: 20, deadline: 45)
        t(school, "ECE 358 final exam", deadline: 38)
        t(inbox, "Plan the winter break trip", when: 52)
        t(home, "Book a dentist cleaning", when: 64)
        t(errands, "Get a spare key cut")
        t(school, "Meet the ECE 358 lab group", done: 3)
        t(home, "Replace the smoke detector battery", done: 6)
        t(inbox, "Order new headphones", done: 12)
        t(tasksApp, "Draft the sync log spec", done: 21)
        t(home, "Pay rent", done: 30)
        t(tasksApp, "Pick a name for the app", done: 47)
        t(inbox, "Try the new notes app", del: 0)
        t(school, "Old group project notes", notes: "Superseded by the shared doc.", del: 1)
        t(home, "Buy a second lamp", when: 2, notes: "The one by the window is fine after all.", del: 3)
        t(errands, "Pick up dry cleaning", done: 9, del: 8)
        t(tasksApp, "Prototype a menu bar widget", del: 20)
        store.perform([Op(id: store.newID(), at: now, type: .listUpdate, target: winter, set: Patch(archivedAt: .some(now - 180 * dayMs)))])
        store.perform([Op(id: store.newID(), at: now, type: .listUpdate, target: move, set: Patch(archivedAt: .some(now - 48 * dayMs)))])
        if let n = Int(d.string(forKey: "demoBulk") ?? ""), n > 0 {
            let big = store.createList(name: "Big")
            for i in 0..<n { store.createTask(title: "Bulk task \(i) with a title of a realistic length", in: big) }
        }
    }

    /// `-debugRoute today|list:<name>`, `-debugSelect <title>[|<title>…]`, `-debugDetail YES`, `-debugAdd YES`,
    /// `-debugThenRoute …` (0.8 s later).
    static func applyDebugRoute(_ store: Store, _ window: WindowState) {
        let d = UserDefaults.standard
        let p = store.projection
        let actions = WindowActions(store: store, window: window)
        func list(_ name: String) -> EntityID? { p.allListIDs.first { p.list($0)?.name == name } }
        func view(_ name: String) -> WindowState.Route {
            switch name {
            case "upcoming": .upcoming
            case "undated": .undated
            case "completed": .completed
            case "trash": .trash
            default: .today
            }
        }
        if let route = d.string(forKey: "debugRoute") {
            if route.hasPrefix("list:"), let id = list(String(route.dropFirst(5))) { window.route = .list(id) } else { window.route = view(route) }
        }
        if let titles = d.string(forKey: "debugSelect")?.split(separator: "|").map(String.init) {
            // Several titles, separated by "|", select them all.
            let ids = titles.compactMap { t in p.allTaskIDs.first(where: { p.task($0)?.title == t }) }
            if !ids.isEmpty { actions.select(ids) }
        }
        if d.bool(forKey: "debugDetail") { window.detailOpen = true }
        if d.bool(forKey: "debugSidebarHidden") { window.sidebarVisible = false }
        if d.bool(forKey: "debugAdd") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { actions.newTask() }
        }
        if let then = d.string(forKey: "debugThenRoute") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if then.hasPrefix("list:"), let id = list(String(then.dropFirst(5))) { actions.go(.list(id)) } else { actions.go(view(then)) }
            }
        }
    }
}
#endif
