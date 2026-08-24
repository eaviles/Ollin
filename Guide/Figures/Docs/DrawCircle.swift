// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawCircle): a circle anchored by
// its center with the radius drawn as a ray (the size argument is the
// radius, not the diameter), and three radii sharing one center.
import Ollin

final class DrawCircle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // One circle: center dotted, radius drawn as a ray.
        let c = Vector2(225, 150)
        let r = 100.0
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawCircle(center: c, radius: r)

        let rim = c + Vector2(r, 0).rotated(by: -0.55)
        stroke(accent)
        strokeWeight(2)
        drawLine(c, rim)
        noStroke()
        fill(accent)
        drawCircle(center: c, radius: 3.5)
        textSize(16)
        textAlign(.left, .middle)
        drawText("radius", rim.x + 8, rim.y - 4)

        // Three radii, one center: the anchor never moves.
        let c2 = Vector2(650, 150)
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawCircle(center: c2, radius: 38)
        drawCircle(center: c2, radius: 72)
        drawCircle(center: c2, radius: 106)
        noStroke()
        fill(accent)
        drawCircle(center: c2, radius: 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("center + radius", 225, 272)
        drawText("same center, three radii", 650, 272)
    }
}
