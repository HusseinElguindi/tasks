import Foundation

/// The prototype's sample (Del.dc.html, INTERACTIONS-v2), with every date relative to today so the cues stay true.
enum SampleData {
    struct Bundle { var lists: [TaskList]; var headings: [Heading]; var tasks: [TaskItem] }

    static func make() -> Bundle {
        func d(_ n: Int) -> Date { Day.offset(n) }
        func at(_ n: Int, _ hour: Int = 10) -> Date { Day.cal.date(byAdding: .hour, value: hour, to: d(n))! }
        let thisYearDec9: Date = {
            var c = Day.cal.dateComponents([.year], from: Day.today); c.month = 12; c.day = 9
            let x = Day.cal.date(from: c)!
            return x > Day.today ? x : d(37)
        }()

        let lists: [TaskList] = [
            TaskList(id: "inbox", name: "Inbox", mono: "I", hue: .ink, created: d(-90), order: 0),
            TaskList(id: "school", name: "School", mono: "S", hue: .blue, notes: "Fall term: ECE 358, CS 489 and MSE 333.", created: d(-63), order: 1),
            TaskList(id: "phys", name: "PHYS 122", mono: "P", hue: .yellow,
                     notes: "Waves, electricity and magnetism. Lectures Mon, Wed, Fri 9:30 in STC 0010; labs Tuesdays in PHY 2009.\nMidterm Nov 6, final in December.",
                     created: d(-60), order: 2),
            TaskList(id: "tasks", name: "Tasks app", mono: "T", hue: .magenta, notes: "The Mac app, then the phone.", created: d(-61), order: 3),
            TaskList(id: "home", name: "Home", mono: "H", hue: .green, created: d(-120), order: 4),
            TaskList(id: "errands", name: "Errands", mono: "E", hue: .cyan, created: d(-120), order: 5),
            TaskList(id: "w26", name: "Winter 2026", mono: "W", hue: .yellow, created: d(-322), deletedAt: at(-181), order: 6),
            TaskList(id: "move", name: "Apartment move", mono: "A", hue: .red, created: d(-105), deletedAt: at(-49), order: 7),
        ]

        let headings: [Heading] = [
            Heading(id: "h-lec", listID: "phys", title: "Lectures", order: 0),
            Heading(id: "h-lab", listID: "phys", title: "Labs", order: 1),
            Heading(id: "h-exam", listID: "phys", title: "Exam prep", order: 2),
        ]

        var o = 0
        func t(_ id: String, _ title: String, _ list: String, heading: String? = nil, when: Int? = nil, deadline: Int? = nil,
               deadlineDate: Date? = nil, done: Int? = nil, deleted: Int? = nil, created: Int = -30, notes: String = "") -> TaskItem {
            o += 1
            return TaskItem(id: id, title: title, notes: notes, listID: list, headingID: heading,
                            when: when.map { d($0) }, deadline: deadlineDate ?? deadline.map { d($0) },
                            completedAt: done.map { at($0, 15) }, deletedAt: deleted.map { at($0, 11) },
                            created: d(created), order: o)
        }

        let tasks: [TaskItem] = [
            // Inbox
            t("i1", "Reply to the landlord about the lease", "inbox", when: 0, created: -2),
            t("i2", "Call the dentist about a cleaning", "inbox", when: 0, created: -6),
            t("i3", "Renew the library books", "inbox", deadline: 1, created: -12),
            t("i4", "Back up the laptop", "inbox", when: 4, created: -9),
            t("i5", "Look into a standing desk", "inbox", created: -20,
              notes: "Under **$400**. Check the one on the 4th floor first.\n\n- [ ] Measure the desk nook\n- [x] Ask about the office discount"),
            t("x1", "Try the new notes app", "inbox", deleted: 0, created: -31),

            // School
            t("s1", "ECE 358 lab report", "school", deadline: -2, created: -14),
            t("s2", "Email TA about midterm regrade", "school", when: 0, created: -60,
              notes: "Question 4(b): the marking scheme gives part marks for the setup.\nAsk before **Thursday's** tutorial."),
            t("s3", "Review CS 489 lectures 10–14", "school", when: 0, deadline: 3, created: -8),
            t("s4", "Submit MSE 333 A2", "school", when: 2, deadline: 3, created: -15),
            t("s5", "Return the ECE 358 lab kit", "school", deadline: 0, created: -20),
            t("s6", "Pay the MSE 333 field trip fee", "school", when: 0, deadline: 0, created: -10),
            t("s7", "CS 489 final study plan", "school", when: 10, created: -5),
            t("s8", "Print ECE 358 formula sheet", "school", created: -4),
            t("s9", "Ask about co-op interview slots", "school", created: -3),
            t("s10", "Midterm review session", "school", when: 1, created: -7),
            t("s11", "ECE 358 final exam", "school", deadlineDate: thisYearDec9, created: -50),
            t("sd1", "Meet the ECE 358 lab group", "school", done: -1, created: -40),
            t("sd2", "Submit ECE 358 lab 3", "school", done: -3, created: -30),
            t("sd3", "Read MSE 333 chapter 6", "school", done: -5, created: -25),
            t("sd4", "Register for winter courses", "school", done: -12, created: -45),
            t("x2", "Old group project notes", "school", deleted: -1, created: -54, notes: "Superseded by the shared doc."),

            // PHYS 122
            t("p1", "Buy safety glasses for the lab", "phys", when: 0, created: -6),
            t("p2", "Read chapter 15 · oscillations", "phys", heading: "h-lec", when: 0, created: -5),
            t("p3", "Redo the worked examples from lecture 9", "phys", heading: "h-lec", created: -5),
            t("p4", "Watch the recording on standing waves", "phys", heading: "h-lec", when: 1, created: -4),
            t("p5", "Lab 3 report · pendulum", "phys", heading: "h-lab", when: 0, deadline: 1, created: -9),
            t("p6", "Lab 4 pre-lab · RC circuits", "phys", heading: "h-lab", deadline: 5, created: -2),
            t("p7", "Book a make-up lab bench", "phys", heading: "h-lab", created: -2),
            t("p8", "Make the midterm formula sheet", "phys", heading: "h-exam", when: 2, created: -3),
            t("p9", "Past midterms 2024 and 2025, timed", "phys", heading: "h-exam", when: 3, created: -3),
            t("p10", "Ask about problem 7 at office hours", "phys", heading: "h-exam", created: -1),
            t("pd1", "Lab 2 report · projectile motion", "phys", heading: "h-lab", done: -6, created: -20),

            // Tasks app
            t("a1", "Ship the When and Deadline pickers", "tasks", when: 0, created: -4),
            t("a2", "Sidebar footer: a settings button", "tasks", created: -2),
            t("a3", "Write the phone's sheet detents spec", "tasks", when: 4, created: -1),
            t("a4", "Fix the title flicker on rename", "tasks", deadline: 6, created: -3),
            t("a5", "Try Glass on the detail pane", "tasks", created: -2),
            t("ad1", "Theme cards in Settings", "tasks", done: 0, created: -6),
            t("x5", "Prototype a menu bar widget", "tasks", deleted: -21, created: -61),

            // Home
            t("o1", "Water the plants", "home", when: 0, created: -3),
            t("o2", "Replace the hallway bulb", "home", created: -8),
            t("o3", "Book the furnace check", "home", deadline: 9, created: -14),
            t("o4", "Clean out the fridge", "home", when: 5, created: -2),
            t("od1", "Take out the recycling", "home", done: -1, created: -2),
            t("x3", "Buy a second lamp", "home", deleted: -4, created: -38, notes: "The one by the window is fine after all."),

            // Errands
            t("e1", "Pick up the prescription", "errands", when: 0, created: -1),
            t("e2", "Get groceries for the week", "errands", when: 1, created: -1),
            t("e3", "Return the boots", "errands", deadline: 2, created: -6),
            t("e4", "Drop off the dry cleaning", "errands", created: -4),
            t("x4", "Pick up dry cleaning", "errands", done: -10, deleted: -9, created: -32),

            // Lists in Trash, with what they held
            t("w1", "Return the oscilloscope kit", "w26", created: -300),
            t("wd1", "Study for ECE 222 final", "w26", done: -200, created: -260),
            t("m1", "Cancel the old internet plan", "move", created: -100),
            t("m2", "Return the moving boxes", "move", created: -90),
            t("md1", "Forward mail", "move", done: -60, created: -100),
        ]
        return Bundle(lists: lists, headings: headings, tasks: tasks)
    }
}
