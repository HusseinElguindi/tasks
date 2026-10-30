import AppKit
import QuartzCore
import SwiftUI

/// The v2 tokens (design/INTERACTIONS-v2.md §3), with the prototype's values: `design/prototype-v2/tasks-v2.css`
/// lines 5–78 for colors and motion, `Main.dc.html` lines 393–412 for metrics and timers. The comment on each value
/// names the CSS variable to search for in the prototype.
enum TK {}

// MARK: - Colors

extension TK {
    /// Every color, for one appearance. AppKit views read the `NSColor`s; SwiftUI views the `Color`s.
    struct Palette: Equatable, @unchecked Sendable {
        let isDark: Bool
        let ground, base, dim, popover, lift: NSColor                 // --ground --base --dim --popover --lift
        let linePane, linePaneDim, lineSep, lineField: NSColor        // --line-pane --line-pane-dim --line-sep --line-field
        let ink, ink2, ink3, inkQ: NSColor                            // --ink --ink-2 --ink-3 --ink-q
        let sel, selDim: NSColor                                      // --sel --sel-dim
        let fillControl, fillTrack, fillStrong: NSColor              // --fill-control --fill-track --fill-strong
        let edgeOuter, edgeInner: NSColor                             // --edge-outer --edge-inner
        let hover, press: NSColor                                     // --hover --press
        let accent, accentText, accentTint, onAccent: NSColor         // --accent --accent-text --accent-tint --on-accent
        let danger, dangerTint, attn, attnTint: NSColor               // --danger --danger-tint --attn --attn-tint
        let textSel: NSColor                                          // --text-sel
        let tileFill, tileRing: NSColor                               // .tile (css:124–125)
        let liftChip: NSColor                                         // .lifted .chip (css:246–247)
        /// The seven ANSI slots in the prototype's hand-out order (`COLORS`, dc:414): blue, magenta, green, cyan,
        /// yellow, red, ink. A list's slot comes from its id (`ListModel.colorSlot`).
        let ansi: [NSColor]
        let ansiYellow: NSColor
        /// Shadows: a 0.5pt ring plus a blur (css:57–58, 74–75).
        let popoverRing, popoverShadow: NSColor
        let liftRing, liftShadow: NSColor

        static func == (a: Palette, b: Palette) -> Bool { a.isDark == b.isDark }

        static let dark = Palette(
            isDark: true,
            ground: hex(0x181818), base: hex(0x1C1C1C), dim: hex(0x181818), popover: hex(0x262626), lift: hex(0x2C2C2C),
            linePane: hex(0x323334), linePaneDim: hex(0x282929), lineSep: hex(0x363738), lineField: hex(0x696B6E),
            ink: hex(0xE6EDF3), ink2: hex(0xA8ADB1), ink3: hex(0x7F8386), inkQ: hex(0x6D7072),
            sel: hex(0x333333), selDim: hex(0x292929),
            fillControl: hex(0x2D2E2E), fillTrack: hex(0x303132), fillStrong: hex(0x444444),
            edgeOuter: hex(0x5E5E5E), edgeInner: hex(0x535353),
            hover: .white.withAlphaComponent(0.07), press: .white.withAlphaComponent(0.12),
            accent: hex(0x2F81F7), accentText: hex(0x5799F6), accentTint: hex(0x1E2938), onAccent: .white,
            danger: hex(0xFF7B72), dangerTint: hex(0x3C2928), attn: hex(0xD29922), attnTint: hex(0x352E1D),
            textSel: hex(0x2F81F7).withAlphaComponent(0.45),
            tileFill: hex(0x444444), tileRing: .white.withAlphaComponent(0.10),
            liftChip: hex(0x3A3A3A),
            ansi: [hex(0x58A6FF), hex(0xBC8CFF), hex(0x3FB950), hex(0x39C5CF), hex(0xD29922), hex(0xFF7B72), hex(0xE6EDF3)],
            ansiYellow: hex(0xD29922),
            popoverRing: .white.withAlphaComponent(0.14), popoverShadow: .black.withAlphaComponent(0.5),
            liftRing: .white.withAlphaComponent(0.14), liftShadow: .black.withAlphaComponent(0.5))

        static let light = Palette(
            isDark: false,
            ground: hex(0xF5F5F5), base: hex(0xFFFFFF), dim: hex(0xFAFAFA), popover: hex(0xFFFFFF), lift: hex(0xFFFFFF),
            linePane: hex(0xD4D5D6), linePaneDim: hex(0xEBEBEC), lineSep: hex(0xE7E8E8), lineField: hex(0x848689),
            ink: hex(0x1F2328), ink2: hex(0x626568), ink3: hex(0x6C6F72), inkQ: hex(0x888A8D),
            sel: hex(0xE6E6E8), selDim: hex(0xEFEFF0),
            fillControl: hex(0xEDEDEE), fillTrack: hex(0xE9E9EA), fillStrong: hex(0xE0E0E1),
            edgeOuter: hex(0xCFCFD0), edgeInner: hex(0xD6D6D7),
            hover: hex(0x1F2328).withAlphaComponent(0.06), press: hex(0x1F2328).withAlphaComponent(0.11),
            accent: hex(0x0969DA), accentText: hex(0x0969DA), accentTint: hex(0xE6F0FB), onAccent: .white,
            danger: hex(0xCF222E), dangerTint: hex(0xFBEBEC), attn: hex(0x9A6700), attnTint: hex(0xFAF7F2),
            textSel: hex(0x0969DA).withAlphaComponent(0.25),
            tileFill: hex(0xE3E3E4), tileRing: hex(0x1F2328).withAlphaComponent(0.10),
            liftChip: hex(0xE9E9EA),
            ansi: [hex(0x0969DA), hex(0x8250DF), hex(0x116329), hex(0x1B7C83), hex(0x9A6700), hex(0xCF222E), hex(0x1F2328)],
            ansiYellow: hex(0x9A6700),
            popoverRing: hex(0x1F2328).withAlphaComponent(0.16), popoverShadow: hex(0x1F2328).withAlphaComponent(0.16),
            liftRing: hex(0x1F2328).withAlphaComponent(0.14), liftShadow: hex(0x1F2328).withAlphaComponent(0.18))

        func listColor(slot: Int) -> NSColor { ansi[((slot % 7) + 7) % 7] }

        /// Brightness filters (css:208–210, 293–295): hover 1.18 / 0.96 (chips), 1.12 / 0.97 (capsule buttons and
        /// quick picks), press 0.86.
        var chipHoverBrightness: CGFloat { isDark ? 1.18 : 0.96 }
        var buttonHoverBrightness: CGFloat { isDark ? 1.12 : 0.97 }
        static let pressBrightness: CGFloat = 0.86
    }

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
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
        nonisolated(unsafe) static let chip = NSFont.systemFont(ofSize: 11, weight: .medium)         // .chip 11/14
        nonisolated(unsafe) static let chipLarge = NSFont.systemFont(ofSize: 12, weight: .medium)    // .chip.lg
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
        static let sidebar: CGFloat = 230         // SB_W
        static let sidebarTop: CGFloat = 50       // SB_TOP: the first sidebar row
        static let paneTop: CGFloat = 8           // PANE_TOP
        static let header: CGFloat = 34           // HEAD_H
        static let gutter: CGFloat = 8            // GUTTER
        static let detail: CGFloat = 420          // DETAIL_W
        static let paneRadius: CGFloat = 10
        /// The list pane header's left padding with the sidebar hidden, so its tile starts at window x 132 (css:146,
        /// dc:1914).
        static let headerInsetCollapsed: CGFloat = 124
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
        static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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

        nonisolated(unsafe) static let hoverInT = Timing(duration: 0.06, curve: hoverIn)
        nonisolated(unsafe) static let hoverOutT = Timing(duration: 0.085, curve: decel)
        nonisolated(unsafe) static let iconT = Timing(duration: 0.1, curve: decel)
        nonisolated(unsafe) static let focusT = Timing(duration: 0.06, curve: decel)
        nonisolated(unsafe) static let fadeInT = Timing(duration: 0.18, curve: easeOut)
        nonisolated(unsafe) static let fadeOutT = Timing(duration: 0.15, curve: easeOut)
        nonisolated(unsafe) static let colorT = Timing(duration: 0.2, curve: easeOut)     // a done title's color (css:169)
        nonisolated(unsafe) static let checkFillT = Timing(duration: 0.16, curve: easeOut)
        nonisolated(unsafe) static let pressT = Timing(duration: 0.08, curve: easeOut)    // the checkbox press (css:195)
        nonisolated(unsafe) static let chevronT = Timing(duration: 0.2, curve: easeOut)
        nonisolated(unsafe) static let flightT = Timing(duration: 0.16, curve: flight)
        nonisolated(unsafe) static let widthT = Timing(duration: 0.16, curve: easeOut)

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
