import SwiftUI

/// The iPhone's row grid and type, scaled up from the Mac's 13/16 on a 32pt pitch (tasks-v2.css) to 17/22 on 48.
enum Metric {
    static let rowHeight: CGFloat = 48
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

/// Pane's three curves. Reduce Motion turns them all off.
enum Motion {
    static var natural: Animation { .smooth(duration: 0.3) }
    static var layout: Animation { .smooth(duration: 0.25) }
    static var snappy: Animation { .snappy(duration: 0.2) }
}

@MainActor
func animate(_ animation: Animation = Motion.natural, _ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled { body(); return }
    withAnimation(animation, body)
}
