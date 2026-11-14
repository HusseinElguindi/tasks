import AppKit
import SwiftUI

/// What a pane's wrapping text is told about the pane's width (§4): the width the window's layout is taking the pane
/// to (`PaneFrames`). `placed(_:)` gives it to every pane through the environment, so whatever wraps inside one (the
/// list's large title and notes, the detail pane's title and notes, a deleted list shown in the detail pane) can wrap
/// once as the pane starts to slide instead of on every frame of it (`WrapSettle`).
struct PaneSettle: Equatable {
    /// The pane's width once the layout has settled.
    var width: CGFloat
    /// The pane is closing: its text keeps the wrap it has while it slides off.
    var leaving = false
}

private struct PaneSettleKey: EnvironmentKey {
    static let defaultValue: PaneSettle? = nil
}

extension EnvironmentValues {
    /// Nil outside a pane: the text follows its view's width live.
    var paneSettle: PaneSettle? {
        get { self[PaneSettleKey.self] }
        set { self[PaneSettleKey.self] = newValue }
    }
}

/// One view's wrapping text while its pane's width animates (the detail pane or the sidebar opening or closing, a zoom,
/// a divider springing back): the text re-wraps once, at the width it's going to, as the slide starts, in both
/// directions, and what's under it glides. It never re-wraps on every frame of the slide (the user, 2026-11-08: "the
/// line wrapping is a bit distracting when it animates for the whole duration, and it's choppy when more lines are
/// needed") and never waits for the slide to end (the user, 2026-11-08: "there's definitely a delay in the wrap, which
/// i dont quite like, it should be smooth"). The same for the detail pane (the user, 2026-11-14: "we need to do the
/// same on detail").
///
/// The view owns one, tells it each `PaneSettle` it's given (`pane`), asks it where to wrap (`to`), and tells it each
/// width its own frame takes (`arrived`). A change that isn't animated (a divider dragged, the window resized) ends
/// the settle and the text follows live, as before.
@MainActor
final class WrapSettle {
    /// From the width the text wrapped at, to the width it's going to. Nil at rest.
    private(set) var span: (from: CGFloat, to: CGFloat)?
    /// The pane's width as last given.
    private var pane: CGFloat?
    /// The pane is leaving: the wrap is kept until the timer, whatever widths the view takes.
    private var held = false
    private var timer: Timer?
    /// The settle is over (the view arrived, the slide stopped short, or a live change took over): wrap at the view's
    /// own width again.
    var onEnd: () -> Void = {}

    /// The width to wrap at while the pane animates; nil at rest (the view's own width).
    var to: CGFloat? { span?.to }

    /// The pane's settle as the view's update gave it, with whether that update is animated. `wrap` is the width the
    /// view's text is wrapped at now. The view's width is the pane's less what's around it, which doesn't change, so
    /// it's going to `wrap` plus what the pane gains. True when a settle began: the view re-wraps now, at `to`.
    func pane(_ p: PaneSettle?, animated: Bool, wrap: CGFloat, inWindow: Bool) -> Bool {
        guard let p else { return false }
        if p.leaving {
            if animated, inWindow, !held {
                held = true
                begin(wrap, wrap)
            }
            return false
        }
        guard p.width != pane || held else { return false }
        let old = pane
        pane = p.width
        held = false
        guard animated, inWindow, let old, abs(p.width - old) > 0.5 else {
            end()
            return false
        }
        begin(wrap, wrap + p.width - old)
        return true
    }

    private func begin(_ from: CGFloat, _ to: CGFloat) {
        span = (from, to)
        // A safety: the slide ends with the view at `to`; should it stop short, the text settles anyway.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    /// The view's frame took `width`: at the width it was going to, the settle is over. True when that ended it.
    /// Exactly there, not near it: the last half point of a spring takes a few frames, and following the view through
    /// them could move a word down a line and back.
    @discardableResult
    func arrived(_ width: CGFloat) -> Bool {
        guard let s = span, !held, abs(width - s.to) <= 0.01 else { return false }
        end()
        return true
    }

    func end() {
        timer?.invalidate()
        timer = nil
        held = false
        guard span != nil else { return }
        span = nil
        onEnd()
    }

    /// How far along the slide a view `width` wide is: 0 at the width it began at, 1 where it's going. What's under
    /// the text moves by this, so it glides on the pane's own motion.
    func progress(at width: CGFloat) -> CGFloat {
        guard let s = span, abs(s.to - s.from) > 0.5 else { return 1 }
        return min(1, max(0, (width - s.from) / (s.to - s.from)))
    }
}
