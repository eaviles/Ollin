import Ollin

/// Additive blending — colors sum as *light* instead of laying over one another,
/// so where marks overlap the canvas brightens toward white rather than the
/// topmost shape winning. `blendMode(.add)` is what light-accumulation and
/// particle sketches reach for; it's also the first renderer step toward
/// depth-of-field "sandpainting" rendering, where a scene is drawn as a haze of
/// faint accumulated samples.
///
/// Here a drifting field of faint colored disks is drawn additively over a
/// near-black canvas. Nothing is opaque: each disk barely registers on its own,
/// and the picture is pure accumulation — dense regions glow white, sparse ones
/// hold a dim hue. Three slow orbits keep the clusters sweeping through each
/// other so the bright overlaps move.
///
/// Try changing `.add` to `.normal` to see the difference: the same disks then
/// just stack flatly, the last one drawn on top, with no glow.
@main
final class Blending_Example: Sketch {
    private struct Particle {
        var orbit: Int        // which of the three drifting clusters it belongs to
        var hue: Double
        var phase: Double     // angle offset within its orbit
        var radius: Double    // distance from the cluster center
        var size: Double      // disk radius
    }
    private var particles: [Particle] = []

    override func setup() {
        seed(7)
        for _ in 0 ..< 900 {
            particles.append(Particle(
                orbit: Int(random(3)),
                hue: random(),
                phase: random(.tau),
                radius: random(20, 260) * scale,
                size: random(8, 30) * scale))
        }
    }

    /// The moving center of cluster `i` — three lobes sweeping a slow figure.
    private func center(_ i: Int) -> Vector2 {
        let t = time * 0.25 + Double(i) * .tau / 3
        return Vector2(width * 0.5 + cos(t) * width * 0.22,
                       height * 0.5 + sin(t * 1.3) * height * 0.22)
    }

    override func draw() {
        background(Color(white: 0.02))
        blendMode(.add)          // sum colors as light — overlaps brighten
        noStroke()

        for p in particles {
            let a = p.phase + time * 0.4
            let c = center(p.orbit)
            let x = c.x + cos(a) * p.radius
            let y = c.y + sin(a) * p.radius
            // Faint fill: a lone disk is nearly invisible, so only overlap and
            // accumulation build the brightness.
            fill(Color(hue: p.hue, saturation: 0.75, brightness: 1, alpha: 0.09))
            drawCircle(x, y, p.size)
        }

        // A caption drawn back in normal blending, isolated so the additive mode
        // doesn't leak past the field.
        withState {
            blendMode(.normal)
            drawCaption("blendMode(.add) — colors accumulate as light")
        }
    }
}
