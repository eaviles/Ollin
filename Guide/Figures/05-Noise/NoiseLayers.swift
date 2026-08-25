// figure: frame=0 probe themed
//
// Guide diagram: layering two scales of noise by hand. A big-scale sample
// gives the shape, a small-scale sample gives the detail, and a weighted
// sum gives terrain with both.
import Ollin
import OllinDiagram

final class NoiseLayers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    override func setup() {
        noiseSeed(9)
    }

    override func draw() {
        background(paper)
        textSize(21)

        strip(top: 74, label: "shape = noise(x * 0.004) · the big moves") { x in
            noise(x * 0.004)
        }
        strip(top: 240, label: "detail = noise(x * 0.03) · the texture") { x in
            noise(x * 0.03)
        }
        strip(top: 406, label: "shape * 0.7 + detail * 0.3 · both at once", hero: true) { x in
            noise(x * 0.004) * 0.7 + noise(x * 0.03) * 0.3
        }
    }

    func strip(top: Double, label: String, hero: Bool = false, sample: (Double) -> Double) {
        let left = 70.0, w = width - 140, h = 96.0

        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText(label, left, top - 10)

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(left, top, w, h)

        var points: [Vector2] = []
        for i in 0...240 {
            let x = Double(i) / 240 * w
            points.append(Vector2(left + x, top + h - sample(x) * h))
        }
        stroke(hero ? accent : ink)
        strokeWeight(hero ? 3 : 2.5)
        drawPolyline(points)
    }
}
