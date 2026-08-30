import Ollin
import OllinAudio

/// A note you keep playing.
///
/// Every other instrument here is set going and then let go: a string is
/// plucked, a shape is struck, and the whole note is decided at its start. A
/// bow and a breath are not like that. They go on happening, so a note has a
/// middle, and the middle is yours.
///
/// Hold the mouse down to play. Moving it up and down is the drive: how fast
/// the bow is drawn, or how hard the tube is blown. Let go and the note stops,
/// because you stopped. Moving left and right changes the note.
///
/// Press `B` to swap the bow for a reed. Watch the ring while you play: it is
/// the sound the sketch is making, read back off its own playing.
@main
final class Bowing: Sketch {

    enum Instrument: String, ParamOption { case bowed, blown }

    @Param(icon: "hand.draw", group: "Playing") var instrument = Instrument.bowed
    @Param(0.02 ... 0.5, icon: "arrow.left.and.right", group: "Bow") var position = 0.16
    @Param(0 ... 1, icon: "arrow.down.circle", group: "Bow") var force = 0.6
    @Param(0 ... 1, icon: "mouth", group: "Reed") var embouchure = 0.45

    let synth = Synth(.cello, polyphony: 4)
    let tuning = Scale(.minorPentatonic, root: "D2")

    var playing: Pitch?
    var trail: [Double] = []
    var lastBuilt = Instrument.bowed

    override func setup() {
        synth.gain = 0.7
        synth.reverb = Reverb(.hall, mix: 0.24)
        synth.drive = 0
        rebuild()
    }

    /// The whole difference between the two, in one call each.
    private func rebuild() {
        switch instrument {
        case .bowed:
            synth.voice = Voice(bowed: BowedString(position: position, force: force,
                                                   decay: 2.2, damping: 0.45),
                                gain: 0.75)
        case .blown:
            synth.voice = Voice(blown: BlownTube(embouchure: embouchure, breathiness: 0.14,
                                                 decay: 0.17, damping: 0.42),
                                gain: 0.62)
        }
        lastBuilt = instrument
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))

        if instrument != lastBuilt { rebuild() }

        // Up the window is a faster bow or a harder breath. This is read every
        // frame while the note sounds, which is the thing an envelope cannot do.
        let wanted = mouseIsPressed ? map(mouseY, height, 0, 0, 1) : 0
        synth.drive = clamp(wanted, 0, 1)

        if mouseIsPressed {
            let degree = Int(map(mouseX, 0, width, 0, 12))
            let pitch = tuning[degree]
            if playing != pitch {
                if playing != nil { synth.allNotesOff() }
                synth.noteOn(pitch, velocity: 0.85)
                playing = pitch
            }
        } else if playing != nil {
            synth.allNotesOff()
            playing = nil
        }

        drawInstrument()
        drawCaption("Hold to play. Up and down is the bow speed, or the breath.", edge: .top)
        drawCaption(instrument == .bowed
                    ? "A bowed string: it sounds for as long as the bow keeps moving."
                    : "A stopped tube: only the odd harmonics, which is why it is hollow.")
    }

    private func drawInstrument() {
        let middle = center
        let level = Double(synth.amplitude)
        trail.append(level)
        if trail.count > 260 { trail.removeFirst() }

        // What is actually sounding, read back off the sketch's own playing.
        noFill()
        stroke(Color(hex: 0x7FD4C1, alpha: 0.5))
        strokeWeight(2 * scale)
        let radius = (150 + level * 700) * scale
        drawCircle(middle.x, middle.y, radius)

        // The drive, as a wedge: how hard the player is leaning on it now.
        stroke(Color(hex: 0xE8A33D, alpha: 0.8))
        strokeWeight(6 * scale)
        let start: Double = -Double.pi / 2
        let sweep: Double = synth.drive * Double.tau * 0.999
        let ring = 120 * scale
        drawArc(center: middle, radiusX: ring, radiusY: ring,
                start: start, stop: start + sweep, mode: .open)

        // The last few seconds of what came out, so a held note visibly has a
        // middle rather than only an attack.
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.75))
        strokeWeight(2 * scale)
        let frame = Rectangle(x: width * 0.12, y: height * 0.78,
                              width: width * 0.76, height: height * 0.12)
        if trail.count > 2 {
            drawPolyline(trail.enumerated().map { index, value in
                Vector2(frame.x + frame.width * Double(index) / Double(max(1, trail.count - 1)),
                        frame.y + frame.height * (1 - min(value * 5, 1)))
            })
        }

        if let playing {
            noStroke()
            fill(Color(white: 0.8))
            textSize(22 * scale)
            textAlign(.center)
            drawText("\(playing)", at: Vector2(middle.x, middle.y + 8 * scale))
        }
    }

    override func keyPressed() {
        guard key == "b" || key == "B" else { return }
        instrument = instrument == .bowed ? .blown : .bowed
    }
}
