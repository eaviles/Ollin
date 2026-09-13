// figure: frame=0 themed
//
// Guide diagram (Chapter 29): what one note can be told while it sounds.
// Three panels: two notes on a time axis, one bent up a fifth and back while
// its neighbor holds; a note's level against how hard it is pressed, rising
// from where it was struck toward full by the voice's pressure amount; and
// the filter a slide moves, three lowpass curves on a frequency axis for the
// bottom, the middle, and the top of the key. The curves are the formulas
// the renderer applies, drawn rather than rendered, so the picture is the
// rule and not one voice's opinion of it.
import Ollin
import OllinDiagram

final class Expression: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let panels = [Rectangle(x: 40, y: 44, width: 250, height: 210),
                      Rectangle(x: 315, y: 44, width: 250, height: 210),
                      Rectangle(x: 590, y: 44, width: 250, height: 210)]
        diagramFrame(panels[0], title: "one note bent, one still", theme: theme)
        drawBend(in: panels[0])
        diagramFrame(panels[1], title: "a press, from the strike", theme: theme)
        drawPress(in: panels[1])
        diagramFrame(panels[2], title: "a slide opens the filter", theme: theme)
        drawSlide(in: panels[2])

        diagramCaption("three things a note is told while it sounds, each reaching that note alone", at: 290, theme: theme)
    }

    /// Two notes over time. One is bent up a fifth over half a second and let
    /// back down; the other sits where it was struck the whole way.
    private func drawBend(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let seconds = 2.0
        func x(_ t: Double) -> Double { inset.x + inset.width * t / seconds }
        func y(_ semitones: Double) -> Double { inset.bottomRight.y - inset.height * (semitones + 2) / 14 }

        noFill()
        stroke(faint)
        strokeWeight(1)
        for semitones in stride(from: 0.0, through: 12, by: 2) {
            drawLine(inset.x, y(semitones), inset.topRight.x, y(semitones))
        }

        // The neighbor: struck a fourth up, never touched.
        stroke(soft)
        strokeWeight(2.5)
        drawLine(x(0), y(5), x(seconds), y(5))

        // The bent one: the glide is the renderer's own, an eight millisecond
        // step, which on this axis is the corner it rounds.
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline((0...160).map { step in
            let t = seconds * Double(step) / 160
            let target: Double = t < 0.5 ? 0 : t < 1.0 ? 7 * (t - 0.5) / 0.5 : t < 1.5 ? 7 : 7 * max(0, 1 - (t - 1.5) / 0.3)
            return Vector2(x(t), y(target))
        })

        label("bend(note, semitones: 7)", at: Vector2(x(1.05), y(7) - 18), align: .left)
        label("the other note", at: Vector2(x(1.2), y(5) + 6), align: .left)
        label("struck", at: Vector2(x(0.04), y(0) + 6), align: .left)
        axis(inset, left: "0 s", right: "2 s")
    }

    /// A note's level against the pressure on it: the struck level at the
    /// left, rising toward full by the voice's pressure amount.
    private func drawPress(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        func x(_ pressure: Double) -> Double { inset.x + inset.width * pressure }
        func y(_ level: Double) -> Double { inset.bottomRight.y - inset.height * level * 0.92 }
        let struck = 0.4

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(inset.x, y(1), inset.topRight.x, y(1))
        drawLine(inset.x, y(struck), inset.topRight.x, y(struck))

        for (amount, color, weight) in [(0.5, soft, 2.0), (1.0, accent, 2.5)] {
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...40).map { step in
                let p = Double(step) / 40
                return Vector2(x(p), y(struck + (1 - struck) * amount * p))
            })
        }

        label("full", at: Vector2(inset.x + 2, y(1) + 4), align: .left)
        label("as struck, velocity 0.4", at: Vector2(inset.x + 2, y(struck) + 4), align: .left)
        label("pressureAmount 1", at: Vector2(x(0.55), y(struck + (1 - struck) * 0.55) - 17), align: .left)
        label("0.5", at: Vector2(x(0.86), y(struck + (1 - struck) * 0.5 * 0.86) + 8), align: .left)
        axis(inset, left: "pressure 0", right: "1")
    }

    /// The lowpass a slide moves: at the bottom of the key an octave down
    /// from where the note started, at the top an octave up.
    private func drawSlide(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let octaves = 7.0
        func x(_ hz: Double) -> Double { inset.x + inset.width * log2(hz / 50) / octaves }
        func y(_ level: Double) -> Double { inset.bottomRight.y - inset.height * level * 0.92 }
        let cutoff = 400.0

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(x(cutoff), y(0), x(cutoff), y(1))

        for (slide, color, weight) in [(0.0, soft, 2.0), (0.5, soft, 2.0), (1.0, accent, 2.5)] {
            let corner = cutoff * pow(2, (slide - 0.5) * 2)
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...120).map { step in
                let hz = 50 * pow(2, octaves * Double(step) / 120)
                let ratio = hz / corner
                let level = 1 / (1 + ratio * ratio * ratio * ratio).squareRoot()
                return Vector2(x(hz), y(level))
            })
        }

        // Each curve named where it has fallen to a fifth, which is where the
        // three sit furthest apart.
        func knee(_ corner: Double) -> Double { corner * pow(1 / (0.2 * 0.2) - 1, 0.25) }
        label("bottom", at: Vector2(x(knee(cutoff / 4)) + 4, y(0.2) - 5), align: .left)
        label("rest", at: Vector2(x(knee(cutoff)) + 4, y(0.2) - 5), align: .left)
        label("top", at: Vector2(x(knee(cutoff * 4)) + 4, y(0.2) - 5), align: .left)
        axis(inset, left: "50 Hz", right: "6.4 kHz")
    }

    private func inset(_ r: Rectangle, _ dx: Double, _ dy: Double) -> Rectangle {
        Rectangle(x: r.x + dx, y: r.y + dy, width: r.width - 2 * dx, height: r.height - 2 * dy)
    }

    private func label(_ text: String, at point: Vector2, align: HorizontalTextAlign) {
        noStroke()
        fill(soft)
        textSize(11)
        textAlign(align, .top)
        drawText(text, at: point)
    }

    private func axis(_ inset: Rectangle, left: String, right: String) {
        noStroke()
        fill(soft)
        textSize(11)
        textAlign(.left, .bottom)
        drawText(left, inset.x, inset.bottomRight.y + 18)
        textAlign(.right, .bottom)
        drawText(right, inset.topRight.x, inset.bottomRight.y + 18)
    }
}
