// figure: frame=200 themed
//
// Guide diagram (Chapter 31): a live-coding set as five evaluations. Each
// thumbnail is the payoff chain truncated at that step and rendered for real,
// so the strip is the set the way the audience sees it grow: bands, then the
// fold, then the melt, then the print look, then flight.
import Ollin
import OllinDiagram

final class SetSteps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var soft: Color { theme.ink(0.6) }

    override func draw() {
        background(paper)

        let bands: Visual = .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
        let folded = bands.kaleidoscope(5)
        let melted = folded.displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)
        let printed = melted.posterized(bins: 6, gamma: 0.75)
        let flying = printed.rotated(time * 0.03).colorCycled(time * 0.04)

        thumb(bands, index: 0, note: "the oscillator")
        thumb(folded, index: 1, note: ".kaleidoscope(5)")
        thumb(melted, index: 2, note: ".displaced(by: noise)")
        thumb(printed, index: 3, note: ".posterized(bins: 6)")
        thumb(flying, index: 4, note: ".rotated .colorCycled")

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("one set, five evaluations: each return key reshapes the piece without stopping it",
                 width / 2, 400)
    }

    func thumb(_ chain: Visual, index: Int, note: String) {
        let w = 152.0
        let x = 30 + Double(index) * (w + 15)
        let panel = Rectangle(x: x, y: 150, width: w, height: w)
        drawImage(generate(chain, width: Int(w), height: Int(w)).image, in: panel)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(panel)
        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.center, .top)
        drawText("\(index + 1)", panel.center.x, 120)
        fill(soft)
        drawText(note, panel.center.x, 312)
    }
}
