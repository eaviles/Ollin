// figure: frame=0 themed
//
// Guide diagram (Chapter 29): the two effects that work in the spectrum,
// and the stretch beside them. Three panels: the partials of a note as bars
// on a frequency axis, with the same partials a fifth higher over them,
// which is the pitch shift under a harmonizer's mix; four partials fading
// over time until the freeze, and holding flat from there; and a struck
// recording beside the same recording stretched three times, on one time
// axis. The third panel is the shipped stretch run on a real recording, so
// the outline is what the code draws rather than what it is meant to.
import Ollin
import OllinAudio
import OllinDiagram

final class Spectral: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    /// A struck note: partials at the ratios of a free bar, each fading at
    /// its own rate, at a rate the stretch reads it back at.
    let sampleRate = 48000.0
    lazy var recorded: [Float] = {
        let seconds = 0.35
        let ratios = [1.0, 2.76, 5.4, 8.93]
        let levels = [1.0, 0.5, 0.3, 0.18]
        let decays = [5.0, 8.0, 12.0, 18.0]
        return (0..<Int(seconds * sampleRate)).map { index in
            let t = Double(index) / sampleRate
            var sum = 0.0
            for (ratio, (level, decay)) in zip(ratios, zip(levels, decays)) {
                sum += level * exp(-decay * t) * sin(2 * .pi * 180 * ratio * t)
            }
            return Float(0.5 * sum * min(1, t * 400))
        }
    }()
    lazy var stretched: [Float] = {
        SampledInstrument.Recording(frames: recorded, sampleRate: sampleRate, rootKey: 54)
            .stretched(by: 3).frames
    }()

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let panels = [Rectangle(x: 40, y: 44, width: 250, height: 210),
                      Rectangle(x: 315, y: 44, width: 250, height: 210),
                      Rectangle(x: 590, y: 44, width: 250, height: 210)]
        diagramFrame(panels[0], title: "the pitch moved", theme: theme)
        drawShift(in: panels[0])
        diagramFrame(panels[1], title: "an instant held", theme: theme)
        drawFreeze(in: panels[1])
        diagramFrame(panels[2], title: "a recording stretched", theme: theme)
        drawStretch(in: panels[2])

        diagramCaption("a frame taken apart into its partials, and three things that buys", at: 290, theme: theme)
    }

    /// The partials of a note on a frequency axis, and the same partials a
    /// fifth higher over them, which is a harmonizer at half mix.
    private func drawShift(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let octaves = 6.0
        func x(_ hz: Double) -> Double { inset.x + inset.width * log2(hz / 100) / octaves }
        func y(_ level: Double) -> Double { inset.bottomRight.y - inset.height * level * 0.9 }
        let fundamental = 220.0
        let levels = [1.0, 0.55, 0.4, 0.28, 0.2, 0.15, 0.11, 0.08]
        let fifth = pow(2, 7.0 / 12)

        noStroke()
        for (index, level) in levels.enumerated() {
            let hz = fundamental * Double(index + 1)
            fill(soft)
            drawRect(x(hz) - 3, y(level), 6, inset.bottomRight.y - y(level))
        }
        for (index, level) in levels.enumerated() {
            let hz = fundamental * Double(index + 1) * fifth
            fill(accent)
            drawRect(x(hz) - 3, y(level), 6, inset.bottomRight.y - y(level))
        }
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(x(fundamental) + 4, y(1) - 8, x(fundamental * fifth) - 4, y(1) - 8)

        label("the note", at: Vector2(x(fundamental) - 6, y(0.55) - 20), align: .right)
        label("a fifth up, over it", at: Vector2(x(fundamental * fifth) + 8, y(1) - 20), align: .left)
        axis(inset, left: "100 Hz", right: "6.4 kHz")
    }

    /// Four partials fading over time, until the freeze catches them.
    private func drawFreeze(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let seconds = 1.2, frozenAt = 0.42
        func x(_ t: Double) -> Double { inset.x + inset.width * t / seconds }
        func y(_ level: Double) -> Double { inset.bottomRight.y - inset.height * level * 0.9 }
        let starts = [1.0, 0.62, 0.4, 0.25]
        let decays = [1.6, 2.8, 4.2, 6.0]

        noFill()
        strokeWeight(1)
        stroke(faint)
        drawLine(x(frozenAt), y(0), x(frozenAt), y(1))

        for (start, decay) in zip(starts, decays) {
            func level(_ t: Double) -> Double { start * exp(-decay * t) }
            // What would have happened, faint, then what does.
            stroke(faint)
            strokeWeight(1.5)
            drawPolyline((0...80).map { step in
                let t = frozenAt + (seconds - frozenAt) * Double(step) / 80
                return Vector2(x(t), y(level(t)))
            })
            stroke(soft)
            strokeWeight(2)
            drawPolyline((0...80).map { step in
                let t = frozenAt * Double(step) / 80
                return Vector2(x(t), y(level(t)))
            })
            stroke(accent)
            strokeWeight(2.5)
            drawLine(x(frozenAt), y(level(frozenAt)), x(seconds), y(level(frozenAt)))
        }

        label("the amount rises", at: Vector2(x(frozenAt) + 4, y(1) - 2), align: .left)
        label("held", at: Vector2(x(seconds) - 4, y(starts[0] * exp(-decays[0] * frozenAt)) - 18), align: .right)
        label("fading", at: Vector2(x(0.16), y(starts[0] * exp(-decays[0] * 0.16)) + 6), align: .left)
        axis(inset, left: "0 s", right: "1.2 s")
    }

    /// The recording and its stretch, drawn as outlines on one time axis.
    private func drawStretch(in panel: Rectangle) {
        let inset = inset(panel, 20, 22)
        let span = Double(stretched.count) / sampleRate * 1.04
        func outline(_ samples: [Float], center: Double, height: Double, color: Color) {
            let columns = 240
            let visible = Int(Double(columns) * Double(samples.count) / sampleRate / span)
            guard visible > 1 else { return }
            var top: [Vector2] = [], bottom: [Vector2] = []
            for column in 0..<visible {
                let from = column * samples.count / visible
                let to = max(from + 1, (column + 1) * samples.count / visible)
                var peak: Float = 0
                for index in from..<to { peak = max(peak, abs(samples[index])) }
                let x = inset.x + inset.width * Double(column) / Double(columns)
                let y = Double(peak) * height
                top.append(Vector2(x, center - y))
                bottom.append(Vector2(x, center + y))
            }
            noStroke()
            fill(color)
            drawShape(Shape(top + bottom.reversed()))
        }
        let third = inset.height / 3
        outline(recorded, center: inset.y + third * 0.7, height: third * 0.6, color: soft)
        outline(stretched, center: inset.y + third * 2.1, height: third * 0.6, color: accent)

        label("as recorded", at: Vector2(inset.x + 2, inset.y + third * 1.3), align: .left)
        label("three times as long, the same pitch", at: Vector2(inset.x + 2, inset.y + third * 2.7), align: .left)
        axis(inset, left: "0 s", right: String(format: "%.1f s", span))
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
