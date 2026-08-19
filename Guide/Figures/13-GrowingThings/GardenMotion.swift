// figure: gif duration=5 fps=16 width=420
//
// Guide figure (Chapter 13): the garden growing. The tree claims its crown,
// the lichen creeps, and the plants stand ready (they grew by rewriting
// before the first frame). Sped up so five seconds covers the whole growth.
import Ollin

final class GardenMotion: Sketch {
    private var tree: SpaceColonization?
    private var plants: [[Contour]] = []
    private var tufts: [DiffusionLimitedAggregation] = []
    private let groundY = 880.0

    override func setup() {
        seed(5)

        let crown = Vector2(540, 430)
        let attractors = poissonDisk(in: Rectangle(x: 190, y: 180, width: 700, height: 520),
                                     radius: 24).filter { p in
            let dx = (p.x - crown.x) / 350, dy = (p.y - crown.y) / 260
            return dx * dx + dy * dy < 1
        }
        tree = SpaceColonization(attractors: attractors, roots: [Vector2(540, groundY)],
                                 influenceRadius: 280, killRadius: 20, stepLength: 10)

        for (i, x) in [130.0, 260, 400, 700, 830, 950].enumerated() {
            let height = 150 + Double((i * 37) % 90)
            let patch = Rectangle(x: x - 70, y: groundY - height, width: 140, height: height)
            let preset: LSystem = i % 3 == 2 ? .bush : .randomPlant
            plants.append(lSystem(preset, iterations: 4, in: patch, padding: 6))
        }

        for x in [220.0, 620, 890] {
            tufts.append(DiffusionLimitedAggregation(
                seeds: [Vector2(x, groundY)], particleRadius: 2.2,
                maxParticles: 280, seed: UInt64(x)))
        }
    }

    override func draw() {
        guard let tree else { return }
        tree.step(4)
        for tuft in tufts { tuft.step(6) }

        background(Color(hex: 0x0F130D))

        noStroke()
        fill(Color(hex: 0x1A2014))
        drawRect(Rectangle(x: 0, y: groundY, width: width, height: height - groundY))

        for (i, tuft) in tufts.enumerated() {
            fill(Color(hex: i % 2 == 0 ? 0x66805E : 0x4E6B57).withAlpha(0.85))
            drawCircles(tuft.positions, radius: 2.2)
        }

        noFill()
        strokeCap(.round)
        strokeWeight(2.4)
        for (i, plant) in plants.enumerated() {
            stroke(Color(hex: i % 2 == 0 ? 0x7FB069 : 0x5C8D5A))
            for contour in plant { drawPolyline(contour.points) }
        }

        let widths = tree.thicknesses(leafWidth: 1.1, exponent: 2.4)
        stroke(Color(hex: 0xD9C9A0))
        for (i, node) in tree.nodes.enumerated() {
            guard let parent = node.parent else { continue }
            strokeWeight(widths[i])
            drawLine(tree.nodes[parent].position, node.position)
        }
    }
}
