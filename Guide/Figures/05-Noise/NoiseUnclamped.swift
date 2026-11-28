// figure: frame=0 themed
//
// Guide figure (Chapter 5, and Docs/Generators/Noise.md § clamped): one row of
// the 2D field read twice. Above, `noise` cuts the field off at 0 and at 1, and the curve runs
// flat along each line (marked). Below, the same row with nothing cut off: the
// curve is the same wherever the first was between its lines, and keeps going
// where the first rested.
import Ollin
import OllinDiagram

final class NoiseUnclamped: Sketch {
    override var canvasSize: CanvasSize { .size(880, 640) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var accent: Color { theme.accent }

    let left = 70.0
    let samples = 371
    var row = 0.5

    override func setup() {
        noiseSeed(6)
        // The row, out of a few hundred, that rests on its ends the most over
        // the span drawn, so the cut is in view.
        var most = 0
        for candidate in 0 ..< 300 {
            let v = Double(candidate) * 0.37 + 0.5
            let resting = (0 ..< samples).filter { i in
                let n = noise(u(i), v)
                return n == 0 || n == 1
            }.count
            if resting > most {
                most = resting
                row = v
            }
        }
    }

    func u(_ i: Int) -> Double { Double(i) * 2 * 0.012 }

    override func draw() {
        background(paper)
        textSize(21)
        let w = width - 2 * left

        strip(one: 112, zero: 232, width: w, label: "noise(x, y) · cut off at 0 and at 1, where it runs flat") { i in
            let n = noise(u(i), row)
            return (n, n == 0 || n == 1)
        }
        strip(one: 410, zero: 530, width: w, label: "noise(x, y, clamped: false) · the same field, nothing cut off") { i in
            let n = noise(u(i), row, clamped: false)
            return (n, n <= 0 || n >= 1)
        }
    }

    /// One reading of the row between the lines for 1 and for 0, the stretches
    /// `marked` drawn heavier in the accent.
    func strip(one: Double, zero: Double, width w: Double, label: String, sample: (Int) -> (value: Double, marked: Bool)) {
        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText(label, left, one - 72)

        stroke(faint)
        strokeWeight(2)
        drawLine(left, one, left + w, one)
        drawLine(left, zero, left + w, zero)
        noStroke()
        fill(faint)
        textAlign(.right, .middle)
        drawText("1", left - 14, one)
        drawText("0", left - 14, zero)

        var previous = sample(0)
        for i in 1 ..< samples {
            let next = sample(i)
            let x0 = left + Double(i - 1) / Double(samples - 1) * w, x1 = left + Double(i) / Double(samples - 1) * w
            let heavy = previous.marked && next.marked
            stroke(heavy ? accent : ink)
            strokeWeight(heavy ? 5 : 2)
            drawLine(x0, zero + (one - zero) * previous.value, x1, zero + (one - zero) * next.value)
            previous = next
        }
    }
}
