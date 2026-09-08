import Ollin
import OllinAudio

/// A room of your own around an instrument.
///
/// A reverb is a room, and a room is what it does to a click: clap once in a
/// stairwell and what comes back is the stairwell. `ImpulseResponse` is that
/// answer written down, recorded or drawn, and `Reverb(room)` plays the
/// instrument through it. Every room here is drawn from a rule: fading noise
/// at two sizes, the same noise run backward, a resonator that hums at one
/// pitch, and a dropped ball whose echoes close in. The picture is the
/// room's answer to a click, and the trace under it is the instrument heard
/// in it. Turning `mix` rides the room that is sounding; changing the room,
/// its damping, or the pre-delay starts a fresh one.
@main
final class Rooms: Sketch {

    enum Room: String, ParamOption { case small, hall, reversed, humming, bouncing }
    @Param(icon: "building.columns", group: "The room") var room = Room.hall
    @Param(0 ... 1, icon: "cloud.fog", group: "The room") var damping = 0.6
    @Param(0 ... 0.2, icon: "arrow.right.to.line", group: "The room") var preDelay = 0.0
    @Param(0 ... 1, icon: "drop", group: "Finish") var mix = 0.45

    let synth = Synth(.pluck, polyphony: 8)
    let pentatonic = Scale(.majorPentatonic, root: "D3")
    let tempo: Tempo = 84
    var counter = StepCounter(perBeat: 2)
    let phrase = [0, 2, 4, 3, 1, 4, 2, -1, 3, 1, 0, -1]
    var impulse = ImpulseResponse.decay(seconds: 1)
    var built = ""
    var columns: [Double] = []
    var trace: [Double] = []

    override func setup() {
        synth.gain = 0.5
        rebuild()
    }

    private var recipe: String { "\(room)-\(damping)-\(preDelay)" }

    /// The room, drawn. Each is a rule over time and a stream of noise, and
    /// the same rule draws the same room every run.
    private func drawnRoom() -> ImpulseResponse {
        switch room {
        case .small:
            return .decay(seconds: 0.5, damping: damping, seed: 1)
        case .hall:
            return .decay(seconds: 3.5, damping: damping, seed: 2)
        case .reversed:
            // The answer swells toward the click instead of fading from it.
            return ImpulseResponse.decay(seconds: 1.6, damping: damping, seed: 3).reversed()
        case .humming:
            // A resonator rather than a room: it rings at the root of the
            // scale, with a breath of noise so the ring has some width.
            let hum = 2 * Double.pi * 146.83
            let brightness = 0.02 + 0.2 * (1 - damping)
            return ImpulseResponse(seconds: 2.5, seed: 4) { time, noise in
                exp(-2.2 * time) * (sin(hum * time) + brightness * noise)
            }
        case .bouncing:
            // A dropped ball: a burst on every bounce, the gaps closing by a
            // fixed ratio, each burst a little softer than the last.
            let rebound = 0.72
            return ImpulseResponse(seconds: 1.8, seed: 5) { time, noise in
                var sum = 0.0
                var at = 0.0, gap = 0.42
                for bounce in 0..<14 where time >= at {
                    sum += exp(-(time - at) / (0.012 + 0.03 * damping)) * pow(rebound, Double(bounce))
                    at += gap
                    gap *= rebound
                }
                return sum * (0.5 + 0.5 * noise)
            }
        }
    }

    private func rebuild() {
        impulse = drawnRoom()
        synth.reverb = Reverb(impulse, mix: mix, preDelay: preDelay)
        built = recipe

        // The picture: the peak of the answer over each column of the frame.
        let side = impulse.channels[0]
        let count = 420
        columns = (0..<count).map { column in
            let from = side.count * column / count
            let to = max(from + 1, side.count * (column + 1) / count)
            return Double(side[from..<to].reduce(Float(0)) { max($0, abs($1)) })
        }
        let peak = columns.max() ?? 1
        if peak > 0 { columns = columns.map { $0 / peak } }
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        if built != recipe { rebuild() }
        // The mix rides the room already sounding, so it is set every frame
        // without starting the room over.
        synth.reverb = Reverb(impulse, mix: mix, preDelay: preDelay)

        for next in counter.steps(upTo: tempo.beats(at: time)) {
            let degree = phrase[next % phrase.count]
            guard degree >= 0 else { continue }
            synth.play(pentatonic[degree + (next / phrase.count % 2) * 5], velocity: 0.85, for: 0.2)
        }

        trace.append(Double(synth.amplitude))
        if trace.count > 360 { trace.removeFirst() }

        drawRoom()
        drawTrace()
        drawCaption("A room drawn from a rule, and an instrument heard in it.", edge: .top)
        drawCaption("The picture is the room's answer to one click, "
                    + "\(String(format: "%.1f", impulse.duration)) s long. "
                    + "The trace is the instrument in that room.")
    }

    /// The room's answer to a click, as a waveform across the frame.
    private func drawRoom() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.26,
                              width: width * 0.8, height: height * 0.38)
        let middle = frame.center.y
        let lead = min(preDelay, 0.2) / (impulse.duration + min(preDelay, 0.2))

        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.25))
        strokeWeight(1 * scale)
        drawLine(frame.x, middle, frame.topRight.x, middle)

        // The pre-delay is the silence before the room, drawn as its own band.
        let start = frame.x + frame.width * lead
        if lead > 0 {
            noStroke()
            fill(Color(hex: 0x6FA8DC, alpha: 0.08))
            drawRect(frame.x, frame.y, start - frame.x, frame.height)
        }

        let span = frame.topRight.x - start
        let warmth = Ramp([Color(hex: 0xE8A33D), Color(hex: 0x7FD4C1)])
        strokeWeight(max(1, span / Double(columns.count) * 0.7))
        for (index, value) in columns.enumerated() {
            let x = start + span * (Double(index) + 0.5) / Double(columns.count)
            stroke(warmth.color(at: Double(index) / Double(max(1, columns.count - 1))))
            let reach = value * frame.height * 0.48
            drawLine(x, middle - reach, x, middle + reach)
        }
    }

    /// What actually came out, so the room and the sound share a screen.
    private func drawTrace() {
        guard trace.count > 2 else { return }
        let frame = Rectangle(x: width * 0.1, y: height * 0.72,
                              width: width * 0.8, height: height * 0.12)
        noFill()
        stroke(Color(hex: 0x7FD4C1, alpha: 0.85))
        strokeWeight(2 * scale)
        drawPolyline(trace.enumerated().map { position, value in
            Vector2(frame.x + frame.width * Double(position) / Double(max(1, trace.count - 1)),
                    frame.y + frame.height * (1 - min(value * 4, 1)))
        })
    }
}
