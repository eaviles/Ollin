// figure: frame=0
//
// Guide diagram (Chapter 18): four members of the two-generator trace family,
// drawn as circle orbits. The gasket at traces (2, 2), two complex-trace
// deformations that wobble it, and a loosened real-trace member. One recipe,
// four pictures. No randomness anywhere.
import Ollin

final class GasketFamily: Sketch {
    override var canvasSize: CanvasSize { .size(880, 960) }

    let night = Color(hex: 0x0C0F16)
    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let lace = Color(hex: 0xE8C97D)

    override func draw() {
        background(paper)

        let panels = [
            Rectangle(x: 25, y: 46, width: 400, height: 400),
            Rectangle(x: 455, y: 46, width: 400, height: 400),
            Rectangle(x: 25, y: 486, width: 400, height: 400),
            Rectangle(x: 455, y: 486, width: 400, height: 400),
        ]
        let members: [(String, Vector2)] = [
            ("traces (2, 2): the gasket", Vector2(2, 0)),
            ("traces (2.015 + 0.035i)", Vector2(2.015, 0.035)),
            ("traces (2.05 + 0.025i)", Vector2(2.05, 0.025)),
            ("traces (2.12, 2.12)", Vector2(2.12, 0)),
        ]

        for (panel, member) in zip(panels, members) {
            noStroke()
            fill(night)
            drawRect(panel)
            drawOrbit(ta: member.1, in: panel)
            frame(panel, title: member.0)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one recipe, four members of its parameter space", width / 2, 916)
    }

    /// One member's orbit, framed on its limit set and turned a quarter turn
    /// so the parabolic fans sit left and right.
    func drawOrbit(ta: Vector2, in panel: Rectangle) {
        let circles = schottkyCircles(ta: ta, tb: ta, in: panel,
                                      minRadius: 0.5, maxDepth: 100)
        let points = schottkyLimitSet(ta: ta, tb: ta, in: panel, minRadius: 5)
        guard let first = points.first else { return }

        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
        }
        let span = max(hi.x - lo.x, hi.y - lo.y, 1e-6)
        let factor = (panel.width - 24) / span
        let mid = Vector2((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)

        noFill()
        stroke(lace.withAlpha(0.42))
        strokeWeight(0.45)
        withClip(panel) {
            for circle in circles {
                let d = (circle.center - mid) * factor
                drawCircle(Circle(center: panel.center + Vector2(-d.y, d.x),
                                  radius: circle.radius * factor))
            }
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
