// figure: frame=0
//
// Guide diagram (Chapter 4): three walks from the same seed. The plain walk
// wanders a small patch, the Lévy flight mostly shuffles and occasionally
// leaps, and the self-avoiding walk refuses to cross itself and so fills the
// space instead of pooling in it.
import Ollin

final class WalkFamily: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 62, width: 262, height: 262)
        }

        noFill()
        strokeWeight(1.2)
        stroke(ink)

        // Both wandering walks are fitted rather than clipped, so no straight
        // segment in the picture is an artifact of the panel edge.
        seed(7)
        let plain = randomWalk(from: .zero, steps: 6000, stepLength: 3)
        drawPolyline(fitted(plain, in: panels[0].inset(by: .all(12))))

        seed(7)
        let leaps = levyFlight(from: .zero, steps: 2600, minStep: 1.5, maxStep: 70)
        drawPolyline(fitted(leaps, in: panels[1].inset(by: .all(12))))

        seed(7)
        stroke(accent)
        strokeWeight(5)
        strokeCap(.round)
        drawPolyline(selfAvoidingWalk(in: panels[2].inset(by: .all(16)),
                                      cellSize: 22))

        let titles = ["randomWalk", "levyFlight", "selfAvoidingWalk"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("same seed, three rules about what the next step may be",
                 width / 2, 348)
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
        drawText(title, r.x, r.y - 18)
    }
}
