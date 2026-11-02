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
