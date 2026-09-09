import Ollin
import OllinAudio

/// The three effects that hold a level.
///
/// Where the four motions move a sound, these three watch how loud it is. A
/// **compressor** lets what is over its threshold through at a fraction of what
/// it does, so the accents stop towering over the quiet notes, and `Makeup`
/// brings the whole thing back up with them still held. A **limiter** is a
/// promise instead of a shape: nothing leaves above `Ceiling`, whatever
/// arrives. A **gate** turns the sound down below its threshold, which takes
/// the room out of the gaps; the chain here puts a hiss in front of it to have
/// something to take out.
///
/// The meter is the last four seconds in decibels, with the line where the
/// threshold sits. Watch the accents flatten against it as `Threshold` comes
/// down and `Ratio` goes up, and watch a fast `Attack` catch the very start of
/// a note where a slow one lets it through. `Dry` is the phrase with nothing
/// done to it.
@main
final class Levels: Sketch {

    enum Work: String, ParamOption { case dry, compressor, limiter, gate }
    @Param(style: .segmented, group: "Level") var work = Work.compressor
    @Param("Threshold", -60 ... 0, icon: "arrow.down.to.line", group: "Level") var threshold = -20.0
    @Param("Ratio", 1 ... 20, icon: "divide", group: "Level") var ratio = 4.0
    @Param("Attack", 0.001 ... 0.2, icon: "hare", group: "Level") var attack = 0.01
    @Param("Release", 0.01 ... 1, icon: "tortoise", group: "Level") var release = 0.2
    @Param("Makeup", 0 ... 24, icon: "arrow.up.to.line", group: "Level") var makeup = 6.0
    @Param("Ceiling", -24 ... 0, icon: "square.topthird.inset.filled", group: "Limiter") var ceiling = -12.0
    @Param("Hold", 0 ... 0.5, icon: "clock", group: "Gate") var hold = 0.06

    let synth = Synth(.pluck, polyphony: 8)
    let notes = Scale(.minorPentatonic, root: "A2")
    let tempo: Tempo = 96
    var counter = StepCounter(perBeat: 2)
    let phrase = [0, 3, 1, 4, 2, 5, 1, 3]
    /// The last four seconds of level, in decibels.
    var meter: [Double] = []

    override func setup() {
        synth.gain = 0.5
    }

    /// A hiss under everything, so the gate has a room to take out. It sits
    /// first in the chain, which is what puts it where the gate can hear it.
    private var hiss: Effect {
        .custom("room", state: UInt32(22)) { sound, seed in
            for index in 0..<sound.frameCount {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = (Float(seed >> 9) / Float(1 << 23) - 0.5) * 0.008
                sound.left[index] += noise
                sound.right[index] += noise
            }
        }
    }

    /// The chain the parameters describe. Set every frame: it only rewires when
    /// the kind changes, and a setting change rides the level already followed.
    private var chain: [Effect] {
        switch work {
        case .dry:
            return [hiss]
        case .compressor:
            return [hiss, .compressor(Compressor(threshold: threshold, ratio: ratio,
                                                 attack: attack, release: release,
                                                 knee: 6, makeup: makeup))]
        case .limiter:
            return [hiss, .limiter(Limiter(ceiling: ceiling, release: release))]
        case .gate:
            return [hiss, .gate(Gate(threshold: threshold, attack: attack,
                                     hold: hold, release: release))]
        }
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        synth.effects = chain

        // A phrase whose every fourth note is an accent, so there is a range
        // to hold: without one a compressor has nothing to say.
        for next in counter.steps(upTo: tempo.beats(at: time)) {
            let accent = next % 4 == 0
            synth.play(notes[phrase[next % phrase.count]],
                       velocity: accent ? 1.0 : 0.28,
                       for: accent ? 0.9 : 0.35)
        }

        meter.append(20 * log10(max(Double(synth.amplitude), 1e-6)))
        if meter.count > 240 { meter.removeFirst() }

        drawMeter()
        drawCaption(caption, edge: .top)
        drawCaption("The line is the threshold. Watch the accents meet it.")
    }

    private var caption: String {
        switch work {
        case .dry:        return "Dry: the accents tower over the quiet notes."
        case .compressor: return "Compressor: over the threshold, four decibels arrive as one."
        case .limiter:    return "Limiter: nothing leaves above the ceiling."
        case .gate:       return "Gate: under the threshold, the room goes quiet."
        }
    }

    /// The last four seconds of level, in decibels, with the line the settings
    /// put across it.
    private func drawMeter() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.24,
                              width: width * 0.8, height: height * 0.5)
        let floor = -60.0
        func y(_ decibels: Double) -> Double {
            frame.y + frame.height * (1 - (min(max(decibels, floor), 0) - floor) / -floor)
        }

        stroke(Color(hex: 0x2A3340))
        strokeWeight(1 * scale)
        for level in stride(from: 0.0, through: floor, by: -12) {
            drawLine(frame.x, y(level), frame.topRight.x, y(level))
        }

        let line = work == .limiter ? ceiling : threshold
        if work != .dry {
            stroke(Color(hex: 0xE8A33D, alpha: 0.9))
            strokeWeight(2 * scale)
            drawLine(frame.x, y(line), frame.topRight.x, y(line))
        }

        guard meter.count > 2 else { return }
        noFill()
        stroke(Color(hex: 0x7FD4C1))
        strokeWeight(2.5 * scale)
        drawPolyline(meter.enumerated().map { position, level in
            Vector2(frame.x + frame.width * Double(position) / Double(max(1, meter.count - 1)),
                    y(level))
        })
    }
}
