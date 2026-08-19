// figure: frame=0 probe
//
// Guide diagram (Chapter 11): a spring has one happy distance, its rest
// length. Stretched past it, the spring pulls its ends back in; squeezed
// short of it, the spring pushes them apart; at rest length it does nothing.
import Ollin

final class SpringRestLength: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    let rest = 220.0

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        panel(Rectangle(x: 50, y: 60, width: 780, height: 115),
              title: "at rest length: no pull, no push", span: rest, force: 0)
        panel(Rectangle(x: 50, y: 220, width: 780, height: 115),
              title: "stretched: it pulls both ends back in", span: rest * 1.45, force: -1)
        panel(Rectangle(x: 50, y: 380, width: 780, height: 115),
              title: "squeezed: it pushes both ends apart", span: rest * 0.62, force: 1)
    }

    /// One spring between two discs, centered in the panel at the given span.
    /// `force` marks the arrows on the ends: -1 inward, +1 outward, 0 none.
    func panel(_ r: Rectangle, title: String, span: Double, force: Int) {
        frame(r, title: title)
        let mid = Vector2(r.x + r.width / 2, r.y + 58)
        let a = mid - Vector2(span / 2, 0)
        let b = mid + Vector2(span / 2, 0)

        // The coil: a zigzag polyline with straight leads at both ends. The
        // amplitude tracks the span, so stretching flattens it and squeezing
        // bunches it up, the way a real coil reads.
        let zigs = 12
        let amp = 17.0 * (rest / span)
        let lead = 26.0
        let inner = span - lead * 2
        var points = [a]
        for i in 0 ... zigs {
            let t = Double(i) / Double(zigs)
            let up = i == 0 || i == zigs ? 0 : (i % 2 == 0 ? -amp : amp)
            points.append(a + Vector2(lead + inner * t, up))
        }
        points.append(b)
        noFill()
        stroke(ink)
        strokeWeight(2.5)
        drawPolyline(points)

        noStroke()
        fill(ink)
        drawCircle(center: a, radius: 10)
        drawCircle(center: b, radius: 10)

        if force == -1 {              // stretched: pulled back in
            arrow(from: a - Vector2(82, 0), to: a - Vector2(24, 0))
            arrow(from: b + Vector2(82, 0), to: b + Vector2(24, 0))
        } else if force == 1 {        // squeezed: pushed apart
            arrow(from: a - Vector2(24, 0), to: a - Vector2(82, 0))
            arrow(from: b + Vector2(24, 0), to: b + Vector2(82, 0))
        } else {
            // The rest-length ruler, for comparing the other two against.
            stroke(faint)
            strokeWeight(1.5)
            drawLine(a.x, mid.y + 32, b.x, mid.y + 32)
            drawLine(a.x, mid.y + 26, a.x, mid.y + 38)
            drawLine(b.x, mid.y + 26, b.x, mid.y + 38)
            noStroke()
            fill(faint)
            textSize(15)
            textAlign(.center, .top)
            drawText("rest length", mid.x, mid.y + 40)
            textSize(17)
        }
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

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(4)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 16 + dir.perpendicular * 6,
                        b - dir * 16 - dir.perpendicular * 6])
    }
}
