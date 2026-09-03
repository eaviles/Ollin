import Ollin

/// A ring of drifting, breathing circles: twenty-eight outlines spaced around a
/// circle, each wandering in and out, swelling and fading on its own beat, the
/// whole ring turning slowly. The picture the site opens on, written as a sketch.
///
/// Every motion is a sine of one shared phase that runs once around per `loop`
/// seconds, and each beat counts a whole number of cycles per loop, so the
/// picture returns to its first frame exactly: a video loop or a web page can
/// wrap it with no seam. The ink and the paper are parameters, so a page can set
/// them to its own theme. A reader who asked the system for less motion gets
/// the ring standing still.
@main
final class BreathingRing: Sketch {
    @Param(icon: "paintbrush") var ink: Color = .black
    @Param(icon: "doc") var paper: Color = .white

    /// Seconds for one whole turn of the ring, the period every beat divides.
    /// Declared as the loop, so `--export-loop` and `--export-web` record one
    /// lap with no length given.
    private let loop = 60.0
    override var loopDuration: Double? { loop }
    private let count = 28

    override func draw() {
        background(paper)
        noFill()
        strokeWeight(2.5 * scale)

        let phase = prefersReducedMotion ? 0 : time / loop * .tau
        let ring = shortSide * 0.3
        for i in 0 ..< count {
            let n = Double(i)
            let angle = n / Double(count) * .tau + phase
            let drift = sin(phase * 7 + n * 1.31) * ring * 0.08
            let radius = ring * 0.19 + sin(phase * 10 + n * 0.83) * ring * 0.07
            let fade = 0.28 + 0.22 * sin(phase * 9 + n * 0.5)
            stroke(Color(red: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha * fade))
            drawCircle(center: center + Vector2(cos(angle), sin(angle)) * (ring + drift), radius: radius)
        }
    }
}
