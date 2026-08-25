import Ollin

/// A kinetic mandala of nested hollow shapes. Each ring is a single `hollow`
/// shape: the `fill` paints a constant-width band and the `stroke` frames both
/// of its edges, so every ring is a filled, two-color band drawn in one call.
/// That framed band is the new trick — before `hollow`, a filled outline of a
/// *non-circular* shape meant tessellated thick strokes (no clean edges) or
/// stacking two shapes to fake the hole, and neither composites cleanly when
/// layered like this. The rings counter-rotate at speeds set by their depth, so
/// their straight edges and star points slide past each other into a moiré.
@main
final class Mandala: Sketch {
    let rings = 15

    override func setup() {
        stroke(Color(white: 0.93))
    }

    override func draw() {
        background(Color(white: 0.05))
        strokeWeight(1.5 * scale)
        let cx = width / 2, cy = height / 2
        let maxR = shortSide * 0.46
        let dr = maxR / Double(rings)

        // Outer rings last, so the layers composite cleanly back-to-front.
        for i in 1...rings {
            let t = Double(i) / Double(rings)
            let radius = dr * Double(i)
            // Band breathes; rings nearly meet but leave a thin dark gap.
            let band = dr * (0.5 + 0.18 * sin(time * 1.1 + t * 6))
            // Alternate spin direction by ring, faster toward the rim.
            let dir = (i % 2 == 0) ? 1.0 : -1.0
            let angle = dir * time * (0.12 + t * 0.45)

            hollow(band)
            fill(Colormap.turbo.color(at: (t + time * 0.04).truncatingRemainder(dividingBy: 1)))

            withState {
                translate(cx, cy)
                rotate(angle)
                if i % 2 == 0 {
                    drawStar(0, 0, radius, radius * 0.62, points: 6 + i / 2)
                } else {
                    drawNgon(0, 0, radius, sides: 6)
                }
            }
        }
    }
}
