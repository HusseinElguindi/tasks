import Foundation
import Synchronization
import TasksCore

/// A clock the sample data moves while it seeds, so each completion and deletion is stamped on its own day. Otherwise
/// it's the real time.
final class MovableClock: Sendable {
    private let offset = Mutex<TimeInterval>(0)

    /// From now on the clock reads `date` (and runs on from it); nil puts it back on the real time.
    func set(_ date: Date?) { offset.withLock { $0 = date.map { $0.timeIntervalSinceNow } ?? 0 } }

    var storeClock: StoreClock {
        StoreClock(now: { [self] in Date().addingTimeInterval(offset.withLock { $0 }) }, calendar: .autoupdatingCurrent)
    }
}

/// The prototype's sample (Del.dc.html, INTERACTIONS-v2), for the UI tests and screenshots (`-sampleData YES`). It's
/// made with the Store's own actions, in a scratch folder of its own, never the app's data, and never syncs. Every date
/// is relative to today, so the cues stay true.
enum SampleData {
    /// Where `-sampleData` keeps its store: wiped and seeded again at each launch.
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sample Data", isDirectory: true)
    }

    /// The lists' ids, by the short names the launch arguments use (`-screen list:school`). A list's colour comes from
    /// its id (`ListModel.slot(for:)`), so these are picked to give the prototype's colours. The Inbox is the Store's own.
    static let listIDs: [String: EntityID] = [
        "school": "school-9", "phys": "phys-6", "tasks": "tasks-5", "home": "home", "errands": "errands-2",
        "w26": "w26-4", "move": "move",
    ]

    /// A list id from a launch argument: a short name (above, or `inbox`), or an id.
    @MainActor static func listID(_ name: String, in p: Projection) -> EntityID {
        if let id = listIDs[name] { return id }
        if name == "inbox", let id = p.allListIDs.first(where: { p.list($0)?.name == "Inbox" }) { return id }
        return name
    }

    private enum Item {
        case task(id: String, title: String, when: Int? = nil, deadline: Int? = nil, deadlineDate: CalendarDate? = nil,
                  done: Int? = nil, deleted: Int? = nil, created: Int = -30, notes: String = "")
        case heading(id: String, title: String)
    }

    @MainActor static func seed(_ store: Store, clock: MovableClock) {
        let cal = Calendar.autoupdatingCurrent
        let today = store.projection.day.date
        func d(_ n: Int) -> CalendarDate { today.adding(days: n) }
        /// `n` days from today at `hour`, never later than now.
        func at(_ n: Int, _ hour: Int) -> Date {
            min(Date(), d(n).startDate(in: cal).addingTimeInterval(TimeInterval(hour * 3600)))
        }
        let dec9 = CalendarDate(year: today.year, month: 12, day: 9).flatMap { $0 > today ? $0 : nil } ?? d(37)
        func t(_ id: String, _ title: String, when: Int? = nil, deadline: Int? = nil, deadlineDate: CalendarDate? = nil,
               done: Int? = nil, deleted: Int? = nil, created: Int = -30, notes: String = "") -> Item {
            .task(id: id, title: title, when: when, deadline: deadline, deadlineDate: deadlineDate, done: done,
                  deleted: deleted, created: created, notes: notes)
        }

        guard let inbox = store.defaultListID else { return }
        let lists: [(key: String, name: String, created: Int, notes: String)] = [
            ("school", "School", -63, "Fall term: ECE 358, CS 489 and MSE 333."),
            ("phys", "PHYS 122", -60, "Waves, electricity and magnetism. Lectures Mon, Wed, Fri 9:30 in STC 0010; labs Tuesdays in PHY 2009.\nMidterm Nov 6, final in December."),
            ("tasks", "Tasks app", -61, "The Mac app, then the phone."),
            ("home", "Home", -120, ""),
            ("errands", "Errands", -120, ""),
            ("w26", "Winter 2026", -322, ""),
            ("move", "Apartment move", -105, ""),
        ]
        for l in lists {
            clock.set(at(l.created, 9))
            let id = store.createList(id: listIDs[l.key]!, name: l.name)
            if !l.notes.isEmpty { store.setNotes(list: id, l.notes) }
        }

        // Each list's tasks and headings in its order.
        let items: [(list: EntityID, items: [Item])] = [
            (inbox, [
                t("i1", "Reply to the landlord about the lease", when: 0, created: -2),
                t("i2", "Call the dentist about a cleaning", when: 0, created: -6),
                t("i3", "Renew the library books", deadline: 1, created: -12),
                t("i4", "Back up the laptop", when: 4, created: -9),
                t("i5", "Look into a standing desk", created: -20,
                  notes: "Under **$400**. Check the one on the 4th floor first.\n\n- [ ] Measure the desk nook\n- [x] Ask about the office discount"),
                t("x1", "Try the new notes app", deleted: 0, created: -31),
            ]),
            (listIDs["school"]!, [
                t("s1", "ECE 358 lab report", deadline: -2, created: -14),
                t("s2", "Email TA about midterm regrade", when: 0, created: -60,
                  notes: "Question 4(b): the marking scheme gives part marks for the setup.\nAsk before **Thursday's** tutorial."),
                t("s3", "Review CS 489 lectures 10–14", when: 0, deadline: 3, created: -8),
                t("s4", "Submit MSE 333 A2", when: 2, deadline: 3, created: -15),
                t("s5", "Return the ECE 358 lab kit", deadline: 0, created: -20),
                t("s6", "Pay the MSE 333 field trip fee", when: 0, deadline: 0, created: -10),
                t("s7", "CS 489 final study plan", when: 10, created: -5),
                t("s8", "Print ECE 358 formula sheet", created: -4),
                t("s9", "Ask about co-op interview slots", created: -3),
                t("s10", "Midterm review session", when: 1, created: -7),
                t("s11", "ECE 358 final exam", deadlineDate: dec9, created: -50),
                t("sd1", "Meet the ECE 358 lab group", done: -1, created: -40),
                t("sd2", "Submit ECE 358 lab 3", done: -3, created: -30),
                t("sd3", "Read MSE 333 chapter 6", done: -5, created: -25),
                t("sd4", "Register for winter courses", done: -12, created: -45),
                t("x2", "Old group project notes", deleted: -1, created: -54, notes: "Superseded by the shared doc."),
            ]),
            (listIDs["phys"]!, [
                t("p1", "Buy safety glasses for the lab", when: 0, created: -6),
                .heading(id: "h-lec", title: "Lectures"),
                t("p2", "Read chapter 15 · oscillations", when: 0, created: -5),
                t("p3", "Redo the worked examples from lecture 9", created: -5),
                t("p4", "Watch the recording on standing waves", when: 1, created: -4),
                .heading(id: "h-lab", title: "Labs"),
                t("p5", "Lab 3 report · pendulum", when: 0, deadline: 1, created: -9),
                t("p6", "Lab 4 pre-lab · RC circuits", deadline: 5, created: -2),
                t("p7", "Book a make-up lab bench", created: -2),
                t("pd1", "Lab 2 report · projectile motion", done: -6, created: -20),
                .heading(id: "h-exam", title: "Exam prep"),
                t("p8", "Make the midterm formula sheet", when: 2, created: -3),
                t("p9", "Past midterms 2024 and 2025, timed", when: 3, created: -3),
                t("p10", "Ask about problem 7 at office hours", created: -1),
            ]),
            (listIDs["tasks"]!, [
                t("a1", "Ship the When and Deadline pickers", when: 0, created: -4),
                t("a2", "Sidebar footer: a settings button", created: -2),
                t("a3", "Write the phone's sheet detents spec", when: 4, created: -1),
                t("a4", "Fix the title flicker on rename", deadline: 6, created: -3),
                t("a5", "Try Glass on the detail pane", created: -2),
                t("ad1", "Theme cards in Settings", done: 0, created: -6),
                t("x5", "Prototype a menu bar widget", deleted: -21, created: -61),
            ]),
            (listIDs["home"]!, [
                t("o1", "Water the plants", when: 0, created: -3),
                t("o2", "Replace the hallway bulb", created: -8),
                t("o3", "Book the furnace check", deadline: 9, created: -14),
                t("o4", "Clean out the fridge", when: 5, created: -2),
                t("od1", "Take out the recycling", done: -1, created: -2),
                t("x3", "Buy a second lamp", deleted: -4, created: -38, notes: "The one by the window is fine after all."),
            ]),
            (listIDs["errands"]!, [
                t("e1", "Pick up the prescription", when: 0, created: -1),
                t("e2", "Get groceries for the week", when: 1, created: -1),
                t("e3", "Return the boots", deadline: 2, created: -6),
                t("e4", "Drop off the dry cleaning", created: -4),
                t("x4", "Pick up dry cleaning", done: -10, deleted: -9, created: -32),
            ]),
            (listIDs["w26"]!, [
                t("w1", "Return the oscilloscope kit", created: -300),
                t("wd1", "Study for ECE 222 final", done: -200, created: -260),
            ]),
            (listIDs["move"]!, [
                t("m1", "Cancel the old internet plan", created: -100),
                t("m2", "Return the moving boxes", created: -90),
                t("md1", "Forward mail", done: -60, created: -100),
            ]),
        ]

        var later: [(Date, () -> Void)] = []
        for (list, its) in items {
            for item in its {
                switch item {
                case let .heading(id, title):
                    clock.set(at(-60, 9))
                    store.createHeading(id: id, title: title, in: list)
                case let .task(id, title, when, deadline, deadlineDate, done, deleted, created, notes):
                    clock.set(at(created, 9))
                    store.createTask(id: id, title: title, notes: notes, in: list, when: when.map(d),
                                     deadline: deadlineDate ?? deadline.map(d))
                    if let done { later.append((at(done, 15), { _ = store.toggleComplete([id]) })) }
                    if let deleted { later.append((at(deleted, 11), { _ = store.delete([id]) })) }
                }
            }
        }
        // Completions and deletions in the order they happened, then the two lists in Trash.
        later.append((at(-181, 11), { _ = store.deleteList(listIDs["w26"]!) }))
        later.append((at(-49, 11), { _ = store.deleteList(listIDs["move"]!) }))
        for (date, change) in later.sorted(by: { $0.0 < $1.0 }) {
            clock.set(date)
            change()
        }
        clock.set(nil)
        store.persistNow()
    }
}
