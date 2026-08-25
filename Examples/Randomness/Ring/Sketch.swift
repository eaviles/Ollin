import Ollin

/// `ring()` scatters points in an annulus: 1500 dots a frame between an inner and
/// outer radius around the canvas center. Radii and dot size are multiplied by
/// `scale` (`shortSide / 1000`), so the piece keeps its proportions at
/// any window size. Unseeded, so the ring shimmers as it re-rolls.
@main
final class Ring: Sketch {
    override func setup() {
        noStroke()
        fill(Color(white: 1, alpha: 0.5))
    }

    override func draw() {
        background(.black)
        let center = center
        let inner = 150 * scale
        let outer = 350 * scale
        for _ in 0..<1500 {
            drawCircle(center: center + ring(innerRadius: inner, outerRadius: outer),
                   radius: 2 * scale)
        }
    }
}
