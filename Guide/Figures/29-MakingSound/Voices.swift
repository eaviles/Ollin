// figure: frame=0 themed
//
// Guide diagram (Chapter 29): the four numbers that shape a note, and what
// different settings of them sound like. Each curve is the real envelope, read
// from Envelope.level(at:heldFor:), which is the same shape the voices play.
// The top one is labeled with its parts; the rest are presets, drawn to the
// same scale so the differences between them are the point.
import Ollin
import OllinDiagram
import OllinAudio

final class Voices: Sketch {
    override var canvasSize: CanvasSize { .size(880, 630) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.45) }
    var faint: Color { theme.ink(0.14) }
    var accent: Color { theme.accent }

    let left = 70.0, plotWidth = 740.0
    /// Every curve is drawn over the same three seconds, so they compare.
    let span = 3.0
    /// The key is let go here, which is where release begins.
    let hold = 1.4

    override func draw() {
        background(paper)

        drawCurve(Envelope(attack: 0.35, decay: 0.5, sustain: 0.55, release: 0.7),
                  top: 88, height: 120, name: "Envelope",
                  note: "attack, decay, sustain, release", detail: true)

        let presets: [(String, Envelope, String)] = [
            ("percussive", .percussive, "struck and gone: holding the key adds nothing"),
            ("organ", .organ, "on while held, off when let go"),
            ("swell", .swell, "slow in and slow out, so notes overlap each other"),
        ]
        for (index, entry) in presets.enumerated() {
            drawCurve(entry.1, top: 316 + Double(index) * 108, height: 60,
                      name: entry.0, note: entry.2, detail: false)
        }

        fill(soft)
        textSize(14)
        textAlign(.left, .top)
        drawText("all four over the same 3 seconds, key let go at 1.4 s", left, 600)
    }

    private func drawCurve(
        _ envelope: Envelope, top: Double, height: Double,
        name: String, note: String, detail: Bool
    ) {
        let baseline = top + height

        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        // Measured at the size it is drawn at, before the note's smaller one.
        let nameWidth = Double(textWidth(name))
        drawText(name, left, top - 12)
        fill(soft)
        textSize(13)
        drawText(note, left + nameWidth + 18, top - 13)

        stroke(faint)
        strokeWeight(1)
        drawLine(left, baseline, left + plotWidth, baseline)

        // Where the key is let go, which is the only event in the picture.
        let releaseX = left + plotWidth * hold / span
        drawLine(releaseX, top - 6, releaseX, baseline + 6)

        // The envelope itself, asked for the way a sketch would ask.
        let steps = 700
        let points = (0...steps).map { step -> Vector2 in
            let t = span * Double(step) / Double(steps)
            let level = envelope.level(at: t, heldFor: hold)
            return Vector2(left + plotWidth * Double(step) / Double(steps),
                           baseline - level * height)
        }
        stroke(accent)
        strokeWeight(2.5)
        noFill()
        drawPolyline(points)
        noStroke()

        guard detail else { return }

        // Sustain is the one that is a level rather than a length.
        let sustainY = baseline - envelope.sustain * height
        stroke(soft)
        strokeWeight(1)
        drawLine(left, sustainY, left + plotWidth, sustainY)
        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.right, .bottom)
        drawText("sustain is a level, not a time", left + plotWidth, sustainY - 6)

        // Name the four parts under the segments they actually cover.
        let marks: [(String, Double, Double)] = [
            ("attack", 0, envelope.attack),
            ("decay", envelope.attack, envelope.attack + envelope.decay),
            ("sustain", envelope.attack + envelope.decay, hold),
            ("release", hold, hold + envelope.release),
        ]
        for (label, start, end) in marks {
            let x0 = left + plotWidth * start / span
            let x1 = left + plotWidth * min(end, span) / span
            stroke(soft)
            strokeWeight(1)
            drawLine(x0, baseline + 16, x1, baseline + 16)
            drawLine(x0, baseline + 12, x0, baseline + 20)
            drawLine(x1, baseline + 12, x1, baseline + 20)
            noStroke()
            fill(ink)
            textSize(14)
            textAlign(.center, .top)
            drawText(label, (x0 + x1) / 2, baseline + 24)
        }
    }
}
