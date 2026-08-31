import Ollin
import OllinAudio

/// Twelve is a choice.
///
/// A `Tuning` describes pitches by frequency ratios and the interval they
/// repeat over, which covers the ordinary keyboard as one case among many.
/// This sketch keeps a triad sounding and walks a melody up the whole tuning,
/// one degree per step, while the ladder shows where every degree actually
/// sits: each rung is a pitch, placed by its `cents` above the root, and the
/// label is how far it leans away from the equal-tempered grid on the left.
///
/// Switch the tuning with the knob and listen for two things. In `.just` and
/// `.thirtyOne` the held triad locks and sits still where the equal one beats
/// slowly, because their thirds are whole number ratios or near them; the
/// ladder shows the same fact as rungs pulled 14 cents off the grid. And
/// `.bohlenPierce` repeats over a twelfth rather than an octave, so its ladder
/// is taller than everyone else's and almost nothing lines up.
///
/// The triad is found with `snap(_:)`: the sketch asks for an equal-tempered
/// root, third, and fifth, and each tuning answers with its own nearest
/// pitches, which is how a number that did not come from music joins a tuning.
@main
final class Tunings: Sketch {

    /// The named tunings, on a menu. A local enum rather than the type itself,
    /// because a menu needs a fixed roster of named values.
    enum Choice: String, CaseIterable, ParamOption {
        case equalTemperament, just, pythagorean, quarterTones
        case nineteen, thirtyOne, bohlenPierce

        var tuning: Tuning {
            switch self {
            case .equalTemperament: return .equalTemperament
            case .just:             return .just
            case .pythagorean:      return .pythagorean
            case .quarterTones:     return .quarterTones
            case .nineteen:         return .nineteen
            case .thirtyOne:        return .thirtyOne
            case .bohlenPierce:     return .bohlenPierce
            }
        }

        /// One line of what to listen for.
        var lesson: String {
            switch self {
            case .equalTemperament:
                return "Every key equally usable, every interval slightly wrong: the triad beats slowly."
            case .just:
                return "Whole number ratios: the third sits 14 cents low and the triad locks."
            case .pythagorean:
                return "Stacked fifths: a very pure fifth, and a third 8 cents wide of even the grid."
            case .quarterTones:
                return "The keyboard plus every pitch between its keys."
            case .nineteen:
                return "Nineteen equal steps: a sweeter third, and notes a piano spells the same come apart."
            case .thirtyOne:
                return "Thirty one steps, close enough to whole number thirds that chords stop beating."
            case .bohlenPierce:
                return "Thirteen steps of a twelfth: no octave anywhere, and odd harmonics still line up."
            }
        }
    }

    @Param(icon: "tuningfork", group: "Tuning") var choice = Choice.just
    @Param(60 ... 180, icon: "metronome", group: "Playing") var tempo = 132.0

    let pad = Synth(.pad, polyphony: 12)
    let steps = Synth(.pluck, polyphony: 8)
    var counter = StepCounter(perBeat: 2)
    var chordCounter = StepCounter(perBeat: 0.125)

    var tuning = Tuning.just
    var triad: [Pitch] = []
    var triadDegrees: Set<Int> = []
    var lit: [Double] = []
    var sounding = 0
    var built = ""

    override func setup() {
        pad.gain = 0.3
        pad.reverb = Reverb(.hall, mix: 0.25)
        steps.gain = 0.5
        rebuild()
    }

    private var recipe: String { "\(choice)" }

    private func rebuild() {
        tuning = choice.tuning
        // An equal-tempered root, third, and fifth, and the tuning's own
        // nearest answer to each. This is what snap is for.
        let root = tuning.root
        triad = [root, tuning.snap(root.transposed(by: 4)),
                 tuning.snap(root.transposed(by: 7))]
        triadDegrees = Set(triad.compactMap { pitch in
            tuning.cents.indices.first { index in
                abs(tuning.pitch(index).midi - pitch.midi) < 0.001
            }
        })
        lit = [Double](repeating: 0, count: tuning.degreeCount + 1)
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0C0E12))
        if built != recipe { rebuild() }

        // The melody climbs the whole tuning, one degree per step, top note
        // included, so every rung on the ladder gets heard.
        let lap = tuning.degreeCount + 1
        for step in counter.steps(upTo: time * tempo / 60) {
            sounding = step % lap
            lit[sounding] = 1
            steps.play(tuning[sounding], velocity: 0.6, for: 0.5)
        }
        // The triad holds underneath, replayed every couple of bars.
        for _ in chordCounter.steps(upTo: time * tempo / 60) {
            pad.play(chord: triad, velocity: 0.5, for: 8 * 60 / tempo)
        }

        drawLadder()
        drawCaption("Each rung is a pitch; its label is how far it leans off the equal grid, in cents.",
                    edge: .top)
        drawCaption(choice.lesson)
    }

    private func drawLadder() {
        let cents = tuning.cents + [1200 * log2(tuning.period)]
        let span = cents.last ?? 1200
        let top = height * 0.16
        let bottom = height * 0.86
        let railX = width * 0.36
        let rungX = width * 0.56

        func y(_ cent: Double) -> Double { bottom - cent / span * (bottom - top) }

        // The left rail: the equal-tempered grid, one mark per 100 cents,
        // which is the keyboard the deviations are measured against.
        stroke(Color(white: 0.3))
        strokeWeight(2 * scale)
        drawLine(railX, y(0), railX, y(span))
        var grid = 0.0
        while grid <= span + 0.5 {
            stroke(Color(white: 0.3))
            drawLine(railX - 14 * scale, y(grid), railX, y(grid))
            grid += 100
        }

        // The rungs: every degree at its true height, joined to the grid mark
        // it is nearest, so a leaning line is an interval the keyboard bends.
        for (index, cent) in cents.enumerated() {
            lit[index] *= pow(0.08, deltaTime)
            let glow = index == sounding % cents.count ? 1.0 : lit[index]
            let inTriad = triadDegrees.contains(index % tuning.degreeCount)
            let nearest = (cent / 100).rounded() * 100
            let deviation = Int((cent - nearest).rounded())

            let tone = inTriad ? Color(hex: 0xE4B34C)
                               : Colormap.viridis.color(at: 0.25 + 0.6 * cent / span)
            stroke(tone.withAlpha(0.35 + glow * 0.65))
            strokeWeight((1.5 + glow * 3) * scale)
            drawLine(railX, y(min(nearest, span)), rungX, y(cent))
            drawLine(rungX, y(cent), rungX + 44 * scale, y(cent))

            noStroke()
            fill(tone.withAlpha(0.55 + glow * 0.45))
            textSize(13 * scale)
            textAlign(.left, .middle)
            let sign = deviation > 0 ? "+" : ""
            drawText("\(tuning.pitch(index))  \(sign)\(deviation)",
                     at: Vector2(rungX + 54 * scale, y(cent)))
        }

        // What is sounding, written large.
        noStroke()
        fill(Color(white: 0.85))
        textSize(30 * scale)
        textAlign(.center)
        drawText("\(tuning[sounding])", at: Vector2(width * 0.18, height * 0.5))
        fill(Color(white: 0.5))
        textSize(15 * scale)
        drawText("\(tuning.degreeCount) degrees", at: Vector2(width * 0.18, height * 0.5 + 28 * scale))
    }
}
