// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawCurve): one point list, drawn
// twice. Open, the spline is a stroked line through every dotted point;
// closed, it loops back into a fillable ring.
import Ollin

final class DrawCurve: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    func loop(cx: Double, cy: Double) -> [Vector2] {
        [Vector2(cx - 104, cy + 20), Vector2(cx - 48, cy - 78),
         Vector2(cx + 42, cy - 56), Vector2(cx + 102, cy + 6),
         Vector2(cx + 34, cy + 86), Vector2(cx - 52, cy + 62)]
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let open = loop(cx: 236, cy: 142)
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawCurve(open)
        dots(open)
        label("open: a stroked line through the points", 236, 260)

        let closed = loop(cx: 632, cy: 142)
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawCurve(closed, closed: true)
        dots(closed)
        label("closed: true, a fillable loop", 632, 260)
    }

    func dots(_ points: [Vector2]) {
        noStroke()
        fill(accent)
        for p in points { drawCircle(center: p, radius: 4) }
    }

    func label(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(text, x, y)
    }
}
