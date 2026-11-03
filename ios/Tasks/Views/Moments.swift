import SwiftUI

// Today all done (IX §13; COLOR.md §4; the Mac's `AllDoneSunLayer` and `Sunrise`, Moments.swift:97–170): a sun in
// `spark` and "All done for today" above the Completed group, under a faint sunrise at the top of the screen. The
// checkbox's spark is the Checkbox's own (`CheckMoment`, Components.swift).

/// The Mac's sun glyph (`Draw.swift`'s `.sun`: eight rays around an r 2.6 circle, in a 16-unit box, stroked 1.5),
/// without its centre, which `AllDoneSun` fills and keeps still.
private struct SunRays: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var p = Path()
        let rays: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (8, 1.9, 8, 3.2), (8, 12.8, 8, 14.1), (1.9, 8, 3.2, 8), (12.8, 8, 14.1, 8),
            (3.7, 3.7, 4.6, 4.6), (11.4, 11.4, 12.3, 12.3), (3.7, 12.3, 4.6, 11.4), (11.4, 4.6, 12.3, 3.7),
        ]
        for (x0, y0, x1, y1) in rays {
            p.move(to: pt(x0, y0))
            p.addLine(to: pt(x1, y1))
        }
        p.addEllipse(in: CGRect(x: r.minX + 5.4 * k, y: r.minY + 5.4 * k, width: 5.2 * k, height: 5.2 * k))
        return p
    }
}

/// The all-done block: the sun at 40pt (the Mac's 30 × 1.3), stroked 3.75, its centre filled, 28 under the header;
/// "All done for today" in 17pt medium ink 8 under it; the Completed group 24 under that. As it appears (`rise`: the
/// last row settled while Today was open, or Today opened all done), its rays and ring turn in from 0.5× and −40° as
/// they fade in, over 900 ms on the Mac's curve; scrolled back into view it just shows. Under Reduce Motion it's shown
/// at rest.
struct AllDoneSun: View {
    @Binding var rise: Bool
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turns = 0

    private static let size: CGFloat = 40

    var body: some View {
        VStack(spacing: 8) {
            KeyframeAnimator(initialValue: rise && !reduceMotion ? SunMoment.start : SunMoment(), trigger: turns) { m in
                let s = Self.size, k = s / 16
                ZStack {
                    SunRays()
                        .stroke(p.spark, style: StrokeStyle(lineWidth: 1.5 * k, lineCap: .round, lineJoin: .round))
                        .scaleEffect(m.scale)
                        .rotationEffect(.degrees(m.angle))
                        .opacity(m.alpha)
                    // The centre: the glyph's r 2.6 circle and its stroke, filled; it doesn't move.
                    Circle().fill(p.spark).frame(width: 2 * (2.6 + 0.75) * k, height: 2 * (2.6 + 0.75) * k)
                }
                .frame(width: s, height: s)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(reduceMotion ? 1 : SunMoment.start.scale)
                    LinearKeyframe(1, duration: 0.9, timingCurve: Motion.flight)
                }
                KeyframeTrack(\.angle) {
                    MoveKeyframe(reduceMotion ? 0 : SunMoment.start.angle)
                    LinearKeyframe(0, duration: 0.9, timingCurve: Motion.flight)
                }
                KeyframeTrack(\.alpha) {
                    MoveKeyframe(reduceMotion ? 1 : 0)
                    LinearKeyframe(1, duration: 0.9, timingCurve: Motion.flight)
                }
            }
            .accessibilityHidden(true)
            Text("All done for today").font(.system(size: 17, weight: .medium)).foregroundStyle(p.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
        // It turns in once per appearance that `rise` marks, and not when it scrolls back into view.
        .onAppear { turnIn() }
        .onChange(of: rise) { turnIn() }
    }

    private func turnIn() {
        guard rise else { return }
        rise = false
        if !reduceMotion { turns += 1 }
    }
}

struct SunMoment {
    var scale: CGFloat = 1
    var angle: Double = 0
    var alpha: Double = 1
    static let start = SunMoment(scale: 0.5, angle: -40, alpha: 0)
}

/// The sunrise while Today is all done (the Mac's `Sunrise`, `.lp:has(.eg-alldone)::before`): `spark` at 13% (light
/// 9%) fading to clear by 70% of an ellipse 120% of the screen's width and 338 tall (the Mac's 260 × 1.3), centred on
/// the screen's top edge, behind the status bar, the bar and every row. It fades in over 900 ms ease-out, goes at once
/// when a task arrives, and stays put as the rows scroll. Under Reduce Motion it's shown at once.
struct Sunrise: View {
    let shown: Bool
    @Environment(\.palette) private var p

    var body: some View {
        let a = p.isDark ? 0.13 : 0.09
        let g = Gradient(stops: [.init(color: p.spark.opacity(a), location: 0), .init(color: p.spark.opacity(0), location: 0.7)])
        Canvas { ctx, size in
            ctx.translateBy(x: size.width / 2, y: 0)
            ctx.scaleBy(x: 1.2 * size.width, y: size.height)
            ctx.fill(Path(CGRect(x: -1, y: 0, width: 2, height: 1)),
                     with: .radialGradient(g, center: .zero, startRadius: 0, endRadius: 1))
        }
        .frame(height: 338)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(shown ? 1 : 0)
        .motion(shown ? .easeOut(duration: 0.9) : nil, value: shown)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
