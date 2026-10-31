import AppKit
import QuartzCore
import SwiftUI
import TasksCore

// The date popover's calendar (INTERACTIONS-v2 §25 "Building it"), ported from the prototype: the calendar
// dc:2625–2745, its constants dc:474–484, and css:521–534 (the days, css:332–338).
//
// One column of weeks, 30pt a row (the 28pt day and 1pt above and below), six in view, endless both ways. Weeks are
// numbered from today's (0; earlier ones negative), and a week works out its seven dates from its number. The scroll
// view's document is a fixed strip of 120 weeks whose top is week `base`, so week n sits at y = (n − base) × 30, and
// where the view is, in points from the top of today's week, is pos = clip origin + base × 30. When the view comes
// within 30 weeks of either end, `base` moves to put it in the strip's middle and the clip origin moves by the same
// amount in the same turn of the run loop, before anything draws: nothing on screen moves, and a flick keeps its
// momentum, because the scroll view adds each event's delta to the origin it finds. Only the weeks in view and four
// either side exist, in 15 reused row layers.

/// What the days show (§11, §24): today, the tasks' shared date (the ring), the other date (the dot) and the
/// highlighted day.
struct CalendarMarks: Equatable {
    var today: CalendarDate
    var cur: CalendarDate?
    var other: CalendarDate?
    var otherIsDeadline: Bool
    /// nil while the text reads as no date.
    var hot: CalendarDate?
}

/// A request to bring a date into view (prototype `calReveal`). From the keys, the least scroll that shows its week;
/// typed, its month with the first week on top; both only when it's out of view, so typing doesn't jitter the grid.
/// Today, today's month, always. `seq` makes each request new.
struct CalendarReveal: Equatable {
    enum Why { case key, typed, today }
    var date: CalendarDate
    var why: Why
    var seq: Int
}

/// The header: the month with the most of the 42 days in view (at a tie, the later), and the Today pill, shown once
/// today is more than two weeks out of view, with its arrow (true: today is above).
struct CalendarHeader: Equatable {
    var month: CalendarDate
    var todayAbove: Bool?
}

/// Weeks counted from today's, in the locale's first weekday; positions in points from the top of today's week.
struct WeekMath {
    static let row: CGFloat = 30
    static let rows = 6

    /// The day number of the first day of today's week.
    let w0: Int

    init(today: CalendarDate, firstWeekday: Int = Calendar.current.firstWeekday) {
        let n = today.dayNumber
        let weekday = ((n + 4) % 7 + 7) % 7 + 1   // 1 = Sunday, as `Calendar` counts (1970-01-01 was a Thursday)
        w0 = n - (weekday - firstWeekday + 7) % 7
    }

    func week(of d: CalendarDate) -> Int {
        let n = d.dayNumber - w0
        return n >= 0 ? n / 7 : -((-n + 6) / 7)
    }

    /// Day `j` (0–6) of week `n`; nil past `CalendarDate`'s years 0–9999.
    func day(week n: Int, _ j: Int) -> CalendarDate? { CalendarDate(dayNumber: w0 + 7 * n + j) }

    /// A date's month with its first week on top (prototype `calMonthPos`).
    func monthPos(_ d: CalendarDate) -> CGFloat {
        CGFloat(week(of: CalendarDate(year: d.year, month: d.month, day: 1) ?? d)) * Self.row
    }

    /// The header at `pos` (prototype `calVM`): the month counted over the six rows nearest the view.
    func header(pos: CGFloat, fallback: CalendarDate) -> CalendarHeader {
        let r0 = Int((pos / Self.row + 0.5).rounded(.down))
        var keys: [Int] = []
        var counts: [Int] = []
        for i in 0..<(Self.rows * 7) {
            guard let d = CalendarDate(dayNumber: w0 + 7 * r0 + i) else { continue }
            let k = d.year * 12 + d.month - 1
            if let j = keys.firstIndex(of: k) { counts[j] += 1 } else { keys.append(k); counts.append(1) }
        }
        var best = -1
        for j in keys.indices where best < 0 || counts[j] > counts[best] || (counts[j] == counts[best] && keys[j] > keys[best]) { best = j }
        let month = best < 0 ? fallback : CalendarDate(year: keys[best] / 12, month: keys[best] % 12 + 1, day: 1) ?? fallback
        // Today's week is 0: in view, give or take two weeks.
        let at = pos / Self.row
        let near = at - 2.5 <= 0 && 0 <= at + CGFloat(Self.rows) + 1.5
        return CalendarHeader(month: month, todayAbove: near ? nil : pos > 0)
    }
}

struct WeekCalendar: NSViewRepresentable {
    let marks: CalendarMarks
    /// Where it opens: this month's first week on top. It never animates on opening.
    let opening: CalendarDate
    let reveal: CalendarReveal?
    let onPick: (CalendarDate) -> Void
    let onHeader: (CalendarHeader) -> Void

    func makeNSView(context: Context) -> WeekCalendarView {
        WeekCalendarView(today: marks.today, opening: opening)
    }

    func updateNSView(_ v: WeekCalendarView, context: Context) {
        v.onPick = onPick
        v.onHeader = onHeader
        v.update(marks: marks, palette: context.environment.tk)
        if let reveal, reveal.seq != v.revealSeq {
            v.revealSeq = reveal.seq
            // After this update, as the prototype's setTimeout: the request may come from typing mid-update.
            DispatchQueue.main.async { [weak v] in v?.reveal(reveal.date, reveal.why) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WeekCalendarView, context: Context) -> CGSize? {
        CGSize(width: WeekCalendarView.width, height: WeekCalendarView.height)
    }
}

final class WeekCalendarView: NSScrollView {
    nonisolated static let width: CGFloat = 224
    nonisolated static let height: CGFloat = 180
    private static let row = WeekMath.row
    private static let rows = WeekMath.rows
    /// The strip, in weeks; recentre within `edge` of either end; the weeks kept either side of the view.
    private static let span = 120, edge = 30, buffer = 4
    /// A move farther than this many weeks lands this far short first, then animates the rest.
    private static let jump = 6
    /// Rows made: six in view, a seventh while between weeks, and four either side.
    private static let pool = rows + 1 + 2 * buffer

    var onPick: ((CalendarDate) -> Void)?
    var onHeader: ((CalendarHeader) -> Void)?
    var revealSeq = -1

    let math: WeekMath
    private let strip = WeekStrip()
    private let rowLayers: [WeekRowLayer]
    private(set) var base: Int
    private var marks: CalendarMarks
    private var palette: TK.Palette?
    private(set) var header: CalendarHeader
    private var hovered: CalendarDate?
    private var recentring = false
    private var live = false
    /// Where the calendar last came to rest (opening, a snap, a move to a date), while the user isn't scrolling it.
    /// Nothing else moves it: SwiftUI resizes the scroll view through "Popover in" (§21), and AppKit nudges the clip
    /// origin as it does, which left the weeks up to 2pt off; they go back here.
    private var rest: CGFloat?
    private var anim: Anim?
    private var link: CADisplayLink?
    private var snapLater: DispatchWorkItem?

    private struct Anim {
        var from: CGFloat
        var to: CGFloat
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    /// Where the view is, in points from the top of today's week.
    var pos: CGFloat { contentView.bounds.origin.y + CGFloat(base) * Self.row }

    init(today: CalendarDate, opening: CalendarDate) {
        math = WeekMath(today: today)
        marks = CalendarMarks(today: today, otherIsDeadline: false)
        let p = math.monthPos(opening)
        base = Self.base(for: p)
        header = math.header(pos: p, fallback: opening)
        rowLayers = (0..<Self.pool).map { _ in WeekRowLayer() }
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        contentView = WeekClip()
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        // The prototype hides the scroll bar (css:532–533): a knob over a window that recentres would jump.
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero
        // A wheel mouse's notch moves a week.
        verticalLineScroll = Self.row
        strip.frame = NSRect(x: 0, y: 0, width: Self.width, height: CGFloat(Self.span) * Self.row)
        strip.owner = self
        documentView = strip
        for r in rowLayers { strip.layer?.addSublayer(r) }
        contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(clipMoved), name: NSView.boundsDidChangeNotification, object: contentView)
        nc.addObserver(self, selector: #selector(liveStarted), name: NSScrollView.willStartLiveScrollNotification, object: self)
        nc.addObserver(self, selector: #selector(liveEnded), name: NSScrollView.didEndLiveScrollNotification, object: self)
        setOrigin(p - CGFloat(base) * Self.row)
        rest = p
        #if DEBUG
        DebugPicker.calendar = self
        #endif
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The window's first week that puts `pos` in the strip's middle.
    private static func base(for pos: CGFloat) -> Int {
        Int((pos / row + 0.5).rounded(.down)) - (span - rows) / 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimation() }
    }

    func update(marks m: CalendarMarks, palette p: TK.Palette) {
        guard m != marks || p != palette else { return }
        // The highlighted day eases (css:334); a new theme doesn't.
        let animated = palette == p
        marks = m
        palette = p
        restyle(animated: animated)
    }

    // MARK: Scrolling

    /// On device pixels, as the clip view keeps it (`WeekClip`), so it isn't moved twice in a frame.
    private func setOrigin(_ y: CGFloat) {
        let s = window?.backingScaleFactor ?? 2
        contentView.setBoundsOrigin(NSPoint(x: 0, y: (y * s).rounded() / s))
        reflectScrolledClipView(contentView)
    }

    @objc private func clipMoved() {
        guard !recentring else { return }
        if let rest, anim == nil, !live, pos != rest {
            recentring = true
            setOrigin(rest - CGFloat(base) * Self.row)
            recentring = false
        }
        #if DEBUG
        let t0 = CACurrentMediaTime()
        #endif
        if anim == nil { recentreIfNeeded() }
        placeRows()
        reportHeader()
        refreshHover()
        #if DEBUG
        DebugPicker.calendarMoved(self, ms: (CACurrentMediaTime() - t0) * 1000)
        #endif
    }

    /// Moves the window of weeks under the view when the view is within `edge` weeks of either end.
    private func recentreIfNeeded() {
        let y = contentView.bounds.origin.y
        let off = y / Self.row
        guard off < CGFloat(Self.edge) || off > CGFloat(Self.span - Self.rows - Self.edge) else { return }
        let b = Self.base(for: pos)
        guard b != base else { return }
        let dy = CGFloat(b - base) * Self.row
        base = b
        recentring = true
        setOrigin(y - dy)
        recentring = false
    }

    override func scrollWheel(with event: NSEvent) {
        // A hand on the trackpad or wheel takes over from a move in progress.
        stopAnimation()
        rest = nil
        super.scrollWheel(with: event)
        // A wheel mouse has no live scroll to end: snap once its notches stop (the prototype's 120ms).
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            snapLater?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.snap() }
            snapLater = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
        }
    }

    @objc private func liveStarted() {
        live = true
        rest = nil
        snapLater?.cancel()
    }

    /// After the momentum, too: ease to the nearest week.
    @objc private func liveEnded() {
        live = false
        snap()
    }

    private func snap() {
        guard anim == nil, !live else { return }
        let p = pos
        let t = (p / Self.row + 0.5).rounded(.down) * Self.row
        if abs(t - p) >= 1 {
            scroll(to: t, duration: 0.14)
        } else {
            if t != p { setOrigin(t - CGFloat(base) * Self.row) }
            rest = t
        }
    }

    /// Brings `d` into view (prototype `calReveal`).
    func reveal(_ d: CalendarDate, _ why: CalendarReveal.Why) {
        let r = CGFloat(math.week(of: d))
        let first = pos / Self.row, last = first + CGFloat(Self.rows - 1)
        var target: CGFloat?
        if why == .today {
            target = math.monthPos(d)
        } else if r < first - 0.01 || r > last + 0.01 {
            target = why == .key ? (r < first ? r : r - CGFloat(Self.rows - 1)) * Self.row : math.monthPos(d)
        }
        if let target { scroll(to: target) }
    }

    /// Eases to `target` (260ms, the prototype's cubic ease-out). Farther than six weeks, the window moves to the
    /// target first and the view lands six weeks short of it, then animates the rest: motion, without flicking
    /// through years. No recentring while it moves; the strip's middle leaves 57 weeks either way.
    func scroll(to target: CGFloat, duration: CFTimeInterval = 0.26) {
        stopAnimation()
        rest = target
        var from = pos
        let reach = CGFloat(Self.jump) * Self.row
        if abs(target - from) > reach {
            from = target - (target > from ? reach : -reach)
            base = Self.base(for: target)
            if TK.Motion.reduce { setOrigin(target - CGFloat(base) * Self.row); return }
            anim = Anim(from: from, to: target, start: CACurrentMediaTime(), duration: duration)
            setOrigin(from - CGFloat(base) * Self.row)
        } else if TK.Motion.reduce {
            setOrigin(target - CGFloat(base) * Self.row)
            return
        }
        anim = Anim(from: from, to: target, start: CACurrentMediaTime(), duration: duration)
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        guard let a = anim else { stopAnimation(); return }
        // Where it should be when this frame shows.
        let k = min(1, max(0, (l.targetTimestamp - a.start) / a.duration))
        let e = 1 - pow(1 - k, 3)
        setOrigin(a.from + (a.to - a.from) * CGFloat(e) - CGFloat(base) * Self.row)
        if k >= 1 { stopAnimation() }
    }

    private func stopAnimation() {
        link?.invalidate()
        link = nil
        anim = nil
    }

    // MARK: Rows

    /// Gives the rows outside first … last the weeks that came in, and places every row at its y.
    private func placeRows() {
        let p = pos
        let first = max(base, Int((p / Self.row).rounded(.down)) - Self.buffer)
        let end = min(base + Self.span, first + Self.pool)
        var free: [WeekRowLayer] = []
        var have = Set<Int>()
        for r in rowLayers {
            if r.week >= first && r.week < end { have.insert(r.week) } else { free.append(r) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if first < end {
            for n in first..<end where !have.contains(n) {
                guard let r = free.popLast() else { break }
                r.week = n
                style(r, animated: false)
            }
        }
        for r in rowLayers {
            let inside = r.week >= first && r.week < end
            r.isHidden = !inside
            if inside { r.frame = CGRect(x: 0, y: CGFloat(r.week - base) * Self.row, width: Self.width, height: Self.row) }
        }
        CATransaction.commit()
    }

    private func restyle(animated: Bool) {
        for r in rowLayers where r.week != WeekRowLayer.unset { style(r, animated: animated) }
    }

    private func style(_ r: WeekRowLayer, animated: Bool) {
        guard let palette else { return }
        let m = header.month
        for j in 0..<7 {
            let d = math.day(week: r.week, j)
            var look = DayLayer.Look()
            if let d {
                look.out = d.year != m.year || d.month != m.month
                look.today = d == marks.today
                look.cur = d == marks.cur
                look.other = d == marks.other
                look.otherIsDeadline = marks.otherIsDeadline
                look.hot = d == marks.hot
                look.hovered = d == hovered
            }
            r.days[j].set(d, look: look, palette: palette, animated: animated)
        }
    }

    private func reportHeader() {
        let h = math.header(pos: pos, fallback: header.month)
        guard h != header else { return }
        let dims = h.month != header.month
        header = h
        // The dimming changes with the header.
        if dims { restyle(animated: false) }
        onHeader?(h)
    }

    // MARK: The pointer

    /// The day under a point in the strip: the 28pt capsule, not the 1pt between weeks.
    func day(at p: NSPoint) -> CalendarDate? {
        let inRow = p.y - (p.y / Self.row).rounded(.down) * Self.row
        guard inRow >= 1, inRow < Self.row - 1, p.x >= 0, p.x < Self.width else { return nil }
        let n = Int((p.y / Self.row).rounded(.down)) + base
        return math.day(week: n, Int(p.x / (Self.width / 7)))
    }

    fileprivate func hover(_ d: CalendarDate?) {
        guard d != hovered else { return }
        hovered = d
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for r in rowLayers where r.week != WeekRowLayer.unset && r.days.contains(where: { $0.date != nil && $0.isHovered != ($0.date == d) }) {
            style(r, animated: true)
        }
        CATransaction.commit()
    }

    /// The days move under a still pointer as it scrolls.
    private func refreshHover() {
        guard strip.pointerInside, let w = window else { return }
        hover(day(at: strip.convert(w.mouseLocationOutsideOfEventStream, from: nil)))
    }

    fileprivate func pick(_ d: CalendarDate) { onPick?(d) }

    // MARK: Accessibility

    /// The days in view, each a button named by its full date (as the paged grid's were).
    fileprivate func accessibilityDays() -> [Any] {
        let first = Int((pos / Self.row).rounded(.down))
        var out: [Any] = []
        for n in first...(first + Self.rows) {
            let y = CGFloat(n - base) * Self.row + 1
            for j in 0..<7 {
                guard let d = math.day(week: n, j) else { continue }
                let e = DayElement()
                e.setAccessibilityRole(.button)
                e.setAccessibilityLabel(DateLabel.long(d, today: marks.today))
                e.setAccessibilitySelected(d == marks.hot)
                e.setAccessibilityParent(strip)
                e.setAccessibilityFrameInParentSpace(NSRect(x: CGFloat(j) * Self.width / 7, y: y, width: Self.width / 7, height: Self.row - 2))
                e.press = { [weak self] in self?.pick(d) }
                out.append(e)
            }
        }
        return out
    }

    #if DEBUG
    /// The weeks in view, as their first days, for the debug log.
    var debugWeeks: String {
        let first = Int((pos / Self.row).rounded(.down))
        return (first..<(first + Self.rows)).map { n in math.day(week: n, 0).map { "\($0)" } ?? "-" }.joined(separator: " ")
    }

    /// Whether every row in view shows its own week, at its own y.
    var debugRowsConsistent: Bool {
        let first = Int((pos / Self.row).rounded(.down))
        for n in first..<(first + Self.rows) {
            guard let r = rowLayers.first(where: { $0.week == n }), !r.isHidden,
                  r.frame.minY == CGFloat(n - base) * Self.row,
                  r.days[0].date == math.day(week: n, 0) else { return false }
        }
        return true
    }

    var debugClipY: CGFloat { contentView.bounds.origin.y }
    /// Hover as the pointer would at (x, y) in the calendar's frame (hover can't be posted).
    func debugHover(_ x: CGFloat, _ y: CGFloat) { hover(day(at: NSPoint(x: x, y: y + contentView.bounds.origin.y))) }
    var debugAnimating: Bool { anim != nil }
    #endif
}

/// Keeps the origin on device pixels wherever the calendar sits in the window. The default aligns the document to
/// the window's pixels, which moved the weeks by up to 1.5pt while "Popover in" scaled the frame (§21) and could
/// leave them half a point off a week at rest. No rounding to weeks here: that's the snap's, at rest.
private final class WeekClip: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = proposed
        let s = window?.backingScaleFactor ?? 2
        let maxY = max(0, (documentView?.frame.height ?? 0) - r.height)
        r.origin.x = 0
        r.origin.y = min(max(0, (r.origin.y * s).rounded() / s), maxY)
        return r
    }
}

/// The scroll view's document: draws nothing itself, holds the row layers, and takes the pointer.
private final class WeekStrip: FlippedLayerView {
    weak var owner: WeekCalendarView?
    private(set) var pointerInside = false
    private var pressed: CalendarDate?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func point(_ e: NSEvent) -> NSPoint { convert(e.locationInWindow, from: nil) }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        owner?.hover(owner?.day(at: point(event)))
    }

    override func mouseMoved(with event: NSEvent) {
        pointerInside = true
        owner?.hover(owner?.day(at: point(event)))
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        owner?.hover(nil)
    }

    // A day sets the date on release over the same day, as a click (the field keeps the keys: nothing here takes them).
    override func mouseDown(with event: NSEvent) { pressed = owner?.day(at: point(event)) }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let d = owner?.day(at: point(event)), d == pressed else { return }
        owner?.pick(d)
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { owner?.accessibilityDays() }
}

private final class DayElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        press?()
        return true
    }
}

/// A week: seven days, 32pt apart.
private final class WeekRowLayer: CALayer {
    static let unset = Int.min
    var week = WeekRowLayer.unset
    let days: [DayLayer] = (0..<7).map { _ in DayLayer() }

    override init() {
        super.init()
        isHidden = true
        let w = WeekCalendarView.width / 7
        for (j, d) in days.enumerated() {
            d.frame = CGRect(x: CGFloat(j) * w, y: 1, width: w, height: 28)
            addSublayer(d)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
}

/// A day (css:333–338, §24): a 28pt capsule, 12pt tabular. Other months `ink-quiet`; today `accent-text` semibold; the
/// tasks' date a 1.5pt inset `accent` ring; the other date a 4pt dot 3pt from the bottom, `attention` for a deadline,
/// `ink-tertiary` for a When; the highlighted day `accent` with `on-accent` semibold and no ring. Hover: `hover`. Only
/// the fill eases (`icon`), as in the CSS.
private final class DayLayer: CALayer {
    struct Look: Equatable {
        var out = false, today = false, cur = false, other = false, otherIsDeadline = false, hot = false, hovered = false
    }

    nonisolated(unsafe) private static let regular = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    nonisolated(unsafe) private static let bold = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    private let label = TextLayer()
    private let ring = CALayer()
    private let dot = CALayer()
    private(set) var date: CalendarDate?
    private var look = Look()
    private var palette: TK.Palette?
    var isHovered: Bool { look.hovered }

    override init() {
        super.init()
        cornerRadius = 14
        label.alignmentMode = .center
        ring.cornerRadius = 14
        ring.borderWidth = 1.5
        dot.cornerRadius = 2
        addSublayer(label)
        addSublayer(ring)
        addSublayer(dot)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ d: CalendarDate?, look l: Look, palette p: TK.Palette, animated: Bool) {
        guard d != date || l != look || p != palette else { return }
        let fillOnly = d == date && p == palette
        date = d
        look = l
        palette = p
        let fill: NSColor = l.hot ? p.accent : l.hovered ? p.hover : .clear
        setInstant {
            isHidden = d == nil
            if let d {
                let ink: NSColor = l.hot ? p.onAccent : l.today ? p.accentText : l.out ? p.inkQuiet : p.ink
                label.set(String(d.day), font: l.hot || l.today ? Self.bold : Self.regular, color: ink)
                // `place-items: center` with the 16pt line (css:334).
                label.place(x: 0, lineTop: 6, lineHeight: 16, width: bounds.width)
            }
            ring.frame = bounds
            ring.isHidden = !(l.cur && !l.hot)
            dot.frame = CGRect(x: bounds.width / 2 - 2, y: bounds.height - 7, width: 4, height: 4)
            ring.borderColor = p.focus.cgColor
            dot.isHidden = !l.other
            dot.backgroundColor = (l.otherIsDeadline ? p.attention : p.inkTertiary).cgColor
        }
        if animated && fillOnly { animate("backgroundColor", to: fill.cgColor, TK.CA.iconT) } else { setInstant { backgroundColor = fill.cgColor } }
    }
}
