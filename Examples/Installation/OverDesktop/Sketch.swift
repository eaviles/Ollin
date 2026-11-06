import Ollin

/// OverDesktop: a sketch that floats over the desktop. A few fireflies drift
/// on a clear canvas and lean toward the pointer. Run with `--overlay`, the
/// piece sits above every other window, see-through wherever the canvas is
/// clear, and a click lands on it only where a firefly is: press one and the
/// swarm scatters, press anywhere else and the click goes to whatever is
/// underneath. Without the flag it runs in a window, over black.
///
/// ```sh
/// swift run Example-Installation-OverDesktop --overlay
/// ```
///
/// Quit from the mark the piece puts in the menu bar. The same thing in code
/// is `OllinApp.runAsOverlay { OverDesktop() }`.
@main
final class OverDesktop: Sketch {
    // The canvas follows its view, so over the desktop it covers the display.
    override var windowMode: WindowMode { .resizable }

    @Param("Fireflies", 3 ... 40, icon: "sparkles") var count = 14
    @Param("Glow", 10 ... 60, icon: "sun.max") var glow = 28.0
    @Param("Pull", 0 ... 1, icon: "cursorarrow.motionlines") var pull = 0.35

    /// When the swarm was last scattered, in seconds of the sketch's clock.
    private var scattered = -10.0

    override func draw() {
        background(.clear)
        noStroke()
        let since = time - scattered
        // A scatter throws every firefly outward and lets it settle back.
        let burst = max(0, 1 - since / 1.5)
        for i in 0 ..< count {
            let seed = Double(i) * 7.31
            // Each one wanders on its own slow path across the canvas.
            var p = Vector2(noise(seed, time * 0.07) * width, noise(seed + 50, time * 0.07) * height)
            let toPointer = mouse - p
            p += toPointer * (pull * 0.5 * noise(seed + 9, time * 0.2))
            p += Vector2(cos(seed), sin(seed)) * (burst * burst * 260)
            let blink = 0.55 + 0.45 * sin(time * (1.2 + noise(seed) * 1.5) + seed)
            let hue = 0.12 + 0.08 * noise(seed + 3)
            // A soft halo and a bright core: the halo fades to nothing, so the
            // piece ends where the light does.
            for ring in stride(from: 5, through: 1, by: -1) {
                let t = Double(ring) / 5
                fill(Color(hue: hue, saturation: 0.7, brightness: 1, alpha: 0.10 * blink * (1.2 - t)))
                drawCircle(center: p, radius: glow * t)
            }
            fill(Color(hue: hue, saturation: 0.35, brightness: 1, alpha: 0.95))
            drawCircle(center: p, radius: glow * 0.16)
        }
    }

    override func mousePressed() {
        scattered = time
    }
}
