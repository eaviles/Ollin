import Ollin

/// An HSB color wheel: hue runs around the circle, saturation grows from the
/// center out, and the whole wheel turns slowly. Each ring is a fan of pie
/// wedges drawn outermost-first, so the inner rings overpaint the outer ones.
/// The backdrop is a hex literal in the integer form, `Color(hex: 0x14171C)`.
@main
final class HSBWheel: Sketch {
    let rings = 8
    let sectors = 36

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x14171C))
        translate(width / 2, height / 2)
        rotate(time * 0.1)

        let outer = min(width, height) * 0.42
        for ring in (0..<rings).reversed() {
            let radius = outer * Double(ring + 1) / Double(rings)
            let saturation = Double(ring + 1) / Double(rings)
            for sector in 0..<sectors {
                let start = Double.tau * Double(sector) / Double(sectors)
                let stop = Double.tau * Double(sector + 1) / Double(sectors)
                fill(Color(hue: Double(sector) / Double(sectors),
                           saturation: saturation,
                           brightness: 1))
                drawArc(0, 0, radius, radius, start: start, stop: stop, mode: .pie)
            }
        }
    }
}
