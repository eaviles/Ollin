// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Geometry.md, producing new vectors): lerp
// dots along a segment, a point rotated about a pivot, limited capping a
// long vector at a maximum length, and projected dropping a's shadow onto
// b's line.
import Ollin

final class VectorMoves: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.55) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.25) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // Panel 1: lerp slides from a toward b; t = 0.5 is the midpoint.
        let a1 = Vector2(38, 140), b1 = Vector2(208, 110)
        stroke(faint)
        strokeWeight(1.5)
        drawLine(a1, b1)
        noStroke()
        for step in 0...4 {
            let t = Double(step) / 4
            let p = a1.lerp(to: b1, t)
            fill(t == 0.5 ? accent : ink)
            drawCircle(center: p, radius: t == 0.5 ? 5 : 3.5)
        }
        fill(ink)
        textSize(16)
        textAlign(.center, .top)
        drawText("a", a1.x, a1.y + 12)
        drawText("b", b1.x, b1.y + 12)
        fill(accent)
        textAlign(.center, .bottom)
        drawText("t = 0.5", a1.lerp(to: b1, 0.5).x, a1.lerp(to: b1, 0.5).y - 12)
        caption("a.lerp(to: b, t)", cx: 123)

        // Panel 2: rotated(by:around:) swings v about the pivot p.
        let p2 = Vector2(298, 163)
        let v2 = Vector2(86, -56)
        let theta = 1.15
        let r2 = v2.rotated(by: theta)
        arrow(from: p2, to: p2 + v2, color: faint, weight: 2.5)
        arrow(from: p2, to: p2 + r2, color: ink, weight: 2.5)
        stroke(accent)
        strokeWeight(2)
        noFill()
        arc(center: p2, radius: 60, from: v2.angle + 0.1, to: r2.angle - 0.16)
        noStroke()
        fill(accent)
        drawCircle(center: p2, radius: 4)
        fill(soft)
        textSize(16)
        textAlign(.left, .bottom)
        drawText("v", p2.x + v2.x + 6, p2.y + v2.y + 2)
        fill(ink)
        textAlign(.left, .top)
        drawText("rotated", p2.x + r2.x + 2, p2.y + r2.y + 8)
        fill(accent)
        textAlign(.center, .bottom)
        drawText("p", p2.x - 12, p2.y + 4)
        textAlign(.left, .middle)
        drawText("θ", p2.x + 74, p2.y + 6)
        caption("v.rotated(by: θ, around: p)", cx: 340)

        // Panel 3: limited clamps a long vector to length m; a short one
        // passes through untouched.
        let o3 = Vector2(524, 168)
        let dir3 = Vector2(angle: -0.55)
        stroke(faint)
        strokeWeight(1.5)
        noFill()
        drawCircle(center: o3, radius: 74)
        arrow(from: o3, to: o3 + dir3 * 136, color: faint, weight: 2.5)
        arrow(from: o3, to: o3 + dir3 * 74, color: accent, weight: 3)
        noStroke()
        fill(accent)
        drawCircle(center: o3, radius: 3.5)
        fill(soft)
        textSize(16)
        textAlign(.left, .top)
        drawText("v", o3.x + 136 * dir3.x + 8, o3.y + 136 * dir3.y - 4)
        fill(accent)
        textAlign(.right, .top)
        drawText("length m", o3.x + 34, o3.y + 80)
        caption("v.limited(to: m)", cx: 560)

        // Panel 4: projected drops a straight down onto b's line.
        let o4 = Vector2(694, 212)
        let b4 = Vector2(158, 0)
        let a4 = Vector2(98, -100)
        arrow(from: o4, to: o4 + b4, color: ink, weight: 2.5)
        arrow(from: o4, to: o4 + a4, color: ink, weight: 2.5)
        stroke(faint)
        strokeWeight(1.5)
        drawLine(o4 + a4, o4 + Vector2(a4.x, 0))
        squareMark(at: o4 + Vector2(a4.x, 0), into: Vector2(-1, -1))
        arrow(from: o4, to: o4 + a4.projected(onto: b4), color: accent, weight: 4)
        noStroke()
        fill(accent)
        drawCircle(center: o4, radius: 3.5)
        fill(ink)
        textSize(16)
        textAlign(.left, .bottom)
        drawText("a", o4.x + a4.x + 8, o4.y + a4.y + 4)
        textAlign(.left, .middle)
        drawText("b", o4.x + b4.x + 6, o4.y)
        fill(accent)
        textAlign(.center, .top)
        drawText("projected", o4.x + a4.x / 2, o4.y + 12)
        caption("a.projected(onto: b)", cx: 780)
    }

    func caption(_ text: String, cx: Double) {
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.center, .top)
        drawText(text, cx, 278)
    }

    // An arc with a small arrowhead at its end, showing the turn's sense.
    func arc(center: Vector2, radius: Double, from: Double, to: Double) {
        drawArc(center: center, rx: radius, ry: radius, start: from, stop: to)
        let tip = center + Vector2(angle: to, length: radius)
        let dir = Vector2(angle: to + 0.5 * Double.pi)
        noStroke()
        fill(accent)
        drawPolygon([tip + dir * 10,
                     tip - dir * 3 + dir.perpendicular * 5,
                     tip - dir * 3 - dir.perpendicular * 5])
    }

    func squareMark(at corner: Vector2, into: Vector2, size: Double = 10) {
        let a = corner + Vector2(into.x * size, 0)
        let b = corner + Vector2(into.x * size, into.y * size)
        let c = corner + Vector2(0, into.y * size)
        drawPolyline([a, b, c])
    }

    func arrow(from a: Vector2, to b: Vector2, color: Color, weight: Double) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
