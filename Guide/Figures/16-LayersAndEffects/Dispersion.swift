// figure: frame=0
//
// Guide diagram (Chapter 16): one amount, six pictures. The same scene split by
// each mode of the chromatic-aberration filter, plus the tap budget that turns
// three hard ghosts into a continuous smear.
import Ollin

final class Dispersion: Sketch {
    override var canvasSize: CanvasSize { .size(880, 730) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        let panels = (0 ..< 6).map { i in
            Rectangle(x: 25 + Double(i % 3) * 284, y: 62 + Double(i / 3) * 310,
                      width: 262, height: 262)
        }

        // One scene: a pale disc off to one side, a block, and a stack of thin
        // lines. Hard edges for the edge-reading mode, thin marks for the ghosts.
        let source = renderTarget(width: 520, height: 520)
        withTarget(source) {
            // The layer is its own 520-square world, so these are its coordinates.
            background(Color(hex: 0x0E1424))
            noStroke()
            fill(Color(hex: 0xF2F0E6)); drawCircle(165, 150, 80)
            fill(Color(hex: 0xE4572E)); drawRect(310, 60, 155, 100)
            stroke(Color(hex: 0xF2F0E6)); strokeWeight(3); noFill()
            for i in 0 ..< 8 { drawLine(55, 300 + Double(i) * 26, 465, 300 + Double(i) * 26) }
        }

        let treatments: [(String, Filter)] = [
            (".magnify", .chromaticAberration(amount: 0.018)),
            (".lens(radius: 0.3, falloff: 2)",
             .chromaticAberration(amount: 0.05, mode: .lens(radius: 0.3, falloff: 2))),
            (".offset(angle: .pi / 5)",
             .chromaticAberration(amount: 0.012, mode: .offset(angle: .pi / 5))),
            (".edges", .chromaticAberration(amount: 0.03, mode: .edges)),
            (".axial", .chromaticAberration(amount: 0.022, mode: .axial)),
            ("spectral: true", .chromaticAberration(amount: 0.018, spectral: true)),
        ]
        for (i, treatment) in treatments.enumerated() {
            drawImage(source.filtered(treatment.1).image, in: panels[i])
            frame(panels[i], title: treatment.0)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one filter, five ways to pull the channels apart,", width / 2, 660)
        drawText("and the tap budget that turns three ghosts into a smear", width / 2, 686)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
