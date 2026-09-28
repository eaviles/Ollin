// figure: frame=0 themed
//
// Guide diagram (Appendix B): a face's normal from two of its edges. A flat
// triangle lies on the floor, seen from above and in front. Its corners a, b,
// and c run counter-clockwise as you look down on it. The edges b - a and
// c - a leave the same corner, and their cross product stands straight up
// out of the face, drawn from the triangle's center. Drawn flat in 2D; the
// floor is a plain parallelogram.
import Ollin
import OllinDiagram

final class EdgesAndNormal: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    // The corners on screen: a front left, b front right, c at the back.
    let a = Vector2(250, 380)
    let b = Vector2(560, 395)
    let c = Vector2(470, 260)

    override func draw() {
        background(theme.paper)

        // A hint of the floor the triangle lies on.
        noStroke()
        fill(theme.ink(0.05))
        drawPolygon([Vector2(120, 430), Vector2(700, 430), Vector2(780, 230), Vector2(200, 230)])

        noStroke()
        fill(theme.ink(0.12))
        drawPolygon([a, b, c])
        stroke(theme.ink(0.6))
        strokeWeight(2)
        drawPolyline([a, b, c], closed: true)

        arrow(from: a, to: b, color: theme.ink, weight: 3.5)
        arrow(from: a, to: c, color: theme.ink, weight: 3.5)

        let middle = (a + b + c) / 3
        arrow(from: middle, to: middle + Vector2(0, -210), color: theme.accent, weight: 4.5)

        noStroke()
        textSize(18)
        fill(theme.ink)
        textAlign(.center, .middle)
        drawText("a", at: a + Vector2(-18, 12))
        drawText("b", at: b + Vector2(18, 12))
        drawText("c", at: c + Vector2(10, -20))

        textSize(16)
        textAlign(.center, .top)
        drawText("b − a", at: a.lerp(to: b, 0.5) + Vector2(0, 16))
        textAlign(.right, .middle)
        drawText("c − a", at: a.lerp(to: c, 0.5) + Vector2(-16, -10))

        fill(theme.accent)
        textAlign(.left, .middle)
        drawText("(b − a).cross(c − a)", at: middle + Vector2(16, -190))
        fill(theme.muted)
        textSize(14)
        drawText("the normal, straight out of the face", at: middle + Vector2(16, -166))

        diagramCaption("the cross of two edges points straight out of the face", at: 488, theme: theme)
    }

    func arrow(from start: Vector2, to end: Vector2, color: Color, weight: Double) {
        let direction = (end - start).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(start, end - direction * 12)
        noStroke()
        fill(color)
        drawPolygon([end, end - direction * 16 + direction.perpendicular * 6,
                     end - direction * 16 - direction.perpendicular * 6])
    }
}
