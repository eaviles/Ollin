import Ollin

/// A guilloche rosette, the engine-turned ornament of watch faces and
/// banknotes: concentric wavy rings, each turned a hair against its neighbor,
/// weaving into a braided moiré. Two stacked cams shape every ring, a coarse
/// wave and a fine ripple riding it. The twist creeps with time, so the braid
/// slowly crawls around the face while the rings themselves hold still.
@main
final class Guilloche: Sketch {
    override func draw() {
        background(Color(hex: 0x0F2A24))   // deep enamel green

        let reach = Double(shortSide)
        let rosettes = [
            Rosette(bumps: 8, amplitude: 0.022 * reach, phase: time * 0.1),
            Rosette(bumps: 40, amplitude: 0.004 * reach),
        ]
        let rings = guilloche(rings: 42,
                              innerRadius: 0.07 * reach,
                              outerRadius: 0.44 * reach,
                              rosettes: rosettes,
                              twist: .pi / 90 + sin(time * 0.23) * 0.012)

        noFill()
        stroke(Color(hex: 0xEFE6CF, alpha: 0.85))   // ivory line-work
        strokeWeight(1.3 * scale)
        withState {
            translate(center)
            for ring in rings {
                drawPolyline(ring.points, closed: true)
            }
        }
    }
}
