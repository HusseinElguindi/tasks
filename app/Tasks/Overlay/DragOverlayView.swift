import AppKit
import QuartzCore
import SwiftUI

/// The window-level layer that draws a dragged task's lifted copy (§14, css:239–250): a copy of the grabbed row on
/// `fill-lift`, radius 8, `shadow-lift`, with a count badge when several tasks travel. Over the sidebar it becomes a
/// compact 210pt tag at the pointer. It never takes the pointer. Coordinates are the window's, y down.
final class DragOverlayView: NSView {
    private let container = CALayer()
    private let ring = CALayer()
    private var copy: TaskRowView?
    private let badge = CALayer()
    private let badgeText = TextLayer()
    private var model: RowModel?
    private var palette = TK.Palette.dark
    private var fullWidth: CGFloat = 0
    private var compact = false
    /// Bumped by every new copy, so a settling copy's late hide can't hide the next one.
    private var generation = 0

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        container.isHidden = true
        container.actions = TaskRowView.noActions
        ring.actions = TaskRowView.noActions
        badge.actions = TaskRowView.noActions
        badgeText.actions = TaskRowView.noActions
        badge.addSublayer(badgeText)
        layer?.addSublayer(container)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
    }

    /// `minBadge`: the count shows from this many (a task drag's from 2; a heading's open tasks from 1).
    func beginTaskCopy(_ m: RowModel, palette: TK.Palette, frame: CGRect, count: Int, minBadge: Int = 2) {
        self.palette = palette
        model = m
        generation += 1
        fullWidth = frame.width
        compact = false
        let row = copy ?? TaskRowView(style: .lifted)
        copy = row
        if row.superview !== self { addSubview(row) }
        row.layer?.removeAllAnimations()
        row.layer?.setInstant { row.layer?.opacity = 1 }
        row.configure(m, palette: palette, width: frame.width, animated: false)
        row.frame = frame
        row.isHidden = false
        layer?.setScaleDeep(window?.backingScaleFactor ?? 2)
        container.setInstant {
            container.isHidden = true
            guard let rl = row.layer else { return }
            // shadow-lift: a 0.5pt ring plus 0 8 24 (css:58, 75).
            rl.masksToBounds = false
            rl.shadowColor = palette.shadowLift.cgColor
            rl.shadowOpacity = 1
            rl.shadowRadius = 12
            rl.shadowOffset = CGSize(width: 0, height: rl.isGeometryFlipped ? 8 : -8)
            rl.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: TK.M.rowRadius, cornerHeight: TK.M.rowRadius, transform: nil)
            ring.frame = CGRect(origin: .zero, size: frame.size).insetBy(dx: -0.5, dy: -0.5)
            ring.cornerRadius = TK.M.rowRadius + 0.5
            ring.borderWidth = 0.5
            ring.borderColor = palette.shadowLiftRing.cgColor
            if ring.superlayer !== rl { rl.insertSublayer(ring, at: 0) }
            // The count: an accent capsule 7pt past the copy's top-right corner.
            badge.isHidden = count < minBadge
            if count >= minBadge {
                let text = "\(count)"
                badgeText.set(text, font: TK.Font.label, color: palette.onAccent)
                let tw = TextLayer.width(text, font: TK.Font.label)
                let w = max(18, tw + 10)
                badge.frame = CGRect(x: frame.width + 7 - w, y: -7, width: w, height: 18)
                badge.cornerRadius = 9
                badge.backgroundColor = palette.accent.cgColor
                badgeText.alignmentMode = .center
                badgeText.place(x: 0, lineTop: 0, lineHeight: 18, width: w)
                if badge.superlayer !== rl { rl.addSublayer(badge) }
            }
        }
    }

    /// Follows the pointer (no animation); `compact` over the sidebar: 210 wide, no chips, width on 160 ms ease-out.
    func moveCopy(to origin: CGPoint, compact c: Bool) {
        guard let row = copy else { return }
        setCompact(c)
        row.layer?.removeAnimation(forKey: "fly")
        row.frame.origin = origin
    }

    private func setCompact(_ c: Bool) {
        guard let row = copy, var m = model else { return }
        if c != compact {
            compact = c
            let w = c ? TK.M.dragTagWidth : fullWidth
            if c { m.chips = [] }
            row.configure(m, palette: palette, width: w, animated: false)
            row.layer?.shadowPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: TK.M.row), cornerWidth: TK.M.rowRadius, cornerHeight: TK.M.rowRadius, transform: nil)
            ring.setInstant { ring.frame = CGRect(x: -0.5, y: -0.5, width: w + 1, height: TK.M.row + 1) }
            badge.setInstant { badge.frame.origin.x = w + 7 - badge.frame.width }
            let old = row.frame.width
            row.frame.size.width = w
            if !TK.CA.reduce, let rl = row.layer {
                let a = TK.CA.basic("bounds.size.width", TK.CA.widthT, from: old, to: w)
                rl.add(a, forKey: "width")
            }
        }
    }

    /// The drop or cancel: the copy flies to `origin` (160 ms, cubic-bezier(0.2, 0.8, 0.2, 1)); `shrink` also fades it
    /// out (a drop on a sidebar list). Otherwise a tag widens back into the row on the way (dc:2011).
    func flyCopy(to origin: CGPoint, shrink: Bool) {
        guard let row = copy, let rl = row.layer else { return }
        if !shrink { setCompact(false) }
        let from = rl.presentation()?.position ?? rl.position
        row.frame.origin = origin
        let to = rl.position
        if !TK.CA.reduce {
            rl.add(TK.CA.basic("position", TK.CA.flightT, from: NSValue(point: from), to: NSValue(point: to)), forKey: "fly")
        }
        if shrink {
            rl.animate("opacity", to: 0, TK.CA.Timing(duration: 0.16, curve: TK.CA.easeOut))
        }
    }

    #if DEBUG
    /// The copy as drawn: its presentation origin and opacity, while it's shown.
    var debugCopy: (origin: CGPoint, opacity: Float)? {
        guard let row = copy, !row.isHidden, let l = row.layer?.presentation() ?? row.layer else { return nil }
        return (l.frame.origin, l.opacity)
    }
    #endif

    func endCopy() {
        copy?.isHidden = true
        model = nil
    }

    /// The copy has landed on its row, which shows at full opacity under it in this same frame: the copy fades out over
    /// it (`fadeOut`, 150 ms), so the lift dissolves into the row. Hiding the copy while the row faded in left a frame or
    /// more with nothing there, a blink (v2 feedback 5).
    func settleCopy() {
        model = nil
        guard let row = copy, let rl = row.layer, !TK.CA.reduce else { copy?.isHidden = true; return }
        rl.animate("opacity", to: Float(0), TK.CA.fadeOutT)
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + TK.CA.fadeOutT.duration + 0.02) { [weak self] in
            guard let self, self.generation == g else { return }
            row.isHidden = true
        }
    }
}

struct DragOverlayRepresentable: NSViewRepresentable {
    let window: WindowState
    let palette: TK.Palette

    func makeNSView(context: Context) -> DragOverlayView {
        let v = DragOverlayView(frame: .zero)
        window.dragOverlay = v
        return v
    }

    func updateNSView(_ nsView: DragOverlayView, context: Context) {}
}
