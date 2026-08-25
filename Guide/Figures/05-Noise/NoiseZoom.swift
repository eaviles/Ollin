// figure: frame=0 themed
//
// Guide diagram: the multiplier on noise's input is a zoom knob. Three panels
// sample the same field with steps of three different sizes: tiny steps read
// one hillside, bigger steps cross whole hills, big steps skim a mountain
// range's worth of terrain into the same frame.
import Ollin
import OllinDiagram

final class NoiseZoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func setup() {
        noiseSeed(6)
    }

    override func draw() {
        background(paper)
        textSize(21)

        drawPanel(x: 70, multiplier: 0.004, note: "gentle")
        drawPanel(x: 340, multiplier: 0.015, note: "rolling")
        drawPanel(x: 610, multiplier: 0.06, note: "busy")

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("the same field, walked with three step sizes", width / 2, 440)
    }

    func drawPanel(x: Double, multiplier: Double, note: String) {
        let size = 200.0
        let top = 110.0, bottom = top + size

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)

        var points: [Vector2] = []
        for i in 0...200 {
            let n = noise(Double(i) * size / 200 * multiplier)
            points.append(Vector2(x + Double(i), bottom - n * size))
        }
        stroke(accent)
        strokeWeight(3)
        drawPolyline(points)

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText("noise(x * \(multiplier))", x + size / 2, top - 40)
        fill(theme.ink(0.6))
        drawText(note, x + size / 2, top - 14)
    }
}
