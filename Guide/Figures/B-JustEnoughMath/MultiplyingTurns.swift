// figure: frame=0 themed
//
// Guide diagram (Appendix B): multiplying complex numbers. Both panels draw
// the plane the way mathematicians do, with the imaginary axis pointing up.
// Left, z at length 1.2 and 20 degrees and w at length 1.5 and 50 degrees;
// their product is the accent arrow at length 1.8 and 70 degrees, the
// lengths multiplied and the angles added. Right, multiplying by i is a
// quarter turn: 1 becomes i, and i times i is -1, half a turn.
import Ollin
import OllinDiagram

final class MultiplyingTurns: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let unit = 115.0

    override func draw() {
        background(theme.paper)
        productPanel(origin: Vector2(150, 380))
        quarterTurnPanel(origin: Vector2(650, 290))
        diagramCaption("multiplying multiplies the lengths and adds the angles", at: 488, theme: theme)
    }

    /// A point of the plane, `re` across and `im` up, on screen.
    func screen(_ origin: Vector2, _ re: Double, _ im: Double) -> Vector2 {
        origin + Vector2(re, -im) * unit
    }

    func polar(_ origin: Vector2, length: Double, degrees: Double) -> Vector2 {
        let a = Double.degrees(degrees)
        return screen(origin, length * cos(a), length * sin(a))
    }

    func axes(_ origin: Vector2, left: Double, right: Double, down: Double, up: Double) {
        stroke(theme.ink(0.35))
        strokeWeight(1.5)
        drawLine(screen(origin, -left, 0), screen(origin, right, 0))
        drawLine(screen(origin, 0, -down), screen(origin, 0, up))
        noStroke()
        fill(theme.muted)
        textSize(13)
        textAlign(.left, .top)
        let end = screen(origin, right, 0)
        drawText("real", end.x - 26, end.y + 6)
        let top = screen(origin, 0, up)
        drawText("imaginary", top.x + 8, top.y)
    }

    func productPanel(origin: Vector2) {
        axes(origin, left: 0.3, right: 2.4, down: 0.3, up: 2.0)

        let z = polar(origin, length: 1.2, degrees: 20)
        let w = polar(origin, length: 1.5, degrees: 50)
        let product = polar(origin, length: 1.8, degrees: 70)

        arrow(from: origin, to: z, color: theme.ink, weight: 3)
        arrow(from: origin, to: w, color: theme.ink, weight: 3)
        arrow(from: origin, to: product, color: theme.accent, weight: 4)

        noStroke()
        textSize(16)
        fill(theme.ink)
        textAlign(.left, .middle)
        drawText("z: 1.2 at 20°", z.x + 12, z.y)
        drawText("w: 1.5 at 50°", w.x + 12, w.y)
        fill(theme.accent)
        drawText("z × w: 1.8 at 70°", product.x + 12, product.y - 6)
    }

    func quarterTurnPanel(origin: Vector2) {
        axes(origin, left: 1.5, right: 1.5, down: 0.4, up: 1.5)

        let one = screen(origin, 1, 0)
        let i = screen(origin, 0, 1)
        let minusOne = screen(origin, -1, 0)

        // The two quarter turns, drawn as arcs just inside the unit circle.
        noFill()
        stroke(theme.accent)
        strokeWeight(2)
        drawArc(origin.x, origin.y, unit * 0.55, unit * 0.55, start: -.pi / 2 + 0.08, stop: -0.08, mode: .open)
        drawArc(origin.x, origin.y, unit * 0.55, unit * 0.55, start: -.pi + 0.08, stop: -.pi / 2 - 0.08, mode: .open)

        arrow(from: origin, to: one, color: theme.ink, weight: 3)
        arrow(from: origin, to: i, color: theme.ink, weight: 3)
        arrow(from: origin, to: minusOne, color: theme.ink, weight: 3)

        noStroke()
        textSize(16)
        fill(theme.ink)
        textAlign(.center, .top)
        drawText("1", one.x, one.y + 8)
        drawText("−1 = i × i", minusOne.x, minusOne.y + 8)
        textAlign(.left, .middle)
        drawText("i = 1 × i", i.x + 12, i.y)
        fill(theme.accent)
        textAlign(.center, .top)
        drawText("each × i is a quarter turn", origin.x, origin.y + 0.55 * unit + 24)
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
