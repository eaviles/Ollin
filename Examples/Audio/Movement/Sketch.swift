import Ollin
import OllinAudio

/// The four effects that move a sound.
///
/// Each is one slow wave and the thing it moves. A **chorus** moves a copy
/// of the sound, twenty milliseconds behind, later and earlier, so one voice
/// reads as several. A **flanger** brings the copy in to a millisecond or
/// so, where it cuts a comb of notches through the spectrum, and sweeps the
/// comb. A **phaser** turns the sound's phase through a row of stages and
/// adds it back, one notch per pair of stages, swept up and down. A
/// **tremolo** moves the level. `Rate` and `Depth` are the wave, on every
/// one of them; `Feedback` sharpens a flanger's teeth or makes a phaser's
/// peaks ring, `Stages` is the phaser's row, `Spread` swings a tremolo from
/// side to side, and `Mix` is how much of the moved sound is heard. Turn any
/// of them while the phrase plays: the motion carries on from where it was.
/// The wave drawn over the trace is one at the rate and depth set.
@main
final class Movement: Sketch {

    enum Motion: String, ParamOption { case chorus, flanger, phaser, tremolo }
    @Param(icon: "waveform.path", group: "Motion") var motion = Motion.chorus
    @Param("Rate", 0.05 ... 8, icon: "metronome", group: "Motion") var rate = 0.8
    @Param("Depth", 0 ... 1, icon: "arrow.up.and.down", group: "Motion") var depth = 0.6
    @Param("Feedback", -0.9 ... 0.9, icon: "arrow.uturn.backward", group: "Motion") var feedback = 0.4
    @Param("Stages", 1 ... 12, icon: "square.stack", group: "Motion") var stages = 4
    @Param("Spread", 0 ... 1, icon: "arrow.left.and.right", group: "Motion") var spread = 0.0
    @Param("Mix", 0 ... 1, icon: "drop", group: "Finish") var mix = 0.5

    let synth = Synth(.pad, polyphony: 8)
    let dorian = Scale(.dorian, root: "D3")
    let tempo: Tempo = 76
    var counter = StepCounter(perBeat: 2)
    let phrase = [0, 4, 2, 6, 4, 7, 2, 5]
    var trace: [Double] = []

    override func setup() {
        synth.gain = 0.45
    }

    /// The effect the parameters describe. Set every frame: the chain only
    /// rewires when the kind changes, and a setting change rides the motion
    /// already running.
    private var effect: Effect {
        switch motion {
        case .chorus:
            return .chorus(Chorus(rate: rate, depth: depth, mix: mix))
        case .flanger:
            return .flanger(Flanger(rate: rate, depth: depth, feedback: feedback, mix: mix))
        case .phaser:
            return .phaser(Phaser(rate: rate, depth: depth, stages: stages, feedback: feedback, mix: mix))
        case .tremolo:
            return .tremolo(Tremolo(rate: rate, depth: depth, spread: spread))
        }
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        synth.effects = [effect]

        // A slow phrase, and a low note held under every bar so the motion
        // has something sustained to move.
        for next in counter.steps(upTo: tempo.beats(at: time)) {
            synth.play(dorian[phrase[next % phrase.count]], velocity: 0.8, for: 0.55)
            if next % 8 == 0 { synth.play(dorian[-7], velocity: 0.7, for: 3.6) }
        }

        trace.append(Double(synth.amplitude))
        if trace.count > 360 { trace.removeFirst() }

        drawWave()
        drawTrace()
        drawCaption(caption, edge: .top)
        drawCaption("Rate and depth are the wave; the rest is what it moves.")
    }

    private var caption: String {
        switch motion {
        case .chorus:  return "Chorus: a copy sliding later and earlier, so one voice reads as several."
        case .flanger: return "Flanger: a copy a hair behind, sweeping a comb of notches through the sound."
        case .phaser:  return "Phaser: a notch per pair of stages, swept up and down the spectrum."
        case .tremolo: return "Tremolo: the level breathing."
        }
    }

    /// The wave, at the rate and depth set, over the last three seconds.
    private func drawWave() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.26,
                              width: width * 0.8, height: height * 0.38)
        let middle = frame.center.y
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.25))
        strokeWeight(1 * scale)
        drawLine(frame.x, middle, frame.topRight.x, middle)

        let warmth = Ramp([Color(hex: 0xE8A33D), Color(hex: 0x7FD4C1)])
        let count = 240
        strokeWeight(3 * scale)
        var previous: Vector2? = nil
        for column in 0...count {
            let u = Double(column) / Double(count)
            let t = time - 3 + 3 * u
            let value = depth * sin(2 * .pi * rate * t)
            let point = Vector2(frame.x + frame.width * u, middle - value * frame.height * 0.45)
            if let previous {
                stroke(warmth.color(at: u))
                drawLine(previous, point)
            }
            previous = point
        }
        // The tremolo's second side, when it breathes apart from the first.
        if motion == .tremolo && spread > 0.01 {
            stroke(Color(hex: 0xE8A33D, alpha: 0.35))
            strokeWeight(1.5 * scale)
            drawPolyline((0...count).map { column in
                let u = Double(column) / Double(count)
                let t = time - 3 + 3 * u
                let value = depth * sin(2 * .pi * (rate * t + spread * 0.5))
                return Vector2(frame.x + frame.width * u, middle - value * frame.height * 0.45)
            })
        }
    }

    /// What came out, so the wave and the sound share a screen.
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
