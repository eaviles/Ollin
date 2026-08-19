// figure: frame=0
//
// Guide diagram (Chapter 15): nine curves you can write down. Each panel is
// one function call with a couple of numbers, and none of them uses
// randomness. The last panel is the corner-cutting smoother rather than a
// curve, shown as the rough polygon it started from.
import Ollin

final class ClassicCurves: Sketch {
    override var canvasSize: CanvasSize { .size(880, 900) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        seed(3)

        let panels = (0 ..< 9).map {
            Rectangle(x: 45 + Double($0 % 3) * 275, y: 62 + Double($0 / 3) * 268,
                      width: 240, height: 240)
        }
        let titles = ["phyllotaxis", "lissajous", "rose",
                      "superellipse", "hypotrochoid", "harmonograph",
                      "supershape", "guilloche", "smoothed"]

        // A sunflower head: every seed lands in the gap the others left.
        let seeds = fitted(phyllotaxis(count: 520, spacing: 7),
                           in: panels[0].inset(by: .all(14)))
        noStroke()
        fill(ink)
        for (i, p) in seeds.enumerated() {
            drawCircle(p.x, p.y, 1.2 + Double(i) * 0.004)
        }

        // Two sine waves meeting at right angles.
        curve(fitted(lissajous(a: 3, b: 2, width: 200).points,
                     in: panels[1].inset(by: .all(18))), closed: true)

        // Petals from one polar equation.
        curve(fitted(rose(n: 5, radius: 100).points,
                     in: panels[2].inset(by: .all(18))), closed: true)

        // One exponent from squircle to pinched star.
        curve(fitted(superellipse(width: 200, n: 4).points,
                     in: panels[3].inset(by: .all(18))), closed: true)
        curve(fitted(superellipse(width: 200, n: 0.7).points,
                     in: panels[3].inset(by: .all(48))), closed: true)

        // A gear rolling inside a gear, pen offset from its center.
        curve(fitted(hypotrochoid(ring: 84, wheel: 33, pen: 26).points,
                     in: panels[4].inset(by: .all(18))), closed: true)

        // Swinging pendulums, drawing as they die away.
        let graph = Harmonograph(
            x: [.init(amplitude: 100, frequency: 2.01, phase: 0, damping: 0.05),
                .init(amplitude: 46, frequency: 3, phase: .pi / 3, damping: 0.055)],
            y: [.init(amplitude: 100, frequency: 3, phase: .pi / 2, damping: 0.048),
                .init(amplitude: 40, frequency: 2, phase: 0, damping: 0.055)])
        curve(fitted(graph.contour().points, in: panels[5].inset(by: .all(18))),
              closed: false)

        // The superformula: lobes and shaping numbers on one dial.
        curve(fitted(supershape(radius: 100, m: 7, n1: 0.3, n2: 1.2, n3: 1.2).points,
                     in: panels[6].inset(by: .all(18))), closed: true)

        // The rose engine: cam-shaped rings, each turned a hair.
        withState {
            translate(panels[7].center.x, panels[7].center.y)
            noFill()
            stroke(accent)
            strokeWeight(0.7)
            for ring in guilloche(rings: 16, innerRadius: 22, outerRadius: 100,
                                  rosettes: [Rosette(bumps: 8, amplitude: 6),
                                             Rosette(bumps: 32, amplitude: 1.4)]) {
                drawPolyline(ring.points, closed: true)
            }
        }

        // Corner cutting: the same rough loop, before and after.
        let rough = (0 ..< 9).map { i -> Vector2 in
            let a = Double(i) / 9 * .tau
            let r = 60 + random(-34, 34)
            return Vector2(panels[8].x + panels[8].width / 2 + cos(a) * r,
                           panels[8].y + panels[8].height / 2 + sin(a) * r)
        }
        noFill()
        stroke(ink.withAlpha(0.5))
        strokeWeight(1.6)
        drawPolygon(rough)
        curve(Contour(rough, closed: true).smoothed(iterations: 4).points,
              closed: true)

        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("no randomness anywhere: every one is a formula with a few knobs",
                 width / 2, 860)
    }

    func curve(_ points: [Vector2], closed: Bool) {
        noFill()
        stroke(accent)
        strokeWeight(1.8)
        if closed { drawPolygon(points) } else { drawPolyline(points) }
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
