import Ollin

/// Three answers to "what shape are these points?". One scatter (a ring of
/// dots plus an offshore island), three outlines: the convex hull bridges
/// everything into one taut band; the concave hull (`concaveHull`) breathes
/// between that band and a tight wrap that dips into the gulf, always one
/// simple polygon; and the alpha shape (`alphaShape`) underneath resolves
/// what neither hull can say, two islands and a hole in the ring.
///
/// ```sh
/// swift run Example-Shapes-Hulls --export-loop /tmp/hulls.gif
/// ```
///
/// Pure geometry on the way out: hulls and islands feed `drawPolygon` and
/// `drawShape`, so `--export-svg` writes plottable outlines.
@main
final class Hulls_Example: Sketch {
    private let period = 12.0
    override var loopDuration: Double? { period }

    private var scatter: [Vector2] = []

    override func setup() {
        seed(9)
        // A jittered polar grid makes an evenly-dotted ring (so the alpha
        // probe finds its hole), and a small cluster moors offshore.
        let hub = Vector2(470, 570)
        for band in 0 ..< 5 {
            let radius = 230.0 + Double(band) * 33
            let count = Int(radius * .tau / 34)
            for i in 0 ..< count {
                let angle = Double(i) / Double(count) * .tau + random(-0.04, 0.04)
                let r = radius + random(-13, 13)
                scatter.append(hub + Vector2(cos(angle), sin(angle)) * r)
            }
        }
        let island = Vector2(870, 240)
        for _ in 0 ..< 42 {
            scatter.append(island + ring(innerRadius: 0, outerRadius: 78))
        }
    }

    override func draw() {
        background(Color(hex: 0x101318))

        // The alpha shape: the scatter's true footprint, islands and hole.
        noStroke()
        fill(Color(hex: 0x1B2436))
        for islandShape in alphaShape(of: scatter, alpha: 52) {
            drawShape(islandShape)
        }

        // The convex hull: the loosest answer, faint.
        noFill()
        stroke(Color(hex: 0x3A4458))
        strokeWeight(1.5 * scale)
        drawPolygon(convexHull(of: scatter))

        // The concave hull: one simple polygon breathing from loose to tight.
        // Capped short of 1, where the chi-shape goes full labyrinth and the
        // three-outline story drowns in zigzag.
        let concavity = smoothstep(0, 1, pingPong(over: period)) * 0.72
        stroke(Color(hex: 0xE8B44A))
        strokeWeight(3 * scale)
        drawPolygon(concaveHull(of: scatter, concavity: concavity))

        // The scatter itself.
        noStroke()
        fill(Color(hex: 0x8B97AB))
        drawCircles(scatter, radius: 3.2 * scale)

        drawCaption("convex, concave, and alpha: three outlines of one scatter")
    }
}
