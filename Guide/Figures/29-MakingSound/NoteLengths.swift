// figure: frame=0 themed
//
// Guide diagram (Chapter 29): what a Tempo and a NoteLength say. One bar of
// four beats at 96 beats a minute runs across the top, each beat marked with
// the second it lands on. Under it, the named lengths are laid across that
// same bar as many times as they fit. Every width, every name, and every
// number is read off the two types themselves, so the picture cannot drift
// from what they compute.
import Ollin
import OllinDiagram

final class NoteLengths: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    let tempo = Tempo(96)
    let left = 200.0
    let right = 720.0
    var beatWidth: Double { (right - left) / Double(tempo.beatsPerBar) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        noStroke()

        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText("Tempo(96)", 40, 40)
        fill(soft)
        textSize(14)
        textAlign(.right, .middle)
        drawText("a beat is \(seconds(tempo.secondsPerBeat)), a bar \(seconds(tempo.secondsPerBar))", 840, 40)

        drawBar(y: 92)

        let lengths: [NoteLength] = [
            .whole, .half, .quarter, .eighth, .sixteenth, .quarter.dotted, .eighth.triplet,
        ]
        for (index, length) in lengths.enumerated() {
            drawRow(length, y: 160 + Double(index) * 42)
        }
    }

    /// One bar: a tick per beat, numbered above and timed below.
    private func drawBar(y: Double) {
        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, right, y)
        for beat in 0 ... tempo.beatsPerBar {
            let x = left + Double(beat) * beatWidth
            stroke(soft)
            drawLine(x, y - 7, x, y + 7)
            noStroke()
            fill(soft)
            textSize(12)
            textAlign(.center, .bottom)
            drawText("beat \(beat)", x, y - 12)
            textAlign(.center, .top)
            drawText(seconds(tempo.seconds(beats: Double(beat))), x, y + 12)
        }
        noStroke()
    }

    /// One length laid across the bar as many times as it fits, its name and
    /// its width from the type, its seconds from the tempo.
    private func drawRow(_ length: NoteLength, y: Double) {
        fill(ink)
        textSize(15)
        textAlign(.right, .middle)
        drawText("\(length)", left - 18, y)

        let width = length.beats * beatWidth
        var x = left
        var count = 0
        while x + width <= right + 0.5 {
            fill(count == 0 ? accent : accent.withAlpha(0.32))
            drawRect(x + 1.5, y - 11, width - 3, 22, cornerRadius: 4)
            x += width
            count += 1
        }

        fill(soft)
        textSize(14)
        textAlign(.left, .middle)
        drawText(seconds(tempo.seconds(of: length)), right + 18, y)
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.3g s", value)
    }
}
