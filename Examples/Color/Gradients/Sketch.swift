import Ollin

/// Gradient paint on every path the renderer has: a linear-gradient sky behind
/// a radial sun (analytic SDF shapes), a star and a wavy filled shape shading
/// across their tessellation, an along-path ramp running down a Bézier and a
/// polyline, and the same ramp swept once around a ring outline. The sun
/// drifts so the radial center and the reflections move with it.
@main
final class Gradients: Sketch {
    let sky = Ramp(stops: [(0.0, Color(hex: 0x0B1A40)),
                           (0.55, Color(hex: 0x3C6DD0)),
                           (1.0, Color(hex: 0xFFB36B))], in: .oklch)
    let heat = Ramp([Color(hex: 0xFFF3C4), Color(hex: 0xFF8A3D), Color(hex: 0xD03060)])

    override func setup() {
        noStroke()
    }

    override func draw() {
        // The sky: one linear gradient over a full-canvas rect.
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, height), sky))
        drawRect(0, 0, width, height)

        let sun = Vector2(width * 0.5 + sin(time * 0.4) * width * 0.18,
                          height * 0.42 + cos(time * 0.3) * height * 0.08)

        // The sun: a radial gradient fading to clear at the rim.
        fill(.radial(center: sun, radius: 260,
                     Ramp(stops: [(0.0, Color(hex: 0xFFF3C4)),
                                  (0.45, Color(hex: 0xFFB36B)),
                                  (1.0, Color(hex: 0xFFB36B, alpha: 0))])))
        drawCircle(sun.x, sun.y, 260)

        // A halo: the heat ramp swept once around a hollow ring outline.
        noFill()
        stroke(.alongPath(heat))
        strokeWeight(10)
        drawCircle(sun.x, sun.y, 320)

        // The tessellated path shades per vertex: a star shading across its own
        // extent, and a wavy drawShape lagoon under a linear ramp.
        let starCenter = Vector2(width * 0.18, height * 0.2)
        fill(.linear(from: starCenter - Vector2(70, 70), to: starCenter + Vector2(70, 70), heat))
        withState {
            translate(starCenter.x, starCenter.y)
            rotate(time * 0.2)
            drawStar(0, 0, 90, 42, points: 5)
        }
        fill(.linear(from: Vector2(0, height * 0.62), to: Vector2(0, height),
                     [Color(hex: 0x103A52), Color(hex: 0x2BB3A3)]))
        drawShape { p in
            p.move(to: Vector2(-40, height * 0.7))
            for i in 0...10 {
                let t = Double(i) / 10
                p.curve(to: Vector2(width * t, height * (0.7 + 0.04 * sin(t * 9 + time))))
            }
            p.line(to: Vector2(width + 40, height * 0.7))
            p.line(to: Vector2(width + 40, height + 40))
            p.line(to: Vector2(-40, height + 40))
            p.close()
        }

        // Along-path on real paths, over the water: a Bézier swinging under the
        // sun and a zig-zag polyline, both running the ramp start → end by arc
        // length.
        strokeWeight(16)
        stroke(.alongPath(heat))
        drawBezier(Vector2(width * 0.08, height * 0.82),
                   Vector2(sun.x, height * 0.55),
                   Vector2(width * 0.92, height * 0.82))
        let zigzag = (0...12).map { i -> Vector2 in
            let t = Double(i) / 12
            return Vector2(width * (0.08 + 0.84 * t),
                           height * 0.92 + (i.isMultiple(of: 2) ? -18 : 18))
        }
        drawPolyline(zigzag)
        noStroke()
    }
}
