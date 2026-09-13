import Ollin
import OllinAudio

/// A guitar tuner. Play a string and the nearest of the six lights up, the
/// needle swings to how many cents the string sits from that string's own
/// pitch (not the nearest note on the piano, so a string a semitone flat
/// still points at its peg), and the face turns green within three cents.
/// Standard tuning, low E to high E.
///
/// The microphone drives it as soon as it hears a string played
/// (`AudioInput.start()` asks for permission the first time). A reading counts
/// only within three semitones of one of the six strings, which is as far as a
/// string on a guitar gets from its peg; a room's hum, a fifth or more below
/// the low E, is left alone and never takes the floor. Until a string is
/// heard, and whenever the room has been quiet for a few seconds, a pretend
/// guitar stands in: the sketch synthesizes each string a little flat and
/// tunes it up peg-turn by peg-turn, feeding the samples to a real
/// `AudioAnalyzer` the way a microphone would. It makes no sound of its own,
/// so the demonstration is silent; play a string and your guitar takes over.
///
/// The one read that matters is `pitch`: its `midi` is compared to each
/// string's, the nearest wins, and the difference times a hundred is the cents
/// the needle shows.
@main
final class GuitarTuner: Sketch {
    struct GuitarString {
        let name: String
        let pitch: Pitch
    }
    let strings: [GuitarString] = [
        GuitarString(name: "E", pitch: "E2"), GuitarString(name: "A", pitch: "A2"),
        GuitarString(name: "D", pitch: "D3"), GuitarString(name: "G", pitch: "G3"),
        GuitarString(name: "B", pitch: "B3"), GuitarString(name: "E", pitch: "E4"),
    ]

    let mic = AudioInput()
    let pretend = PretendGuitar()
    var needle = 0.0
    var lit: Int? = nil
    var sinceHeard = 0.0
    var micHeardAt = -10.0

    override func setup() {
        noStroke()
        try? mic.start()
    }

    override func draw() {
        background(Color(white: 0.08))
        // The microphone takes the floor when it hears a note near one of the
        // strings, and hands the picture back to the pretend guitar three
        // seconds after the last one. A room's hum reads as a pitch too, but
        // far below the low E, so it never counts.
        let fromMic = mic.isRunning ? mic.pitch.flatMap(string(for:)) : nil
        if fromMic != nil { micHeardAt = time }
        let live = time - micHeardAt < 3
        if !live { pretend.pluck(at: time) }
        let reading = live ? fromMic : pretend.analyzer.pitch.flatMap(string(for:))

        var cents: Double? = nil
        if let reading {
            if lit != reading.index { needle = reading.cents } else { needle += (reading.cents - needle) * 0.25 }
            lit = reading.index
            cents = reading.cents
            sinceHeard = time
        } else if time - sinceHeard > 1.5 {
            lit = nil
        }

        drawGauge(cents: cents, top: 90 * scale)
        drawStrings(top: 560 * scale, height: 320 * scale)
        drawCaption(live ? "Guitar tuner: listening"
                         : mic.isRunning ? "Guitar tuner: a pretend guitar tuning itself; play a string and yours takes over"
                         : "Guitar tuner: a pretend guitar tuning itself; allow the microphone and yours takes over",
                    edge: .top)
    }

    /// The nearest string to a pitch and the cents from that string's own
    /// pitch, or nil when the pitch is more than three semitones from every
    /// string, which no string on a guitar is.
    private func string(for heard: DetectedPitch) -> (index: Int, cents: Double)? {
        let nearest = strings.indices.min {
            abs(strings[$0].pitch.midi - heard.midi) < abs(strings[$1].pitch.midi - heard.midi)
        }!
        let cents = (heard.midi - strings[nearest].pitch.midi) * 100
        return abs(cents) <= 300 ? (nearest, cents) : nil
    }

    /// A half-dial from fifty cents flat to fifty sharp, the string's name in
    /// the middle, and a word for which way to turn the peg.
    private func drawGauge(cents: Double?, top: Double) {
        let hub = Vector2(width / 2, top + 330 * scale)
        let radius = 300 * scale
        let inTune = cents.map { abs($0) < 3 } ?? false
        let accent = inTune ? Color(hex: 0x7ED957) : Color(hex: 0xFFB454)

        // The arc and its ticks, every ten cents, taller at the ends and the middle.
        for step in -50...50 {
            let angle = map(Double(step), -50, 50, .pi * 1.15, .pi * 1.85)
            let tall: Double = step == 0 ? 34 : (step % 10 == 0 ? 22 : 8)
            let inner = hub + Vector2(angle: angle) * (radius - tall * scale)
            let outer = hub + Vector2(angle: angle) * radius
            fill(Color(white: step == 0 ? 0.85 : (step % 10 == 0 ? 0.5 : 0.25)))
            drawOrientedBox(inner, outer, thickness: (step % 10 == 0 ? 3 : 1.5) * scale)
        }
        drawText("-50", hub.x - radius * 0.9, hub.y + 30 * scale, size: 22 * scale, color: Color(white: 0.5), align: .center, .middle)
        drawText("+50", hub.x + radius * 0.9, hub.y + 30 * scale, size: 22 * scale, color: Color(white: 0.5), align: .center, .middle)
        drawText("flat", hub.x - radius * 0.62, hub.y - radius * 0.55, size: 22 * scale, color: Color(white: 0.45), align: .center, .middle)
        drawText("sharp", hub.x + radius * 0.62, hub.y - radius * 0.55, size: 22 * scale, color: Color(white: 0.45), align: .center, .middle)

        // The string's name, and the needle.
        if let lit {
            let string = strings[lit]
            drawText(string.name, hub.x, hub.y - 110 * scale, size: 150 * scale, color: accent, align: .center, .middle)
            drawText("\(string.pitch)  ·  \(String(format: "%.2f", string.pitch.frequency)) Hz",
                     hub.x, hub.y - 10 * scale, size: 24 * scale, color: Color(white: 0.55), align: .center, .middle)
            // A short pointer riding the inside of the arc, so the name stays clear.
            let angle = map(max(-50, min(50, needle)), -50, 50, .pi * 1.15, .pi * 1.85)
            let tail = hub + Vector2(angle: angle) * (radius - 110 * scale)
            let tip = hub + Vector2(angle: angle) * (radius - 42 * scale)
            fill(accent)
            drawOrientedBox(tail, tip, thickness: 6 * scale)
            drawCircle(tail.x, tail.y, 8 * scale)
            if let cents {
                let word = inTune ? "in tune" : (cents < 0 ? "tune up" : "tune down")
                let sign = cents >= 0 ? "+" : ""
                let amount = abs(cents) > 50 ? "more than 50 cents" : "\(sign)\(Int(cents.rounded())) cents"
                drawText("\(word)  \(amount)", hub.x, hub.y + 70 * scale,
                         size: 30 * scale, color: accent, align: .center, .middle)
            }
        } else {
            drawText("play a string", hub.x, hub.y - 40 * scale, size: 40 * scale, color: Color(white: 0.35), align: .center, .middle)
        }
    }

    /// The six strings, low E on the left, the one being tuned lit.
    private func drawStrings(top: Double, height: Double) {
        let left = width * 0.2, right = width * 0.8
        for (i, string) in strings.enumerated() {
            let x = map(Double(i), 0, 5, left, right)
            let isLit = lit == i
            let color = isLit ? (abs(needle) < 3 ? Color(hex: 0x7ED957) : Color(hex: 0xFFB454)) : Color(white: 0.35)
            fill(color)
            drawRect(x - (6 - Double(i)) * 0.5 * scale, top, (6 - Double(i)) * scale, height)
            drawText(string.name, x, top + height + 34 * scale, size: 34 * scale,
                     color: isLit ? color : Color(white: 0.6), align: .center, .middle)
            drawText("\(string.pitch)", x, top + height + 70 * scale, size: 20 * scale,
                     color: Color(white: 0.4), align: .center, .middle)
        }
    }
}

/// A pretend guitar: each open string plucked a little flat and tuned up a
/// few cents at a time, string after string, its samples fed to a real
/// analyzer the way a microphone's would be. Every read the tuner makes comes
/// out of the analyzer; only the air has been replaced.
final class PretendGuitar {
    let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 44100)
    private let rate = 44100.0
    private let strings: [Double] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
    private let perString = 6.0       // seconds spent on each string
    private var fed = 0.0             // seconds of tape fed so far
    private var phase = 0.0

    /// Feeds the tape up to `time`, a frame at a time. After a spell on the
    /// microphone it skips ahead rather than catching up the whole gap.
    func pluck(at time: Double) {
        if time - fed > 0.5 { fed = time - 1.0 / 60 }
        while fed < time {
            let count = Int(rate / 60)
            var tape = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let t = fed + Double(i) / rate
                let index = Int(t / perString) % strings.count
                let within = t.truncatingRemainder(dividingBy: perString)
                // A pluck every 0.75 s; each one a peg-turn closer, in tune from the fifth on.
                let pluck = Int(within / 0.75)
                let flat = max(0, 30 - Double(pluck) * 7.5)
                let hz = strings[index] * pow(2, -flat / 1200)
                let since = within - Double(pluck) * 0.75
                phase = (phase + hz / rate).truncatingRemainder(dividingBy: 1)
                var s = 0.0
                for k in 1...6 {
                    let decay = exp(-since * (1.2 + Double(k) * 0.9))
                    s += sin(phase * Double(k) * .tau) * decay / Double(k)
                }
                tape[i] = Float(s * 0.35 * min(1, since * 300))
            }
            tape.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: count) }
            fed += Double(count) / rate
        }
    }
}
