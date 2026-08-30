// figure: frame=0 themed
//
// Guide diagram (Chapter 31): proofing a poster against a press profile. The
// artwork as the screen shows it, the same artwork carried into the press
// profile and back (which is what the print will look like), and the gamut
// check, which marks the colors that press cannot make at all.
import Ollin
import OllinDiagram

final class ProofBeforePrint: Sketch {
    override var canvasSize: CanvasSize { .size(880, 380) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    var panels: [Image] = []
    let titles = ["on screen", "printed", "what will not print"]

    override func setup() {
        let press = SoftProof(.genericCMYK)
        let artwork = poster(size: 240)
        panels = [artwork,
                  artwork.softProofed(press),
                  artwork.softProofed(press, warning: Color(white: 0.55), amount: 0)]
    }

    override func draw() {
        background(paper)

        for (index, panel) in panels.enumerated() {
            let box = Rectangle(x: 50 + Double(index) * 270, y: 62,
                                width: 240, height: 240)
            drawImage(panel, in: box)
            frame(box, title: titles[index])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("ink cannot hold what a lit screen can, and the profile says so",
                 width / 2, 330)
    }

    /// Colors a screen is good at and a press is not, over a ramp of neutrals
    /// it handles perfectly: the strip along the bottom is the control, and it
    /// has to come through all three panels unchanged.
    func poster(size: Int) -> Image {
        let image = Image(width: size, height: size)
        for y in 0 ..< size {
            let v = Double(y) / Double(size - 1)
            for x in 0 ..< size {
                let u = Double(x) / Double(size - 1)
                var c = Color.mix(Color(hex: 0x2B1B6B), Color(hex: 0xFF2D55),
                                  smoothstep(0.05, 0.62, v))
                c = Color.mix(c, Color(hex: 0xFFD400),
                              1 - smoothstep(0.145, 0.152, dist(u, v, 0.62, 0.30)))
                if v > 0.62 { c = Color(hex: 0x00E5FF) }
                if v > 0.74 + 0.08 * sin(u * 3.4 + 2.1) { c = Color(hex: 0x00FF66) }
                if v > 0.88 { c = Color(white: 0.12 + (u * 8).rounded(.down) / 7 * 0.8) }
                image[x, y] = c
            }
        }
        return image
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
