// figure: frame=760
//
// Guide figure (Chapter 10): differential growth. A small ring of nodes,
// stepped every frame: each node is pulled toward its path neighbors, pushed
// away from everyone nearby, and stretched edges split. The line buckles and
// folds like coral because that's the only way a growing line can stay
// uncrowded.
import Ollin

final class Coral: Sketch {
    let growth = DifferentialGrowth.ring(
        center: Vector2(540, 540), radius: 80, count: 40, seed: 7,
        maxSegmentLength: 8, repulsionRadius: 16, growthRate: 0.9,
        bounds: Rectangle(x: 70, y: 70, width: 940, height: 940))

    override func draw() {
        growth.step(4)

        background(Color(hex: 0x101318))
        noFill()
        stroke(Color(hex: 0x9AD9CE))
        strokeWeight(2.2)
        strokeJoin(.round)
        drawPolygon(growth.nodes)
    }
}
