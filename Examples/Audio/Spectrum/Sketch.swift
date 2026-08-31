import Ollin
import OllinAudio

/// Sound drives the picture, from whichever source the Mac will give it. An
/// `AudioInput` asks for the microphone on launch; once permission is granted
/// and the input runs, the ring of bars traces what the room sounds like and
/// the central disc flashes on every detected `beat` (clap and watch it pulse).
/// Until then a `Tone` oscillator stands in: an evolving sawtooth, gliding in
/// pitch and breathing in level, analyzed exactly the same way, its harmonics
/// lighting up many bands while the glide sweeps the pattern around.
///
/// That fallback is the permission lesson. The microphone needs the user's
/// consent (`AudioInput.start()` asks the first time; from `swift run` the
/// system attributes the prompt to the binary, and a packaged app would carry a
/// usage description), so the sketch keeps a generated signal ready and swaps
/// to the real one the moment it is allowed. Deny it and the picture still
/// plays; allow it and the room takes over.
///
/// `bands(_:)` returns values already shaped for drawing (spaced like hearing,
/// auto-scaled to `0...1`) on every source alike, so the bar lengths are a
/// plain map to pixels with no hand-tuned gain, and both paths share one
/// visual and one colormap.
@main
final class Spectrum: Sketch {
    let mic = AudioInput()
    let tone = Tone(frequency: 110, amplitude: 0.16, waveform: .sawtooth)
    let bars = 72
    var tonePlaying = false

    override func setup() {
        noStroke()
        try? mic.start()
    }

    override func draw() {
        background(Color(white: 0.07))

        // The microphone the moment it's allowed; the generated tone until then.
        let live = mic.isRunning
        if live, tonePlaying { tone.stop(); tonePlaying = false }
        if !live, !tonePlaying { tone.play(); tonePlaying = true }

        if !live {
            // Glide the pitch over ~1.5 octaves and breathe the level, so the
            // analyzed picture keeps moving.
            tone.frequency = 110 * pow(2, sin(time * 0.2) * 1.5)
            tone.amplitude = 0.10 + 0.08 * unipolar(sin(time * 1.7))
        }

        let levels = live ? mic.bands(bars) : tone.bands(bars)   // already normalized 0...1
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

        // The central disc: on the microphone it flashes on each detected beat
        // (`beat` snaps to 1 on an onset and decays); on the tone it pulses
        // with the overall (normalized) level.
        let pulse = live ? Double(mic.beat) * 300
                         : Double(levels.reduce(0, +)) / Double(bars) * 260
        fill(Color(white: 0.95))
        drawCircle(center.x, center.y, (40 + pulse) * scale)

        // Screen-space label saying which source is driving.
        drawCaption(live ? "Spectrum: listening, make some noise"
                         : "Spectrum: a generated tone; allow the microphone and the room takes over")
    }
}
