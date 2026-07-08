// figure: frame=0
//
// Guide diagram (Appendix B): the convex hull. A scatter of points and the
// tightest band around them; the points on the band are its corners.
import Ollin

final class Hull: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        seed(6)
        var points: [Vector2] = []
        for _ in 0..<26 {
            points.append(Vector2(440 + randomGaussian() * 145, 255 + randomGaussian() * 82))
        }

        let hull = convexHull(of: points)

        noFill()
        stroke(accent)
        strokeWeight(3)
        drawPolygon(hull)

        noStroke()
        for p in points {
            let onHull = hull.contains { ($0 - p).length < 0.001 }
            fill(onHull ? accent : ink.withAlpha(0.55))
            drawCircle(center: p, radius: onHull ? 8 : 6)
        }

        fill(ink)
        textAlign(.center, .top)
        drawText("convexHull(of: points): the shape a rubber band around them would take",
                 width / 2, 500)
    }
}
