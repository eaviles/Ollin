import Ollin
import OllinAudio

/// An instrument you made yourself, loaded from your own `.sfz` file.
///
/// The sibling `Sampler` example plays the instrument Ollin bundles. This one
/// shows the rest of the path: an `.sfz` is a plain text map naming audio
/// files and the notes each answers to, and `SampledInstrument(sfz:in:)`
/// reads yours from the sketch's own bundle, recordings and all. The map
/// here is three lines long:
///
///     <region> sample=hum-c4.wav lokey=55 hikey=63 pitch_keycenter=60 tune=3.5
///
/// Everything beside this sketch is our own work: `make-samples.py` in this
/// folder generated the three recordings and the map, so the assets carry no
/// license of anyone else's. The script builds each file to loop seamlessly,
/// a whole number of periods in the loop region, and writes the tiny pitch
/// nudge that costs back into the map as the `tune=` correction.
///
/// The panels are the three recordings themselves, the shaded band on each
/// being the loop region the map declares. The lit panel is the recording
/// answering the note sounding. Each recording is barely half a second long,
/// yet every note holds as long as it likes, because the read head circles
/// the band while the note is held. Press `L` to stop it looping and the same
/// notes die the moment their recording runs out, which is the whole reason
/// the loop opcodes exist.
@main
final class OwnSampler: Sketch {

    @Param(40 ... 120, icon: "metronome", group: "Playing") var tempo = 60.0
    @Param(0 ... 1, icon: "speaker.wave.2", group: "Playing") var velocityFeel = 0.5

    /// The loop region the generator wrote into Hum.sfz, for the drawing.
    static let loopRegion = 4410 ..< 20794

    let synth = Synth(polyphony: 10)
    let scale5 = Scale(.majorPentatonic, root: "C3")
    var counter = StepCounter(perBeat: 1)

    var instrument: SampledInstrument?
    var waves: [[(low: Double, high: Double)]] = []
    var roots: [Int] = []
    var lit: [Double] = []
    var sounding = -1
    var playing: Pitch?
    var loops = true
    var built = ""

    override func setup() {
        // The whole point of the example: your own file, from your own bundle.
        // The bundle is named because a default would resolve to Ollin's own.
        instrument = SampledInstrument(sfz: "Hum", in: .module)
        synth.gain = 0.55
        synth.reverb = Reverb(.hall, mix: 0.25)
        roots = instrument?.recordingRoots ?? []
        lit = [Double](repeating: 0, count: max(1, roots.count))
        buildWaves()
        rebuild()
    }

    private var recipe: String { "\(loops)-\(velocityFeel)" }

    private func rebuild() {
        synth.instrument = instrument
        synth.voice = Voice(sampled: Sampler(loops: loops,
                                             velocitySensitivity: velocityFeel),
                            envelope: .sustained, gain: 0.8)
        built = recipe
    }

    /// Reads each recording back and folds it into drawable columns, once.
    private func buildWaves() {
        guard let instrument else { return }
        waves = (0 ..< instrument.recordingCount).map { index in
            let frames = instrument.recording(at: index, over: 0 ... 127).frames
            let columns = 420
            let step = max(1, frames.count / columns)
            return (0 ..< columns).map { column in
                let from = min(column * step, max(0, frames.count - 1))
                let slice = frames[from ..< min(from + step, frames.count)]
                return (Double(slice.min() ?? 0), Double(slice.max() ?? 0))
            }
        }
    }

    override func draw() {
        background(Color(hex: 0x0C0E12))
        if built != recipe { rebuild() }

        guard let instrument, !instrument.isEmpty else {
            // The house rule: say what is missing and keep the picture alive.
            noFill()
            stroke(Color(white: 0.4))
            strokeWeight(3 * scale)
            drawCircle(center: center, radius: (120 + 30 * sin(time * 1.5)) * scale)
            drawCaption("The instrument did not load. Run make-samples.py in this "
                        + "example's folder, then build again.")
            return
        }

        // A slow line with long notes, because the loop is only audible on a
        // note that outlasts its half-second recording.
        for step in counter.steps(upTo: time * tempo / 60) {
            let shape = [0, 4, 7, 5, 9, 7, 11, 4]
            let pitch = scale5[shape[step % shape.count]]
            playing = pitch
            synth.play(pitch, velocity: 0.6 + 0.3 * sin(Double(step) * 1.3),
                       for: 3.4 * 60 / tempo)
            sounding = instrument.recordingIndex(for: Int(pitch.midi.rounded())) ?? -1
            if sounding >= 0, sounding < lit.count { lit[sounding] = 1 }
        }

        drawRecordings()
        drawCaption("Your own .sfz: three generated recordings, and the loop band that lets half a second hold forever.",
                    edge: .top)
        drawCaption(loops ? "Looping inside the shaded band. Press L to let each recording run out instead."
                          : "Not looping: every note dies when its recording ends. Press L to loop again.")
    }

    private func drawRecordings() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.2,
                              width: width * 0.8, height: height * 0.52)
        let count = max(1, waves.count)
        let lane = frame.height / Double(count)

        for index in 0 ..< count {
            lit[index] *= pow(0.08, deltaTime)
            let glow = index == sounding ? 1.0 : lit[index]
            let middleY = frame.y + lane * (Double(index) + 0.5)
            let tall = lane * 0.36
            let columns = waves[index]
            let tone = Colormap.magma.color(at: 0.25 + Double(index) / Double(count) * 0.5)

            // The loop region the map declares, as a band under the wave.
            let total = Double(Self.loopRegion.upperBound + 2048)
            let loopFrom = frame.x + Double(Self.loopRegion.lowerBound) / total * frame.width
            let loopTo = frame.x + Double(Self.loopRegion.upperBound) / total * frame.width
            noStroke()
            fill(tone.withAlpha(0.10 + glow * 0.12))
            drawRect(corner: Vector2(loopFrom, middleY - tall - 6 * scale),
                     width: loopTo - loopFrom, height: (tall + 6 * scale) * 2)

            // The recording itself, one thin column per slice of it.
            stroke(tone.withAlpha(0.35 + glow * 0.65))
            strokeWeight(max(1, frame.width / Double(columns.count) * 0.8))
            for (column, extent) in columns.enumerated() {
                let x = frame.x + Double(column) / Double(columns.count) * frame.width
                drawLine(x, middleY + extent.low * tall, x, middleY + extent.high * tall)
            }

            noStroke()
            fill(Color(white: 0.4 + glow * 0.5))
            textSize(15 * scale)
            textAlign(.left, .middle)
            drawText("\(Pitch(Double(roots[index])))",
                     at: Vector2(frame.x - 46 * scale, middleY))
        }

        // The note sounding, and which recording answered it.
        if let playing, sounding >= 0, sounding < roots.count {
            let moved = Int(playing.midi.rounded()) - roots[sounding]
            noStroke()
            fill(Color(white: 0.88))
            textSize(28 * scale)
            textAlign(.center)
            drawText("\(playing)", at: Vector2(width / 2, height * 0.82))
            fill(Color(white: 0.5))
            textSize(15 * scale)
            drawText(moved == 0 ? "played at its own pitch"
                     : "answered by \(Pitch(Double(roots[sounding]))), moved \(moved > 0 ? "+" : "")\(moved) semitones",
                     at: Vector2(width / 2, height * 0.82 + 28 * scale))
        }
    }

    override func keyPressed() {
        guard key == "l" || key == "L" else { return }
        loops.toggle()
    }
}
