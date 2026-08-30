import Ollin

/// Space colonization: veins grow live toward a blue-noise scatter of
/// attraction points, from a single root at the bottom edge. Every step each
/// remaining attractor pulls on its closest vein tip, tips grow toward the
/// average of their pulls, and reached attractors are consumed, so the
/// structure branches into every open pocket of the canvas. Branch thickness
/// comes from the pipe model: tips stay hairline, the trunk carries them all.
@main
final class Venation: Sketch {
    private var growth: SpaceColonization?

    override func setup() {
        seed(7)
        let region = bounds.inset(by: .all(90 * scale))
        growth = SpaceColonization(
            attractors: poissonDisk(in: region, radius: 26 * scale),
            roots: [Vector2(width / 2, height - 70 * scale)],
            influenceRadius: 170 * scale, killRadius: 22 * scale,
            stepLength: 11 * scale)
    }

    override func draw() {
        guard let growth else { return }
        growth.step()

        background(Color(hex: 0x101410))
        strokeCap(.round)

        // Remaining attractors as faint seeds the veins are still reaching for.
        noStroke()
        fill(Color(hex: 0x3A4A3A))
        drawCircles(growth.attractors, radius: 3 * scale)

        // The vein network, thick where it carries many branches.
        let widths = growth.thicknesses(tipWidth: 1.4 * scale, exponent: 2.2)
        stroke(Color(hex: 0xBFE8C2))
        for (i, node) in growth.nodes.enumerated() {
            guard let parent = node.parent else { continue }
            strokeWeight(widths[i])
            drawLine(growth.nodes[parent].position, node.position)
        }
    }
}
