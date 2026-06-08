import Ollin
import OllinAudio

/// Sound drives the picture. A `Tone` oscillator synthesizes an evolving
/// sawtooth — gliding in pitch, breathing in level — and the same signal is
/// analyzed back into an `amplitude` and a frequency `spectrum`. The spectrum
/// becomes a ring of bars (a sawtooth's harmonics light up many of them, and the
/// pitch glide sweeps the pattern around); the central disc pulses with the
/// overall level.
///
/// It's self-contained on purpose: the audio is generated, so the sketch runs
/// with no microphone permission and no bundled file. Swap the `Tone` for an
/// `AudioInput()` (microphone) or an `AudioPlayer(path:)` and the same `spectrum`
/// / `amplitude` reads drive the same visual.
@main
final class Spectrum: Sketch {
    let tone = Tone(frequency: 110, amplitude: 0.16, waveform: .sawtooth)
    let bars = 128

    override func setup() {
        noStroke()
        textFont(OutlineFont.system)
        tone.play()
    }

    override func draw() {
        background(Color(white: 0.07))

        // Glide the pitch over ~1.5 octaves and breathe the level, so the
        // analyzed picture keeps moving.
        tone.frequency = 110 * pow(2, sin(time * 0.2) * 1.5)
        tone.amplitude = 0.10 + 0.08 * (sin(time * 1.7) * 0.5 + 0.5)

        let center = Vector2(width / 2, height / 2)
        let spectrum = tone.spectrum
        let inner = 150 * scale
        let maxLen = 320 * scale

        withState {
            translate(center)
            rotate(time * 0.1)
            for i in 0..<bars {
                let mag = Double(spectrum[i])
                let len = min(sqrt(mag) * 520 * scale, maxLen)
                let angle = Double(i) / Double(bars) * .tau
                let dir = Vector2(cos(angle), sin(angle))
                fill(Colormap.turbo.color(at: Double(i) / Double(bars - 1)))
                drawOrientedBox(dir * inner, dir * (inner + len), thickness: 5 * scale)
            }
        }

        // Central disc, pulsing with the overall level.
        let level = Double(tone.amplitude)
        fill(Color(white: 0.95))
        drawCircle(center.x, center.y, (40 + level * 600) * scale)

        // Screen-space label.
        fill(.white)
        textAlign(.center, .top)
        textSize(15 * scale)
        drawText("Spectrum", width / 2, height - 44 * scale)
    }
}
