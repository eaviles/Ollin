// figure: frame=0
//
// Guide figure (Chapter 27): what the phone hears, as a level and as a trigger.
// Four sounds over eight seconds of staged readings, one window every three
// quarters of a second, run through the real PhoneSounds: each row is the
// phone's confidence in one label as a filled curve, the threshold a dashed line
// across it, and a ring wherever that label climbed over the line, drawn at the
// end of the window that crossed, which is the time the event carries. Speech
// climbs once and stays, so it rings once; the dog barks twice and rings twice;
// music hovers under the line and never rings, though its level is there.
//
// The readings are staged rather than heard, the way this chapter's other
// figures stage a phone: the same object a phone feeds, fed by hand, so the
// figure renders anywhere and says exactly what was heard.
import Foundation
import Ollin
import OllinPhone

final class HeardAsMarks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let paper = Color(hex: 0x0D1017)
    let ink = Color(hex: 0xF2EBDD)
    let warm = Color(hex: 0xFFB84D)
    let cool = Color(hex: 0x7FE0D4)

    /// The window the phone judges, and how often a reading arrives.
    static let window = 1.5
    static let hop = 0.75
    static let seconds = 8.0

    static let labels = ["speech", "dog_bark", "clapping", "music"]

    /// Each label's confidence per reading, in reading order: what a phone
    /// would have sent over eight seconds of a room with a person talking, a
    /// dog barking twice, one clap, and a radio too faint to count.
    static let readings: [[Double]] = {
        let count = Int(seconds / hop) + 1
        return (0..<count).map { i in
            let t = Double(i) * hop
            let speech = t < 1.5 ? 0.12 + 0.2 * t : min(0.92, 0.45 + 0.25 * (t - 1.5))
            let bark = max(0.05, 0.95 * exp(-pow((t - 2.25) / 0.45, 2))
                          + 0.85 * exp(-pow((t - 6.0) / 0.45, 2)))
            let clap = max(0.04, 0.88 * exp(-pow((t - 4.5) / 0.3, 2)))
            let music = 0.5 + 0.08 * sin(t * 1.7)
            return [speech, bark, clap, music]
        }
    }()

    /// The rings: (label index, time), read off the object rather than guessed.
    var rings: [(Int, Double)] = []

    override func setup() {
        noLoop()
        let ears = PhoneSounds()
        for (i, reading) in Self.readings.enumerated() {
            let at = Double(i) * Self.hop
            ears.hear(zip(Self.labels, reading).map { SoundClassification(label: $0, confidence: $1) },
                      at: at, duration: Self.window)
            for event in ears.events() {
                guard let row = Self.labels.firstIndex(of: event.label) else { continue }
                rings.append((row, event.time))
            }
        }
    }

    override func draw() {
        background(paper)
        let left = 150.0, right = width - 40
        let top = 70.0, rowHeight = 108.0, curveHeight = 72.0
        let threshold = 0.6
        let span = Self.seconds + Self.window

        func x(_ t: Double) -> Double { left + (right - left) * t / span }

        for (row, label) in Self.labels.enumerated() {
            let base = top + rowHeight * Double(row) + curveHeight
            withState {
                // The level, as a filled curve: each reading's confidence held
                // from the start of its window to the start of the next.
                // The level, held from the start of each window to the start of
                // the next: one stepped shape, filled, under a stepped line.
                var steps: [Vector2] = []
                for (i, reading) in Self.readings.enumerated() {
                    let t0 = Double(i) * Self.hop, t1 = t0 + Self.hop
                    let y = base - curveHeight * reading[row]
                    steps.append(Vector2(x(t0), y))
                    steps.append(Vector2(x(t1), y))
                }
                let end = x(Double(Self.readings.count) * Self.hop)
                noStroke()
                fill(cool.withAlpha(0.28))
                drawShape { path in
                    path.move(to: Vector2(x(0), base))
                    for step in steps { path.line(to: step) }
                    path.line(to: Vector2(end, base))
                    path.close()
                }
                stroke(cool)
                strokeWeight(2)
                noFill()
                drawPolyline(steps)

                // The threshold, dashed across the row.
                stroke(ink.withAlpha(0.45))
                strokeWeight(1)
                let ty = base - curveHeight * threshold
                var t = 0.0
                while t < span {
                    drawLine(x(t), ty, x(min(span, t + 0.18)), ty)
                    t += 0.36
                }

                // The baseline and the label.
                stroke(ink.withAlpha(0.2))
                drawLine(left, base, right, base)
                noStroke()
                fill(ink.withAlpha(0.85))
                textFont(OutlineFont.system)
                textSize(20)
                textAlign(.right)
                drawText(label.replacingOccurrences(of: "_", with: " "),
                         at: Vector2(left - 18, base - 22))
            }

            // A ring wherever this label crossed the line, at the end of the
            // window it crossed in, which is the time the event carries.
            for (r, when) in rings where r == row {
                withState {
                    noFill()
                    stroke(warm)
                    strokeWeight(3)
                    drawCircle(x(when), base - curveHeight * threshold, 13)
                    strokeWeight(1)
                    stroke(warm.withAlpha(0.5))
                    drawCircle(x(when), base - curveHeight * threshold, 22)
                }
            }
        }

        // The clock along the bottom, and the caption.
        withState {
            noStroke()
            fill(ink.withAlpha(0.55))
            textFont(OutlineFont.system)
            textSize(16)
            textAlign(.center)
            let axis = top + rowHeight * Double(Self.labels.count) + 4
            for s in stride(from: 0.0, through: Self.seconds, by: 2) {
                drawText("\(Int(s)) s", at: Vector2(x(s), axis))
            }
            textSize(17)
            drawText("the level is the curve, the threshold the dashed line, and a ring is a crossing from below",
                     at: Vector2((left + right) * 0.5, height - 26))
        }
    }
}
