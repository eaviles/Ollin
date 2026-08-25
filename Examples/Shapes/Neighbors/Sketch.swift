import Ollin

/// Four thousand points, and three questions asked of them every frame: which
/// one is nearest, which ones are within reach, and which ones are inside a box.
/// A `SpatialIndex` answers all three without looking at the other 3,999.
///
/// The faint web is the same idea at rest: every point joined to its own nearest
/// neighbor, four thousand searches done once in `setup()`.
///
/// ```sh
/// swift run Example-Shapes-Neighbors --export-loop /tmp/neighbors.gif
/// ```
///
/// Hold the mouse down to drive the probe yourself.
@main
final class Neighbors_Example: Sketch {
    private let period = 14.0
    override var loopDuration: Double? { period }

    private var points: [Vector2] = []
    private var index = SpatialIndex([])
    private var web: [(Vector2, Vector2)] = []

    override func setup() {
        seed(11)
        points = poissonDisk(radius: 14)
        index = SpatialIndex(points)

        // Every point joined to its nearest neighbor. Four thousand searches,
        // each reading a handful of cells instead of the whole scatter.
        for i in points.indices {
            // Two nearest, because the nearest point to a point is itself.
            let near = index.kNearest(2, to: points[i])
            if let other = near.first(where: { $0 != i }) {
                web.append((points[i], points[other]))
            }
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1117))

        let probe = mouseIsPressed
            ? mouse
            : center + Vector2(cos(time * 0.7) * 300, sin(time * 0.9) * 260)
        let reach = 92 + sin(time * 1.3) * 42

        // The resting answer: each point to its nearest neighbor.
        stroke(Color(hex: 0x232B3A))
        strokeWeight(1 * scale)
        for (a, b) in web { drawLine(a, b) }

        // A box sliding across, holding whatever is inside it.
        let boxWidth = 250.0, boxHeight = 170.0
        let slide = smoothstep(0, 1, pingPong(over: period))
        let box = Rectangle(x: 70 + slide * (width - boxWidth - 140),
                            y: height - boxHeight - 90,
                            width: boxWidth, height: boxHeight)
        noFill()
        stroke(Color(hex: 0x3E5C7E))
        strokeWeight(1.5 * scale)
        drawRect(corner: box.corner, width: box.width, height: box.height)
        let inBox = index.indices(in: box)
        noStroke()
        fill(Color(hex: 0x5B8FB9))
        for i in inBox { drawCircle(center: points[i], radius: 3.4 * scale) }

        // Everything within reach of the probe, each one drawn back to it.
        let within = index.neighbors(of: probe, within: reach)
        let reached = Set(within)
        stroke(Color(hex: 0xE8B44A).withAlpha(0.5))
        strokeWeight(1 * scale)
        for i in within { drawLine(probe, points[i]) }
        noStroke()
        fill(Color(hex: 0xE8B44A))
        for i in within { drawCircle(center: points[i], radius: 3.6 * scale) }

        // The reach itself.
        noFill()
        stroke(Color(hex: 0x4A5568))
        strokeWeight(1 * scale)
        drawCircle(center: probe, radius: reach)

        // The scatter that is left over, so the answers read against something.
        noStroke()
        fill(Color(hex: 0x39404E))
        for i in points.indices where !reached.contains(i) {
            drawCircle(center: points[i], radius: 2.2 * scale)
        }

        // The single nearest point, ringed last so the fan cannot hide it.
        if let nearest = index.nearest(to: probe) {
            noFill()
            stroke(Color(hex: 0xF2EFE8))
            strokeWeight(2 * scale)
            drawCircle(center: points[nearest], radius: 11 * scale)
        }
        noStroke()
        fill(Color(hex: 0xF2EFE8))
        drawCircle(center: probe, radius: 5 * scale)

        drawCaption("\(points.count) points: the nearest one, "
                    + "\(within.count) within reach, \(inBox.count) in the box")
    }
}
