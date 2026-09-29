// figure: frame=0 themed
//
// Guide diagram (Chapter 40): the seven named tunings on one axis in cents,
// from the root to three times its frequency. Each row marks every pitch the
// tuning has in that span, read off the tuning's own subscript, so the
// octave tunings repeat their pattern past the octave line and Bohlen-Pierce
// runs on to the line at three. In each octave tuning the pitch nearest a
// just major third (386 cents) is marked in the accent, with its value under
// the row's name: equal temperament's is 400, just intonation's 386.
import Ollin
import OllinDiagram
import OllinAudio

final class Tunings: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let axisLeft = 270.0
    let axisRight = 840.0
    let span = 1200 * log2(3.0)          // the root to three times its frequency

    func x(ofCents cents: Double) -> Double {
        axisLeft + cents / span * (axisRight - axisLeft)
    }

    override func draw() {
        background(theme.paper)

        let rows: [(name: String, tuning: Tuning)] = [
            ("equal temperament", .equalTemperament),
            ("just intonation", .just),
            ("pythagorean", .pythagorean),
            ("quarter tones", .quarterTones),
            ("nineteen", .nineteen),
            ("thirty-one", .thirtyOne),
            ("Bohlen-Pierce", .bohlenPierce),
        ]

        // The octave and the ratio three, as guides through every row.
        let top = 70.0, bottom = 452.0
        stroke(theme.ink(0.25))
        strokeWeight(1.5)
        drawLine(x(ofCents: 0), top, x(ofCents: 0), bottom)
        drawLine(x(ofCents: 1200), top, x(ofCents: 1200), bottom)
        drawLine(x(ofCents: span), top, x(ofCents: span), bottom)
        noStroke()
        fill(theme.muted)
        textSize(14)
        textAlign(.center, .bottom)
        drawText("root", x(ofCents: 0), top - 6)
        drawText("octave, 2 times", x(ofCents: 1200), top - 6)
        drawText("3 times", x(ofCents: span), top - 6)

        for (i, row) in rows.enumerated() {
            let y = 104 + Double(i) * 52
            drawRow(row.name, row.tuning, y: y)
        }

        // The cents ruler under the rows.
        stroke(theme.ink(0.5))
        strokeWeight(1)
        drawLine(axisLeft, bottom + 8, axisRight, bottom + 8)
        noStroke()
        fill(theme.muted)
        textSize(12)
        textAlign(.center, .top)
        for cents in stride(from: 0.0, through: 1800, by: 300) {
            drawText("\(Int(cents))", x(ofCents: cents), bottom + 14)
        }
        textAlign(.left, .top)
        drawText("cents above the root", 40, bottom + 14)

        diagramCaption("six repeat at the octave, and Bohlen-Pierce at three times the root",
                       at: 500, theme: theme)
    }

    func drawRow(_ name: String, _ tuning: Tuning, y: Double) {
        // Every pitch the tuning has between the root and three times it.
        var cents: [Double] = []
        var degree = 0
        while true {
            let c = 100 * (tuning[degree].midi - tuning.root.midi)
            if c > span + 0.5 { break }
            cents.append(c)
            degree += 1
        }

        let octaveTuning = abs(tuning.period - 2) < 1e-9
        let third = octaveTuning
            ? cents.min { abs($0 - 386.3) < abs($1 - 386.3) }
            : nil

        stroke(theme.ink(0.15))
        strokeWeight(1)
        drawLine(axisLeft, y, axisRight, y)

        stroke(theme.ink(0.8))
        strokeWeight(2)
        for c in cents where c != third {
            drawLine(x(ofCents: c), y - 11, x(ofCents: c), y + 11)
        }
        if let third {
            stroke(theme.accent)
            strokeWeight(3)
            drawLine(x(ofCents: third), y - 15, x(ofCents: third), y + 15)
        }

        noStroke()
        fill(theme.ink)
        textSize(15)
        textAlign(.left, .bottom)
        drawText(name, 40, y - 1)
        fill(theme.muted)
        textSize(12)
        textAlign(.left, .top)
        if let third {
            drawText("\(tuning.degreeCount) to the octave, third at \(Int(third.rounded()))", 40, y + 3)
        } else {
            drawText("\(tuning.degreeCount) steps to 3 times, no octave", 40, y + 3)
        }
    }
}
