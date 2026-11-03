import SwiftUI
import TasksCore

/// The When and Deadline picker: quick choices, then one endless column of weeks (the Mac's §25 calendar), then what
/// the choice means.
struct DatePickerSheet: View {
    let target: DateTarget
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topWeek: Int?
    @State private var picked: CalendarDate?

    private static let weeksBack = 26
    private static let weeksAhead = 104
    private let rowH: CGFloat = 44
    private let visibleRows: CGFloat = 6

    private var task: TaskModel? { app.task(target.taskID) }
    private var today: CalendarDate { app.today }
    private var current: CalendarDate? { picked ?? (target.kind == .when ? task?.when : task?.deadline) }
    private var other: CalendarDate? { target.kind == .when ? task?.deadline : task?.when }

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

    /// The month with the most days showing.
    private var headerMonth: CalendarDate {
        let top = topWeek ?? todayWeek
        return weekStart(top + 2).adding(days: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(target.kind == .when ? "When" : "Deadline")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            quickPicks

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

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.letters[(first - 1 + i) % 7]).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.inkTertiary).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 26)

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
            .frame(height: rowH * visibleRows)
            .padding(.horizontal, 14)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))

            preview
            Spacer(minLength: 0)
        }
        .background(p.popover)
        .motion(.easeOut(duration: 0.15), value: topWeek.map { abs($0 + 1 - todayWeek) > 2 })
        .onAppear {
            let anchor = current.map(weekIndex) ?? todayWeek
            topWeek = max(0, anchor - 1)
        }
    }

    // MARK: Parts

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

    private func quick(_ title: String, _ date: CalendarDate, symbol: String, tint: Color) -> some View {
        let on = current == date
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
        let selected = current == d
        let otherMonth = d.month != headerMonth.month || d.year != headerMonth.year
        let marked = other == d
        return Button { choose(d) } label: {
            ZStack {
                if selected { Circle().fill(p.accent).frame(width: 38, height: 38) }
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

    private var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: target.kind == .when ? "calendar" : "flag.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.inkTertiary)
            if let c = current {
                // The Mac's popover: the date, then how far it is, or for a past deadline how overdue.
                let overdue = target.kind == .deadline && c < today
                Text(DateLabel.long(c, today: today)).font(Typo.body).foregroundStyle(p.ink)
                Text("· " + (overdue ? DateLabel.deadlineWords(c, today: today) : DateLabel.relative(c, today: today)))
                    .font(Typo.body).foregroundStyle(overdue ? p.danger : p.inkTertiary)
            } else {
                Text(target.kind == .when ? "No date · it waits in Undated" : "No deadline").font(Typo.body).foregroundStyle(p.inkTertiary)
            }
            Spacer()
        }
        .lineLimit(1)
        .padding(.horizontal, 22)
        .frame(height: 50)
        .overlay(alignment: .top) { Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.horizontal, 20) }
        .padding(.top, 6)
    }

    // MARK: Behaviour

    private func scroll(to week: Int) {
        // Under Reduce Motion the calendar jumps.
        animate(Motion.natural) { topWeek = max(0, week - 1) }
    }

    private func choose(_ d: CalendarDate?) {
        picked = d
        app.setDate(target.taskID, target.kind, d)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22))
            dismiss()
        }
    }
}
