// figure: frame=0
//
// Guide diagram (Chapter 29): why a plucked string is a model rather than a
// wave. The top panel is the loop itself, labeled. Below it, the same note
// plucked at four points along the string: the shape is the sum of the modes
// that pluck actually excites, and the bars beside it are those modes, so the
// missing ones are visible as gaps rather than described.
import Ollin
import OllinAudio

final class PluckedString: Sketch {
    override var canvasSize: CanvasSize { .size(880, 720) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.5)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        drawLoop(top: 46)

        let picks = [0.5, 0.33, 0.2, 0.08]
        for (row, pick) in picks.enumerated() {
            drawPluck(pick: pick, y: 300 + Double(row) * 102)
        }

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center, .top)
        drawText("the shape a pluck leaves, and the modes it puts into the sound",
                 440, 690)
    }

    /// The loop the sound actually comes out of.
    private func drawLoop(top: Double) {
        let boxes: [(String, Double, Double)] = [
            ("delay line", 96, 132),
            ("loses its top", 262, 118),
            ("tunes the rest", 414, 122),
            ("keeps a little less", 572, 146),
        ]

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("one period of delay, and what it loses going round", 40, top)

        let middle = top + 62
        var x = 40.0
        for (label, _, boxWidth) in boxes {
            noFill()
            stroke(soft)
            strokeWeight(1.2)
            drawRect(corner: Vector2(x, middle - 20), width: boxWidth, height: 40)
            noStroke()
            fill(ink)
            textSize(12)
            textAlign(.center, .middle)
            drawText(label, x + boxWidth / 2, middle)

            stroke(soft)
            strokeWeight(1.2)
            drawLine(x + boxWidth, middle, x + boxWidth + 22, middle)
            noStroke()
            x += boxWidth + 22
        }

        // The way back round, which is what makes it a loop rather than a chain.
        stroke(accent)
        strokeWeight(1.4)
        drawLine(x, middle, x + 18, middle)
        drawLine(x + 18, middle, x + 18, middle + 44)
        drawLine(x + 18, middle + 44, 40, middle + 44)
        drawLine(40, middle + 44, 40, middle)
        noStroke()
        fill(accent)
        drawCircle(40, middle, 4)
        fill(soft)
        textSize(12)
        textAlign(.center, .top)
        drawText("and round again", (x + 58) / 2, middle + 50)

        stroke(faint)
        strokeWeight(1)
        drawLine(40, top + 200, 840, top + 200)
        noStroke()
    }

    /// One pluck: the shape it leaves, and the modes that shape is made of.
    private func drawPluck(pick: Double, y: Double) {
        let left = 130.0
        let span = 380.0

        // The modes a pluck at this point excites. A mode with a node under the
        // finger gets nothing, which is what the missing bars show.
        let amplitudes = (1...12).map { mode -> Double in
            let harmonic = Double(mode)
            return sin(harmonic * .pi * pick) / (harmonic * harmonic)
        }

        func displacement(at along: Double) -> Double {
            amplitudes.enumerated().reduce(0.0) { total, entry in
                total + entry.element * sin(Double(entry.offset + 1) * .pi * along)
            }
        }

        let tallest = max(1e-6, abs(displacement(at: pick)))
        var outline = [Vector2]()
        for step in 0...120 {
            let along = Double(step) / 120
            outline.append(Vector2(left + along * span,
                                   y - displacement(at: along) / tallest * 30))
        }

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, left + span, y)
        stroke(accent)
        strokeWeight(1.6)
        noFill()
        drawPolyline(outline)

        noStroke()
        fill(accent)
        drawCircle(left + pick * span, y - 30, 4)
        fill(soft)
        textSize(12)
        textAlign(.right, .middle)
        drawText("pick \(String(format: "%.2f", pick))", left - 14, y)

        // The same fact as bars: how much of each mode the pluck put in.
        let barLeft = 578.0
        let barSpan = 250.0
        let biggest = amplitudes.map { abs($0) }.max() ?? 1
        for (index, amplitude) in amplitudes.enumerated() {
            let x = barLeft + Double(index) / 12 * barSpan
            let height = abs(amplitude) / biggest * 40
            fill(height < 0.8 ? faint : accent)
            drawRect(corner: Vector2(x, y + 20 - height), width: barSpan / 12 - 5, height: max(1.5, height))
        }
        fill(soft)
        textSize(11)
        textAlign(.left, .top)
        drawText("modes 1 to 12", barLeft, y + 26)
    }
}
