import Ollin
import OllinAudio

/// Chords that come out of a key.
///
/// A progression is written as scale degrees rather than as chord names,
/// because that is the fact that survives changing key. `I vi IV V` is the same
/// progression in every key there is, and the qualities fall out of the scale
/// instead of having to be said. Change the key with the knob while it plays
/// and the same four numbers come out major, minor, or somewhere stranger.
///
/// Press `W` to let it wander: the moves this progression already makes become
/// the moves a longer one is allowed to make, so what follows belongs to the
/// same music without being the same cycle.
///
/// The ring is the cycle, the lit wedge is the chord sounding, and the columns
/// under it are its notes.
@main
final class Changes: Sketch {

    @Param(icon: "music.quarternote.3", group: "Key") var mode = Scale.Mode.major
    @Param(0 ... 11, icon: "pianokeys", group: "Key") var root = 0
    @Param(3 ... 5, icon: "square.stack.3d.up", group: "Chords") var notes = 4
    @Param(50 ... 150, icon: "metronome", group: "Chords") var tempo = 74.0

    let chords = Synth(.pad, polyphony: 16)
    let bass = Synth(.bass, polyphony: 4)

    var changes = Progression([0], in: Scale())
    var counter = StepCounter(perBeat: 0.5)
    var sounding = 0
    var lit: [Double] = []
    var built = ""
    var wandering = false

    override func setup() {
        chords.gain = 0.36
        chords.reverb = Reverb(.hall, mix: 0.3)
        bass.gain = 0.42
        rebuild()
    }

    private var recipe: String { "\(mode)-\(root)-\(notes)-\(wandering)" }

    private func rebuild() {
        let key = Scale(mode, root: Pitch(48 + Double(root)))
        let base = Progression("I vi IV V ii V", in: key, notes: notes)
        // A wander is seeded, so the same one comes back rather than a new one
        // every time a knob moves.
        changes = wandering ? base.wandering(24, seed: 5) : base
        lit = [Double](repeating: 0, count: changes.count)
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        if built != recipe { rebuild() }

        for step in counter.steps(upTo: time * tempo / 60) {
            let index = step % max(1, changes.count)
            sounding = index
            if index < lit.count { lit[index] = 1 }
            chords.play(chord: changes.pitches(at: index), velocity: 0.5, for: 1.6)
            bass.play(changes.root(at: index).transposed(by: -12), velocity: 0.85, for: 1.4)
        }

        drawCycle()
        drawCaption("The same four numbers in any key. Change the key while it plays.",
                    edge: .top)
        drawCaption(wandering
                    ? "Wandering: only the moves the progression already made."
                    : "Press W to let it wander off, using only its own moves.")
    }

    private func drawCycle() {
        let middle = Vector2(width / 2, height * 0.46)
        let radius = shortSide * 0.26
        let count = max(1, changes.count)

        // The cycle as a ring of wedges, one per chord.
        for index in 0 ..< count {
            let from = -Double.pi / 2 + Double(index) / Double(count) * .tau
            let to = -Double.pi / 2 + Double(index + 1) / Double(count) * .tau
            lit[index] *= pow(0.06, deltaTime)

            let glow = index == sounding ? 1.0 : lit[index]
            noFill()
            stroke(Colormap.magma.color(at: 0.25 + Double(changes.degree(at: index))
                                        / Double(max(1, changes.scale.degreeCount)) * 0.55)
                .withAlpha(0.2 + glow * 0.8))
            strokeWeight((3 + glow * 9) * scale)
            drawArc(center: middle, rx: radius, ry: radius,
                    start: from + 0.02, stop: to - 0.02, mode: .open)
        }

        // The chord sounding now, written out and drawn as its notes.
        let pitches = changes.pitches(at: sounding)
        noStroke()
        fill(Color(white: 0.85))
        textSize(26 * scale)
        textAlign(.center)
        let name = changes.chord(at: sounding).map { "\($0.root)" }
            ?? "\(changes.root(at: sounding))"
        drawText(name, at: Vector2(middle.x, middle.y + 8 * scale))

        let base = height * 0.82
        for (index, pitch) in pitches.enumerated() {
            let x = middle.x + (Double(index) - Double(pitches.count - 1) / 2) * 54 * scale
            let lift = (pitch.midi - 48) / 36
            fill(Colormap.magma.color(at: 0.3 + lift * 0.5).withAlpha(0.85))
            drawRect(center: Vector2(x, base - lift * 90 * scale),
                     width: 34 * scale, height: 34 * scale)
        }
    }

    override func keyPressed() {
        guard key == "w" || key == "W" else { return }
        wandering.toggle()
    }
}
