import Ollin
import OllinAudio

/// An instrument made of recordings.
///
/// Everything else Ollin plays is worked out as it goes. This is the other way
/// round: someone recorded the thing, and a note means finding the nearest
/// recording and moving it to the pitch asked for.
///
/// The instrument here is the one Ollin bundles, a struck bar recorded at five
/// pitches. The bars across the bottom are those five recordings, and the one
/// that lights is the one answering the note. Watch which lights as the tune
/// climbs: notes near a recording use it, and notes between two take whichever
/// is nearer, because moving a recording a long way is what makes a sampler
/// sound wrong.
///
/// Press `S` to stretch a single recording across the whole range instead,
/// which is what one recording rather than five sounds like. The high notes go
/// thin and hurried and the low ones go slow and heavy, because moving a
/// recording moves its pitch and its length together, exactly as a tape does.
@main
final class SamplerSketch: Sketch {

    @Param(0 ... 1, icon: "speaker.wave.2", group: "Playing") var velocityFeel = 0.7
    @Param(-12 ... 12, icon: "arrow.up.arrow.down", group: "Playing") var transpose = 0.0
    @Param(60 ... 160, icon: "metronome", group: "Playing") var tempo = 104.0

    let synth = Synth(polyphony: 12)
    let pentatonic = Scale(.minorPentatonic, root: "C3")
    var counter = StepCounter(perBeat: 2)

    var roots: [Int] = []
    var lit: [Double] = []
    var sounding = -1
    var playing: Pitch?
    var oneRecording = false
    var built = ""

    override func setup() {
        synth.gain = 0.6
        synth.effects = [.reverb(Reverb(.hall, mix: 0.28))]
        rebuild()
    }

    private var recipe: String { "\(velocityFeel)-\(transpose)-\(oneRecording)" }

    private func rebuild() {
        // The whole feature, in two lines: which recordings, and how to play
        // them. They are set apart because recordings are far too large to
        // travel inside a note.
        if oneRecording, let full = SampledInstrument.builtIn {
            // Just the middle recording, stretched over everything.
            let middle = full.recordingCount / 2
            synth.instrument = SampledInstrument(
                name: "one", recordings: [full.recording(at: middle, over: 0 ... 127)]
            )
        } else {
            synth.instrument = SampledInstrument.builtIn
        }
        synth.voice = Voice(sampled: Sampled(velocitySensitivity: velocityFeel,
                                             transposition: transpose),
                            envelope: .plucked, gain: 0.8)
        roots = synth.instrument?.recordingRoots ?? []
        lit = [Double](repeating: 0, count: max(1, roots.count))
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0B0E13))
        if built != recipe { rebuild() }

        for step in counter.steps(upTo: time * tempo / 60) {
            let shape = [0, 2, 4, 7, 9, 7, 4, 2, 0, 4, 9, 11, 14, 11, 9, 4]
            let degree = shape[step % shape.count]
            let pitch = pentatonic[degree]
            playing = pitch
            synth.play(pitch, velocity: 0.55 + 0.4 * abs(sin(Double(step) * 0.7)), for: 1.1)

            // Which recording answered, which is the thing worth seeing.
            sounding = synth.instrument?.recordingIndex(
                for: Int((pitch.midi + transpose).rounded()), velocity: 0.8) ?? -1
            if sounding >= 0, sounding < lit.count { lit[sounding] = 1 }
        }

        drawRecordings()
        drawCaption("An instrument made of recordings. The lit bar is the one answering.",
                    edge: .top)
        drawCaption(oneRecording
                    ? "One recording stretched over everything: high notes thin, low ones heavy."
                    : "Press S to stretch one recording over the whole range instead.")
    }

    private func drawRecordings() {
        let frame = Rectangle(x: width * 0.12, y: height * 0.62,
                              width: width * 0.76, height: height * 0.18)
        let count = max(1, roots.count)
        let slot = frame.width / Double(count)

        for index in 0 ..< count {
            lit[index] *= pow(0.05, deltaTime)
            let glow = lit[index]
            let x = frame.x + slot * (Double(index) + 0.5)
            let tall = frame.height * (0.35 + glow * 0.65)

            noStroke()
            fill(Colormap.magma.color(at: 0.25 + Double(index) / Double(count) * 0.5)
                .withAlpha(0.25 + glow * 0.75))
            drawRect(center: Vector2(x, frame.y + frame.height - tall / 2),
                     width: slot * 0.55, height: tall)

            fill(Color(white: 0.55))
            textSize(13 * scale)
            textAlign(.center)
            drawText("\(Pitch(Double(roots[index])))",
                     at: Vector2(x, frame.y + frame.height + 24 * scale))
        }

        // The note sounding, and how far it is being moved from its recording.
        if let playing {
            let played = Int((playing.midi + transpose).rounded())
            let root = sounding >= 0 && sounding < roots.count ? roots[sounding] : played
            let moved = played - root
            noStroke()
            fill(Color(white: 0.88))
            textSize(30 * scale)
            textAlign(.center)
            drawText("\(playing)", at: Vector2(width / 2, height * 0.4))
            fill(Color(white: 0.5))
            textSize(15 * scale)
            drawText(moved == 0 ? "played at its own pitch"
                     : "moved \(moved > 0 ? "+" : "")\(moved) semitones",
                     at: Vector2(width / 2, height * 0.46))
        }
    }

    override func keyPressed() {
        guard key == "s" || key == "S" else { return }
        oneRecording.toggle()
    }
}
