import Ollin
import OllinAudio

/// An effect written in the sketch itself.
///
/// The chain's built-in kinds cover the classics; `.custom` is the seam for
/// everything they do not. Each bend here is a few lines of arithmetic over
/// the samples: `fold` bends a sound back on itself, `crush` holds each
/// sample long enough to be heard as grit, and `wobble` breathes with the
/// clock the effect is handed. The second one keeps memory between blocks,
/// which is what `state:` is for.
///
/// The dim line is the sound going in, the bright one is what comes out, and
/// the room at the end of the chain hears the bent sound, not the clean one:
/// order in the chain is order in fact.
@main
final class Shaping: Sketch {

    enum Bend: String, ParamOption { case fold, crush, wobble }
    @Param(icon: "waveform.path", group: "The effect") var bend = Bend.fold
    @Param(1 ... 12, icon: "dial.high", group: "The effect") var amount = 6.0
    @Param(icon: "slider.horizontal.3", group: "Finish") var room = true

    let synth = Synth(.stab, polyphony: 6)
    let pentatonic = Scale(.minorPentatonic, root: "C3")
    let tempo: Tempo = 96
    var counter = StepCounter(perBeat: 2)
    var built = ""
    var trace: [Double] = []
    var step = 0

    override func setup() {
        synth.gain = 0.5
        rebuild()
    }

    private var recipe: String { "\(bend)-\(amount)-\(room)" }

    /// The effect, written here. A closure the audio thread runs over every
    /// block of samples on its way to the speakers.
    private var bent: Effect {
        switch bend {
        case .fold:
            // Push a sample past the top and it comes back down: the shape of
            // a wavefolder, and the harmonics of one.
            let strength = Float(amount)
            return .custom("fold") { sound in
                for channel in 0..<sound.channelCount {
                    let samples = sound[channel]
                    for i in samples.indices { samples[i] = sin(samples[i] * strength) }
                }
            }
        case .crush:
            // Hold each sample for a while instead of letting the next one
            // through. The memory of what is being held rides in as `state:`
            // and comes back on every block.
            let hold = max(1, Int(amount * 3))
            return .custom("crush", state: (left: Float(0), right: Float(0), count: 0)) { sound, held in
                for i in 0..<sound.frameCount {
                    if held.count % hold == 0 {
                        held.left = sound.left[i]
                        held.right = sound.right[i]
                    }
                    held.count += 1
                    sound.left[i] = held.left
                    sound.right[i] = held.right
                }
            }
        case .wobble:
            // No memory at all: the block says what time it is, and the gain
            // is a wave over that clock.
            let rate = amount
            return .custom("wobble") { sound in
                for i in 0..<sound.frameCount {
                    let phase = (sound.time + Double(i) / sound.sampleRate) * rate * 2 * .pi
                    let gain = Float(0.55 + 0.45 * sin(phase))
                    sound.left[i] *= gain
                    sound.right[i] *= gain
                }
            }
        }
    }

    /// The effect is a value: a new one swaps onto the same link in the chain
    /// without the wiring being touched, so the sound never stops to change.
    private func rebuild() {
        synth.effects = [bent] + (room ? [.reverb(Reverb(.hall, mix: 0.25))] : [])
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))
        if built != recipe { rebuild() }

        for next in counter.steps(upTo: tempo.beats(at: time)) {
            step = next
            synth.play(pentatonic[[0, 3, 2, 4, 1, 5][next % 6]], velocity: 0.8, for: 0.45)
        }

        trace.append(Double(synth.amplitude))
        if trace.count > 320 { trace.removeFirst() }

        drawResponse()
        drawTrace()
        drawCaption("An effect written in the sketch: a closure over the samples.",
                    edge: .top)
        drawCaption("The dim line goes in, the bright one comes out. Fold bends, "
                    + "crush holds, wobble breathes on the clock it is handed.")
    }

    /// The same wave in and out of the closure, so the arithmetic is visible.
    private func drawResponse() {
        let frame = Rectangle(x: width * 0.12, y: height * 0.3,
                              width: width * 0.76, height: height * 0.34)
        let points = 480
        // Two cycles across the frame, standing in for the sound going in.
        // For the crush the horizontal axis is real samples, so the stairs on
        // screen are the stairs in the sound.
        let audioSamples = 200.0
        func input(_ position: Int) -> Double {
            sin(Double(position) / Double(points) * 2 * .pi * 2)
        }

        var held = 0.0
        let output: [Double] = (0..<points).map { position in
            let value = input(position)
            switch bend {
            case .fold:
                return sin(value * amount)
            case .crush:
                let sample = Int(Double(position) / Double(points) * audioSamples)
                if sample % max(1, Int(amount * 3)) == 0 || position == 0 { held = value }
                return held
            case .wobble:
                // A second of breathing, kept moving by the sketch's clock so
                // the picture wobbles the way the sound does.
                let phase = (time + Double(position) / Double(points)) * amount * 2 * .pi
                return value * (0.55 + 0.45 * sin(phase))
            }
        }

        func plotted(_ values: [Double]) -> [Vector2] {
            values.enumerated().map { position, value in
                Vector2(frame.x + frame.width * Double(position) / Double(points - 1),
                        frame.y + frame.height * (0.5 - value * 0.48))
            }
        }

        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.3))
        strokeWeight(2 * scale)
        drawPolyline(plotted((0..<points).map(input)))

        stroke(Color(hex: 0xE8A33D, alpha: 0.9))
        strokeWeight(3 * scale)
        drawPolyline(plotted(output))
    }

    /// What actually came out, so the arithmetic and the sound share a screen.
    private func drawTrace() {
        guard trace.count > 2 else { return }
        let frame = Rectangle(x: width * 0.12, y: height * 0.74,
                              width: width * 0.76, height: height * 0.1)
        noFill()
        stroke(Color(hex: 0x7FD4C1, alpha: 0.8))
        strokeWeight(2 * scale)
        drawPolyline(trace.enumerated().map { position, value in
            Vector2(frame.x + frame.width * Double(position) / Double(max(1, trace.count - 1)),
                    frame.y + frame.height * (1 - min(value * 4, 1)))
        })
    }
}
