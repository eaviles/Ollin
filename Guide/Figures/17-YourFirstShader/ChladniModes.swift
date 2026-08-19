// figure: frame=0
//
// Guide diagram (Chapter 17): six Chladni modes. Each panel scatters grains
// over a square plate and keeps only the ones sitting near a nodal line,
// where the plate is not moving. The mode numbers m and n are the whole
// input, and every figure here is one closed-form expression, not a sim.
import Ollin

final class ChladniModes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)
        seed(11)

        let modes: [(m: Double, n: Double)] = [(2, 1), (3, 1), (4, 2),
                                               (5, 2), (7, 3), (8, 5)]
        for (i, mode) in modes.enumerated() {
            let panel = Rectangle(x: 45 + Double(i % 3) * 275,
                                  y: 62 + Double(i / 3) * 272,
                                  width: 240, height: 240)
            plate(panel, m: mode.m, n: mode.n)
            frame(panel, title: "m = \(Int(mode.m)), n = \(Int(mode.n))")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("sand settles where the plate holds still",
                 width / 2, 578)
    }

    /// Grains scattered over the plate, kept only where the mode is near zero.
    func plate(_ r: Rectangle, m: Double, n: Double) {
        noStroke()
        for _ in 0 ..< 26000 {
            let u = random(0, 1)
            let v = random(0, 1)
            let s = abs(chladni(u, v, m: m, n: n))
            let settle = 1 - smoothstep(0, 0.06, s)
            guard settle > 0.02 else { continue }
            fill(ink.withAlpha(settle * 0.75))
            drawCircle(r.x + u * r.width, r.y + v * r.height, 0.9)
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
        drawText(title, r.x, r.y - 18)
    }
}
