// figure: frame=183
//
// Guide diagram (Chapter 24): one instant of sound, read three ways off a real
// AudioAnalyzer. Top: the waveform, the raw samples. Middle: the spectrum,
// energy per frequency (the pretend band's parts are visible as spikes).
// Bottom: bands(24), the spectrum reshaped for drawing. The sound comes from
// StageMic, the chapter's synthesized stand-in for a microphone.
import Ollin
import OllinAudio

final class Anatomy: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let mic = StageMic()

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    let left = 70.0, plotWidth = 740.0

    override func draw() {
        mic.listen()
        let audio = mic.analyzer

        background(Color(hex: 0xF7F5F1))
        textSize(19)

        // 1. The waveform: the rolling analysis window, the last ~46 ms.
        panelFrame(top: 56, height: 100,
                   title: "waveform", note: "the raw samples, the last 46 ms")
        let wave = audio.waveform
        var points: [Vector2] = []
        for (i, sample) in wave.enumerated() {
            let x = left + Double(i) / Double(wave.count - 1) * plotWidth
            points.append(Vector2(x, 106 - Double(sample) * 46))
        }
        stroke(ink)
        strokeWeight(1.6)
        drawPolyline(points)

        // 2. The spectrum: energy per frequency, low notes on the left.
        panelFrame(top: 210, height: 102,
                   title: "spectrum", note: "energy per frequency, 0 to 4 kHz shown")
        let spectrum = audio.spectrum
        let binWidth = 44100.0 / 2048.0                 // Hz per bin
        let bins = Int(4000 / binWidth)                 // up to 4 kHz
        let tallest = Double(spectrum.prefix(bins).max() ?? 1)
        noStroke()
        fill(ink)
        for b in 0 ..< bins {
            let h = Double(spectrum[b]) / tallest * 94
            let x = left + Double(b) / Double(bins) * plotWidth
            drawRect(x, 312 - h, plotWidth / Double(bins) * 0.9, h)
        }
        marker(hz: 55, of: binWidth, bins: bins, label: "kick 55 Hz", row: 0)
        marker(hz: 110, of: binWidth, bins: bins, label: "bass 110 Hz", row: 1)
        marker(hz: 659, of: binWidth, bins: bins, label: "melody 659 Hz", row: 0)

        // 3. bands(24): the same spectrum, shaped for drawing.
        panelFrame(top: 398, height: 98,
                   title: "bands(24)", note: "log-spaced like hearing, normalized 0…1")
        let levels = audio.bands(24)
        let barSpace = plotWidth / 24
        noStroke()
        for (i, level) in levels.enumerated() {
            let h = Double(level) * 90
            fill(accent.withAlpha(0.45 + Double(level) * 0.55))
            drawRect(left + Double(i) * barSpace + 3, 496 - h, barSpace - 6, h)
        }

        noStroke()
        fill(soft)
        textAlign(.center, .top)
        drawText("one instant of sound, read three ways", width / 2, 522)
    }

    func panelFrame(top: Double, height: Double, title: String, note: String) {
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(left, top, plotWidth, height)
        noStroke()
        fill(ink)
        textAlign(.left, .bottom)
        drawText(title, left, top - 8)
        fill(soft)
        textAlign(.right, .bottom)
        drawText(note, left + plotWidth, top - 8)
    }

    func marker(hz: Double, of binWidth: Double, bins: Int, label: String, row: Int) {
        let x = left + (hz / binWidth) / Double(bins) * plotWidth
        stroke(accent)
        strokeWeight(2)
        drawLine(x, 306, x, 320)
        noStroke()
        fill(accent)
        textSize(15)
        textAlign(.center, .top)
        drawText(label, x, 322 + Double(row) * 22)
        textSize(19)
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
