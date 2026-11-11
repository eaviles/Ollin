import Foundation
import Ollin
import OllinAudio

/// A phrase that comes round again.
///
/// An echo with a long time and a high feedback is a loop. Every note played
/// goes into a line of sound six seconds long, comes out the other end
/// under whatever is being played by then, and goes round again a little
/// quieter. One slow line of notes becomes a canon with itself.
///
/// The ring is the loop. The hand is now, a note sits where it was played,
/// and it lights each time the hand comes back to it, dimmer on every pass by
/// the feedback. Click to add a note of your own: higher on the canvas is a
/// higher note.
@main
final class Loop: Sketch {

    @Param(2 ... 16, icon: "clock.arrow.circlepath", group: "The loop") var length = 6.0
    @Param(0 ... 0.95, icon: "arrow.triangle.2.circlepath", group: "The loop") var feedback = 0.85
    @Param(500 ... 20000, icon: "slider.horizontal.3", group: "The loop") var damping = 5000.0
    @Param(icon: "music.note", group: "Playing") var playsItself = true

    /// One note, and when it went into the line.
    struct Played {
        var at: Double
        var degree: Int
    }

    let synth = Synth(.pluck, polyphony: 8)
    let pentatonic = Scale(.minorPentatonic, root: "C3")
    let degrees = 10
    var played: [Played] = []
    var nextAt = 0.4
    var built = ""
    var builtLength = 0.0

    override func setup() {
        synth.gain = 0.5
        rebuild()
    }

    private var recipe: String { "\(length)-\(feedback)-\(damping)" }

    /// The echo is a value: turning one of its settings swaps the numbers on
    /// the link that is already in the chain, and the line keeps what it holds.
    private func rebuild() {
        synth.effects = [
            .delay(Delay(time: length, feedback: feedback, mix: 0.5, damping: damping)),
            .limiter(Limiter()),
        ]
        // The ring is drawn for one length, so a new length starts a new ring.
        // The sound itself carries on across the turn.
        if builtLength != length { played.removeAll() }
        builtLength = length
        built = recipe
    }

    private func play(_ degree: Int) {
        synth.play(pentatonic[degree], velocity: 0.8, for: 0.5)
        played.append(Played(at: time, degree: degree))
    }

    override func mousePressed() {
        let lifted = 1 - mouseY / height
        play(min(degrees - 1, max(0, Int(lifted * Double(degrees)))))
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))
        if built != recipe { rebuild() }

        if playsItself, time >= nextAt {
            play(Int(random(0, Double(degrees))))
            nextAt = time + random(0.7, 1.9)
        }
        // A note that has faded past hearing has left the line.
        played.removeAll { level(of: $0) < 0.03 }

        drawRing()
        drawCaption("An echo \(Int(length.rounded())) seconds long is a loop: each note comes round again, quieter.",
                    edge: .top)
        drawCaption("The hand is now. A note lights when the hand comes back to it. Click to add one.")
    }

    /// How many times a note has been round, and how loud that leaves it.
    private func passes(of note: Played) -> Int { Int((time - note.at) / length) }
    private func level(of note: Played) -> Double { pow(feedback, Double(passes(of: note))) }

    private func drawRing() {
        let center = Vector2(width / 2, height / 2)
        let radius = min(width, height) * 0.27
        let lane = radius * 0.07

        // One faint circle for each note of the scale: higher is further out.
        noFill()
        strokeWeight(1 * scale)
        stroke(Color(hex: 0x6FA8DC, alpha: 0.1))
        for degree in 0..<degrees {
            drawCircle(center.x, center.y, radius + (Double(degree) - Double(degrees - 1) / 2) * lane)
        }
        stroke(Color(hex: 0x6FA8DC, alpha: 0.3))
        strokeWeight(1.5 * scale)
        drawCircle(center.x, center.y, radius - lane * Double(degrees) / 2 - lane)
        drawCircle(center.x, center.y, radius + lane * Double(degrees) / 2 + lane)

        // Now, as an angle: a full turn is one trip round the line.
        let now = time.truncatingRemainder(dividingBy: length) / length * 2 * .pi - .pi / 2
        stroke(Color(hex: 0xE8A33D, alpha: 0.9))
        strokeWeight(2 * scale)
        let inner = radius - lane * Double(degrees) / 2 - lane
        let outer = radius + lane * Double(degrees) / 2 + lane
        drawLine(center.x + cos(now) * inner, center.y + sin(now) * inner,
                 center.x + cos(now) * outer, center.y + sin(now) * outer)

        noStroke()
        for note in played {
            let angle = note.at.truncatingRemainder(dividingBy: length) / length * 2 * .pi - .pi / 2
            let distance = radius + (Double(note.degree) - Double(degrees - 1) / 2) * lane
            let loud = level(of: note)
            // Seconds since the hand last came back to it.
            let since = (time - note.at) - Double(passes(of: note)) * length
            let lit = exp(-since * 2.5)
            fill(Color(hex: 0x7FD4C1, alpha: loud * (0.45 + 0.55 * lit)))
            drawCircle(center.x + cos(angle) * distance, center.y + sin(angle) * distance,
                       (7 + 13 * lit) * scale * (0.55 + 0.45 * loud))
        }
    }
}
