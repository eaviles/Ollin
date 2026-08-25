import Ollin
import OllinAudio

/// Sound drives the picture. A `Tone` oscillator synthesizes an evolving
/// sawtooth — gliding in pitch, breathing in level — and the same signal is
/// analyzed back into a ring of `bands`: log-spaced, normalized frequency bars
/// (a sawtooth's harmonics light up many of them, and the pitch glide sweeps the
/// pattern around). The central disc pulses with the overall level.
///
/// `bands(_:)` returns values already shaped for drawing — spaced like hearing,
/// auto-scaled to `0...1` — so the bar lengths are a plain map to pixels, with no
/// hand-tuned gain. It's self-contained on purpose: the audio is generated, so
/// the sketch runs with no microphone permission and no bundled file. Swap the
/// `Tone` for an `AudioInput()` (microphone) or an `AudioPlayer(path:)` and the
/// same reads drive the same visual.
@main
final class Spectrum: Sketch {
    let tone = Tone(frequency: 110, amplitude: 0.16, waveform: .sawtooth)
    let bars = 72

    override func setup() {
        noStroke()
        tone.play()
    }

    override func draw() {
        background(Color(white: 0.07))

        // Glide the pitch over ~1.5 octaves and breathe the level, so the
        // analyzed picture keeps moving.
        tone.frequency = 110 * pow(2, sin(time * 0.2) * 1.5)
        tone.amplitude = 0.10 + 0.08 * unipolar(sin(time * 1.7))

        let levels = tone.bands(bars)        // already normalized 0...1
        let inner = 150 * scale
        let maxLen = 320 * scale

        withState {
            translate(center)
            rotate(time * 0.1)
            for i in 0..<bars {
                let len = Double(levels[i]) * maxLen
                let angle = Double(i) / Double(bars) * .tau
                let dir = Vector2(angle: angle)
                fill(Colormap.turbo.color(at: Double(i) / Double(bars - 1)))
                drawOrientedBox(dir * inner, dir * (inner + len), thickness: 6 * scale)
            }
        }

        // Central disc, pulsing with the overall (normalized) level.
        let level = Double(levels.reduce(0, +)) / Double(bars)
        fill(Color(white: 0.95))
        drawCircle(center.x, center.y, (40 + level * 260) * scale)

        // Screen-space label.
        drawCaption("Spectrum")
    }
}
