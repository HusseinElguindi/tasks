import SwiftUI
import TasksCore
import UIKit

/// The When and Deadline picker: a field to type the day (batch 2 §2, the Mac's IX §11), quick choices, then one
/// endless column of weeks (the Mac's §25 calendar), then what the choice means. It sets one task's date, or every
/// selected task's (§3).
struct DatePickerSheet: View {
    let target: DateTarget
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topWeek: Int?
    /// What a tap or Return set, shown until the sheet goes (`.some(nil)`: Clear).
    @State private var picked: CalendarDate??
    /// The field's text.
    @State private var text = ""
    /// Where typing or the keys moved the highlight; nil while they haven't (the highlight is then the tasks' date).
    @State private var hot: CalendarDate?
    /// The text reads as no date: nothing is highlighted and Return sets nothing (the Mac's `none`).
    @State private var none = false
    /// The field has the caret with the on-screen keyboard up: the sheet goes large and the calendar takes the height.
    @State private var typing = false
    @State private var detent: PresentationDetent = Self.resting
    @State private var calendarHeight: CGFloat = 0
    /// Counts Returns that set nothing, for the warning haptic.
    @State private var misses = 0
    /// Read once, as the sheet opens.
    @State private var keysOnOpen = hardwareKeyboard()

    private static let weeksBack = 26
    private static let weeksAhead = 104
    /// The sheet's height until typing takes it large: the parts, with six weeks of the calendar.
    static let resting = PresentationDetent.height(612)
    private let rowH: CGFloat = 44
    private let visibleRows: CGFloat = 6
    /// How "11/9" reads in the user's locale (read once: it builds a date format; the Mac's `DatePickModel.order`).
    private static let order = DatePhrase.numericOrder(for: .current)

    private var tasks: [TaskModel] { target.ids.compactMap { app.task($0) } }
    private var today: CalendarDate { app.today }
    private func value(_ t: TaskModel) -> CalendarDate? { target.kind == .when ? t.when : t.deadline }
    /// The tasks' date when they all share it (the Mac's `cur`, dc:1119): the ring, Clear and the tinted pick need it.
    private var shared: CalendarDate? {
        let ts = tasks
        guard let v = ts.first.flatMap(value) else { return nil }
        return ts.allSatisfy { value($0) == v } ? v : nil
    }
    private var current: CalendarDate? { picked ?? shared }
    /// The first task's other date: the calendar's dot, and the footer's note.
    private var other: CalendarDate? { tasks.first.flatMap { target.kind == .when ? $0.deadline : $0.when } }
    /// The highlighted day: what Return sets. With nothing typed it's the tasks' date (none when they have none).
    private var shownDay: CalendarDate? {
        if let picked { return picked }
        return none ? nil : hot ?? current
    }

    /// The locale's first weekday (1 = Sunday, as `CalendarDate.weekday` counts), as the Mac's calendar starts its weeks
    /// (DatePopover.swift:327).
    private let first = Calendar.current.firstWeekday
    private static let letters = ["S", "M", "T", "W", "T", "F", "S"]  // Sunday first, like `CalendarDate.weekday`

    /// The first day of the grid's first week, `weeksBack` weeks before this one.
    private var firstWeekStart: CalendarDate {
        today.adding(days: -((today.weekday - first + 7) % 7) - 7 * Self.weeksBack)
    }
    private func weekStart(_ i: Int) -> CalendarDate { firstWeekStart.adding(days: 7 * i) }
    private func weekIndex(_ d: CalendarDate) -> Int { firstWeekStart.days(until: d) / 7 }
    private var todayWeek: Int { weekIndex(today) }
    /// The weeks the calendar's height shows whole.
    private var rowsInView: Int { max(2, Int(((calendarHeight > 0 ? calendarHeight : rowH * visibleRows) + 1) / rowH)) }

    /// The month with the most days showing.
    private var headerMonth: CalendarDate {
        let top = topWeek ?? todayWeek
        return weekStart(top + (rowsInView - 1) / 2).adding(days: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            field
            quickPicks.padding(.top, 10)
            monthRow
            weekdays
            calendar
            footer
            Spacer(minLength: 0)
        }
        .background(p.popover)
        .motion(.easeOut(duration: 0.15), value: topWeek.map { abs($0 + 1 - todayWeek) > 2 })
        .presentationDetents([Self.resting, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.warning, trigger: misses)
        .onAppear {
            let anchor = current.map(weekIndex) ?? todayWeek
            topWeek = max(0, anchor - 1)
        }
        .onChange(of: shownDay) { _, d in if let d { reveal(d) } }
        .onChange(of: rowsInView) { if let d = shownDay { reveal(d, animated: false) } }
        // VoiceOver reads the footer once typing stops for half a second.
        .task(id: text) {
            guard !text.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(footerWords).post()
        }
    }

    // MARK: Parts

    private var titleRow: some View {
        HStack {
            // For several tasks (§3): "When · 3 tasks", the count in `ink-tertiary`.
            HStack(spacing: 0) {
                Text(target.kind == .when ? "When" : "Deadline").foregroundStyle(p.ink)
                if target.ids.count > 1 { Text(" · \(target.ids.count) tasks").foregroundStyle(p.inkTertiary) }
            }
            .font(.system(size: 17, weight: .semibold))
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    /// 44 tall (the Mac's 28 × 1.3, raised to the touch minimum), radius 12, `fill-control`; the icon of the date it
    /// sets, 10 before the text.
    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: target.kind == .when ? "calendar" : "flag")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(p.inkTertiary)
                .accessibilityHidden(true)
            DateField(placeholder: target.kind == .when ? "Try fri, 3d, nov 9" : "Try fri, nov 9, 2w",
                      ink: p.ink, placeholderInk: p.inkTertiary, tint: p.accent, focusOnAppear: keysOnOpen,
                      onText: typed, onFocus: fieldFocus, onReturn: returned, onKey: key)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var quickPicks: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                quick("Today", today, symbol: "sun.max.fill", tint: p.list(.yellow))
                quick("Tomorrow", today.adding(days: 1), symbol: "sunrise.fill", tint: p.list(.red))
                quick("This Weekend", DatePhrase.weekend(from: today), symbol: "sofa.fill", tint: p.list(.cyan))
                quick("Next Week", DatePhrase.nextWeek(from: today), symbol: "arrow.right.circle.fill", tint: p.list(.magenta))
                if current != nil {
                    Button { choose(nil) } label: {
                        Text("Clear").font(.system(size: 14, weight: .medium)).foregroundStyle(p.inkSecondary)
                            .padding(.horizontal, 12).frame(height: 32)
                            .overlay(Capsule().strokeBorder(p.lineSeparator, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    /// With text, the pick the text means is tinted (the Mac's rule); with none, the one that is the tasks' date.
    private func quick(_ title: String, _ date: CalendarDate, symbol: String, tint: Color) -> some View {
        let on = text.isEmpty || picked != nil ? current == date : shownDay == date
        return Button { choose(date) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? p.accentText : tint)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(on ? p.accentText : p.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(on ? p.accentTint : p.fillControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var monthRow: some View {
        HStack(spacing: 8) {
            Text(DateLabel.monthTitle(year: headerMonth.year, month: headerMonth.month))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.ink)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .motion(.easeOut(duration: 0.15), value: headerMonth.month)
            Spacer()
            if let top = topWeek, abs(top + 1 - todayWeek) > 2 {
                Button { scroll(to: todayWeek) } label: {
                    HStack(spacing: 3) {
                        Text("Today")
                        Image(systemName: top + 1 > todayWeek ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.accentText)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(p.accentTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .motionTransition(.opacity)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(Self.letters[(first - 1 + i) % 7]).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.inkTertiary).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }

    /// Six weeks; while typing, the height between the weekday row and the footer, at least two weeks.
    private var calendar: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<(Self.weeksBack + Self.weeksAhead), id: \.self) { i in
                    week(i).frame(height: rowH).id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $topWeek, anchor: .top)
        .scrollDismissesKeyboard(.interactively)
        .frame(minHeight: rowH * 2, maxHeight: typing ? .infinity : rowH * visibleRows)
        .layoutPriority(1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
        .padding(.horizontal, 14)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                     .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func week(_ i: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { k in
                day(weekStart(i).adding(days: k))
            }
        }
    }

    private func day(_ d: CalendarDate) -> some View {
        let isToday = d == today
        let selected = shownDay == d
        // The tasks' date, once the highlight has moved off it: the Mac's inset ring (1.5 on 28 × 1.3).
        let ringed = !selected && current == d
        let otherMonth = d.month != headerMonth.month || d.year != headerMonth.year
        let marked = other == d
        return Button { choose(d) } label: {
            ZStack {
                if selected { Circle().fill(p.accent).frame(width: 38, height: 38) }
                if ringed { Circle().strokeBorder(p.accent, lineWidth: 2).frame(width: 38, height: 38) }
                Text("\(d.day)")
                    .font(.system(size: 16, weight: selected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(selected ? p.onAccent : isToday ? p.accentText : otherMonth ? p.inkQuiet : p.ink)
                if marked && !selected {
                    Circle().fill(target.kind == .when ? p.attention : p.inkTertiary).frame(width: 4, height: 4).offset(y: 13)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateLabel.long(d, today: today) + (isToday ? ", today" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: The footer

    /// What Return sets, the Mac's lines (DatePopover.swift:151–175): the first that fits.
    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: target.kind == .when ? "calendar" : "flag.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.inkTertiary)
            ViewThatFits(in: .horizontal) {
                ForEach(footerLines.indices, id: \.self) { i in footerLine(footerLines[i]) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .frame(height: 50)
        .overlay(alignment: .top) { Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.horizontal, 20) }
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(footerWords)
        .accessibilityIdentifier("dateFooter")
    }

    /// One of the footer's lines: the date, then what follows it (how far, how overdue, or the note).
    private struct FooterLine {
        var main: String
        var rest: String?
        var restColor: Color?
    }

    private var footerLines: [FooterLine] {
        if none {
            return [FooterLine(main: "No date matches “" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "”")]
        }
        guard let d = shownDay else {
            if tasks.count > 1, tasks.contains(where: { value($0) != nil }) {
                return [FooterLine(main: target.kind == .when ? "Different dates" : "Different deadlines")]
            }
            return [FooterLine(main: target.kind == .when ? "No date · it waits in Undated" : "No deadline")]
        }
        let pre = target.kind == .deadline ? "Due " : ""
        let long = pre + DateLabel.long(d, today: today)
        let short = pre + DateLabel.monthDayYear(d, today: today)
        // A When after the deadline, or a deadline before the When: the note takes the relative words' place, and stays.
        if let hint = hint(d) {
            return [FooterLine(main: long, rest: hint, restColor: p.attention),
                    FooterLine(main: short, rest: hint, restColor: p.attention)]
        }
        let overdue = target.kind == .deadline && d < today
        let rel = overdue ? DateLabel.deadlineWords(d, today: today) : DateLabel.relative(d, today: today)
        let color = overdue ? p.danger : p.inkTertiary
        return [FooterLine(main: long, rest: rel, restColor: color), FooterLine(main: short, rest: rel, restColor: color),
                FooterLine(main: short)]
    }

    /// The Mac's `hint` (DatePopover.swift:171): a note, not a rule.
    private func hint(_ d: CalendarDate) -> String? {
        guard let other else { return nil }
        if target.kind == .when, d > other { return "after the deadline" }
        if target.kind == .deadline, d < other { return "before the When" }
        return nil
    }

    private func footerLine(_ l: FooterLine) -> some View {
        HStack(spacing: 0) {
            Text(l.main).foregroundStyle(none ? p.inkTertiary : p.ink)
                .truncationMode(.tail)
            if let rest = l.rest {
                Text(" · ").foregroundStyle(p.inkTertiary)
                Text(rest).foregroundStyle(l.restColor ?? p.inkTertiary)
            }
        }
        .font(Typo.body)
        .lineLimit(1)
        .fixedSize(horizontal: !none, vertical: false)
    }

    private var footerWords: String {
        let l = footerLines[0]
        return l.main + (l.rest.map { " · " + $0 } ?? "")
    }

    // MARK: Behaviour

    private func scroll(to week: Int) {
        // Under Reduce Motion the calendar jumps.
        animate(Motion.natural) { topWeek = max(0, week - 1) }
    }

    /// The highlighted week, brought into view with the least scroll when it isn't whole in view.
    private func reveal(_ d: CalendarDate, animated: Bool = true) {
        let w = weekIndex(d)
        let top = topWeek ?? max(0, w - 1)
        let n = rowsInView
        let to: Int
        if w < top { to = w } else if w > top + n - 1 { to = w - n + 1 } else { return }
        if animated { animate(Motion.natural) { topWeek = max(0, to) } } else { topWeek = max(0, to) }
    }

    /// Every keystroke: the highlight goes to what the text means (the Mac's `typed`, DatePopover.swift:91–104).
    private func typed(_ new: String) {
        text = new
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            none = false
            hot = nil
        } else if let hit = DatePhrase.match(new, today: today, numericOrder: Self.order) {
            none = false
            hot = hit
        } else {
            none = true
        }
    }

    private func fieldFocus(_ on: Bool) {
        let keyboard = on && !hardwareKeyboard()
        guard keyboard != typing else { return }
        typing = keyboard
        if keyboard, detent != .large { animate(Motion.natural) { detent = .large } }
    }

    /// Return sets the highlighted day and closes; with none, it sets nothing and the keyboard stays.
    private func returned() {
        guard picked == nil else { return }
        guard let d = shownDay else { misses += 1; return }
        choose(d)
    }

    /// A hardware keyboard's keys (DatePopover.swift:256): ← → a day, ↑ ↓ a week, Page Up and Page Down a month, Esc
    /// closes.
    private func key(_ k: DateKey) {
        guard picked == nil else { return }
        let base = hot ?? current ?? today
        switch k {
        case .left: move(to: base.adding(days: -1))
        case .right: move(to: base.adding(days: 1))
        case .up: move(to: base.adding(days: -7))
        case .down: move(to: base.adding(days: 7))
        case .pageUp: move(to: DatePhrase.adding(months: -1, to: base))
        case .pageDown: move(to: DatePhrase.adding(months: 1, to: base))
        case .escape: dismiss()
        }
    }

    private func move(to d: CalendarDate) {
        none = false
        hot = d
    }

    private func choose(_ d: CalendarDate?) {
        picked = .some(d)
        app.setDate(target.ids, target.kind, d)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22))
            dismiss()
        }
    }
}
