import Ollin

/// A harmonograph performing: pendulums swing the pen, damping reels each lap
/// in a little tighter, and the trace replays at double speed exactly as the
/// machine would draw it, pen and all. The pendulum recipe (near-unison
/// detunes, a faster overtone on each axis, phases) is rolled from the
/// sketch's seeded `random`, so every `variation` hangs a different figure on
/// the same machine: re-roll the seed in the inspector to commission a new
/// drawing. When the trace completes it rests a moment, then starts over.
@main
final class HarmonographTrace: Sketch {
    private var trace: [Vector2] = []
    private let revealTime = 40.0
    private let holdTime = 5.0

    override func setup() {
        let s = Double(shortSide)
        let sway = 0.40 * s
        let overtone = 0.14 * s

        let h = Harmonograph(
            x: [.init(amplitude: sway,
                      frequency: 2 + random(-0.015, 0.015),
                      phase: random(0, .tau), damping: 0.012),
                .init(amplitude: overtone,
                      frequency: Double(Int(random(2, 4))) * 2 + random(-0.01, 0.01),
                      phase: random(0, .tau), damping: 0.02)],
            y: [.init(amplitude: sway,
                      frequency: 2 + random(-0.015, 0.015),
                      phase: random(0, .tau), damping: 0.012),
                .init(amplitude: overtone,
                      frequency: Double(Int(random(2, 4))) * 2 + random(-0.01, 0.01),
                      phase: random(0, .tau), damping: 0.02)])
        trace = h.contour(duration: revealTime * 2, samples: 16_000).points
    }

    override func draw() {
        background(Color(hex: 0xF4EFE4))
        guard trace.count > 1 else { return }

        let t = time.truncatingRemainder(dividingBy: revealTime + holdTime)
        let progress = min(1, t / revealTime)
        let visible = max(2, Int(progress * Double(trace.count)))

        withState {
            translate(center)
            noFill()
            stroke(Color(hex: 0x232B4A).withAlpha(0.8))
            strokeWeight(1.5 * scale)
            drawPolyline(Array(trace.prefix(visible)), closed: false)

            if progress < 1 {
                let pen = trace[visible - 1]
                noStroke()
                fill(Color(hex: 0xA33B20))
                drawCircle(pen.x, pen.y, 6 * scale)
            }
        }
    }
}
