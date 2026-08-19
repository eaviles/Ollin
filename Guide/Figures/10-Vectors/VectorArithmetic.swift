// figure: frame=0
//
// Guide diagram (Chapter 10): arrow arithmetic in four panels. Adding walks
// one arrow then the other; subtracting gives the arrow from here to there;
// a scalar stretches, shrinks, or flips; normalizing keeps the heading and
// sets the length to exactly one.
import Ollin

final class VectorArithmetic: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        addPanel(Rectangle(x: 50, y: 45, width: 370, height: 200))
        subtractPanel(Rectangle(x: 470, y: 45, width: 370, height: 200))
        scalePanel(Rectangle(x: 50, y: 300, width: 370, height: 200))
        normalizePanel(Rectangle(x: 470, y: 300, width: 370, height: 200))
    }

    func addPanel(_ r: Rectangle) {
        frame(r, title: "a + b: walk a, then walk b")
        let o = Vector2(r.x + 60, r.y + 150)
        let a = Vector2(150, -45)
        let b = Vector2(95, -75)
        arrow(from: o, to: o + a, color: ink)
        arrow(from: o + a, to: o + a + b, color: ink)
        arrow(from: o, to: o + a + b, color: accent)
        label("a", o + a * 0.5 + Vector2(0, 20))
        label("b", o + a + b * 0.5 + Vector2(22, 0))
        label("a + b", o + (a + b) * 0.5 + Vector2(-34, -8), color: accent)
    }

    func subtractPanel(_ r: Rectangle) {
        frame(r, title: "target − pos: the arrow from here to there")
        let pos = Vector2(r.x + 70, r.y + 155)
        let target = Vector2(r.x + 300, r.y + 70)
        arrow(from: pos, to: target, color: accent)
        noStroke()
        fill(ink)
        drawCircle(center: pos, radius: 7)
        drawCircle(center: target, radius: 7)
        label("pos", pos + Vector2(0, 24))
        label("target", target + Vector2(0, -20))
        label("target − pos", pos.lerp(to: target, 0.5) + Vector2(30, 16), color: accent)
    }

    func scalePanel(_ r: Rectangle) {
        frame(r, title: "v × s: same heading, new length")
        let o = Vector2(r.x + 165, r.y + 115)
        let v = Vector2(70, -35)
        arrow(from: o, to: o + v * 2, color: faint)
        arrow(from: o, to: o + v * -1, color: faint)
        arrow(from: o, to: o + v, color: ink)
        label("v", o + v + Vector2(14, 14))
        label("v * 2", o + v * 2 + Vector2(10, -12))
        label("v * -1", o + v * -1 + Vector2(-14, 18))
    }

    func normalizePanel(_ r: Rectangle) {
        frame(r, title: "v.normalized: heading kept, length exactly 1")
        let o = Vector2(r.x + 95, r.y + 70)
        let dir = Vector2(1.75, 0.85).normalized
        arrow(from: o, to: o + dir * 215, color: ink)
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: o, radius: 62)
        arrow(from: o, to: o + dir * 62, color: accent, weight: 5)
        label("v", o + dir * 215 + Vector2(22, 12))
        label("the circle of radius 1", o + Vector2(-2, 94))
        label("v.normalized", o + dir * 62 + Vector2(66, -18), color: accent)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }

    func arrow(from a: Vector2, to b: Vector2, color: Color, weight: Double = 3) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 16 + dir.perpendicular * 6,
                        b - dir * 16 - dir.perpendicular * 6])
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
