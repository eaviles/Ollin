import Ollin

/// The picture dragging its own history around: a **self-warp** `SimField` measures
/// how its picture moves, frame to frame, and carries everything it has already shown
/// along that motion. Whatever visibly moves smears; whatever holds still stays
/// sharp. Three gradient-cored orbs orbit at their own paces and comb the field into
/// ribbons; press and drag to throw a fourth around and paint with its wake.
/// `strength` is the dial to play first: below 1 the orbs outrun their history and
/// stretch it into these ribbons, at 1 the carried ghost hides exactly under each
/// orb, above 1 it overshoots into glitchy echoes racing ahead, and negative drags
/// the wake the other way. `refresh` sets how quickly the fresh picture wins back.
@main
final class SelfWarp_Example: Sketch {
    @Param(-3 ... 3, icon: "wind", group: "Warp") var strength = 0.55
    @Param(0.02 ... 0.5, icon: "arrow.clockwise", group: "Warp") var refresh = 0.05
    @Param(0 ... 0.95, icon: "water.waves", group: "Warp") var smoothing = 0.65

    private var warp: SimField!

    override func setup() {
        warp = makeSimField(.selfWarp())
    }

    /// A soft-cored orb: a radial gradient from a hot center through its color to
    /// clear, so the picture has the smooth luminance ramps the motion fit reads best.
    private func orb(at center: Vector2, radius: Double, _ color: Color) {
        fill(Gradient.radial(center: center, radius: radius,
                             Ramp([.white, color, color.withAlpha(0)])))
        drawCircle(center: center, radius: radius)
    }

    override func draw() {
        // The knobs retune the sim live; the field's accumulated history carries on.
        warp.sim = .selfWarp(amount: strength, refresh: refresh, smoothing: smoothing)

        withField(warp) {
            background(Color(red: 0.03, green: 0.03, blue: 0.06))
            noStroke()
            let c = bounds.center
            // Three orbits, incommensurate paces, so the weave never repeats.
            orb(at: c + Vector2(cos(time * 1.15), sin(time * 1.15)) * 310,
                radius: 84, Color(red: 1.0, green: 0.45, blue: 0.15))
            orb(at: c + Vector2(cos(-time * 0.74 + 2.1), sin(-time * 0.74 + 2.1)) * 215,
                radius: 66, Color(red: 0.2, green: 0.75, blue: 1.0))
            orb(at: c + Vector2(cos(time * 1.7 + 4.4), sin(time * 1.35 + 4.4)) * 130,
                radius: 48, Color(red: 0.95, green: 0.3, blue: 0.85))
            if mouseIsPressed {
                orb(at: mouse, radius: 56, Color(red: 0.55, green: 1.0, blue: 0.4))
            }
        }

        // The warped field covers the canvas, so no main background is needed (and one
        // here would wipe the seed drawn above before the field composites).
        drawImage(warp.image, 0, 0)
        drawCaption("SelfWarp · the picture smeared along its own motion · drag to paint")
    }
}
