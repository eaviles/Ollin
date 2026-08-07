import Ollin
import OllinAudio

/// A playable instrument. The home row is two octaves of a scale: hold a key and
/// the note sounds until you let go, which is `noteOn` and `noteOff`. The number
/// keys 1 to 7 change what a note is made of, and space adds a room around it.
///
/// A `Synth` is also an `AudioSource`, so the sketch draws what it is playing
/// from the same surface a microphone would give it: the line across the middle
/// is `waveform`, read back out of the synth's own output.
///
/// Nothing here is timed by the sketch. Each key press asks for a note, and the
/// envelope on the voice decides how it arrives and how long it takes to go.
@main
final class SynthKeyboard: Sketch {
    let synth = Synth(.pluck)

    /// The home row, as the white keys of two octaves from middle C.
    let keys: [(Character, Pitch)] = [
        ("a", 60), ("s", 62), ("d", 64), ("f", 65),
        ("g", 67), ("h", 69), ("j", 71), ("k", 72),
        ("l", 74), (";", 76),
    ]
    let voices: [(String, Voice)] = [
        ("pluck", .pluck), ("bass", .bass), ("pad", .pad), ("bell", .bell),
        ("stab", .stab), ("breath", .breath), ("sine", .sine),
    ]

    var held = Set<Character>()
    var marks: [(x: Double, start: Double, tone: Double)] = []
    var voiceIndex = 0
    var inARoom = false

    override func setup() {
        noStroke()
        synth.gain = 0.5
    }

    override func draw() {
        background(Color(white: 0.06))
        pollKeys()

        let plateWidth = Double(width) / Double(keys.count)

        // Notes rise from the key that made them and fade as they go.
        marks.removeAll { time - $0.start > 4 }
        for mark in marks {
            let age = (time - mark.start) / 4
            fill(Colormap.magma.color(at: 0.25 + mark.tone * 0.6).withAlpha(1 - age))
            let y = Double(height) - 160 * scale - age * Double(height) * 0.85
            drawRect(corner: Vector2(mark.x + 6 * scale, y),
                     width: plateWidth - 12 * scale, height: 10 * scale)
        }

        // What the synth is actually putting out, straight from its analyzer.
        let trace = synth.waveform
        if !trace.isEmpty {
            stroke(Color(white: 0.38))
            strokeWeight(1.5 * scale)
            noFill()
            let middle = Double(height) * 0.45
            let points = trace.enumerated().map { index, sample in
                Vector2(Double(index) / Double(trace.count - 1) * Double(width),
                        middle + Double(sample) * 200 * scale)
            }
            drawPolyline(points)
            noStroke()
        }

        // The keys themselves, lit while held.
        for (index, entry) in keys.enumerated() {
            let x = Double(index) * plateWidth
            let isDown = held.contains(entry.0)
            fill(isDown ? Colormap.magma.color(at: 0.25 + Double(index) / Double(keys.count) * 0.6)
                        : Color(white: 0.16))
            drawRect(corner: Vector2(x + 6 * scale, Double(height) - 150 * scale),
                     width: plateWidth - 12 * scale, height: 120 * scale)
            fill(Color(white: isDown ? 0.1 : 0.45))
            textSize(22 * scale)
            textAlign(.center)
            drawText(String(entry.0).uppercased(),
                     at: Vector2(x + plateWidth / 2, Double(height) - 80 * scale))
        }

        drawCaption("Synth: hold A to ; ,  1-7 voice (\(voices[voiceIndex].0)),  space room \(inARoom ? "on" : "off")",
                    edge: .top)
    }

    /// Held notes are a poll, not an event: a key that is down and was not is a
    /// note starting, and one that is up and was down is a note being let go.
    private func pollKeys() {
        for (character, pitch) in keys {
            let isDown = isKeyDown(character)
            if isDown && !held.contains(character) {
                held.insert(character)
                synth.noteOn(pitch, velocity: 0.85)
                let index = keys.firstIndex { $0.0 == character } ?? 0
                marks.append((x: Double(index) * Double(width) / Double(keys.count),
                              start: time,
                              tone: Double(index) / Double(keys.count)))
            } else if !isDown && held.contains(character) {
                held.remove(character)
                synth.noteOff(pitch)
            }
        }
    }

    override func keyPressed() {
        if let key, let digit = key.wholeNumberValue, (1...voices.count).contains(digit) {
            voiceIndex = digit - 1
            synth.voice = voices[voiceIndex].1   // notes already sounding are undisturbed
        }
        if key == " " {
            inARoom.toggle()
            synth.reverb = inARoom ? Reverb(.hall, mix: 0.35) : nil
            synth.delay = inARoom ? Delay(time: 0.28, feedback: 0.35, mix: 0.25) : nil
        }
    }
}
