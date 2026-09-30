// figure: frame=0 themed
//
// Guide diagram: the canvas coordinate system. The origin sits at the top-left
// corner, x grows to the right, y grows downward, and a point is named by how
// far it is from that corner.
import Ollin
import OllinDiagram

final class CoordinateSystem: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        // The default canvas, a 1080 square scaled to fit the figure, as a
        // framed rectangle whose top-left corner is the origin.
        let originX = 250.0, originY = 80.0
        let side = 380.0
        let scale = side / 1080
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(originX, originY, side, side)

        noStroke()
        fill(faint)
        textSize(26)
        textAlign(.center, .middle)
        drawText("the canvas", originX + side / 2, originY + side * 0.6)
        textSize(21)
        textAlign(.right, .top)
        drawText("(1080, 1080)", originX + side, originY + side + 10)
        textSize(26)

        // Axes along the canvas edges, arrowheads pointing the way each grows.
        stroke(ink)
        strokeWeight(3)
        drawLine(originX, originY, originX + side + 60, originY)
        drawLine(originX, originY, originX, originY + side + 20)
        noStroke()
        fill(ink)
        arrowhead(x: originX + side + 60, y: originY, dx: 1, dy: 0)
        arrowhead(x: originX, y: originY + side + 20, dx: 0, dy: 1)
        textAlign(.left, .middle)
        drawText("x", originX + side + 84, originY)
        textAlign(.right, .middle)
        drawText("y", originX - 18, originY + side + 24)

        // The origin.
        fill(ink)
        drawCircle(originX, originY, 7)
        textAlign(.right, .bottom)
        drawText("(0, 0)", originX - 14, originY - 12)

        // One point, with guides back to each axis showing how it's named. Its
        // coordinates are canvas pixels, so it lands at the figure's scale, in
        // the upper-left quarter, where the chapter says (380, 240) sits.
        let pointX = 380 * scale, pointY = 240 * scale
        stroke(faint)
        strokeWeight(2)
        drawLine(originX + pointX, originY, originX + pointX, originY + pointY)
        drawLine(originX, originY + pointY, originX + pointX, originY + pointY)
        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText("380", originX + pointX, originY - 10)
        textAlign(.right, .middle)
        drawText("240", originX - 14, originY + pointY)
        fill(accent)
        drawCircle(originX + pointX, originY + pointY, 9)
        textAlign(.left, .middle)
        drawText("(380, 240)", originX + pointX + 22, originY + pointY)
    }

    /// A small solid triangle pointing along (dx, dy), tip at (x, y).
    func arrowhead(x: Double, y: Double, dx: Double, dy: Double) {
        let tip = Vector2(x + dx * 16, y + dy * 16)
        let left = Vector2(x - dy * 8, y + dx * 8)
        let right = Vector2(x + dy * 8, y - dx * 8)
        drawTriangle(tip, left, right)
    }
}
