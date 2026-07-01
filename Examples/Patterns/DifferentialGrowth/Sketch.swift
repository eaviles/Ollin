import Ollin

/// Differential growth: a closed ring of nodes that grows and folds into
/// brain-coral line-work. Every step each node is pulled toward its path-
/// neighbors (attraction) and their midpoint (alignment) and pushed away from
/// every nearby node (repulsion); when an edge stretches past a threshold a new
/// node splits it, so the boundary lengthens and buckles as it expands.
///
/// It's a stateful stepper held across frames, seeded once so the same seed
/// grows the same form. The evolving line is ordinary geometry (`growth.nodes` /
/// `growth.contour`), so it feeds stroking, filling, the shape booleans,
/// hatching, and SVG export for the pen plotter.
@main
final class DifferentialGrowthSketch: Sketch {
    private let growth = DifferentialGrowth.ring(
        center: Vector2(540, 540), radius: 70, count: 40, seed: 7,
        maxSegmentLength: 8, repulsionRadius: 16,
        attraction: 0.18, repulsion: 0.6, alignment: 0.25,
        jitter: 0.4, growthRate: 0.9, maxNodes: 4500,
        bounds: Rectangle(x: 40, y: 40, width: 1000, height: 1000))

    override func draw() {
        growth.step(4)

        background(Color(hex: 0x0F1012))
        noFill()
        strokeWeight(1.6 * scale)
        strokeCap(.round)
        strokeJoin(.round)

        // Tint the line by how far each node has drifted from the center, so the
        // folds read as depth without the geometry jumping.
        let center = Vector2(width / 2, height / 2)
        let nodes = growth.nodes
        for i in nodes.indices {
            let a = nodes[i], b = nodes[(i + 1) % nodes.count]
            let d = a.distance(to: center) / 500
            stroke(Color.mix(Color(hex: 0x6FD3C7), Color(hex: 0xF2B705), t: min(d, 1)))
            drawLine(a, b)
        }
    }
}
