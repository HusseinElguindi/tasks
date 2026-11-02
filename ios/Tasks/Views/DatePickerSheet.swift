import SwiftUI

/// The When and Deadline picker: quick choices, then one endless column of weeks (the Mac's §25 calendar), then what
/// the choice means.
struct DatePickerSheet: View {
    let target: DateTarget
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var topWeek: Int?
    @State private var picked: Date?

    private static let weeksBack = 26
    private static let weeksAhead = 104
    private let rowH: CGFloat = 44
    private let visibleRows: CGFloat = 6

    private var task: TaskItem? { store.task(target.taskID) }
    private var current: Date? { picked ?? (target.kind == .when ? task?.when : task?.deadline) }
    private var other: Date? { target.kind == .when ? task?.deadline : task?.when }

    private var firstWeekStart: Date {
        let t = Day.today
        let wd = Day.cal.component(.weekday, from: t) - 1   // Sunday first, as the header reads
        return Day.offset(-wd - 7 * Self.weeksBack, from: t)
    }
    private func weekStart(_ i: Int) -> Date { Day.offset(7 * i, from: firstWeekStart) }
    private func weekIndex(_ d: Date) -> Int { Day.cal.dateComponents([.day], from: firstWeekStart, to: Day.start(d)).day! / 7 }
    private var todayWeek: Int { weekIndex(Day.today) }

    /// The month with the most days showing.
    private var headerMonth: Date {
        let top = topWeek ?? todayWeek
        return Day.offset(3, from: weekStart(top + 2))
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
                Text(Day.fmt(Day.cal.component(.year, from: headerMonth) == Day.cal.component(.year, from: Day.today) ? "MMMM" : "MMMM yyyy", headerMonth))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: Day.month(headerMonth))
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
                    .transition(.opacity)
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 22)
            .padding(.top, 14)

            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.inkTertiary).frame(maxWidth: .infinity)
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
        .animation(.easeOut(duration: 0.15), value: topWeek.map { abs($0 + 1 - todayWeek) > 2 })
        .onAppear {
            let anchor = current.map(weekIndex) ?? todayWeek
            topWeek = max(0, anchor - 1)
        }
    }

    // MARK: Parts

    private var quickPicks: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                quick("Today", Day.today, symbol: "sun.max.fill", tint: p.list(.yellow))
                quick("Tomorrow", Day.offset(1), symbol: "sunrise.fill", tint: p.list(.red))
                quick("This Weekend", weekend, symbol: "sofa.fill", tint: p.list(.cyan))
                quick("Next Week", nextWeek, symbol: "arrow.right.circle.fill", tint: p.list(.magenta))
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

    private func quick(_ title: String, _ date: Date, symbol: String, tint: Color) -> some View {
        let on = current.map { Day.start($0) == date } ?? false
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
                day(Day.offset(k, from: weekStart(i)))
            }
        }
    }

    private func day(_ d: Date) -> some View {
        let isToday = d == Day.today
        let selected = current.map { Day.start($0) == d } ?? false
        let otherMonth = Day.cal.component(.month, from: d) != Day.cal.component(.month, from: headerMonth)
        let marked = other.map { Day.start($0) == d } ?? false
        return Button { choose(d) } label: {
            ZStack {
                if selected { Circle().fill(p.accent).frame(width: 38, height: 38) }
                Text("\(Day.cal.component(.day, from: d))")
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
        .accessibilityLabel(Day.full(d) + (isToday ? ", today" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: target.kind == .when ? "calendar" : "flag.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.inkTertiary)
            if let c = current {
                Text(Day.full(c)).font(Typo.body).foregroundStyle(p.ink)
                Text("· " + Day.relative(c)).font(Typo.body).foregroundStyle(p.inkTertiary)
                if target.kind == .deadline, Day.tone(c) == .due || Day.tone(c) == .late {
                    Text("· " + Day.deadlineLabel(c)).font(Typo.body).foregroundStyle(Day.tone(c) == .late ? p.danger : p.attention)
                }
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

    private var weekend: Date {
        let wd = Day.cal.component(.weekday, from: Day.today)   // 1 Sunday … 7 Saturday
        return wd == 7 ? Day.today : Day.offset(7 - wd)
    }
    private var nextWeek: Date {
        let wd = Day.cal.component(.weekday, from: Day.today)
        return Day.offset((9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7)   // next Monday
    }

    private func scroll(to week: Int) {
        withAnimation(Motion.natural) { topWeek = max(0, week - 1) }
    }

    private func choose(_ d: Date?) {
        picked = d
        store.setDate(target.taskID, target.kind, d)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22))
            dismiss()
        }
    }
}
