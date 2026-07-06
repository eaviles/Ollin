// figure: frame=0
//
// Guide diagram: phase. Top: the same wave twice, one copy started a little
// later; the horizontal shift between them is the phase. Bottom: a row of
// dots running the same swing, each with a slightly bigger head start, read
// at one instant: a wave appears in space.
import Ollin

final class Phase: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        // Top: two traces, the accent one lagging by `phase`.
        let left = 80.0, right = 800.0
        let midY = 150.0, swing = 62.0
        let turns = 2.0
        let phase = Double.tau / 6

        func traceX(_ a: Double) -> Double { left + a / (.tau * turns) * (right - left) }

        stroke(faint)
        strokeWeight(2)
        drawLine(left, midY, right, midY)

        func wave(_ shift: Double) -> [Vector2] {
            var points: [Vector2] = []
            var a = 0.0
            while a <= .tau * turns {
                points.append(Vector2(traceX(a), midY - sin(a - shift) * swing))
                a += 0.02
            }
            return points
        }
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawPolyline(wave(0))
        stroke(accent)
        drawPolyline(wave(phase))

        // The shift between matching crests, bracketed.
        let crestA = traceX(.tau * 0.25)
        let crestB = traceX(.tau * 0.25 + phase)
        let bracketY = midY - swing - 22
        stroke(ink)
        strokeWeight(2)
        drawLine(crestA, bracketY, crestB, bracketY)
        drawLine(crestA, bracketY - 7, crestA, bracketY + 7)
        drawLine(crestB, bracketY - 7, crestB, bracketY + 7)
        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.left, .middle)
        drawText("phase: the head start", crestB + 16, bracketY)
        textAlign(.left, .top)
        drawText("the same wave, started a little later", left + 4, midY + swing + 20)

        // Bottom: one instant of 26 swings with growing head starts.
        let rowY = 420.0, rowSwing = 60.0
        let snapshot = 0.9
        stroke(faint)
        strokeWeight(2)
        drawLine(left, rowY, right, rowY)
        noStroke()
        for i in 0..<26 {
            let x = left + 24 + Double(i) / 25 * (right - left - 48)
            let headStart = Double(i) * 0.42
            fill(ink)
            drawCircle(x, rowY - sin(snapshot - headStart) * rowSwing, 9)
        }
        fill(ink)
        textAlign(.center, .top)
        drawText("the same swing with growing head starts, at one instant: a wave in space",
                 width / 2, rowY + rowSwing + 20)
    }
}
