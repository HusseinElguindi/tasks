#if DEBUG
import Foundation
import TasksCore

/// Debug aid: `-demoData YES` fills an empty data folder with the lists and tasks from the design boards (dates
/// relative to today), for screenshots and manual testing. `-debugRoute today|archive|list:<name>`,
/// `-debugOpen <task title>` and `-debugQuickAdd YES` set up the window. Never compiled into release builds.
@MainActor
enum DemoData {
    static func seedIfRequested(_ store: Store) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "demoData"), store.projection.allTaskIDs.isEmpty else { return }
        let today = store.projection.day.date
        func day(_ n: Int) -> CalendarDate { today.adding(days: n) }
        let inbox = store.defaultListID
        let school = store.createList(name: "School")
        let tasksApp = store.createList(name: "Tasks app")
        let home = store.createList(name: "Home")
        let errands = store.createList(name: "Errands")

        store.createTask(title: "Look into a standing desk", in: inbox)
        store.createTask(title: "Reply to Sam about the cabin weekend", in: inbox, when: day(3))

        store.createTask(title: "ECE 358 lab report", in: school, deadline: day(-2))
        store.createTask(title: "Email TA about midterm regrade", in: school, when: day(-1))
        let review = store.createTask(title: "Review CS 489 lectures 10–14",
                                      notes: "Slides 10–14 plus the two retrieval readings.\n\n- Make cards for the **attention** derivation\n- Redo tutorial 6, question 3\n\n[Lecture 12 recording](https://example.com/lecture-12) · bring `q3.py` to tutorial",
                                      in: school, when: today, deadline: day(3))
        store.createTask(title: "Submit MSE 333 A2", in: school, when: day(2), deadline: day(3))
        store.createTask(title: "CS 489 final study plan", in: school, when: day(10))
        store.createTask(title: "Print ECE 358 formula sheet", in: school)
        store.createTask(title: "Ask about co-op interview slots", in: school)
        for i in 0..<5 {
            if let id = store.createTask(title: "Problem set \(i + 1)", in: school) { store.toggleComplete([id]) }
        }

        store.createTask(title: "Write sync log spec", in: tasksApp, when: day(-3))
        store.createTask(title: "Fractional index port", in: tasksApp, when: day(4))
        store.createTask(title: "Design review with Pane boards", in: tasksApp)
        store.createTask(title: "Try the drag vocabulary", in: tasksApp)

        store.createTask(title: "Book flu shot", in: home, deadline: today)
        store.createTask(title: "Pick up prescription", in: home, when: today)
        store.createTask(title: "Fix the bathroom fan", in: home)
        store.createTask(title: "Call the dentist about the crown", in: home, when: day(1))
        store.createTask(title: "Water the plants", in: home)

        store.createTask(title: "Return library books", in: errands, deadline: today)
        if let renew = store.createTask(title: "Renew transit pass", in: errands, when: today) { store.toggleComplete([renew]) }
        store.createTask(title: "Buy printer paper", in: errands)

        let winter = store.createList(name: "Winter 2026 term")
        store.createTask(title: "Return lab kit to the E5 parts store", in: winter, when: day(-10))
        store.createTask(title: "Sell the MATH 213 textbook", in: winter)
        store.createTask(title: "Download lecture recordings before access ends", in: winter, deadline: day(1))
        store.archive(list: winter)
        let coop = store.createList(name: "Co-op job hunt")
        store.createTask(title: "Update résumé", in: coop)
        store.archive(list: coop)
        _ = review
    }

    static func applyDebugRoute(_ store: Store, _ window: WindowState) {
        let d = UserDefaults.standard
        if let route = d.string(forKey: "debugRoute") {
            if route == "archive" {
                window.route = .archive
                window.archiveSelection = store.projection.archivedLists.ids.first
            } else if route.hasPrefix("list:") {
                let name = String(route.dropFirst(5))
                if let id = store.projection.activeLists.ids.first(where: { store.projection.list($0)?.name == name }) {
                    window.route = .list(id)
                }
            } else {
                window.route = .today
            }
        }
        if let title = d.string(forKey: "debugOpen"),
           let id = store.projection.allTaskIDs.first(where: { store.projection.task($0)?.title == title }) {
            window.open(id)
        }
        if d.bool(forKey: "debugQuickAdd") {
            WindowActions(store: store, window: window).newTask()
            window.quickAdd?.title = "Call the dentist about the crown"
        }
    }
}
#endif
