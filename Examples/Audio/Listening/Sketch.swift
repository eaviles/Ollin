import Ollin
import OllinAudio

/// Listening: the microphone read for *what* it is hearing rather than how loud
/// it is. Speak and the words appear as a caption that corrects itself; clap,
/// whistle, tap the desk, or play music and the sound is named.
///
/// Both listeners are bound to the same `AudioInput`, which is the point of the
/// tap hub: one microphone, several things listening to it.
///
/// The two reads are deliberately different shapes. A caption is a running
/// guess, so it is drawn. A sound event happens once, so it is drained and
/// leaves a mark. Recognition runs on this Mac and asks for no consent of its
/// own; the microphone asks for its own, the first time `start()` is called.
@main
final class Listening: Sketch {

    let mic = AudioInput()
    var speech: SpeechListener!
    var ears: SoundClassifier!

    /// One named sound, drawn where it landed and fading out.
    struct Mark {
        let label: String
        let confidence: Double
        let at: Vector2
        let born: Double
    }
    var marks: [Mark] = []

    let paper = Color(hex: 0x121316)
    let ink = Color(hex: 0xF2EFE9)
    let accent = Color(hex: 0xE4572E)

    override func setup() {
        speech = SpeechListener(of: mic)
        ears = SoundClassifier(of: mic, threshold: 0.55)
        try? mic.start()
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(paper)

        drawLevel()
        drawNamedSounds()
        drawCaption()
        drawStatusLine()
    }

    /// A quiet ring of the live level, so the sketch is alive even in silence.
    private func drawLevel() {
        let radius = (120 + Double(mic.amplitude) * 900) * scale
        noFill()
        stroke(ink.withAlpha(0.12))
        strokeWeight(2 * scale)
        drawCircle(center: center, radius: radius)
    }

    /// Every sound the classifier names leaves a mark, placed on a ring by the
    /// first letter of its label so the same sound lands in the same place.
    private func drawNamedSounds() {
        for event in ears.events() {
            let hash = event.label.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
            let angle = Double(hash) / 65535 * .tau
            let reach = (280 + Double(hash % 97) * 1.6) * scale
            marks.append(Mark(label: event.label, confidence: event.confidence,
                              at: center + Vector2(angle: angle) * reach,
                              born: time))
        }
        marks.removeAll { time - $0.born > 6 }

        textSize(15 * scale)
        textAlign(.center)
        for mark in marks {
            let age = (time - mark.born) / 6
            let fade = 1 - age * age
            noStroke()
            fill(accent.withAlpha(0.5 * fade))
            drawCircle(center: mark.at, radius: (6 + mark.confidence * 26) * scale * (1 + age))
            fill(ink.withAlpha(fade))
            drawText(mark.label.replacingOccurrences(of: "_", with: " "),
                     at: mark.at + Vector2(0, 34 * scale))
        }
    }

    /// The caption: the running guess, which is the read that is allowed to
    /// change its mind.
    private func drawCaption() {
        noStroke()
        fill(ink)
        textAlign(.center)
        textSize(34 * scale)
        let box = Rectangle(x: width * 0.1, y: height * 0.42, width: width * 0.8, height: height * 0.2)
        drawText(speech.caption, in: box)

        // What the classifier thinks it is hearing right now, under the words.
        if let top = ears.topClassification, top.confidence > 0.25 {
            fill(ink.withAlpha(0.4))
            textSize(17 * scale)
            drawText("sounds like \(top.label.replacingOccurrences(of: "_", with: " "))",
                     at: Vector2(width / 2, height * 0.66))
        }
    }

    private func drawStatusLine() {
        if let reason = speech.unavailableReason ?? ears.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !mic.isRunning { return drawCaption("Microphone: allow access to listen") }
        if !speech.isListening { return drawCaption("Starting the recognizer") }
        drawCaption("Say something, or clap. The caption corrects itself as it hears more.")
    }
}
