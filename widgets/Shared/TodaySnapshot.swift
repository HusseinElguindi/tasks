import Foundation
import TasksCore

/// Today as the widget draws it, for one day: computed in the widget from the feed with TasksCore's own rules
/// (`WidgetOverlay.today`, which is `Today.contains` in Today's order; `ViewGroups.RingCue`; `DateLabel`), so a
/// timeline entry at midnight shows the new day without the app (WIDGETS.md §3.2).
struct TodaySnapshot: Hashable, Sendable {
    /// The ring's cue (COLOR.md §1): a deadline past (late) or today (due), else a When today or earlier (planned).
    enum Cue: Hashable, Sendable { case none, planned, due, late }

    struct Row: Hashable, Sendable, Identifiable {
        let id: EntityID
        let title: String
        let list: ListInfo
        let cue: Cue
        /// The deadline capsule's words ("2d ago", "Due today", "4d left") and tone; nil without a deadline.
        let chip: Chip?
        let done: Bool
    }

    struct Chip: Hashable, Sendable {
        let text: String
        let tone: DateLabel.Tone
    }

    struct ListInfo: Hashable, Sendable, Identifiable {
        let id: EntityID
        let name: String
        let slot: Int
        let monogram: String
    }

    /// One list's open Today tasks, in its order.
    struct Group: Hashable, Sendable, Identifiable {
        let list: ListInfo
        let rows: [Row]
        var id: EntityID { list.id }
    }

    let date: CalendarDate
    /// The open tasks by list, lists in sidebar order (Today's own order, WIDGETS.md Q5).
    let groups: [Group]
    /// Completed today, oldest first.
    let done: [Row]

    var open: [Row] { groups.flatMap(\.rows) }
    var openCount: Int { groups.reduce(0) { $0 + $1.rows.count } }
    var overdueCount: Int { open.filter { $0.cue == .late }.count }
    var dueCount: Int { open.filter { $0.cue == .due }.count }

    init(date: CalendarDate, groups: [Group], done: [Row]) {
        self.date = date
        self.groups = groups
        self.done = done
    }

    init(_ overlay: WidgetOverlay, day: Day) {
        let lists = Dictionary(overlay.lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let today = day.date
        func info(_ id: EntityID) -> ListInfo {
            let l = lists[id]
            let name = l?.name ?? ""
            return ListInfo(id: id, name: name.isEmpty ? "Untitled" : name, slot: l?.slot ?? 6,
                            monogram: Self.monogram(for: name))
        }
        func row(_ t: TaskItem) -> Row {
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let done = t.completedAt != nil
            var cue = Cue.none
            if !done {
                let ring = ViewGroups.RingCue(when: t.when, deadline: t.deadline, today: today, inToday: false)
                switch ring.deadline {
                case .late?: cue = .late
                case .due?: cue = .due
                case nil: cue = ring.planned ? .planned : .none
                }
            }
            let chip = done ? nil : t.deadline.map { d -> Chip in
                let c = DateLabel.deadlineChip(d, today: today)
                return Chip(text: c.text, tone: c.tone)
            }
            return Row(id: t.id, title: title.isEmpty ? "Untitled" : title, list: info(t.list), cue: cue, chip: chip,
                       done: done)
        }
        let (open, done) = overlay.today(day)
        var groups: [Group] = []
        for t in open {
            let r = row(t)
            if let last = groups.last, last.list.id == t.list {
                groups[groups.count - 1] = Group(list: last.list, rows: last.rows + [r])
            } else {
                groups.append(Group(list: r.list, rows: [r]))
            }
        }
        self.init(date: today, groups: groups, done: done.map(row))
    }

    /// The tile's monogram: the name's first letter or digit, as TasksCore's `ListModel.monogram` (which isn't public).
    static func monogram(for name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "·"
    }
}
