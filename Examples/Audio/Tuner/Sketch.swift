import Foundation
import Ollin
import OllinAudio

/// Follows the note being played: the nearest note name and how many cents
/// off it sits, the way a tuner reads them; a trace of the pitch over the last
/// six seconds on a strip of semitones, each dot as solid as the detector is
/// sure; and the twelve pitch classes underneath, every octave folded onto
/// one row of bars, which is what the chord shape looks like when there is
/// one and what a melody looks like when there is not.
///
/// By default it follows the bundled clip, a recording of *El Fandanguito*,
/// a traditional Mexican *son huasteco* for solo violin (performed by Cynthia
/// Molina, CC BY-SA), so it runs out of the box. Two other sources are one
/// flag away:
///
/// ```
/// swift run Example-Audio-Tuner --mic                  # sing, hum, or whistle at it
/// swift run Example-Audio-Tuner /path/to/track.m4a     # your own recording
/// ```
///
/// Every source reads the same: `pitch` is the note heard (or nil when there
/// is none), `note` its short form, and `chroma` the twelve classes.
@main
final class Tuner: Sketch {
    var player: AudioPlayer?
    var mic: AudioInput?
    var source: (any AudioSource)? { mic ?? player }
    var sourceName = ""

    /// The last six seconds of readings, one per frame.
    var trace: [(time: Double, midi: Double, confidence: Double)] = []
    var eased = [Double](repeating: 0, count: 12)
    var needle = 0.0
    var lastNote = ""

    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let span = 6.0
    let lowest = 43.0, highest = 91.0      // G2 to G6 on the strip: a bass voice to a violin's top

    override func setup() {
        noStroke()
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--mic") {
            let mic = AudioInput()
            try? mic.start()
            self.mic = mic
            sourceName = "the microphone"
        } else if let path = args.indices.first(where: { i in
            // A bare path that exists, and not the value of a flag such as --export.
            !args[i].hasPrefix("-") && (i == 0 || !args[i - 1].hasPrefix("-"))
                && FileManager.default.fileExists(atPath: args[i])
        }).map({ args[$0] }) {
            player = try? AudioPlayer(path: path)
            sourceName = (path as NSString).lastPathComponent
        } else {
            player = try? AudioPlayer(resource: "fandanguito", withExtension: "m4a", in: .module)
            sourceName = "El Fandanguito, solo violin"
        }
        player?.loops = true
        player?.play()
    }

    override func draw() {
        background(Color(white: 0.07))

        let heard = source?.pitch
        if let heard {
            trace.append((time, heard.midi, Double(heard.confidence)))
            let name = "\(heard.note)"
            // The needle eases within a note and snaps on a new one, since a
            // different note is a fresh measurement, not a drift.
            needle = name == lastNote ? needle + (heard.cents - needle) * 0.3 : heard.cents
            lastNote = name
        }
        trace.removeAll { time - $0.time > span }
        let chroma = source?.chroma ?? []
        for i in 0..<min(12, chroma.count) {
            eased[i] += (Double(chroma[i]) - eased[i]) * 0.25
        }

        drawTunerFace(heard, top: 60 * scale)
        drawTrace(top: 340 * scale, height: 400 * scale)
        drawClasses(top: 790 * scale, height: 140 * scale)

        drawCaption(mic != nil && mic?.isRunning == false
                    ? "Tuner: waiting for the microphone"
                    : "Tuner: following \(sourceName)", edge: .top)
    }

    /// The note name and the cents needle: a tuner's face.
    private func drawTunerFace(_ heard: DetectedPitch?, top: Double) {
        let inTune = heard.map { abs($0.cents) < 5 } ?? false
        let nameColor = heard == nil ? Color(white: 0.3) : (inTune ? Color(hex: 0x7ED957) : Color(white: 0.95))
        drawText(lastNote.isEmpty ? "-" : lastNote,
                 width / 2, top + 60 * scale, size: 110 * scale, color: nameColor, align: .center, .middle)

        // The scale from fifty cents flat to fifty sharp.
        let left = width * 0.2, right = width * 0.8
        let y = top + 175 * scale
        fill(Color(white: 0.3))
        drawRect(left, y - 1.5 * scale, right - left, 3 * scale)
        for cents in stride(from: -50, through: 50, by: 10) {
            let x = map(Double(cents), -50, 50, left, right)
            let tall = cents % 50 == 0 ? 22.0 : (cents % 20 == 0 ? 14.0 : 8.0)
            fill(Color(white: cents == 0 ? 0.8 : 0.4))
            drawRect(x - 1 * scale, y - tall * scale, 2 * scale, tall * 2 * scale)
        }
        drawText("-50", left, y + 34 * scale, size: 22 * scale, color: Color(white: 0.5), align: .center, .middle)
        drawText("+50", right, y + 34 * scale, size: 22 * scale, color: Color(white: 0.5), align: .center, .middle)
        if let heard {
            let x = map(needle, -50, 50, left, right)
            fill(inTune ? Color(hex: 0x7ED957) : Color(hex: 0xFFB454))
            drawTriangle(x, y - 12 * scale, x - 12 * scale, y - 40 * scale, x + 12 * scale, y - 40 * scale)
            let sign = heard.cents >= 0 ? "+" : ""
            drawText("\(sign)\(Int(heard.cents.rounded())) cents", width / 2, y + 64 * scale,
                     size: 26 * scale, color: Color(white: 0.7), align: .center, .middle)
        }
    }

    /// The pitch over the last six seconds on a strip of semitones, one dot
    /// per frame, as solid as the detector was sure.
    private func drawTrace(top: Double, height: Double) {
        let left = 120 * scale, right = width - 60 * scale
        func y(_ midi: Double) -> Double { map(midi, lowest, highest, top + height, top) }

        // Semitone lines, the C of each octave named.
        for midi in stride(from: lowest, through: highest, by: 1) {
            let index = Int(midi) % 12
            fill(Color(white: index == 0 ? 0.35 : 0.16))
            drawRect(left, y(midi), right - left, 1 * scale)
            if index == 0 {
                drawText("\(Pitch(midi))", left - 16 * scale, y(midi),
                         size: 20 * scale, color: Color(white: 0.6), align: .right, .middle)
            }
        }

        for reading in trace {
            let x = map(time - reading.time, span, 0, left, right)
            let m = reading.midi
            guard m >= lowest, m <= highest else { continue }
            fill(Color(hex: 0xFFB454).withAlpha(0.15 + reading.confidence * 0.85))
            drawCircle(x, y(m), 5 * scale)
        }
        if let last = trace.last, time - last.time < 0.1 {
            fill(Color(white: 0.95))
            drawCircle(right, y(last.midi), 9 * scale)
        }
    }

    /// The twelve pitch classes as bars, C first, every octave folded.
    private func drawClasses(top: Double, height: Double) {
        let left = 120 * scale, right = width - 60 * scale
        let slot = (right - left) / 12
        for i in 0..<12 {
            let h = eased[i] * height
            let x = left + Double(i) * slot
            fill(Color(hex: 0x5AC8FA).withAlpha(0.35 + eased[i] * 0.65))
            drawRect(x + slot * 0.12, top + height - h, slot * 0.76, h)
            drawText(names[i], x + slot / 2, top + height + 24 * scale,
                     size: 22 * scale, color: Color(white: 0.6), align: .center, .middle)
        }
    }
}
