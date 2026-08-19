// figure: frame=430
//
// Guide diagram (Chapter 22): six seconds of listening, as a timeline. Top:
// the loudness curve (amplitude). Middle: the beat pulse, snapping to 1 on
// each detected onset and fading. Bottom: the detections themselves, one tick
// per beatCount increment. The pulse strip records the ready-made `beat`
// property frame by frame; the sample-clocked detector makes the whole
// timeline deterministic.
import Ollin
import OllinAudio

final class BeatTimeline: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let mic = StageMic()
    var loudness: [Double] = []
    var pulses: [Double] = []
    var beatFrames: [Int] = []
    var lastCount = 0

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    let left = 70.0, plotWidth = 740.0
    let window = 360                      // six seconds at 60 fps

    override func draw() {
        // Listen, and take notes.
        mic.listen()
        let audio = mic.analyzer
        loudness.append(Double(audio.amplitude))
        pulses.append(Double(audio.beat))
        if audio.beatCount > lastCount {
            lastCount = audio.beatCount
            beatFrames.append(frameCount)
        }

        background(Color(hex: 0xF7F5F1))
        textSize(19)
        guard loudness.count > window else { return }
        let start = loudness.count - window

        // 1. Loudness: peaks line up with the kick, but so does everything loud.
        title("loudness", note: "amplitude, frame by frame", top: 70)
        var curve: [Vector2] = []
        for i in 0 ..< window {
            curve.append(Vector2(x(of: i), 210 - loudness[start + i] * 340))
        }
        baseline(y: 210)
        stroke(ink)
        strokeWeight(2)
        drawPolyline(curve)

        // 2. The beat pulse: 1 on each detection, fading over a quarter second.
        title("beat", note: "the ready-made pulse: snaps to 1, fades", top: 268)
        var pulse: [Vector2] = []
        for i in 0 ..< window {
            pulse.append(Vector2(x(of: i), 400 - pulses[start + i] * 88))
        }
        baseline(y: 400)
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline(pulse)

        // 3. The detections: beatCount ticked up at each mark.
        title("beats detected", note: "beatCount goes up by one at each tick", top: 448)
        baseline(y: 500)
        noStroke()
        fill(accent)
        for beatFrame in beatFrames where beatFrame > start {
            let px = x(of: beatFrame - start - 1)
            drawRect(px - 2, 478, 4, 22)
        }

        noStroke()
        fill(soft)
        textAlign(.center, .top)
        drawText("every arrival lands: the loud kicks and the quiet off-beat hats alike",
                 width / 2, 522)
    }

    func x(of i: Int) -> Double {
        left + Double(i) / Double(window - 1) * plotWidth
    }

    func title(_ text: String, note: String, top: Double) {
        noStroke()
        fill(ink)
        textAlign(.left, .top)
        drawText(text, left, top)
        fill(soft)
        textAlign(.right, .top)
        drawText(note, left + plotWidth, top)
    }

    func baseline(y: Double) {
        stroke(faint)
        strokeWeight(1.5)
        drawLine(left, y, left + plotWidth, y)
    }
}

/// A pretend microphone. It synthesizes a little band (a kick drum every half
/// second, a hat between the kicks, a held bass note, a slow arpeggio, a
/// whisper of hiss) and feeds the samples into a real `AudioAnalyzer`,
/// exactly the way a live source would. Every audio read in this chapter comes out of the analyzer
/// itself; only the air has been replaced.
final class StageMic {
    let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 44100)
    private var sample = 0
    private let rate = 44100.0

    /// Listen for one frame's worth of the tape (1/60 s by default).
    func listen(seconds: Double = 1.0 / 60) {
        let count = Int(rate * seconds)
        var tape = [Float](repeating: 0, count: count)
        for i in 0 ..< count {
            let t = Double(sample + i) / rate
            let sinceKick = t.truncatingRemainder(dividingBy: 0.5)
            var s = sin(t * 55 * .tau) * 0.6 * exp(-sinceKick * 9)     // the kick's thump
            s += sin(t * 2800 * .tau) * 0.3 * exp(-sinceKick * 70)     // and its click
            let sinceHat = (t + 0.25).truncatingRemainder(dividingBy: 0.5)
            s += white(sample + i + 7919) * 0.07 * exp(-sinceHat * 45)  // an off-beat hat
            s += sin(t * 110 * .tau) * 0.2                             // a held bass note
            let notes: [Double] = [330, 415, 494, 659]
            let melody = notes[Int(t + 0.25) % notes.count]            // a slow arpeggio
            s += sin(t * melody * .tau) * 0.16
            s += sin(t * melody * 2 * .tau) * 0.06
            s += white(sample + i) * 0.02                              // a little hiss
            tape[i] = Float(s)
        }
        sample += count
        tape.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: count) }
    }

    private func white(_ i: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x >> 40) / Double(1 << 23) - 1
    }
}
