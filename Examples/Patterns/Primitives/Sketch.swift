import Ollin

/// Every drawing primitive Ollin ships, one per cell — a living reference sheet
/// for the whole `draw*` vocabulary. Each shape is filled from a perceptual
/// colormap and turns slowly in place, so the sheet doubles as a check that every
/// primitive composites and anti-aliases under the transform stack. Most are
/// single instanced SDF quads; `drawLine`/`drawBezier`/`drawPolyline` are stroked,
/// and `drawPolygon`/`drawShape` go through the tessellated triangle path (the
/// last one a square with a circular hole, via the concave/holed `Shape`).
@main
final class Primitives: Sketch {
    let columns = 5
    let count = 32
    let names = [
        "Point", "Line", "Circle", "Ellipse", "Arc",
        "Triangle", "Rect", "Ngon", "Star", "Rhombus",
        "Trapezoid", "Parallelogram", "Cross", "Vesica", "Moon",
        "Egg", "Heart", "Cut Disk", "Ring", "Uneven Capsule",
        "Horseshoe", "Parabola", "Rounded X", "Blobby Cross", "Tunnel",
        "Stairs", "Cool S", "Triangle 3-pt", "Bézier", "Polyline",
        "Polygon", "Shape",
    ]

    override func setup() {
        noStroke()
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(Color(white: 0.1))
        let rows = (count + columns - 1) / columns
        let cellW = width / Double(columns)
        // A top/bottom margin so the last row's label clears the canvas edge.
        let vMargin = height * 0.04
        let cellH = (height - vMargin * 2) / Double(rows)
        let s = min(cellW, cellH) * 0.34

        for index in 0..<count {
            let row = index / columns
            let col = index % columns
            // Center a short final row under the full ones above it.
            let itemsInRow = min(columns, count - row * columns)
            let x = cellW * (Double(col) + 0.5) + Double(columns - itemsInRow) * cellW / 2
            let y = vMargin + cellH * (Double(row) + 0.5)
            // Start a little into the ramp so the first cells clear turbo's darkest end.
            let t = 0.08 + 0.92 * Double(index) / Double(count - 1)
            let color = Colormap.turbo.color(at: t)

            fill(color)
            withState {
                translate(Vector2(x, y))
                rotate(time * 0.25)
                drawCell(index, s: s, color: color)
            }

            // Name under each cell, in screen space (not turned with the shape).
            fill(.white); textAlign(.center, .top); textSize(14 * scale)
            drawText(names[index], x, y + cellH * 0.40)
        }
    }

    /// One primitive per index, sized off `s` and centered on the origin (the cell
    /// was already translated there). State set here — point size, the stroke the
    /// line/path cells need — is scoped by the caller's `withState`, so it reverts.
    private func drawCell(_ index: Int, s: Double, color: Color) {
        switch index {
        case 0:
            pointSize(s * 1.5)
            drawPoint(0, 0)
        case 1:
            stroke(color); strokeWeight(s * 0.22)
            drawLine(Vector2(-s, s * 0.6), Vector2(s, -s * 0.6))
        case 2:
            drawCircle(0, 0, s)
        case 3:
            drawEllipse(0, 0, s, s * 0.62)
        case 4:
            drawArc(0, 0, s, s, start: 0, stop: .tau * 0.75, mode: .pie)
        case 5:
            drawTriangle(0, 0, s)
        case 6:
            drawRect(center: Vector2(0, 0), width: s * 1.7, height: s * 1.3, cornerRadius: s * 0.25)
        case 7:
            drawNgon(0, 0, s, sides: 6)
        case 8:
            drawStar(0, 0, s, s * 0.45, points: 5)
        case 9:
            drawRhombus(0, 0, s * 1.3, s * 1.9)
        case 10:
            drawTrapezoid(0, 0, s * 0.9, s * 1.7, s * 1.4)
        case 11:
            drawParallelogram(0, 0, s * 1.6, s * 1.2, s * 0.5)
        case 12:
            drawCross(0, 0, s * 1.9, s * 0.6, cornerRadius: s * 0.12)
        case 13:
            drawVesica(0, 0, s * 0.95, s * 1.8)
        case 14:
            drawMoon(0, 0, s, s * 0.92, s * 0.62)
        case 15:
            drawEgg(0, 0, s * 0.85, s * 0.42)
        case 16:
            drawHeart(0, 0, s * 1.7)
        case 17:
            drawCutDisk(0, 0, s, -s * 0.15)
        case 18:
            drawRing(0, 0, s * 0.55, s)
        case 19:
            drawUnevenCapsule(Vector2(-s * 0.7, s * 0.7), Vector2(s * 0.7, -s * 0.7), s * 0.5, s * 0.18)
        case 20:
            drawHorseshoe(0, 0, s * 0.62, s * 0.42, gap: 1.4)
        case 21:
            drawParabola(0, 0, s * 1.7, s * 1.7)
        case 22:
            drawRoundedX(0, 0, s * 1.9, s * 0.42)
        case 23:
            drawBlobbyCross(0, 0, s)
        case 24:
            drawTunnel(0, 0, s * 1.5, s * 1.7)
        case 25:
            drawStairs(0, 0, s * 0.45, s * 0.45, steps: 4)
        case 26:
            drawCoolS(0, 0, s * 1.9)
        case 27:
            // A scalene triangle from three free corners (distinct from the
            // equilateral cell 5).
            drawTriangle(Vector2(-s, s * 0.7), Vector2(s * 0.95, s * 0.25),
                         Vector2(s * 0.1, -s))
        case 28:
            // A quadratic Bézier arc: one analytic SDF stroke, round caps.
            stroke(color); strokeWeight(s * 0.2)
            drawBezier(Vector2(-s, s * 0.6), Vector2(0, -s * 1.7), Vector2(s, s * 0.6))
        case 29:
            stroke(color); strokeWeight(s * 0.18)
            drawPolyline([Vector2(-s, -s * 0.5), Vector2(-s * 0.33, s * 0.5),
                          Vector2(s * 0.33, -s * 0.5), Vector2(s, s * 0.5)])
        case 30:
            drawPolygon([Vector2(0, -s), Vector2(s * 0.95, -s * 0.1),
                         Vector2(s * 0.58, s), Vector2(-s * 0.58, s),
                         Vector2(-s * 0.95, -s * 0.1)])
        default:
            // A square with a circular hole — the concave/holed path (libtess2).
            let half = s * 0.95
            let outer = [Vector2(-half, -half), Vector2(half, -half),
                         Vector2(half, half), Vector2(-half, half)]
            var hole: [Vector2] = []
            let steps = 48
            for i in 0..<steps {
                let a = Double.tau * Double(i) / Double(steps)
                hole.append(Vector2(cos(a) * s * 0.5, sin(a) * s * 0.5))
            }
            drawShape(Shape(outer: outer, holes: [hole]))
        }
    }
}
