// figure: frame=0 themed
//
// Guide diagram (Chapter 29): what the step sequencer and the arpeggiator do
// to time. Every mark is read off the types themselves through
// `events(upTo:)`, so the picture cannot drift from what they compute. Top:
// one bar of sixteen steps straight and at two swings, the offbeats moved and
// the downbeats not. Middle: one lane over four bars, with a soft step, a step
// left to chance, and a ratchet, showing which bars the chance step played
// on. Bottom: an arpeggiator climbing three held notes, a fourth joining the
// ladder mid-pass, and the same notes played up and down over two octaves.
import Ollin
import OllinDiagram
import OllinAudio

final class SequencerFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 760) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    let left = 150.0
    let right = 840.0
    var barWidth: Double { right - left }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        noStroke()

        drawSwing(top: 34)
        drawChanceAndRatchet(top: 250)
        drawArpeggiator(top: 470)
    }

    // MARK: Swing

    private func drawSwing(top: Double) {
        heading("swing", at: top)
        let rows: [(String, Double)] = [("straight", 0.5), ("swing 0.58", 0.58), ("swing 0.67", 2.0 / 3)]

        for (row, entry) in rows.enumerated() {
            let y = top + 40 + Double(row) * 44
            var sequencer = StepSequencer(Array(repeating: Pitch(60), count: 16), swing: entry.1)
            let notes = sequencer.events(upTo: 3.99)

            fill(soft)
            textSize(14)
            textAlign(.right, .middle)
            drawText(entry.0, left - 16, y)

            // The grid every step would land on straight.
            for step in 0..<16 {
                let x = left + Double(step) / 16 * barWidth
                fill(step % 4 == 0 ? theme.ink(0.3) : faint)
                drawRect(x - 0.5, y - 9, 1, 18)
            }

            for note in notes {
                let x = left + note.beat / 4 * barWidth
                let straight = left + Double(note.step) / 16 * barWidth
                if abs(x - straight) > 0.5 {
                    // The move, from where the step would have been.
                    stroke(accent.withAlpha(0.45))
                    strokeWeight(1.2)
                    drawLine(straight, y, x, y)
                    noStroke()
                }
                fill(note.step % 2 == 0 ? ink : accent)
                drawCircle(x, y, note.step % 2 == 0 ? 6 : 5)
            }
        }

        // The size of the last row's move, read off the notes themselves.
        var swung = StepSequencer(Array(repeating: Pitch(60), count: 16), swing: 2.0 / 3)
        let moved = swung.events(upTo: 0.49)
        let shift = (moved[1].beat - 0.25) / 0.25
        fill(soft)
        textSize(13)
        textAlign(.left, .middle)
        drawText("offbeats +\(Int((shift * 100).rounded()))% of a step; downbeats stay",
                 left, top + 40 + 3 * 44 - 4)
    }

    // MARK: Chance and ratchet

    private func drawChanceAndRatchet(top: Double) {
        heading("velocity, chance, ratchet", at: top)

        var lane = StepSequencer("36 . 36 . 36 . 36 36 . 36 . 36 . 36 . 36")
        lane[2] = StepSequencer.Step(Pitch(36), velocity: 0.35)
        lane[6] = StepSequencer.Step(Pitch(36), probability: 0.5)
        lane[14] = StepSequencer.Step(Pitch(36), ratchet: 3)
        lane.seed = 12
        lane.maxCatchUp = 64

        let cell = barWidth / 16
        let labels: [(Int, String)] = [(2, "velocity 0.35"), (6, "chance 0.5"), (14, "ratchet 3")]
        fill(soft)
        textSize(13)
        textAlign(.center, .bottom)
        for (step, label) in labels {
            drawText(label, left + (Double(step) + 0.5) * cell, top + 32)
        }

        for bar in 0..<4 {
            let y = top + 46 + Double(bar) * 36
            let played = lane.events(upTo: Double(bar + 1) * 4 - 0.01)
            fill(soft)
            textSize(14)
            textAlign(.right, .middle)
            drawText("bar \(bar + 1)", left - 16, y + 12)

            for step in 0..<16 {
                let x = left + Double(step) * cell
                let entry = lane[step]
                fill(faint)
                drawRect(x + 2, y, cell - 4, 24, cornerRadius: 3)
                guard !entry.isRest else { continue }

                let strikes = played.filter { $0.step % 16 == step }
                if strikes.isEmpty {
                    // A chance step that stayed quiet this bar.
                    noFill()
                    stroke(accent.withAlpha(0.6))
                    strokeWeight(1.2)
                    drawRect(x + 2, y, cell - 4, 24, cornerRadius: 3)
                    noStroke()
                    continue
                }
                let height = 24 * (0.3 + 0.7 * entry.velocity)
                let width = (cell - 4 - Double(strikes.count - 1) * 2) / Double(strikes.count)
                fill(accent)
                for (index, _) in strikes.enumerated() {
                    drawRect(x + 2 + Double(index) * (width + 2), y + 24 - height, width, height, cornerRadius: 2)
                }
            }
        }

        fill(soft)
        textSize(13)
        textAlign(.left, .middle)
        drawText("a bar as tall as its velocity; an outline where a chance step stayed quiet; a ratchet split into its strikes",
                 left, top + 46 + 4 * 36 + 6)
    }

    // MARK: Arpeggiator

    private func drawArpeggiator(top: Double) {
        heading("arpeggiator", at: top)

        // Three notes held, a fourth joining after five steps.
        var joins = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], .up)
        var first = joins.events(upTo: 1.24)
        joins.hold(Pitch(71))
        first += joins.events(upTo: 3.99)

        var turns = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], .upDown, octaves: 2)
        let second = turns.events(upTo: 3.99)

        let rows: [(String, [ScheduledNote], Int?)] = [
            (".up, B4 joins at step 5", first, 5),
            (".upDown, octaves: 2", second, nil),
        ]
        let pitches: [Double] = [60, 64, 67, 71, 72, 76, 79]
        let names = ["C4", "E4", "G4", "B4", "C5", "E5", "G5"]

        for (row, entry) in rows.enumerated() {
            let y0 = top + 36 + Double(row) * 128
            let height = 96.0
            // One rung per pitch the figure can reach, evenly spaced, so
            // the semitone between B4 and C5 does not stack their labels.
            func y(_ midi: Double) -> Double {
                let rung = Double(pitches.firstIndex(of: midi) ?? 0)
                return y0 + height - rung / Double(pitches.count - 1) * height
            }
            let cell = barWidth / 16

            fill(soft)
            textSize(13)
            textAlign(.left, .bottom)
            drawText(entry.0, left, y0 - 6)

            // The ladder, one rung per pitch the figure can reach.
            for (midi, name) in zip(pitches, names) {
                stroke(faint)
                strokeWeight(1)
                drawLine(left, y(midi), right, y(midi))
                noStroke()
                fill(soft)
                textSize(11)
                textAlign(.right, .middle)
                drawText(name, left - 10, y(midi))
            }

            var previous: Vector2?
            for note in entry.1 {
                let at = Vector2(left + (Double(note.step) + 0.5) * cell, y(note.pitch.midi))
                if let previous {
                    stroke(accent.withAlpha(0.35))
                    strokeWeight(1.2)
                    drawLine(previous, at)
                    noStroke()
                }
                previous = at
            }
            for note in entry.1 {
                let at = Vector2(left + (Double(note.step) + 0.5) * cell, y(note.pitch.midi))
                let joined = entry.2.map { note.step >= $0 && note.pitch == Pitch(71) } ?? false
                fill(joined ? ink : accent)
                drawCircle(center: at, radius: 5)
            }

            if let join = entry.2 {
                let x = left + Double(join) * cell
                stroke(theme.ink(0.35))
                strokeWeight(1)
                drawLine(x, y0 - 2, x, y0 + height + 2)
                noStroke()
            }
        }
    }

    private func heading(_ text: String, at y: Double) {
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(text, 40, y)
    }
}
