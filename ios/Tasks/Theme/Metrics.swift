import SwiftUI

/// The iPhone's row grid and type, scaled up from the Mac's 13/16 on a 32pt pitch (tasks-v2.css) to 17/22 on 48.
enum Metric {
    static let rowHeight: CGFloat = 48
    /// A row with a detail line (ROW-DENSITY.md §6.4): 6 + the title's 22 + 2 + line 2's 20 + 6.
    static let twoLineHeight: CGFloat = 56
    static let twoLinePad: CGFloat = 6
    static let lineGap: CGFloat = 2
    static let detailLine: CGFloat = 20
    /// The list mark's tile (§22): the sidebar's small tile, 16×13.
    static let markTileW: CGFloat = 16
    /// A list column wider than this (iPad) keeps the one-line row (the user, 2026-11-08: "yea sure").
    static let wideColumn: CGFloat = 600
    static let rowInset: CGFloat = 10          // screen edge to the row's pressed fill
    static let rowPad: CGFloat = 10            // fill edge to the checkbox / tile
    static let rowRadius: CGFloat = 12
    static let check: CGFloat = 22
    static let titleGap: CGFloat = 12
    static let tileW: CGFloat = 26
    static let tileH: CGFloat = 21
    static let fab: CGFloat = 56
    static let barHeight: CGFloat = 52
    /// Space under the last row so nothing hides behind the floating bar and the + button.
    static let bottomClearance: CGFloat = 104
    /// A row's title keeps this much (all of a shorter one) before the When, or a list's name after it, gives way
    /// (the Mac's 120 × 1.3, `TaskRowView.titleKeep`).
    static let titleKeep: CGFloat = 156
    /// A list's name after a task's title keeps this much before it's cut (the Mac's 72 × 1.3, `whereKeep`), and goes
    /// rather than show less than this much (the Mac's 32 × 1.3, `whereMin`).
    static let listNameKeep: CGFloat = 94
    static let listNameMin: CGFloat = 42
    /// How far a cut-off name or title fades out at its end, instead of an ellipsis (`fadeTruncation`), the Mac's × 1.3:
    /// a row's title, a list's name on a row, a group label, a deleted list's name (the Mac's 24, `TK.M.titleFade`)…
    static let titleFade: CGFloat = 31
    /// …and a name on Home and in iPad's sidebar (the Mac's sidebar, 16, `SB.titleFade`), which ends 39 short of the
    /// row's edge when there's a count (the Mac's 30, `titleFadeEnd`) and 13 short when not (10, `titleFadeEndBare`).
    static let nameFade: CGFloat = 21
    static let nameEnd: CGFloat = 39
    static let nameEndBare: CGFloat = 13
}

/// Text styles whose default (Large) sizes are the design's: 28 / 20 / 17 / 15 / 13 / 12. They scale with Dynamic Type,
/// and rows, which have a minimum height rather than a fixed one, grow with them.
enum Typo {
    static let largeTitle = Font.title.weight(.semibold)                 // 28
    static let detailTitle = Font.title3.weight(.semibold)               // 20
    static let row = Font.body                                           // 17
    static let rowMedium = Font.body.weight(.medium)
    static let heading = Font.subheadline.weight(.semibold)              // 15
    static let notes = Font.subheadline                                  // 15
    static let detailNotes = Font.callout                                // 16
    static let label = Font.footnote.weight(.semibold)                   // 13
    static let quiet = Font.footnote                                     // 13
    static let chip = Font.caption.weight(.medium)                       // 12
    static let chipLarge = Font.subheadline.weight(.medium)              // 15
    static let meta = Font.caption                                       // 12
    static let body = Font.subheadline                                   // 15
    static let mono = Font.system(.footnote, design: .monospaced).weight(.bold)
}

/// Pane's three curves, and the moments' (COLOR.md §4). Reduce Motion turns them all off.
enum Motion {
    static var natural: Animation { .smooth(duration: 0.3) }
    static var layout: Animation { .smooth(duration: 0.25) }
    static var snappy: Animation { .snappy(duration: 0.2) }
    /// The spark's ring and rays and the all-done sun's turn: `cubic-bezier(0.2, 0.8, 0.2, 1)` (the Mac's `TK.CA.flight`).
    static let flight = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.2, y: 1))
}

// Reduce Motion (IX §3): every duration is 0, and the state still changes, in one frame. Every animation in ios/ goes
// through one of these: `animate` for a change, `motion(_:value:)` for a view's `.animation`, `motionTransition` for an
// insert or removal; a keyframe animation reads `accessibilityReduceMotion` and runs flat. The system's own (sheets,
// push and pop, menus, swipe actions, the keyboard) follow the setting themselves.

@MainActor
func animate(_ animation: Animation = Motion.natural, _ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled { body(); return }
    withAnimation(animation, body)
}

extension View {
    /// `.animation(_:value:)`, off under Reduce Motion (it follows the setting live).
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionGate(animation: animation, value: value))
    }

    /// `.transition(_:)`, the identity under Reduce Motion.
    func motionTransition(_ t: AnyTransition) -> some View { modifier(TransitionGate(transition: t)) }
}

private struct MotionGate<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View { content.animation(reduce ? nil : animation, value: value) }
}

private struct TransitionGate: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View { content.transition(reduce ? .identity : transition) }
}
