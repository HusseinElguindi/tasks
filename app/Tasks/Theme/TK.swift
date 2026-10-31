import AppKit
import QuartzCore
import SwiftUI

/// The v2 tokens (design/INTERACTIONS-v2.md §3), with the prototype's values: `design/prototype-v2/tasks-v2.css`
/// lines 5–78 for colors and motion, `Main.dc.html` lines 393–412 for metrics and timers. The comment on each value
/// names the CSS variable to search for in the prototype.
enum TK {}

// MARK: - Colors

extension TK {
    /// Every colour token for one theme and appearance (THEMES.md §1.1, by its names; the comment on each gives the
    /// prototype's CSS variable). Built once per appearance and kept (`AppModel.palette`), so drawing reads stored
    /// `NSColor`s and nothing reads a theme per frame. AppKit views read the `NSColor`s; SwiftUI views `.swiftUI`.
    struct Palette: Hashable, @unchecked Sendable {
        let isDark: Bool
        // Surfaces
        let ground, base, dim, popover, lift: NSColor                 // --ground --base --dim --popover --lift
        /// Settings' grouped sections (Pane's card; no CSS variable).
        let card: NSColor
        // Ink
        private(set) var ink: NSColor                                 // --ink
        let inkSecondary, inkTertiary, inkQuiet: NSColor              // --ink-2 --ink-3 --ink-q
        // Lines and edges
        let linePane, linePaneDim, lineSeparator, lineField: NSColor  // --line-pane --line-pane-dim --line-sep --line-field
        let edgeOuter, edgeInner: NSColor                             // --edge-outer --edge-inner: the current sidebar row
        // Fills
        let fillRowSelected, fillRowSelectedDim: NSColor              // --sel --sel-dim
        let fillControl, fillTrack, fillStrong: NSColor              // --fill-control --fill-track --fill-strong
        let hover, press: NSColor                                     // --hover --press
        // Accent, focus and state
        let accent, accentText, accentTint, onAccent: NSColor         // --accent --accent-text --accent-tint --on-accent
        /// Editing rings and drop rings (--focus).
        let focus: NSColor
        let textSelection: NSColor                                    // --text-sel
        let danger, dangerTint, attention, attentionTint: NSColor     // --danger --danger-tint --attn --attn-tint
        // Lists, tiles, drag and the brand mark
        let tileFill, tileRing: NSColor                               // --tile-fill --tile-ring (css:124–125)
        let liftChip: NSColor                                         // --lift-chip: a chip on the dragged copy
        let markHead, markBar, markRings, markTrail: NSColor          // --mark-*: the sidebar's brand mark
        // Shadows: a 0.5pt ring plus a blur (css:57–58, 74–75)
        let shadowPopoverRing, shadowPopover: NSColor                 // --shadow-popover
        let shadowLiftRing, shadowLift: NSColor                       // --shadow-lift
        /// The seven list slots in the prototype's hand-out order (`COLORS`, dc:414). A list's slot comes from its id
        /// (`ListModel.colorSlot`); the four views' glyphs use them too.
        private let lists: [NSColor]                                  // --ansi-blue … --ansi-red, --ansi-ink

        enum ListSlot: Int { case blue, magenta, green, cyan, yellow, red, ink }

        /// The token values, by `Token.rawValue`: what equality compares, so any change of colour redraws (rows skip
        /// work while their palette is equal). Comparing the appearance alone would miss a theme change.
        private var values: [RGBA]

        static func == (a: Palette, b: Palette) -> Bool { a.isDark == b.isDark && a.values == b.values }
        func hash(into h: inout Hasher) { h.combine(values) }

        init(theme: Theme, dark: Bool) {
            let v = theme.tokens(dark: dark)
            func c(_ t: Token) -> NSColor { v[t.rawValue].ns }
            isDark = dark
            values = v
            ground = c(.ground); base = c(.base); dim = c(.dim); popover = c(.popover); lift = c(.lift); card = c(.card)
            ink = c(.ink); inkSecondary = c(.inkSecondary); inkTertiary = c(.inkTertiary); inkQuiet = c(.inkQuiet)
            linePane = c(.linePane); linePaneDim = c(.linePaneDim); lineSeparator = c(.lineSeparator); lineField = c(.lineField)
            edgeOuter = c(.edgeOuter); edgeInner = c(.edgeInner)
            fillRowSelected = c(.fillRowSelected); fillRowSelectedDim = c(.fillRowSelectedDim)
            fillControl = c(.fillControl); fillTrack = c(.fillTrack); fillStrong = c(.fillStrong)
            hover = c(.hover); press = c(.press)
            accent = c(.accent); accentText = c(.accentText); accentTint = c(.accentTint); onAccent = c(.onAccent)
            focus = c(.focus); textSelection = c(.textSelection)
            danger = c(.danger); dangerTint = c(.dangerTint); attention = c(.attention); attentionTint = c(.attentionTint)
            tileFill = c(.tileFill); tileRing = c(.tileRing); liftChip = c(.liftChip)
            markHead = c(.markHead); markBar = c(.markBar); markRings = c(.markRings); markTrail = c(.markTrail)
            shadowPopoverRing = c(.shadowPopoverRing); shadowPopover = c(.shadowPopover)
            shadowLiftRing = c(.shadowLiftRing); shadowLift = c(.shadowLift)
            lists = [c(.listBlue), c(.listMagenta), c(.listGreen), c(.listCyan), c(.listYellow), c(.listRed), c(.listInk)]
        }

        /// Text in the list pane, a list's notes and a heading's (§23): a step quieter, its body in `ink-secondary`.
        var quieter: Palette {
            var p = self
            p.ink = inkSecondary
            p.values[Token.ink.rawValue] = values[Token.inkSecondary.rawValue]
            return p
        }

        static let dark = Palette(theme: .rex, dark: true)
        static let light = Palette(theme: .rex, dark: false)

        func list(_ slot: ListSlot) -> NSColor { lists[slot.rawValue] }
        func listColor(slot: Int) -> NSColor { lists[((slot % 7) + 7) % 7] }

        /// Brightness filters (css:208–210, 293–295): hover 1.18 / 0.96 (chips), 1.12 / 0.97 (capsule buttons and
        /// quick picks), press 0.86. Fixed factors, not colours: no theme changes them (THEMES.md §2.2).
        var chipHoverBrightness: CGFloat { isDark ? 1.18 : 0.96 }
        var buttonHoverBrightness: CGFloat { isDark ? 1.12 : 0.97 }
        static let pressBrightness: CGFloat = 0.86
    }
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }

    /// CSS `filter: brightness(b)`: each channel times b, clamped.
    func brightness(_ b: CGFloat) -> NSColor {
        guard b != 1, let c = usingColorSpace(.sRGB) else { return self }
        return NSColor(srgbRed: min(1, c.redComponent * b), green: min(1, c.greenComponent * b),
                       blue: min(1, c.blueComponent * b), alpha: c.alphaComponent)
    }

    /// This color composited over `bg` (for fills that must be opaque).
    func over(_ bg: NSColor) -> NSColor {
        guard let c = usingColorSpace(.sRGB), let b = bg.usingColorSpace(.sRGB) else { return self }
        let a = c.alphaComponent
        return NSColor(srgbRed: c.redComponent * a + b.redComponent * (1 - a),
                       green: c.greenComponent * a + b.greenComponent * (1 - a),
                       blue: c.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
    }
}

private struct TKPaletteKey: EnvironmentKey {
    static let defaultValue = TK.Palette.dark
}

extension EnvironmentValues {
    var tk: TK.Palette {
        get { self[TKPaletteKey.self] }
        set { self[TKPaletteKey.self] = newValue }
    }
}

// MARK: - Type

extension TK {
    enum Font {
        nonisolated(unsafe) static let body = NSFont.systemFont(ofSize: 13)                          // css:25, 13/16
        nonisolated(unsafe) static let bodyMedium = NSFont.systemFont(ofSize: 13, weight: .medium)   // .ph .pt, .crow .cl
        nonisolated(unsafe) static let label = NSFont.systemFont(ofSize: 11, weight: .semibold)      // .glabel 11/14
        nonisolated(unsafe) static let brand = NSFont.systemFont(ofSize: 13, weight: .semibold)      // .sbhead 13/16
        // Dates' digits are tabular, so "3d left" and "14d left" line up down a column (§24, css:487).
        nonisolated(unsafe) static let chip = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)       // .chip 11/14
        nonisolated(unsafe) static let chipLarge = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)  // .chip.lg
        nonisolated(unsafe) static let small = NSFont.systemFont(ofSize: 12)                         // .where, .rel, .bs
        nonisolated(unsafe) static let tooltip = NSFont.systemFont(ofSize: 11)                       // .tip 11/14
        nonisolated(unsafe) static let detailTitle = NSFont.systemFont(ofSize: 15, weight: .semibold) // .dtitle 15/20
        nonisolated(unsafe) static let caption = NSFont.systemFont(ofSize: 11)                       // .dmeta 11/14
        nonisolated(unsafe) static let tile = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold) // .tile 700 10px mono
        nonisolated(unsafe) static let tileSmall = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
        nonisolated(unsafe) static let count = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        nonisolated(unsafe) static let hint = NSFont.systemFont(ofSize: 12)                          // .ct.hint
        nonisolated(unsafe) static let code = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }
}

// MARK: - Metrics (points)

extension TK {
    enum M {
        static let pitch: CGFloat = 32            // PITCH: 30pt rows on a 32pt pitch (Rex)
        static let row: CGFloat = 30
        static let sidebar: CGFloat = 230         // SB_W: the default; dragging its edge resizes it (v2 feedback 4)
        static let sidebarMin: CGFloat = 180
        static let sidebarMax: CGFloat = 400
        static let sidebarTop: CGFloat = 50       // SB_TOP: the first sidebar row
        static let paneTop: CGFloat = 8           // PANE_TOP
        static let header: CGFloat = 34           // HEAD_H
        static let gutter: CGFloat = 8            // GUTTER
        static let detail: CGFloat = 420          // DETAIL_W: the default; dragging the gap before it resizes it
        static let detailMin: CGFloat = 340
        /// The list pane never gets narrower than this from a divider; with the detail pane at its minimum beside it
        /// that can't hold, the window is narrow (the detail pane replaces the list). 220 keeps the defaults' 900.
        static let listMin: CGFloat = 220
        static let narrowWidth: CGFloat = 900
        /// The sidebar divider's grab zone, centered on the list pane's left edge; the detail divider is the gutter.
        static let dividerHit: CGFloat = 8
        static let paneRadius: CGFloat = 10
        /// The list pane header's left padding with the sidebar hidden, so its tile starts at window x 132 (css:146,
        /// dc:1914).
        static let headerInsetCollapsed: CGFloat = 124
        /// …and 156 while the sync cloud shows beside the toggle (§26).
        static let headerInsetCloud: CGFloat = 156
        static let headerInset: CGFloat = 12

        // Task rows (css:160–188)
        static let rowInset: CGFloat = 10         // from the pane's sides
        static let rowRadius: CGFloat = 8
        static let rowTop: CGFloat = 4            // the first row, below the header
        static let rowTopArchived: CGFloat = 64   // under the archived banner
        static let rowPadLeft: CGFloat = 10
        static let rowPadRight: CGFloat = 5
        static let titleGap: CGFloat = 10         // checkbox → title
        static let titleFade: CGFloat = 24        // the title's last 24pt fade out
        static let chipsGap: CGFloat = 8          // title → chips
        static let chipSpacing: CGFloat = 6
        static let openButton: CGFloat = 22       // ›
        static let openGap: CGFloat = 4           // chips → ›

        static let check: CGFloat = 16
        static let checkRing: CGFloat = 1.5
        static let checkHit: CGFloat = 30
        static let checkGlyph: CGFloat = 10

        static let chip: CGFloat = 18
        static let chipPad: CGFloat = 7
        static let chipGap: CGFloat = 4
        static let chipIcon: CGFloat = 11
        static let chipLarge: CGFloat = 22
        static let chipLargePad: CGFloat = 9
        static let chipLargeGap: CGFloat = 5

        static let headerButton: CGFloat = 26
        static let headerButtonRadius: CGFloat = 6
        static let headerGlyph: CGFloat = 14

        static let dragSlop: CGFloat = 4          // DRAG_SLOP
        static let scrollEdge: CGFloat = 24       // SCROLL_EDGE
        static let scrollStep: CGFloat = 8        // SCROLL_STEP per 16 ms
        static let dragTagWidth: CGFloat = 210
    }
}

// MARK: - Motion

extension TK {
    /// SwiftUI animations (§3 Motion). `nil` under Reduce Motion.
    enum Motion {
        static var reduce: Bool {
            #if DEBUG
            // `-debugReduceMotion YES`: Reduce Motion without changing the system setting.
            if UserDefaults.standard.bool(forKey: "debugReduceMotion") { return true }
            #endif
            return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        static var hoverIn: Animation? { reduce ? nil : .timingCurve(0, 0.8, 0.2, 1, duration: 0.06) }
        static var hoverOut: Animation? { reduce ? nil : .timingCurve(0, 0, 0.2, 1, duration: 0.085) }
        static var icon: Animation? { reduce ? nil : .timingCurve(0, 0, 0.2, 1, duration: 0.1) }
        static var focus: Animation? { reduce ? nil : .timingCurve(0, 0, 0.2, 1, duration: 0.06) }
        static var sidebar: Animation? { reduce ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.3) }
        /// Unchanged from v1: the detail pane's open and close.
        static var natural: Animation? { reduce ? nil : .smooth(duration: 0.3) }
        static var layout: Animation? { reduce ? nil : .smooth(duration: 0.25) }
        static var snappy: Animation? { reduce ? nil : .snappy(duration: 0.2) }
        static var fadeIn: Animation? { reduce ? nil : .easeOut(duration: 0.18) }
        static var fadeOut: Animation? { reduce ? nil : .easeOut(duration: 0.15) }
        static var popoverIn: Animation? { reduce ? nil : .timingCurve(0, 0, 0.2, 1, duration: 0.12) }
        static var noticeIn: Animation? { reduce ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22) }
        static var noticeOut: Animation? { reduce ? nil : .easeIn(duration: 0.16) }
        static var tooltipIn: Animation? { reduce ? nil : .easeOut(duration: 0.1) }
        static var chevron: Animation? { reduce ? nil : .easeOut(duration: 0.2) }
    }

    /// The same motion for Core Animation (AppKit views).
    enum CA {
        static var reduce: Bool { Motion.reduce }

        nonisolated(unsafe) static let hoverIn = CAMediaTimingFunction(controlPoints: 0, 0.8, 0.2, 1)
        nonisolated(unsafe) static let decel = CAMediaTimingFunction(controlPoints: 0, 0, 0.2, 1)   // hoverOut, icon, focus, popover
        nonisolated(unsafe) static let sidebarCurve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        nonisolated(unsafe) static let flight = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        nonisolated(unsafe) static let easeOut = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)  // CSS ease-out
        nonisolated(unsafe) static let easeIn = CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)   // CSS ease-in

        struct Timing: @unchecked Sendable {
            let duration: CFTimeInterval
            let curve: CAMediaTimingFunction
        }

        static let hoverInT = Timing(duration: 0.06, curve: hoverIn)
        static let hoverOutT = Timing(duration: 0.085, curve: decel)
        static let iconT = Timing(duration: 0.1, curve: decel)
        static let focusT = Timing(duration: 0.06, curve: decel)
        static let fadeInT = Timing(duration: 0.18, curve: easeOut)
        static let fadeOutT = Timing(duration: 0.15, curve: easeOut)
        /// Rows and notes unfolding from under an expanded heading: faint while they still overlap it (css:476).
        static let unfoldT = Timing(duration: 0.22, curve: easeIn)
        static let colorT = Timing(duration: 0.2, curve: easeOut)     // a done title's color (css:169)
        static let checkFillT = Timing(duration: 0.16, curve: easeOut)
        static let pressT = Timing(duration: 0.08, curve: easeOut)    // the checkbox press (css:195)
        static let chevronT = Timing(duration: 0.2, curve: easeOut)
        static let flightT = Timing(duration: 0.16, curve: flight)
        static let widthT = Timing(duration: 0.16, curve: easeOut)

        /// SwiftUI's springs as CA springs. `.smooth(duration: d)` is critically damped with response d;
        /// `.snappy(duration: d)` has bounce 0.15 (damping ratio 0.85).
        struct Spring: Sendable {
            let stiffness: CGFloat
            let damping: CGFloat

            init(response: CGFloat, dampingRatio: CGFloat) {
                let w = 2 * CGFloat.pi / response
                stiffness = w * w
                damping = 2 * dampingRatio * w
            }
        }

        static let layout = Spring(response: 0.25, dampingRatio: 1)    // .smooth(duration: 0.25)
        static let natural = Spring(response: 0.3, dampingRatio: 1)    // .smooth(duration: 0.3)
        static let snappy = Spring(response: 0.2, dampingRatio: 0.85)  // .snappy(duration: 0.2)

        static func spring(_ keyPath: String, _ s: Spring, from: Any?, to: Any?) -> CASpringAnimation {
            let a = CASpringAnimation(keyPath: keyPath)
            a.mass = 1
            a.stiffness = s.stiffness
            a.damping = s.damping
            a.initialVelocity = 0
            a.fromValue = from
            a.toValue = to
            a.duration = a.settlingDuration
            return a
        }

        static func basic(_ keyPath: String, _ t: Timing, from: Any?, to: Any?, delay: CFTimeInterval = 0) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from
            a.toValue = to
            a.duration = t.duration
            a.timingFunction = t.curve
            if delay > 0 {
                a.beginTime = CACurrentMediaTime() + delay
                a.fillMode = .backwards
            }
            return a
        }
    }

    /// Timers, dc:398–412.
    enum Timer {
        static let settle: TimeInterval = 1.5        // SETTLE_MS
        static let notice: TimeInterval = 5          // NOTICE_MS
        static let noticeInfo: TimeInterval = 1.8    // NOTICE_INFO_MS
        static let noticeRearm: TimeInterval = 2     // NOTICE_REARM_MS
        static let noticeOut: TimeInterval = 0.17    // NOTICE_OUT_MS
        static let tipDelay: TimeInterval = 0.6      // TIP_DELAY
        static let tipWarm: TimeInterval = 0.6       // TIP_WARM_MS
        static let hintHold: TimeInterval = 0.45     // HINT_HOLD_MS
        static let typeSelect: TimeInterval = 1      // TYPE_SELECT_MS
        static let detailClose: TimeInterval = 0.46  // DETAIL_CLOSE_MS
        static let fly: TimeInterval = 0.17          // FLY_MS
        static let motionWindow: TimeInterval = 0.24 // MOTION_WINDOW_MS
    }
}

// MARK: - Layer helpers

extension CALayer {
    /// Sets a property with no implicit animation.
    func setInstant(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    /// Animates `keyPath` from its current presentation value to `to` with `timing`, and sets the model value.
    func animate(_ keyPath: String, to value: Any?, _ t: TK.CA.Timing, delay: CFTimeInterval = 0) {
        let from = presentation()?.value(forKeyPath: keyPath) ?? self.value(forKeyPath: keyPath)
        setInstant { setValue(value, forKeyPath: keyPath) }
        guard !TK.CA.reduce else { removeAnimation(forKey: keyPath); return }
        add(TK.CA.basic(keyPath, t, from: from, to: value, delay: delay), forKey: keyPath)
    }

    /// Springs `keyPath` from its current presentation value to `to`.
    func spring(_ keyPath: String, to value: Any?, _ s: TK.CA.Spring) {
        let from = presentation()?.value(forKeyPath: keyPath) ?? self.value(forKeyPath: keyPath)
        setInstant { setValue(value, forKeyPath: keyPath) }
        guard !TK.CA.reduce else { removeAnimation(forKey: keyPath); return }
        add(TK.CA.spring(keyPath, s, from: from, to: value), forKey: keyPath)
    }
}
