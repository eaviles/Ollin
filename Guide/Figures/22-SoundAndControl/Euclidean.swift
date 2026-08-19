// figure: frame=0
//
// Guide diagram (Chapter 22): what "spread as evenly as whole steps allow"
// means. Every row is a real Rhythm, read through its own subscript and its own
// intervals, so the picture cannot drift from what the type does. The left
// column is the written notation, the middle the steps themselves, the right
// the gaps between strikes: at most two lengths, and they differ by one. Under
// them, three of the named rhythms drawn the way the paper draws them, as the
// shape between the strikes on a circle.
import Ollin
import OllinAudio

final class Euclidean: Sketch {
    override var canvasSize: CanvasSize { .size(880, 700) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.5)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)

    let left = 132.0
    let stepWidth = 30.0

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText("Rhythm(k, in: 16)", 40, 40)
        fill(soft)
        textSize(14)
        textAlign(.right, .middle)
        drawText("gaps", 840, 40)

        for (row, pulses) in [2, 3, 4, 5, 7, 9, 11].enumerated() {
            drawRow(Rhythm(pulses, in: 16), pulses: pulses, y: 78 + Double(row) * 42)
        }

        let named: [(String, Rhythm)] = [
            ("tresillo", .tresillo),
            ("cinquillo", .cinquillo),
            ("bell pattern", .bellPattern),
        ]
        for (index, entry) in named.enumerated() {
            drawWheel(entry.1, name: entry.0, at: Vector2(180 + Double(index) * 260, 520))
        }
    }

    /// One rhythm as a line of steps, read through the type's own subscript.
    private func drawRow(_ rhythm: Rhythm, pulses: Int, y: Double) {
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.right, .middle)
        drawText("k = \(pulses)", 112, y)

        for step in 0..<rhythm.length {
            let x = left + Double(step) * stepWidth + stepWidth / 2
            if rhythm[step] {
                fill(accent)
                drawCircle(x, y, 8)
            } else {
                fill(faint)
                drawCircle(x, y, 3)
            }
        }

        fill(ink)
        textSize(14)
        textAlign(.right, .middle)
        drawText(rhythm.intervals.map(String.init).joined(separator: " "), 840, y)
    }

    /// The same rhythm as the shape between its strikes, which is how the
    /// paper that named these draws them.
    private func drawWheel(_ rhythm: Rhythm, name: String, at center: Vector2) {
        let radius = 66.0
        let place = { (step: Int) -> Vector2 in
            let angle = Double(step) / Double(rhythm.length) * .tau - .pi / 2
            return center + Vector2(cos(angle), sin(angle)) * radius
        }

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawCircle(center: center, radius: radius)

        stroke(accent.withAlpha(0.75))
        strokeWeight(1.6)
        drawPolygon(rhythm.onsets.map(place))

        noStroke()
        for step in 0..<rhythm.length {
            if rhythm[step] {
                fill(accent)
                drawCircle(center: place(step), radius: 6)
            } else {
                fill(faint)
                drawCircle(center: place(step), radius: 2.5)
            }
        }

        fill(ink)
        textSize(15)
        textAlign(.center, .top)
        drawText(name, center.x, center.y + radius + 22)
        fill(soft)
        textSize(13)
        drawText("\(rhythm)".map(String.init).joined(separator: " "),
                 center.x, center.y + radius + 44)
    }
}
