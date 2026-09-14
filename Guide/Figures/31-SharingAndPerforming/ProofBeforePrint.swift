// figure: frame=0 themed
//
// Guide diagram (Chapter 31): proofing a photograph against a press profile.
// A wall of marigolds, one of the bundled photographs, as the screen shows
// it, the same picture carried into the press profile and back (which is
// what the print will look like), and the gamut check, which marks the
// colors that press cannot make at all. That is more than half of the
// picture: the orange of cempasúchil is exactly what four inks reach for
// and miss, measured at 53 percent out of gamut against the generic profile.
import Ollin
import OllinDiagram
import OllinSamplePhotos

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
        let artwork = SamplePhoto.marigolds.load().resized(width: 240, height: 240)
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
