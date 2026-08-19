// figure: frame=0
//
// Guide diagram (Chapter 21): that the frequencies a shape rings at come out of
// its outline. Each row is a real StruckShape, measured by the same code the
// sketch runs, so the numbers beside each outline are not illustrations of the
// idea: they are the answer. The circle's are the zeros of the Bessel
// functions, which is what a real drumhead rings at, and it has each of them
// twice because a pattern that fits at one rotation fits at another.
import Ollin
import OllinAudio

final class StruckShapes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 640) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.5)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("what an outline rings at", 40, 40)
        fill(soft)
        textSize(12)
        textAlign(.left, .top)
        drawText("each tone as a multiple of the lowest, drawn where it falls", 40, 58)

        let outlines: [(String, Shape)] = [
            ("circle", Self.polygon(sides: 96, radius: 44)),
            ("square", Self.polygon(sides: 4, radius: 46, turn: .pi / 4)),
            ("triangle", Self.polygon(sides: 3, radius: 52)),
            ("oblong", Self.oblong(width: 108, height: 44)),
            ("blob", Self.blob(radius: 46)),
        ]

        for (row, entry) in outlines.enumerated() {
            drawRow(name: entry.0, outline: entry.1, y: 130 + Double(row) * 100)
        }

        fill(soft)
        textSize(12)
        textAlign(.center, .top)
        drawText("a symmetric shape rings at some tones twice, because a pattern that fits "
                 + "at one turn fits at another", 440, 610)
    }

    private func drawRow(name: String, outline: Shape, y: Double) {
        withState {
            translate(160, y)
            noStroke()
            fill(faint)
            drawShape(outline)
            noFill()
            stroke(accent)
            strokeWeight(1.5)
            drawShape(outline)
        }

        noStroke()
        fill(ink)
        textSize(14)
        textAlign(.right, .middle)
        drawText(name, 96, y)

        guard let measured = StruckShape(outline, modes: 10, resolution: 40) else { return }

        // The scale runs from one to four, which is where these all live.
        let left = 268.0
        let span = 520.0
        let place = { (ratio: Double) in left + (ratio - 1) / 3 * span }

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y + 26, left + span, y + 26)
        noStroke()
        fill(soft)
        textSize(10)
        textAlign(.center, .top)
        for tick in [1.0, 2.0, 3.0, 4.0] {
            drawText(String(format: "%.0f", tick), place(tick), y + 30)
        }

        // Tones that land on top of each other are drawn side by side, so a
        // doubled one reads as two rather than as a slightly fatter one.
        var drawn = [Double]()
        for ratio in measured.ratios where ratio <= 4.02 {
            let repeats = drawn.count { abs($0 - ratio) < 0.02 }
            drawn.append(ratio)
            let x = place(ratio) + Double(repeats) * 3.5
            stroke(accent)
            strokeWeight(1.8)
            drawLine(x, y - 22, x, y + 22)
            noStroke()
        }

        fill(ink)
        textSize(11)
        textAlign(.left, .middle)
        drawText(measured.ratios.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: "  "),
                 left, y - 36)
    }

    private static func polygon(sides: Int, radius: Double, turn: Double = 0) -> Shape {
        Shape((0..<sides).map { step in
            let angle = Double(step) / Double(sides) * .tau - .pi / 2 + turn
            return Vector2(cos(angle), sin(angle)) * radius
        })
    }

    private static func oblong(width: Double, height: Double) -> Shape {
        Shape([Vector2(-width / 2, -height / 2), Vector2(width / 2, -height / 2),
               Vector2(width / 2, height / 2), Vector2(-width / 2, height / 2)])
    }

    private static func blob(radius: Double) -> Shape {
        Shape((0..<120).map { step in
            let angle = Double(step) / 120 * .tau
            let wobble = 1 + 0.26 * sin(angle * 3 + 0.7) + 0.13 * sin(angle * 5 - 1.9)
            return Vector2(cos(angle), sin(angle)) * radius * wobble
        })
    }
}
