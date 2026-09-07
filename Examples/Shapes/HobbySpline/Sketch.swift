import Ollin

/// `drawCurve(points, spline: .hobby)` threads a curve through points the
/// way a practiced hand does: every gap becomes a Bézier whose control points
/// are solved together, so the bend flows evenly from one point to the next.
/// The default spline decides each tangent from the two neighbors alone,
/// which flattens between far-apart points and swells between close ones.
///
/// Top, an open run: the straight polyline faint, the default curve in gray,
/// Hobby's fit in ink. Bottom, the same comparison on a closed loop, the fit
/// filled. Both runs space their points unevenly on purpose, since a close
/// pair beside a wide gap is where the two curves disagree most. The points
/// drift on slow orbits so the curves can be watched against each other;
/// `tension` pulls the fit toward the chords, and `curl` lets the open ends
/// bend (1) or run straight (0).
@main
final class HobbySpline: Sketch {
    @Param(0.75...3) var tension = 1.0
    @Param(0...2) var curl = 1.0

    override func draw() {
        background(Color(white: 0.96))

        let grid = Grid(in: bounds, columns: 1, rows: 2, padding: .all(60 * scale))
        for cell in grid.cells {
            let closed = cell.row == 1
            let frame = cell.frame.inset(by: .all(40 * scale))
            let points = closed ? loop(in: frame) : run(in: frame)

            withState {
                noFill()
                strokeCap(.round)
                strokeJoin(.round)

                stroke(Color(white: 0.82))
                strokeWeight(2 * scale)
                if closed { drawPolygon(points) } else { drawPolyline(points) }

                stroke(Color(white: 0.62))
                strokeWeight(4 * scale)
                drawCurve(points, closed: closed)

                if closed { fill(Color(hex: 0xE8C170, alpha: 0.55)) }
                stroke(Color(white: 0.1))
                strokeWeight(5 * scale)
                drawCurve(points, closed: closed, spline: .hobby(tension: tension, curl: curl))
            }

            noStroke()
            fill(Color(hex: 0xC1442E))
            for p in points { drawCircle(center: p, radius: 7 * scale) }
        }
    }

    /// Six points across the frame, rising and falling, with the third close
    /// on the heels of the second and a wide gap after it.
    private func run(in frame: Rectangle) -> [Vector2] {
        let spots = [Vector2(0.07, 0.26), Vector2(0.25, -0.26), Vector2(0.35, -0.2),
                     Vector2(0.62, 0.26), Vector2(0.8, -0.26), Vector2(0.93, 0.1)]
        return spots.enumerated().map { i, spot in
            let base = Vector2(frame.x + spot.x * frame.width, frame.center.y + spot.y * frame.height)
            return base + drift(i, in: frame)
        }
    }

    /// Seven points around an ellipse at uneven turns, two of them close.
    private func loop(in frame: Rectangle) -> [Vector2] {
        let turns = [0.0, 0.07, 0.27, 0.42, 0.5, 0.72, 0.86]
        return turns.enumerated().map { i, t in
            let a = t * .pi * 2 - .pi / 2
            let base = frame.center + Vector2(cos(a) * frame.width * 0.44, sin(a) * frame.height * 0.44)
            return base + drift(i, in: frame)
        }
    }

    /// A slow orbit of its own for each point.
    private func drift(_ i: Int, in frame: Rectangle) -> Vector2 {
        let phase = Double(i) * 1.7
        return Vector2(sin(time * 0.35 + phase) * frame.width * 0.02,
                       cos(time * 0.27 + phase * 1.3) * frame.height * 0.06)
    }
}
