import AppKit
import QuartzCore

// D · Moments (design/COLOR.md §4; color.css's D block): grey at rest, colour with an event, gone within a second.
// Completing a task sparks; Today all done shows a sun under a faint sunrise. None of it under Reduce Motion: the box
// fills at once, and the all-done sun and sunrise stand still.

extension TK.CA {
    /// The spark's ring (460 ms) and rays (560 ms), and the all-done sun's rays (900 ms): `cubic-bezier(0.2, 0.8, 0.2, 1)`.
    static let sparkRingT = Timing(duration: 0.46, curve: flight)
    static let sparkRaysT = Timing(duration: 0.56, curve: flight)
    /// The box filling from the spark to the accent (`tk-sp-fill`, 520 ms ease-out).
    static let sparkFillT = Timing(duration: 0.52, curve: easeOut)
    /// The row's and the title's warm flash, settling (`tk-sp-row`, `tk-sp-title`, 700 ms ease-out).
    static let sparkFlashT = Timing(duration: 0.7, curve: easeOut)
    static let sunT = Timing(duration: 0.9, curve: flight)
    /// The sunrise fading in (`tk-fade-in`, 900 ms ease-out).
    static let sunriseT = Timing(duration: 0.9, curve: easeOut)
}

/// The spark that leaves a checkbox as it's checked (`.check .spark`): a ring and eight rays in `spark`, centred on
/// the box, 44pt across (the box is 16). At rest it's hidden.
final class SparkLayer: CALayer {
    private let ring = CAShapeLayer()
    private let rays = CAShapeLayer()

    override init() {
        super.init()
        bounds = CGRect(x: -22, y: -22, width: 44, height: 44)
        actions = TaskRowView.noActions
        ring.path = CGPath(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18), transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 1.5
        // The rays from 11 to 17 out, every 45°, round-capped (`.sp-rays`).
        let p = CGMutablePath()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4, (c, s) = (cos(a), sin(a))
            let (r0, r1): (CGFloat, CGFloat) = i % 2 == 0 ? (11, 17) : (11.03, 15.98)
            p.move(to: CGPoint(x: c * r0, y: s * r0))
            p.addLine(to: CGPoint(x: c * r1, y: s * r1))
        }
        rays.path = p
        rays.fillColor = nil
        rays.lineWidth = 1.75
        rays.lineCap = .round
        for l in [ring, rays] {
            l.actions = TaskRowView.noActions
            l.opacity = 0
            addSublayer(l)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// Runs the spark once (`tk-sp-ring`, `tk-sp-rays`); the layers end clear, as the keyframes do.
    func fire(_ color: NSColor) {
        guard !TK.CA.reduce else { return }
        setInstant {
            ring.strokeColor = color.cgColor
            rays.strokeColor = color.cgColor
        }
        let r = TK.CA.sparkRingT, y = TK.CA.sparkRaysT
        let ringAnims: [CAAnimation] = [
            TK.CA.basic("transform.scale", r, from: 0.9, to: 2.1),
            TK.CA.basic("opacity", r, from: 0.95, to: 0),
            TK.CA.basic("lineWidth", r, from: 2.5, to: 0.4),
        ]
        ring.add(group(ringAnims, r.duration), forKey: "spark")
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.22, 1]
        fade.timingFunctions = [y.curve, y.curve]
        fade.duration = y.duration
        let turn = CABasicAnimation(keyPath: "transform")
        turn.fromValue = CATransform3DRotate(CATransform3DMakeScale(0.55, 0.55, 1), -8 * .pi / 180, 0, 0, 1)
        turn.toValue = CATransform3DMakeScale(1.2, 1.2, 1)
        turn.timingFunction = y.curve
        turn.duration = y.duration
        rays.add(group([fade, turn], y.duration), forKey: "spark")
    }

    func stop() {
        ring.removeAnimation(forKey: "spark")
        rays.removeAnimation(forKey: "spark")
    }

    private func group(_ a: [CAAnimation], _ d: CFTimeInterval) -> CAAnimationGroup {
        let g = CAAnimationGroup()
        g.animations = a
        g.duration = d
        return g
    }
}

/// Today all done (§4, `.eg-alldone` under D): the check-circle becomes a 30pt sun in `spark`, its centre filled, its
/// rays turning in once (900 ms) when it appears.
final class AllDoneSunLayer: CALayer {
    static let size: CGFloat = 30
    private let disc = CAShapeLayer()
    private let rays = GlyphLayer(.sun, size: AllDoneSunLayer.size)

    override init() {
        super.init()
        let s = Self.size, k = s / 16
        bounds = CGRect(x: 0, y: 0, width: s, height: s)
        actions = TaskRowView.noActions
        // The centre: the glyph's r 2.6 circle, filled, with its 1.5 stroke (`.eg-s circle { fill: currentColor }`).
        let r = (2.6 + 0.75) * k
        disc.path = CGPath(ellipseIn: CGRect(x: s / 2 - r, y: s / 2 - r, width: 2 * r, height: 2 * r), transform: nil)
        rays.position = CGPoint(x: s / 2, y: s / 2)
        for l in [disc, rays] as [CALayer] {
            l.actions = TaskRowView.noActions
            addSublayer(l)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func set(color: NSColor, animated: Bool) {
        setInstant {
            disc.fillColor = color.cgColor
            rays.color = color
        }
        guard animated, !TK.CA.reduce else { rays.removeAllAnimations(); return }
        // `tk-sp-sun`: from 0.5 and −40°, clear, to rest.
        let t = TK.CA.sunT
        let turn = CABasicAnimation(keyPath: "transform")
        turn.fromValue = CATransform3DRotate(CATransform3DMakeScale(0.5, 0.5, 1), -40 * .pi / 180, 0, 0, 1)
        turn.toValue = CATransform3DIdentity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let g = CAAnimationGroup()
        g.animations = [turn, fade]
        g.duration = t.duration
        g.timingFunction = t.curve
        rays.add(g, forKey: "sun")
    }
}

/// The sunrise at the top of the list pane while Today is all done: `spark` at 13% (light 9%) fading out by 70% of an
/// ellipse 120% of the pane's width and 260pt tall, centred on the top edge (`.lp:has(.eg-alldone)::before`).
final class SunriseLayer: CAGradientLayer {
    static let height: CGFloat = 260

    override init() {
        super.init()
        type = .radial
        actions = TaskRowView.noActions
        cornerRadius = TK.M.paneRadius - 1
        maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        locations = [0, 0.7]
        opacity = 0
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// `flipped`: the layer's y runs down (its view is flipped), so the top edge is y 0 in unit space.
    func set(shown: Bool, palette: TK.Palette, flipped: Bool, animated: Bool) {
        let a = palette.isDark ? 0.13 : 0.09
        setInstant {
            colors = [palette.spark.withAlphaComponent(a).cgColor, palette.spark.withAlphaComponent(0).cgColor]
            startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
            endPoint = CGPoint(x: 0.5 + 1.2, y: flipped ? 1 : 0)
        }
        let to: Float = shown ? 1 : 0
        guard to != opacity else { return }
        if shown, animated {
            animate("opacity", to: to, TK.CA.sunriseT)
        } else {
            setInstant { opacity = to }
        }
    }
}
