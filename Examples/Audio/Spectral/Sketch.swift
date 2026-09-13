import Ollin
import OllinAudio

/// The two effects that work in the spectrum, and the stretch beside them.
///
/// A phrase plays. In `shift` its pitch moves without its length, by the
/// semitones on the slider, and under a full mix the original sounds with
/// the moved copy, which is a harmonizer. In `freeze` the instant the mouse
/// goes down is caught and held for as long as the button is: whatever was
/// sounding becomes a pad, and letting go eases the phrase back in. In
/// `stretch` the bundled bar's recording is slowed by the factor and played
/// at the pitch it was recorded at, which a sampler cannot do by itself,
/// since a sampler moves pitch and length together like a tape.
///
/// The roll is the notes as they play, the moved copy over each one in the
/// warm color and exactly as long, and the bars under it are the spectrum of
/// what is coming out. In `freeze` the bars stop with the sound and the roll
/// shows how long the instant has been held.
@main
final class Spectral: Sketch {

    enum Mode: String, ParamOption { case shift, freeze, stretch }
    @Param(icon: "waveform.path", group: "The effect") var mode = Mode.shift
    @Param(-24 ... 24, icon: "arrow.up.and.down", group: "Shift") var semitones = 7.0
    @Param(0 ... 1, icon: "dial.medium", group: "Shift") var mix = 0.5
    @Param(1 ... 8, icon: "clock", group: "Stretch") var factor = 4.0

    let synth = Synth(.bell, polyphony: 8)
    let pentatonic = Scale(.minorPentatonic, root: "A3")
    let tempo: Tempo = 84
    var counter = StepCounter(perBeat: 2)
    var built = ""
    var held = 0.0
    var heldSince: Double?

    /// The bundled bar, and the same bar slowed.
    let bar = SampledInstrument.builtIn
    var slowed: SampledInstrument?
    var recorded: [Float] = []
    var stretched: [Float] = []

    /// What has played, for the roll: when, at what pitch, for how long, and
    /// whether it is the moved copy of another.
    struct Played { var at: Double; var pitch: Double; var length: Double; var moved: Bool }
    var played: [Played] = []
    let window = 6.0

    let cool = Color(hex: 0x6FA8DC)
    let warm = Color(hex: 0xE8A33D)

    override func setup() {
        synth.gain = 0.5
        rebuild()
    }

    private var recipe: String { "\(mode)-\(semitones)-\(mix)-\(factor)" }

    /// The chain for the mode. The freeze's amount is not part of the
    /// recipe: it moves every frame with the mouse, and a moved setting
    /// rides the standing effect rather than rebuilding it.
    private func rebuild() {
        switch mode {
        case .shift:
            synth.instrument = nil
            synth.voice = .bell
            synth.effects = [.pitchShift(PitchShift(semitones: semitones, mix: mix)),
                             .reverb(Reverb(.hall, mix: 0.2))]
        case .freeze:
            synth.instrument = nil
            synth.voice = .bell
            synth.effects = [.freeze(Freeze(amount: held)), .reverb(Reverb(.hall, mix: 0.2))]
        case .stretch:
            // One recording, `factor` times as long, at the same pitch. The
            // stretch is a thing done to the recording once, here, and then
            // the sampler plays it like any other.
            if let bar {
                let index = bar.recordingIndex(for: 60) ?? 0
                let recording = bar.recording(at: index, over: 0...127)
                let longer = recording.stretched(by: factor)
                slowed = SampledInstrument(name: "slowed", recordings: [longer])
                recorded = recording.frames
                stretched = longer.frames
            }
            synth.instrument = slowed
            synth.voice = Voice(sampled: Sampler(), envelope: .plucked)
            synth.effects = [.reverb(Reverb(.hall, mix: 0.2))]
        }
        played.removeAll()
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))
        if built != recipe { rebuild() }

        // The freeze follows the mouse, eased, so it fades in and out rather
        // than switching; the amount is also the blend.
        if mode == .freeze {
            let target = mouseIsPressed ? 1.0 : 0.0
            held += (target - held) * 0.2
            if abs(held - target) < 0.002 { held = target }
            synth.effects[0] = .freeze(Freeze(amount: held))
            if held > 0, heldSince == nil { heldSince = time }
            if held == 0 { heldSince = nil }
        }

        for step in counter.steps(upTo: tempo.beats(at: time)) {
            switch mode {
            case .shift, .freeze:
                let degree = [0, 2, 4, 3, 5, 2, 1, 4][step % 8]
                play(pentatonic[degree], velocity: step % 4 == 0 ? 0.9 : 0.6, for: 0.5)
                if step % 8 == 0 { play(pentatonic[degree - 5], velocity: 0.7, for: 1.6) }
            case .stretch:
                // One note every two bars, since each lasts as long as the
                // recording does, times the factor.
                guard step % 8 == 0, let slowed else { continue }
                let root = Double(slowed.recordingRoots[0])
                let sounding = Double(stretched.count) / 48000
                let pitch = Pitch(root + [0, 7, 3][(step / 8) % 3])
                synth.play(pitch, velocity: 0.9, for: 8)
                played.append(Played(at: time, pitch: pitch.midi, length: sounding / factor, moved: false))
                played.append(Played(at: time, pitch: pitch.midi, length: sounding, moved: true))
            }
        }
        played.removeAll { $0.at + $0.length < time - window }

        drawRoll()
        if mode == .stretch { drawRecordings() } else { drawSpectrum() }

        switch mode {
        case .shift:
            let ratio = pow(2, semitones / 12)
            drawCaption("Pitch moved \(semitones >= 0 ? "up" : "down") "
                        + "\(abs(Int(semitones.rounded()))) semitones, a ratio of "
                        + String(format: "%.3f", ratio) + ", with the length untouched.", edge: .top)
            drawCaption(mix < 1 ? "The original sounds under the moved copy: a harmonizer."
                                : "Only the moved sound is heard; the roll shows both.")
        case .freeze:
            drawCaption(held > 0.01 ? "Holding the instant the mouse went down."
                                    : "Press the mouse to hold whatever is sounding.", edge: .top)
            drawCaption("The amount eases in and out, so the freeze fades rather than switches.")
        case .stretch:
            drawCaption("The bundled bar, \(String(format: "%.1f", factor)) times as long "
                        + "at the pitch it was recorded at.", edge: .top)
            drawCaption("Dim is the recording, bright is the same recording stretched.")
        }
    }

    /// A note asked for, and written down for the roll: the note itself, and
    /// in `shift` the copy the effect makes of it, as long and as many
    /// semitones away as the effect says.
    private func play(_ pitch: Pitch, velocity: Double, for length: Double) {
        synth.play(pitch, velocity: velocity, for: length)
        played.append(Played(at: time, pitch: pitch.midi, length: length, moved: false))
        if mode == .shift {
            played.append(Played(at: time, pitch: pitch.midi + semitones, length: length, moved: true))
        }
    }

    /// The last few seconds of notes, scrolling left, with the moved copies
    /// over them.
    private func drawRoll() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.16, width: width * 0.8, height: height * 0.36)
        let low = 36.0, high = 96.0
        func x(_ t: Double) -> Double { frame.x + frame.width * (1 - (time - t) / window) }
        func y(_ pitch: Double) -> Double { frame.bottomRight.y - frame.height * (pitch - low) / (high - low) }
        let rowHeight = frame.height / (high - low)

        noStroke()
        for octave in stride(from: low, through: high, by: 12) {
            fill(Color(white: 1, alpha: 0.05))
            drawRect(frame.x, y(octave) - 0.5, frame.width, 1)
        }
        if mode == .freeze, let heldSince {
            fill(warm.withAlpha(0.12 + 0.18 * held))
            drawRect(x(heldSince), frame.y, x(time) - x(heldSince), frame.height)
        }
        for note in played {
            let start = max(frame.x, x(note.at))
            let end = min(frame.bottomRight.x, x(note.at + note.length))
            guard end > start else { continue }
            if note.moved {
                fill(warm.withAlpha(mode == .shift ? 0.35 + 0.65 * mix : 0.9))
            } else {
                fill(cool.withAlpha(mode == .shift && mix >= 1 ? 0.35 : 0.85))
            }
            drawRect(start, y(note.pitch) - rowHeight * 0.45, end - start, rowHeight * 0.9)
        }
        noFill()
        stroke(Color(white: 1, alpha: 0.12))
        strokeWeight(1 * scale)
        drawRect(frame.x, frame.y, frame.width, frame.height)
    }

    /// What is coming out, as bars across the spectrum.
    private func drawSpectrum() {
        let levels = synth.bands(56)
        let frame = Rectangle(x: width * 0.1, y: height * 0.58, width: width * 0.8, height: height * 0.24)
        let gap = 3 * scale
        let barWidth = (frame.width - gap * Double(levels.count - 1)) / Double(levels.count)
        noStroke()
        for (index, level) in levels.enumerated() {
            let lit = min(Double(level), 1)
            let barHeight = max(2 * scale, frame.height * lit)
            fill((mode == .freeze && held > 0.01 ? warm : cool).withAlpha(0.35 + 0.65 * lit))
            drawRect(frame.x + Double(index) * (barWidth + gap), frame.bottomRight.y - barHeight,
                     barWidth, barHeight)
        }
    }

    /// The recording and its stretch on one time axis, so the stretch reads
    /// as longer rather than merely different.
    private func drawRecordings() {
        guard !recorded.isEmpty, !stretched.isEmpty else { return }
        let frame = Rectangle(x: width * 0.1, y: height * 0.58, width: width * 0.8, height: height * 0.24)
        let span = Double(stretched.count)
        func outline(_ samples: [Float], color: Color) {
            let columns = 400
            var top: [Vector2] = [], bottom: [Vector2] = []
            let visible = Int(Double(columns) * Double(samples.count) / span)
            guard visible > 1 else { return }
            for column in 0..<visible {
                let from = column * samples.count / visible
                let to = max(from + 1, (column + 1) * samples.count / visible)
                var peak: Float = 0
                for index in from..<to { peak = max(peak, abs(samples[index])) }
                let x = frame.x + frame.width * Double(column) / Double(columns)
                let y = Double(peak) * frame.height * 0.48
                top.append(Vector2(x, frame.center.y - y))
                bottom.append(Vector2(x, frame.center.y + y))
            }
            noStroke()
            fill(color)
            drawShape(Shape(top + bottom.reversed()))
        }
        outline(stretched, color: warm.withAlpha(0.8))
        outline(recorded, color: cool.withAlpha(0.45))
    }
}
