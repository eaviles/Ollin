// figure: frame=0
//
// Guide diagram (Chapter 28): how numbers become notes, and the two decisions
// that are easy to get wrong. Every pitch drawn here is read out of a real
// Sonification through pitch(for:) or its subscript, so the picture cannot
// drift from what the type does; the hertz row is the counterfactual, computed
// alongside it, which is the whole point of showing it.
import Ollin
import OllinAudio

final class SonificationFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 720) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.14)
    let accent = Color(hex: 0xE4572E)
    let cool = Color(hex: 0x3A6EA5)

    // A short profile with a clear shape: up, down, up again.
    let series: [Double] = [0.05, 0.22, 0.55, 0.82, 0.97, 0.74, 0.38, 0.16,
                            0.29, 0.61, 0.88, 0.66, 0.41, 0.19, 0.08, 0.34]

    let low = Pitch("C3"), high = Pitch("C6")

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let chromatic = Sonification(series, pitches: low...high, bounds: .fixed(0...1))
        let snapped = Sonification(series, in: Scale(.minorPentatonic, root: "C3"),
                                   pitches: low...high, bounds: .fixed(0...1))

        title("Numbers become notes", at: Vector2(48, 54))
        caption("A series spread over three octaves. Every note below is read out of a real "
                + "Sonification.", at: Vector2(48, 80))

        drawSeries(top: 112)
        drawMapping(top: 232, reading: chromatic,
                    label: "spread evenly in semitones",
                    note: "what hearing does: every step the same size",
                    byFrequency: false)
        drawMapping(top: 396, reading: chromatic,
                    label: "spread evenly in hertz",
                    note: "the obvious thing, and wrong: the low half is crushed",
                    byFrequency: true)
        drawSnapped(top: 560, reading: snapped)
    }

    // MARK: The data

    private func drawSeries(top: Double) {
        label("the numbers", at: Vector2(48, top))
        let frame = Rectangle(x: 232, y: top - 12, width: 600, height: 74)
        noStroke()
        for (index, value) in series.enumerated() {
            let x = frame.x + frame.width * (Double(index) + 0.5) / Double(series.count)
            let barHeight = 8 + value * (frame.height - 10)
            fill(cool.withAlpha(0.30))
            drawRect(center: Vector2(x, frame.y + frame.height - barHeight / 2),
                     width: 26, height: barHeight)
        }
        stroke(faint)
        strokeWeight(1)
        drawLine(frame.x, frame.y + frame.height, frame.x + frame.width, frame.y + frame.height)
    }

    // MARK: The two mappings

    /// One row of note positions. `byFrequency` computes the counterfactual:
    /// the same data spread evenly between the two end *frequencies* instead of
    /// between the two end pitches.
    private func drawMapping(top: Double, reading: Sonification,
                             label text: String, note: String, byFrequency: Bool) {
        label(text, at: Vector2(48, top))
        caption(note, at: Vector2(48, top + 22), width: 170)

        let frame = Rectangle(x: 232, y: top - 16, width: 600, height: 108)
        drawOctaveLines(in: frame)

        // Where each reading lands, as a height inside the pitch span.
        func placed(_ value: Double) -> Double {
            let midi: Double
            if byFrequency {
                let hz = low.frequency + (high.frequency - low.frequency) * value
                midi = 69 + 12 * log2(hz / 440)
            } else {
                midi = reading.pitch(for: value).midi
            }
            let t = (midi - low.midi) / (high.midi - low.midi)
            return frame.y + frame.height - min(max(t, 0), 1) * frame.height
        }

        var dots = [Vector2]()
        for (index, value) in series.enumerated() {
            let x = frame.x + frame.width * (Double(index) + 0.5) / Double(series.count)
            dots.append(Vector2(x, placed(value)))
        }

        noFill()
        stroke((byFrequency ? accent : cool).withAlpha(0.5))
        strokeWeight(1.5)
        drawPolyline(dots)
        noStroke()
        fill(byFrequency ? accent : cool)
        for dot in dots { drawCircle(dot.x, dot.y, 4.5) }
    }

    /// The octave marks, which are what make the crush visible: they are evenly
    /// spaced by ear, so a mapping that bunches against them is bunching.
    private func drawOctaveLines(in frame: Rectangle) {
        stroke(faint)
        strokeWeight(1)
        textSize(11)
        textAlign(.right)
        for octave in 0...3 {
            let midi = low.midi + Double(octave) * 12
            let t = (midi - low.midi) / (high.midi - low.midi)
            let y = frame.y + frame.height - t * frame.height
            drawLine(frame.x, y, frame.x + frame.width, y)
            noStroke()
            fill(soft)
            drawText("C\(3 + octave)", at: Vector2(frame.x - 10, y + 4))
            stroke(faint)
        }
        noStroke()
    }

    // MARK: Snapping

    private func drawSnapped(top: Double, reading: Sonification) {
        label("snapped to a scale", at: Vector2(48, top))
        caption("the same reading, landing only on notes of the key",
                at: Vector2(48, top + 22), width: 170)

        let frame = Rectangle(x: 232, y: top - 16, width: 600, height: 108)

        // The scale's own notes, drawn as the lines the reading may land on.
        let scale = Scale(.minorPentatonic, root: "C3")
        stroke(faint)
        strokeWeight(1)
        for degree in 0...15 {
            let midi = scale[degree].midi
            guard midi >= low.midi, midi <= high.midi else { continue }
            let t = (midi - low.midi) / (high.midi - low.midi)
            let y = frame.y + frame.height - t * frame.height
            drawLine(frame.x, y, frame.x + frame.width, y)
        }

        noStroke()
        for (index, _) in series.enumerated() {
            guard let note = reading.note(at: index) else { continue }
            let x = frame.x + frame.width * (Double(index) + 0.5) / Double(series.count)
            let t = (note.pitch.midi - low.midi) / (high.midi - low.midi)
            let y = frame.y + frame.height - min(max(t, 0), 1) * frame.height
            fill(ink)
            drawRect(center: Vector2(x, y), width: 22, height: 7)
        }

        caption("Every mark sits on a line, so a reading of anything at all stays in key.",
                at: Vector2(232, frame.y + frame.height + 30), width: 600)
    }

    // MARK: Type

    private func title(_ text: String, at point: Vector2) {
        noStroke(); fill(ink); textSize(26); textAlign(.left)
        drawText(text, at: point)
    }

    private func label(_ text: String, at point: Vector2) {
        noStroke(); fill(ink); textSize(14); textAlign(.left)
        drawText(text, at: point)
    }

    private func caption(_ text: String, at point: Vector2, width: Double = 700) {
        noStroke(); fill(soft); textSize(12); textAlign(.left)
        drawText(text, in: Rectangle(x: point.x, y: point.y - 10,
                                     width: width, height: 60))
    }
}
