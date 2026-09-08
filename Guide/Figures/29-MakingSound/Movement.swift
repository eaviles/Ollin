// figure: frame=0 themed
//
// Guide diagram (Chapter 29): the four effects that move a sound, each one
// slow wave and the thing it moves. Four panels: a tremolo's level breathing
// over a tone, the delay of a chorus's copy sliding later and earlier around
// twenty milliseconds, the comb a flanger cuts through the spectrum at two
// points of its sweep, and the pair of notches a four-stage phaser sweeps up
// the spectrum. The curves are the responses the effects are defined by (the
// gain wave, the delay wave, the comb's magnitude, the all-pass row added
// back to the sound), which the tests pin the running code to.
import Ollin
import OllinDiagram

final class Movement: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

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

        let columns = [Rectangle(x: 60, y: 44, width: 360, height: 200),
                       Rectangle(x: 460, y: 44, width: 360, height: 200),
                       Rectangle(x: 60, y: 314, width: 360, height: 200),
                       Rectangle(x: 460, y: 314, width: 360, height: 200)]
        diagramFrame(columns[0], title: "tremolo: the level breathing", theme: theme)
        drawTremolo(in: columns[0])
        diagramFrame(columns[1], title: "chorus: the copy sliding later and earlier", theme: theme)
        drawChorus(in: columns[1])
        diagramFrame(columns[2], title: "flanger: a comb of notches, sweeping", theme: theme)
        drawFlanger(in: columns[2])
        diagramFrame(columns[3], title: "phaser: a notch per pair of stages, sweeping", theme: theme)
        drawPhaser(in: columns[3])

        diagramCaption("one slow wave each, and the thing it moves", at: 560, theme: theme)
    }

    /// A tone's peaks, breathing with the wave: the gain 1 − depth·(½ − ½ sin)
    /// at four hertz, depth 0.7, over one second.
    private func drawTremolo(in panel: Rectangle) {
        let middle = panel.center.y
        let inset = inset(panel, 14, 22)
        let count = 220
        strokeWeight(1)
        for column in 0..<count {
            let t = Double(column) / Double(count)
            let gain = 1 - 0.7 * (0.5 - 0.5 * sin(2 * .pi * 4 * t))
            let x = inset.x + inset.width * (Double(column) + 0.5) / Double(count)
            let reach = gain * inset.height * 0.42
            stroke(faint)
            drawLine(x, middle - reach, x, middle + reach)
        }
        noFill()
        stroke(accent)
        strokeWeight(2)
        for sign in [-1.0, 1.0] {
            drawPolyline((0...count).map { column in
                let t = Double(column) / Double(count)
                let gain = 1 - 0.7 * (0.5 - 0.5 * sin(2 * .pi * 4 * t))
                return Vector2(inset.x + inset.width * t, middle + sign * gain * inset.height * 0.42)
            })
        }
        label("full", at: Vector2(inset.x + 4, middle - inset.height * 0.42 - 6), align: .left)
        label("1 − depth", at: Vector2(inset.topRight.x - 4, middle - 0.3 * inset.height * 0.42 - 6), align: .right)
        axis(inset, left: "0 s", right: "1 s")
    }

    /// Where the copy sits, in milliseconds behind: twenty, sliding six either
    /// way with the wave at 0.8 Hz; the right side a quarter turn apart.
    private func drawChorus(in panel: Rectangle) {
        let inset = inset(panel, 14, 22)
        func y(_ ms: Double) -> Double { inset.bottomRight.y - inset.height * (ms - 10) / 20 }
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(inset.x, y(20), inset.topRight.x, y(20))
        let count = 200
        for (offset, color, weight) in [(0.25, soft, 1.5), (0.0, accent, 2.5)] {
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...count).map { column in
                let t = 2.5 * Double(column) / Double(count)
                let ms = 20 + 6 * sin(2 * .pi * (0.8 * t + offset))
                return Vector2(inset.x + inset.width * Double(column) / Double(count), y(ms))
            })
        }
        label("26 ms", at: Vector2(inset.x + 4, y(26) - 8), align: .left)
        label("20 ms, where the copy sits", at: Vector2(inset.x + 4, y(20) + 4), align: .left)
        label("14 ms", at: Vector2(inset.x + 4, y(14) + 4), align: .left)
        axis(inset, left: "0 s", right: "2.5 s")
    }

    /// The comb: the sound plus a copy one millisecond behind cancels every
    /// odd half wavelength, |½ + ½·e^(−i2πfD)|; the fainter comb is the same
    /// with the gap at three milliseconds, further along the sweep.
    private func drawFlanger(in panel: Rectangle) {
        let inset = inset(panel, 14, 22)
        let count = 400
        for (gap, color, weight) in [(0.003, soft, 1.5), (0.001, accent, 2.5)] {
            noFill()
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...count).map { column in
                let f = 8000 * Double(column) / Double(count)
                let phase = 2 * .pi * f * gap
                let real = 0.5 + 0.5 * cos(phase), imaginary = -0.5 * sin(phase)
                let gain = (real * real + imaginary * imaginary).squareRoot()
                return Vector2(inset.x + inset.width * Double(column) / Double(count),
                               inset.bottomRight.y - inset.height * 0.9 * gain)
            })
        }
        label("1 ms gap", at: Vector2(inset.x + inset.width * 0.135, inset.y + 2), align: .center)
        label("3 ms", at: Vector2(inset.x + inset.width * 0.0417 + 30, inset.y + inset.height * 0.35), align: .left)
        axis(inset, left: "0 Hz", right: "8 kHz")
    }

    /// Four stages of a first-order all-pass added back to the sound,
    /// |½ + ½·H(f)⁴|: two notches, at the corner's tan(π/8) and tan(3π/8).
    /// The accented row sits at 200 Hz, the fainter one at 800, the same row
    /// swept up two octaves.
    private func drawPhaser(in panel: Rectangle) {
        let inset = inset(panel, 14, 22)
        let count = 400
        let low = 40.0, high = 8000.0
        let sampleRate = 48000.0
        func response(_ f: Double, corner: Double) -> Double {
            // H(e^{iω}) = (a + e^{-iω}) / (1 + a·e^{-iω}) with a from the corner.
            let warped = tan(.pi * corner / sampleRate)
            let a = (warped - 1) / (warped + 1)
            let omega = 2 * .pi * f / sampleRate
            let cr = cos(omega), ci = -sin(omega)
            // numerator a + e^{-iω}, denominator 1 + a·e^{-iω}
            let nr = a + cr, ni = ci
            let dr = 1 + a * cr, di = a * ci
            let denominator = dr * dr + di * di
            var hr = (nr * dr + ni * di) / denominator
            var hi = (ni * dr - nr * di) / denominator
            // H to the fourth: square twice.
            for _ in 0..<2 {
                let r = hr * hr - hi * hi, i = 2 * hr * hi
                hr = r; hi = i
            }
            let real = 0.5 + 0.5 * hr, imaginary = 0.5 * hi
            return (real * real + imaginary * imaginary).squareRoot()
        }
        for (corner, color, weight) in [(800.0, soft, 1.5), (200.0, accent, 2.5)] {
            noFill()
            stroke(color)
            strokeWeight(weight)
            drawPolyline((0...count).map { column in
                let f = low * pow(high / low, Double(column) / Double(count))
                return Vector2(inset.x + inset.width * Double(column) / Double(count),
                               inset.bottomRight.y - inset.height * 0.9 * response(f, corner: corner))
            })
        }
        label("stages at 200 Hz", at: Vector2(inset.x + 4, inset.y + 2), align: .left)
        label("swept to 800 Hz", at: Vector2(inset.topRight.x - 4, inset.y + 2), align: .right)
        axis(inset, left: "40 Hz", right: "8 kHz, log")
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
