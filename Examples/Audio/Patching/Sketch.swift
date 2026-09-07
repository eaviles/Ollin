import Ollin
import OllinAudio

/// An instrument built rather than picked.
///
/// A `Voice` is a fixed chain: something makes a wave, an envelope shapes it, a
/// filter takes part of it away. A `Patch` is the tier underneath, where the
/// routing itself is the value. Here two operators are wired live: the lower
/// one pushes the upper one, and the parameters are what the pushing is.
///
/// The thing to listen for is that this cannot be done with a filter. A filter
/// can only take harmonics away, and a sine has none to take. Modulation puts
/// them in, which is why turning `index` up turns a plain tone into brass, and
/// why moving `ratio` off a whole number turns it into metal.
///
/// The graph is drawn as it is wired: the pushing operator above, the one being
/// heard below, and the line between them thick with how hard it pushes.
@main
final class Patching: Sketch {

    @Param(0 ... 8, icon: "dial.high", group: "Modulator") var index = 3.0
    @Param(0.5 ... 8, icon: "waveform.path", group: "Modulator") var ratio = 2.0
    @Param(0 ... 0.9, icon: "arrow.triangle.2.circlepath", group: "Carrier") var feedback = 0.0
    @Param(icon: "waveform", group: "Carrier") var shape = Waveform.sine

    enum Finish: String, ParamOption { case dry, room, echo, echoOfADirtySound, aDirtyEcho }
    @Param(icon: "slider.horizontal.3", group: "Finish") var finish = Finish.room

    let synth = Synth(.sine, polyphony: 8)
    // Neither `scale` nor `key` will do: a Sketch already has both, one the
    // resolution-relative scale and one the keyboard.
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

    private var recipe: String { "\(index)-\(ratio)-\(feedback)-\(shape)-\(finish)" }

    /// The rest of the instrument. A chain rather than two slots, and the last
    /// two differ only in which way round they are, which is audible.
    private var chain: [Effect] {
        switch finish {
        case .dry:               return []
        case .room:              return [.reverb(Reverb(.hall, mix: 0.3))]
        case .echo:              return [.delay(Delay(time: 0.26, feedback: 0.45, mix: 0.4))]
        case .echoOfADirtySound: return [.distortion(Distortion(.overdrive, mix: 0.5)),
                                         .delay(Delay(time: 0.26, feedback: 0.45, mix: 0.4))]
        case .aDirtyEcho:        return [.delay(Delay(time: 0.26, feedback: 0.45, mix: 0.4)),
                                         .distortion(Distortion(.overdrive, mix: 0.5))]
        }
    }

    /// The whole feature, in one expression: the routing is a value.
    private func rebuild() {
        let patch = Patch.tone(shape)
            .modulated(by: .tone(.sine, ratio: ratio), index: index)
            .fedBack(feedback)
        synth.voice = Voice(patch: patch, envelope: .percussive, gain: 0.7)
        synth.effects = chain
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))
        if built != recipe { rebuild() }

        for next in counter.steps(upTo: tempo.beats(at: time)) {
            step = next
            synth.play(pentatonic[[0, 2, 4, 3, 1, 5][next % 6]], velocity: 0.8, for: 0.5)
        }

        trace.append(Double(synth.amplitude))
        if trace.count > 320 { trace.removeFirst() }

        drawGraph()
        drawCaption("Two operators, wired live. The upper one pushes the lower one.",
                    edge: .top)
        drawCaption("A filter can only take harmonics away. This puts them in. "
                    + "The finish is a chain, and its order is audible.")
    }

    private func drawGraph() {
        let modulator = Vector2(width / 2, height * 0.28)
        let carrier = Vector2(width / 2, height * 0.55)

        // The connection, as thick as the pushing is hard.
        stroke(Color(hex: 0xE8A33D, alpha: 0.75))
        strokeWeight((1 + index * 2.2) * scale)
        drawLine(modulator.x, modulator.y + 46 * scale, carrier.x, carrier.y - 46 * scale)

        // The operator that is felt rather than heard.
        drawOperator(at: modulator, label: "×\(String(format: "%.2f", ratio))",
                     color: Color(hex: 0xE8A33D), heard: false)
        // The one that is heard.
        drawOperator(at: carrier, label: "\(shape)".capitalized,
                     color: Color(hex: 0x7FD4C1), heard: true)

        if feedback > 0.001 {
            // A loop back into itself, drawn as a ring beside the operator.
            noFill()
            stroke(Color(hex: 0x7FD4C1, alpha: 0.55))
            strokeWeight((1 + feedback * 5) * scale)
            let side = carrier + Vector2(74 * scale, 0)
            drawCircle(side.x, side.y, 26 * scale)
        }

        // What came out, so the wiring and the sound are on one screen.
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.8))
        strokeWeight(2 * scale)
        let frame = Rectangle(x: width * 0.12, y: height * 0.76,
                              width: width * 0.76, height: height * 0.12)
        if trace.count > 2 {
            drawPolyline(trace.enumerated().map { position, value in
                Vector2(frame.x + frame.width * Double(position) / Double(max(1, trace.count - 1)),
                        frame.y + frame.height * (1 - min(value * 4, 1)))
            })
        }
    }

    private func drawOperator(at point: Vector2, label: String,
                              color: Color, heard: Bool) {
        noStroke()
        fill(color.withAlpha(heard ? 0.22 : 0.14))
        drawCircle(point.x, point.y, 46 * scale)
        noFill()
        stroke(color.withAlpha(0.9))
        strokeWeight(2 * scale)
        drawCircle(point.x, point.y, 46 * scale)

        noStroke()
        fill(Color(white: 0.9))
        textSize(17 * scale)
        textAlign(.center)
        drawText(label, at: Vector2(point.x, point.y + 6 * scale))
        fill(Color(white: 0.5))
        textSize(13 * scale)
        // The heard one is labeled below and the felt one above, so neither
        // label sits under the line running between them.
        drawText(heard ? "heard" : "felt",
                 at: Vector2(point.x, point.y + (heard ? 68 : -58) * scale))
    }
}
