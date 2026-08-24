// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawOrientedBox): a thick bar
// placed by its two centerline endpoints, square-ended, its thickness
// marked across it, and three of them joining three points into a truss.
import Ollin

final class DrawOrientedBox: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // One bar between two endpoints, thickness across the centerline.
        let a = Vector2(96, 226)
        let b = Vector2(382, 106)
        let thickness = 46.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawOrientedBox(a, b, thickness: thickness)

        noStroke()
        fill(accent)
        drawCircle(center: a, radius: 4)
        drawCircle(center: b, radius: 4)
        textSize(16)
        textAlign(.center, .middle)
        drawText("a", a.x - 16, a.y + 8)
        drawText("b", b.x + 16, b.y - 8)

        // The thickness, marked straight across the bar partway along.
        let d = b - a
        let length = (d.x * d.x + d.y * d.y).squareRoot()
        let across = Vector2(-d.y / length, d.x / length)
        let mid = a + d * 0.68
        stroke(accent)
        strokeWeight(2)
        drawLine(mid + across * (thickness / 2), mid - across * (thickness / 2))
        noStroke()
        fill(accent)
        textAlign(.left, .middle)
        drawText("thickness", mid.x + 18, mid.y + 16)

        // Three calls joining three points into a truss.
        let p1 = Vector2(538, 246)
        let p2 = Vector2(822, 246)
        let p3 = Vector2(680, 92)
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawOrientedBox(p1, p2, thickness: 20)
        drawOrientedBox(p2, p3, thickness: 20)
        drawOrientedBox(p3, p1, thickness: 20)
        noStroke()
        fill(accent)
        drawCircle(center: p1, radius: 4)
        drawCircle(center: p2, radius: 4)
        drawCircle(center: p3, radius: 4)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("a bar between two points, square ends", 240, 282)
        drawText("a truss: three calls", 680, 282)
    }
}
