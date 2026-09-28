// figure: frame=0 themed
//
// Guide diagram (Appendix B): inversion in a circle. The accent circle is
// the mirror, radius r. A point P at distance d from the center lands at
// r squared over d along the same ray, so a point inside goes outside and
// the rim stays where it is. A small square inside, near the rim, comes out
// as a larger shape with curved sides, every point of it inverted.
import Ollin
import OllinDiagram

final class CircleInversion: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let center = Vector2(330, 255)
    let radius = 110.0

    /// Inversion in the mirror circle: same direction, distance r² / d.
    func inverted(_ p: Vector2) -> Vector2 {
        let offset = p - center
        return center + offset * (radius * radius / offset.lengthSquared)
    }

    override func draw() {
        background(theme.paper)

        // The mirror.
        noFill()
        stroke(theme.accent)
        strokeWeight(3)
        drawCircle(center: center, radius: radius)
        noStroke()
        fill(theme.ink)
        drawCircle(center: center, radius: 4)

        pointPair()
        squarePair()
        notes()

        diagramCaption("a point at distance d lands at r² / d on the same ray", at: 488, theme: theme)
    }

    func pointPair() {
        let p = center + Vector2(angle: -.pi / 6, length: 62)
        let image = inverted(p)

        stroke(theme.ink(0.35))
        strokeWeight(1.5)
        strokeDash([6, 5])
        drawLine(center, image + (image - center).normalized * 30)
        noStrokeDash()

        noStroke()
        fill(theme.ink)
        drawCircle(center: p, radius: 6)
        fill(theme.accent)
        drawCircle(center: image, radius: 6)

        textSize(15)
        fill(theme.ink)
        textAlign(.right, .bottom)
        drawText("P, at distance d", p.x - 8, p.y - 8)
        fill(theme.accent)
        textAlign(.left, .bottom)
        drawText("its image, at r² / d", image.x + 10, image.y - 6)
    }

    func squarePair() {
        let squareCenter = center + Vector2(angle: .pi * 0.8, length: 74)
        let half = 16.0
        let corners = [Vector2(-half, -half), Vector2(half, -half),
                       Vector2(half, half), Vector2(-half, half)].map { squareCenter + $0 }

        // Every edge sampled finely, so the inverted outline shows its curves.
        var outline: [Vector2] = []
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            for k in 0..<40 {
                outline.append(a.lerp(to: b, Double(k) / 40))
            }
        }

        noStroke()
        fill(theme.ink(0.75))
        drawPolygon(corners)
        fill(theme.accent(0.35))
        drawPolygon(outline.map(inverted))
        noFill()
        stroke(theme.accent)
        strokeWeight(2)
        drawPolyline(outline.map(inverted), closed: true)
    }

    func notes() {
        noStroke()
        fill(theme.ink)
        textSize(16)
        textAlign(.left, .top)
        let x = 620.0
        drawText("the rim stays where it is", x, 230)
        drawText("inside goes outside,", x, 270)
        drawText("and outside comes in", x, 292)
        drawText("near the center goes far", x, 332)
        drawText("straight edges come out curved", x, 372)
        fill(theme.muted)
        textSize(14)
        drawText("r is the mirror's radius", x, 420)
    }
}
