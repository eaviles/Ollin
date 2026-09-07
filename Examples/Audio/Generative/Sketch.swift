import Ollin
import OllinAudio

/// Music the sketch works out for itself, from four small pieces.
///
/// Each ring is a `Rhythm`: a number of strikes spread over a number of steps
/// as evenly as whole steps allow, which is the shape drawn between them. The
/// bar sweeping round is one `StepCounter` turning the sketch clock into step
/// numbers, and all three rings read the same number.
///
/// What is played on a strike comes from the other three. The bass takes a
/// degree from a `MarkovChain` taught a four note motif, so it wanders but
/// keeps the motif's habits. The middle ring plays an `Arpeggio` over a chord
/// built out of the `Scale` itself, so the chord's color follows the key. The
/// outer ring is air rather than pitch.
///
/// Nothing here has a clock of its own. Every one of them answers a step
/// number, which is what lets the same pattern run off the sketch clock now and
/// off a drum machine later.
@main
final class Generative: Sketch {

    @Param(2 ... 12, icon: "circle.grid.cross", group: "Rhythm") var bassStrikes = 3
    @Param(2 ... 12, icon: "circle.grid.cross", group: "Rhythm") var chordStrikes = 5
    @Param(2 ... 15, icon: "circle.grid.cross", group: "Rhythm") var airStrikes = 11
    @Param(60 ... 160, icon: "metronome", group: "Rhythm") var tempo: Tempo = 104

    @Param(icon: "pianokeys", group: "Notes") var mode: Scale.Mode = .minorPentatonic
    @Param(icon: "music.quarternote.3", group: "Notes") var quality: Chord.Quality = .minorSeventh
    @Param(icon: "arrow.up.arrow.down", group: "Notes") var figure: Arpeggio.Pattern = .upDown

    /// One cycle, in steps. Sixteen is the usual bar of sixteenth notes.
    let steps = 16

    let bass = Synth(.bass, polyphony: 4)
    let chords = Synth(.pluck, polyphony: 12)
    let air = Synth(.breath, polyphony: 6)

    var counter = StepCounter(perBeat: 4)
    var melody = MarkovChain<Int>(seed: 4)

    /// Where each ring's playing lands on the picture, and when.
    var marks: [(ring: Int, step: Int, start: Double, tone: Double)] = []
    var lastStep = 0

    override func setup() {
        noStroke()
        bass.gain = 0.55
        chords.gain = 0.32
        air.gain = 0.16
        chords.reverb = Reverb(.hall, mix: 0.25)
        air.reverb = Reverb(.hall, mix: 0.4)

        // A four note motif, learned as a loop so what follows the last degree
        // is the first. The chain then has somewhere to go from anywhere in it.
        melody.learn([0, 2, 4, 2, 0, -3, 0, 4], loops: true)
        melody.start(at: 0)
    }

    override func draw() {
        background(Color(white: 0.05))

        let key = Scale(mode, root: "A2")
        let rings = [
            Rhythm(bassStrikes, in: steps),
            Rhythm(chordStrikes, in: steps),
            Rhythm(airStrikes, in: steps),
        ]

        // The clock the whole piece runs on. Beats, not seconds: everything
        // else here counts steps.
        let beats = tempo.beats(at: time)
        for step in counter.steps(upTo: beats) {
            lastStep = step
            play(step, rings: rings, key: key)
        }

        drawWheel(rings: rings, beats: beats)
        drawMarks()
        // Scoped, because the notation sets a font the notices would otherwise
        // inherit on the next frame.
        withState { drawNotation(rings: rings) }

        drawCaption("\(bassStrikes)/\(chordStrikes)/\(airStrikes) over \(steps) "
                    + "· \(mode.optionLabel) · \(quality.optionLabel) · \(tempo)",
                    edge: .top)
        drawCaption("Three Euclidean rhythms on one step count. The parameters change what is played, live.")
    }

    // MARK: Playing

    private func play(_ step: Int, rings: [Rhythm], key: Scale) {
        let inBar = ((step % steps) + steps) % steps

        if rings[0][step] {
            // A degree from the chain, made into a pitch by the scale, so a
            // wandering number never leaves the key.
            let degree = melody.next() ?? 0
            bass.play(key[degree], velocity: 0.9, for: 0.34)
            mark(ring: 0, step: inBar, tone: Double((degree + 6) % 8) / 8)
        }

        if rings[1][step] {
            // The chord is built out of the scale rather than named, so it
            // changes color with the key rather than fighting it. The figure
            // is read at the step, which is why it keeps its place in the
            // pattern instead of restarting on every strike.
            let chord = Chord(key[0].transposed(by: 12), quality)
            let arp = Arpeggio(chord, figure, octaves: 2)
            let pitch = key.snap(arp[step])
            chords.play(pitch, velocity: 0.55, for: 0.22)
            mark(ring: 1, step: inBar, tone: (pitch.midi - 45) / 40)
        }

        if rings[2][step] {
            air.play(Pitch(78 + Double(inBar % 3) * 5), velocity: 0.4, for: 0.1)
            mark(ring: 2, step: inBar, tone: 0.95)
        }
    }

    private func mark(ring: Int, step: Int, tone: Double) {
        marks.append((ring: ring, step: step, start: time, tone: clamp(0, tone, 1)))
    }

    // MARK: Drawing

    private var wheelCenter: Vector2 { Vector2(Double(width) / 2, Double(height) * 0.42) }
    private var outerRadius: Double { Double(shortSide) * 0.29 }

    private func radius(of ring: Int) -> Double {
        outerRadius - Double(ring) * outerRadius * 0.28
    }

    private func point(ring: Int, step: Double) -> Vector2 {
        let angle = step / Double(steps) * .tau - .pi / 2
        return wheelCenter + Vector2(angle: angle) * radius(of: ring)
    }

    private func drawWheel(rings: [Rhythm], beats: Double) {
        let colors = [Color(hex: 0xF2B134), Color(hex: 0x67C9D9), Color(hex: 0xE56B6F)]

        for (index, rhythm) in rings.enumerated() {
            let color = colors[index]

            // The shape between the strikes is the picture of the rhythm: an
            // even spread makes a regular polygon, an uneven one leans.
            let onsets = rhythm.onsets
            if onsets.count > 1 {
                noFill()
                stroke(color.withAlpha(0.34))
                strokeWeight(1.2 * scale)
                drawPolygon(onsets.map { point(ring: index, step: Double($0)) })
            }

            noStroke()
            for step in 0..<steps {
                let at = point(ring: index, step: Double(step))
                if rhythm[step] {
                    fill(color)
                    drawCircle(center: at, radius: 7 * scale)
                } else {
                    fill(Color(white: 0.2))
                    drawCircle(center: at, radius: 2 * scale)
                }
            }
        }

        // One bar for all three rings, because they share a step count.
        let position = beats * 4
        let angle = position / Double(steps) * .tau - .pi / 2
        let heading = Vector2(angle: angle)
        stroke(Color(white: 0.8))
        strokeWeight(1.5 * scale)
        drawLine(wheelCenter, wheelCenter + heading * (outerRadius + 26 * scale))
        noStroke()
        fill(Color(white: 0.9))
        drawCircle(center: wheelCenter + heading * (outerRadius + 26 * scale), radius: 4 * scale)
    }

    private func drawMarks() {
        marks.removeAll { time - $0.start > 0.9 }
        blendMode(.add)
        noFill()
        for mark in marks {
            let age = (time - mark.start) / 0.9
            let at = point(ring: mark.ring, step: Double(mark.step))
            stroke(Colormap.magma.color(at: 0.35 + mark.tone * 0.5).withAlpha((1 - age) * 0.85))
            strokeWeight((1 - age) * 3 * scale + 0.5)
            drawCircle(center: at, radius: (7 + age * 26) * scale)
        }
        noStroke()
        blendMode(.normal)
    }

    /// The same three rhythms written out, which is the notation the algorithm
    /// is usually discussed in.
    private func drawNotation(rings: [Rhythm]) {
        textFont(BitmapFont.builtIn)
        textSize(20 * scale)
        textAlign(.center)
        let names = ["bass", "chord", "air"]
        for (index, rhythm) in rings.enumerated() {
            let played = rhythm[lastStep]
            fill(Color(white: played ? 0.95 : 0.55))
            let line = Double(height) * 0.8 + Double(index) * 34 * scale
            drawText("\(names[index])  \(rhythm)", Double(width) / 2, line)
        }
    }
}
