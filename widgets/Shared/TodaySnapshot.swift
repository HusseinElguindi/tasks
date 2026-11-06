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
        /// The When as quiet words ("Today", "Mon"), for the List widget; nil in Today, where it goes without saying.
        var when: String? = nil

        /// As VoiceOver reads it: "Problem set 6, Due today", "Read chapter 8, Mon".
        var spoken: String {
            ([title] + (done ? ["completed"] : []) + [when, chip?.text].compactMap { $0 }).joined(separator: ", ")
        }
    }

    struct Chip: Hashable, Sendable {
        let text: String
        let tone: DateLabel.Tone
        /// As VoiceOver says it: "2 days overdue", "due today", "4 days left".
        var words: String? = nil
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
        let today = day.date
        let (open, done) = overlay.today(day)
        var groups: [Group] = []
        for t in open {
            let r = Self.row(t, list: Self.info(t.list, in: overlay), today: today)
            if let last = groups.last, last.list.id == t.list {
                groups[groups.count - 1] = Group(list: last.list, rows: last.rows + [r])
            } else {
                groups.append(Group(list: r.list, rows: [r]))
            }
        }
        self.init(date: today, groups: groups,
                  done: done.map { Self.row($0, list: Self.info($0.list, in: overlay), today: today) })
    }

    /// A list as the widgets draw it: its name ("Untitled" when empty), its tile's slot and monogram.
    static func info(_ id: EntityID, in overlay: WidgetOverlay) -> ListInfo {
        let l = overlay.lists.first { $0.id == id }
        let name = l?.name ?? ""
        return ListInfo(id: id, name: name.isEmpty ? "Untitled" : name, slot: l?.slot ?? 6, monogram: monogram(for: name))
    }

    /// A task's row: its ring's cue and deadline capsule on `today`, and its When in words when `showsWhen`.
    static func row(_ t: TaskItem, list: ListInfo, today: CalendarDate, showsWhen: Bool = false) -> Row {
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
            return Chip(text: c.text, tone: c.tone, words: DateLabel.deadlineWords(d, today: today))
        }
        let when = showsWhen && !done ? t.when.map { DateLabel.whenChip($0, today: today) } : nil
        return Row(id: t.id, title: title.isEmpty ? "Untitled" : title, list: list, cue: cue, chip: chip, done: done,
                   when: when)
    }

    /// The tile's monogram: the name's first letter or digit, as TasksCore's `ListModel.monogram` (which isn't public).
    static func monogram(for name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "·"
    }
}
