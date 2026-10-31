import TasksCore

/// How a row shows its dates (INTERACTIONS-v2 §24): the When as quiet text after the title, the Deadline as a capsule
/// in its tone at the right, both with a tooltip in full words; and the checkbox's ring.
extension RowModel.Chip {
    /// "Today", "Tomorrow", "in 2d" … "in 14d", then the date.
    static func when(_ d: CalendarDate, today: CalendarDate) -> Self {
        .init(field: .when, content: .init(text: DateLabel.whenChip(d, today: today), glyph: .calendar, quiet: true),
              tip: DateLabel.tooltip(deadline: false, d, today: today))
    }

    /// "2d ago", "Due today", "1d left" … "14d left", then the date. In Upcoming, on its own day's group, "Due", with
    /// its tone.
    static func deadline(_ d: CalendarDate, today: CalendarDate, groupDay: CalendarDate?) -> Self {
        let c = DateLabel.deadlineChip(d, today: today)
        let tone: ChipLayer.Tone = switch c.tone {
        case .late: .late
        case .due: .due
        case .soon: .soon
        case .neutral: .neutral
        }
        return .init(field: .deadline, content: .init(text: d == groupDay ? "Due" : c.text, glyph: .flag, tone: tone),
                     tip: DateLabel.tooltip(deadline: true, d, today: today))
    }
}

extension CheckLayer.Cue {
    /// An open task's ring: its deadline past or today; planned for today when its When is today or earlier, except
    /// in Today, where every task is. Done, trashed and new tasks have none.
    init(when: CalendarDate?, deadline: CalendarDate?, today: CalendarDate, inToday: Bool) {
        if let d = deadline, d <= today { self.deadline = d < today ? .late : .due }
        planned = !inToday && when.map { $0 <= today } == true
    }
}
