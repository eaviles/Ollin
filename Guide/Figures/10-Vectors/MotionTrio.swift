// figure: frame=0
//
// Guide diagram (Chapter 10): position, velocity, and acceleration as three
// arrows on one thrown body. The dots are the flight path; at the marked
// moment, velocity points along the path and acceleration points down.
import Ollin

final class MotionTrio: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        let p0 = Vector2(130, 420)
        let v0 = Vector2(300, -380)
        let g = Vector2(0, 330)

        // The flight path, dotted.
        noStroke()
        fill(soft)
        var t = 0.0
        while t <= 2.2 {
            let p = p0 + v0 * t + g * (0.5 * t * t)
            drawCircle(center: p, radius: 5)
            t += 0.055
        }

        // One moment on the path, with its three arrows.
        let tm = 1.2
        let p = p0 + v0 * tm + g * (0.5 * tm * tm)
        let v = v0 + g * tm

        // position: the arrow from the origin to the body.
        let origin = Vector2(46, 46)
        stroke(faint)
        strokeWeight(2)
        var walk = 0.0
        let toBody = p - origin
        while walk < toBody.length {
            let a = origin + toBody.normalized * walk
            let b = origin + toBody.normalized * min(walk + 9, toBody.length)
            drawLine(a, b)
            walk += 18
        }
        noStroke()
        fill(ink)
        drawCircle(center: origin, radius: 5)
        textSize(17)
        textAlign(.left, .middle)
        fill(faint)
        drawText("(0, 0)", 62, 40)
        drawText("position: where it is", 200, 190)

        arrow(from: p, to: p + v * 0.3, color: accent)
        arrow(from: p, to: p + g * 0.3, color: ink)
        noStroke()
        fill(accent)
        drawCircle(center: p, radius: 11)

        textSize(16)
        fill(accent)
        textAlign(.left, .middle)
        drawText("velocity: where it's going", p.x + 112, p.y - 2)
        fill(ink)
        drawText("acceleration: how the going changes", p.x + 20, p.y + 112)

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("three arrows on one body", width / 2, 500)
    }

    func arrow(from a: Vector2, to b: Vector2, color: Color) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(4)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 18 + dir.perpendicular * 7,
                        b - dir * 18 - dir.perpendicular * 7])
    }
}
