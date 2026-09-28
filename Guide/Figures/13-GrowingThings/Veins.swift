// figure: frame=200
//
// Guide figure (Chapter 13): space colonization, drawn by the reader. A
// blue-noise scatter of attraction points fills the canvas inside a margin,
// one root sits at the bottom edge, and the veins grow a step per frame
// toward the points they have not reached yet. Branch widths come from the
// pipe model, so the trunk carries every twig above it. The scatter is
// rolled after `seed(7)`, and the growth itself draws no random numbers, so
// the same veins grow every run.
import Ollin

final class Veins: Sketch {
    var veins: SpaceColonization?

    override func setup() {
        seed(7)
        let region = bounds.inset(by: .all(90))
        veins = SpaceColonization(attractors: poissonDisk(in: region, radius: 26),
                                  roots: [Vector2(width / 2, height - 70)],
                                  influenceRadius: 170, killRadius: 22, stepLength: 11)
    }

    override func draw() {
        guard let veins else { return }
        veins.step()

        background(Color(hex: 0x101318))

        // The attractors nothing has reached yet.
        noStroke()
        fill(Color(hex: 0x3A4A3A))
        drawCircles(veins.attractors, radius: 3)

        // The veins, thick where they carry many branches.
        let widths = veins.thicknesses(tipWidth: 1.4, exponent: 2.2)
        stroke(Color(hex: 0xBFE8C2))
        strokeCap(.round)
        for (i, node) in veins.nodes.enumerated() {
            guard let parent = node.parent else { continue }
            strokeWeight(widths[i])
            drawLine(veins.nodes[parent].position, node.position)
        }
    }
}
