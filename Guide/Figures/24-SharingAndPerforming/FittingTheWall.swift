// figure: frame=1
//
// Guide diagram (Chapter 24): what a projector does to a picture, and what
// corner-pinning does about it. On the left the picture as it lands, on the
// right the same picture with its four corners put where they belong. Below,
// the reason two projectors on one wall each fade out across the band they
// share: the two fades add up to one coat.
import Ollin

final class FittingTheWall: Sketch {
    override var canvasSize: CanvasSize { .size(880, 508) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let beam = Color(hex: 0x6B9EC7)
    let other = Color(hex: 0x8A6A96)

    override func draw() {
        background(paper)
        panel(x: 56, title: "as it lands",
              corners: [Vector2(0.14, 0.10), Vector2(0.98, -0.04),
                        Vector2(0.90, 0.94), Vector2(0.02, 0.82)],
              handles: false,
              note: "the wall is square, the projector is not")
        panel(x: 468, title: "corner-pinned",
              corners: [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
              handles: true,
              note: "drag the four corners, once, per display")
        fades(y: 352)
    }

    // MARK: One panel: a wall, and a picture landing on it

    /// The wall as a plain frame, the picture as the shape it actually makes on
    /// it, and a grid through the picture so the shape is readable.
    func panel(x: Double, title: String, corners: [Vector2], handles: Bool, note: String) {
        let wall = Rectangle(x: x, y: 66, width: 356, height: 200)

        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        drawText(title, wall.x, wall.y - 14)

        noFill()
        stroke(Color(white: 0.72))
        strokeWeight(2)
        drawRect(corner: wall.corner, width: wall.width, height: wall.height)

        let quad = corners.map { onWall($0, wall) }
        noStroke()
        fill(Color(hex: 0x6B9EC7, alpha: 0.16))
        drawPolygon(quad)

        // A grid through the picture, mapped the way the picture itself is: a
        // straight line across the canvas stays straight, so each one is drawn
        // from its two ends.
        stroke(Color(hex: 0x6B9EC7, alpha: 0.85))
        strokeWeight(1.2)
        noFill()
        for step in 1..<5 {
            let t = Double(step) / 5
            drawLine(project(t, 0, quad), project(t, 1, quad))
            drawLine(project(0, t, quad), project(1, t, quad))
        }
        strokeWeight(2.2)
        drawPolyline(quad, closed: true)

        if handles {
            noStroke()
            for corner in quad {
                fill(paper)
                drawCircle(center: corner, radius: 7)
                noFill()
                stroke(accent)
                strokeWeight(2.2)
                drawCircle(center: corner, radius: 7)
                noStroke()
            }
        }

        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.left, .top)
        drawText(note, wall.x, wall.y + wall.height + 14)
    }

    func onWall(_ point: Vector2, _ wall: Rectangle) -> Vector2 {
        Vector2(wall.x + point.x * wall.width, wall.y + point.y * wall.height)
    }

    /// A point inside the picture, worked out the way the map itself works it
    /// out: the four corners of a square sent to four points, with the divide at
    /// the end that lets two parallel edges meet.
    func project(_ u: Double, _ v: Double, _ quad: [Vector2]) -> Vector2 {
        let p0 = quad[0], p1 = quad[1], p2 = quad[2], p3 = quad[3]
        let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y
        var a = p1.x - p0.x, b = p2.x - p1.x
        var d = p1.y - p0.y, e = p2.y - p1.y
        var g = 0.0, h = 0.0
        let denominator = dx1 * dy2 - dy1 * dx2
        if abs(dx3) > 1e-12 || abs(dy3) > 1e-12, abs(denominator) > 1e-12 {
            g = (dx3 * dy2 - dy3 * dx2) / denominator
            h = (dx1 * dy3 - dy1 * dx3) / denominator
            a = p1.x - p0.x + g * p1.x
            b = p3.x - p0.x + h * p3.x
            d = p1.y - p0.y + g * p1.y
            e = p3.y - p0.y + h * p3.y
        }
        let w = g * u + h * v + 1
        return Vector2((a * u + b * v + p0.x) / w, (d * u + e * v + p0.y) / w)
    }

    // MARK: Two machines sharing a band

    /// Each machine's brightness across the wall, and the two of them added up.
    func fades(y: Double) {
        let left = 56.0, right = 824.0, height = 76.0
        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        drawText("two machines, one wall", left, y - 14)

        // The band they share, in the middle.
        let bandFrom = 0.38, bandTo = 0.62
        noStroke()
        fill(Color(white: 0.88))
        drawRect(left + (right - left) * bandFrom, y,
                 (right - left) * (bandTo - bandFrom), height)

        func across(_ t: Double) -> Double { left + (right - left) * t }
        func level(_ share: Double) -> Double { y + height - height * share }

        // Each machine as the light it puts on the wall: full brightness over
        // its own stretch, and the published fade across the band. The one on
        // the right is the mirror of the one on the left.
        for (index, colour) in [beam, other].enumerated() {
            let from = index == 0 ? 0.06 : bandFrom
            let to = index == 0 ? bandTo : 0.94
            var edge: [Vector2] = []
            for step in 0...160 {
                let t = from + (to - from) * Double(step) / 160
                let along = min(max((t - bandFrom) / (bandTo - bandFrom), 0), 1)
                edge.append(Vector2(across(t), level(fade(index == 0 ? 1 - along : along))))
            }
            // One filled outline rather than a column apiece: the region under
            // an S is not convex, so it goes through the path builder, which
            // triangulates it, rather than through `drawPolygon`.
            noStroke()
            fill(colour.withAlpha(0.30))
            drawShape { path in
                path.move(to: Vector2(across(from), level(0)))
                for point in edge { path.line(to: point) }
                path.line(to: Vector2(across(to), level(0)))
                path.close()
            }
            noFill()
            stroke(colour)
            strokeWeight(2.4)
            drawPolyline(edge)
        }

        // The two added together: flat, which is the whole point.
        stroke(accent)
        strokeWeight(2.4)
        drawLine(Vector2(across(0.06), level(1)), Vector2(across(0.94), level(1)))

        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("each one fades across the band they share", (across(bandFrom) + across(bandTo)) / 2,
                 y + height + 12)
        fill(accent)
        textAlign(.right, .bottom)
        drawText("added up: one coat", across(0.94), level(1) - 9)
    }

    /// The published blending function at its usual shape: half at the middle of
    /// the band, and flat where it meets full brightness at either end.
    func fade(_ x: Double) -> Double {
        x < 0.5 ? 0.5 * pow(2 * x, 2) : 1 - 0.5 * pow(2 * (1 - x), 2)
    }
}
