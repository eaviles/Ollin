// figure: frame=0 probe
//
// Guide diagram (Appendix B): Verlet motion. No stored velocity: the gap
// between the previous and current positions is the velocity, carried
// forward and bent by the frame's forces.
import Ollin

final class Verlet: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        let previous = Vector2(200, 240)
        let now = Vector2(400, 185)
        let carried = now + (now - previous)
        let next = carried + Vector2(0, 62)

        // The step just taken.
        stroke(accent)
        strokeWeight(3)
        drawLine(previous, now)
        chevron(at: now, pointing: (now - previous).normalized)

        // The same step replayed, then bent by gravity.
        stroke(faint)
        strokeWeight(3)
        dashed(from: now, to: carried)
        chevron(at: carried, pointing: (carried - now).normalized)
        stroke(ink)
        drawLine(carried, next)
        chevron(at: next, pointing: Vector2(0, 1))

        noStroke()
        fill(faint)
        drawCircle(center: previous, radius: 9)
        fill(ink)
        drawCircle(center: now, radius: 11)
        noFill()
        stroke(faint)
        strokeWeight(2.5)
        drawCircle(center: carried, radius: 9)
        noStroke()
        fill(accent)
        drawCircle(center: next, radius: 11)

        fill(ink)
        textAlign(.center, .top)
        drawText("previous", previous.x, previous.y + 22)
        drawText("now", now.x, now.y + 24)
        textAlign(.left, .middle)
        fill(faint)
        drawText("the same step, replayed", carried.x + 22, carried.y - 4)
        fill(ink)
        drawText("plus gravity", carried.x + 14, carried.y + 34)
        fill(accent)
        drawText("next", next.x + 22, next.y + 6)
        fill(accent)
        textAlign(.center, .bottom)
        let mid = (previous + now) / 2
        drawText("now - previous is the velocity", mid.x - 64, mid.y - 34)

        fill(ink)
        textAlign(.center, .top)
        drawText("no stored velocity: the gap between then and now, carried forward and bent",
                 width / 2, 368)
    }

    func dashed(from a: Vector2, to b: Vector2) {
        let step = (b - a).normalized * 14
        var p = a
        while (p - a).length + 14 < (b - a).length {
            drawLine(p, p + step * 0.6)
            p = p + step
        }
    }

    func chevron(at tip: Vector2, pointing dir: Vector2) {
        let side = Vector2(-dir.y, dir.x)
        drawLine(tip, tip - dir * 15 + side * 8)
        drawLine(tip, tip - dir * 15 - side * 8)
    }
}
