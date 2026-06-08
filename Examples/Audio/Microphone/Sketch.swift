import Ollin
import OllinAudio

/// The same radial visual as `Spectrum`, but driven by the live microphone
/// instead of a generated tone. Talk, clap, or play music near the mic: the bars
/// trace the normalized frequency `bands`, and the central disc flashes on every
/// detected `beat` (clap and watch it pulse).
///
/// The microphone needs the user's permission. `AudioInput.start()` asks the
/// first time; until it's granted the visual sits quiet and the label says so.
/// (From `swift run` the system attributes the prompt to the binary; in a
/// packaged app you'd include a microphone-usage description.)
@main
final class Microphone: Sketch {
    let mic = AudioInput()
    let bars = 72

    override func setup() {
        noStroke()
        textFont(OutlineFont.system)
        try? mic.start()
    }

    override func draw() {
        background(Color(white: 0.07))

        let center = Vector2(width / 2, height / 2)
        let levels = mic.bands(bars)        // normalized 0...1, no gain to guess
        let inner = 150 * scale

        withState {
            translate(center)
            for i in 0..<bars {
                let len = Double(levels[i]) * 340 * scale
                let angle = Double(i) / Double(bars) * .tau
                let dir = Vector2(cos(angle), sin(angle))
                fill(Colormap.magma.color(at: Double(i) / Double(bars - 1)))
                drawOrientedBox(dir * inner, dir * (inner + len), thickness: 6 * scale)
            }
        }

        // Central disc, flashing on each detected beat (`beat` snaps to 1 on an
        // onset and decays), with a small floor so it's always visible.
        let pulse = Double(mic.beat)
        fill(Color(white: 0.95))
        drawCircle(center.x, center.y, (40 + pulse * 300) * scale)

        // Status / hint in screen space.
        fill(.white)
        textAlign(.center, .top)
        textSize(15 * scale)
        let label = mic.isRunning ? "Listening — make some noise" : "Microphone — allow access to react"
        drawText(label, width / 2, height - 44 * scale)
    }
}
