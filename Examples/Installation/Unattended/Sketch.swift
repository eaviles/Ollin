import Ollin

/// A piece made to be left running: on a wall, in a shop window, at a stand for
/// the length of a fair.
///
/// One line does it. `installation` fills the screen, hides the pointer, and
/// keeps the display awake with the screen saver held off, so nothing covers the
/// work overnight and nobody has to nudge a mouse in the morning.
///
/// Declaring `loopDuration` earns a second thing here. The clock a shader reads
/// is a 32-bit number, which is not enough to count seconds for a week, so a
/// piece that repeats hands its shaders a clock that starts over on a whole lap.
/// Nothing on screen moves at the restart, because the piece is back where it
/// began anyway. See `Docs/Output/Installation.md`.
///
/// To work on it in an ordinary window, run it with `--no-installation`; to put
/// any other sketch on a wall for an evening, run that one with `--installation`.
@main
final class Unattended: Sketch {

    /// The whole declaration: left running, unattended.
    override var installation: Installation { .on }

    /// Two minutes a lap. The wave below is the only motion, and it is built
    /// from this, so the piece repeats exactly.
    override var loopDuration: Double? { 120 }

    private let ink = Ramp([Color(red: 0.16, green: 0.20, blue: 0.30),
                            Color(red: 0.52, green: 0.72, blue: 0.86),
                            Color(red: 0.96, green: 0.86, blue: 0.62)])

    override func draw() {
        background(Color(white: 0.05))
        noStroke()

        let step = shortSide / 30
        let lap = loopProgress(over: 120) * .tau
        let middle = center

        var y = step * 0.5
        while y < height {
            var x = step * 0.5
            while x < width {
                let point = Vector2(x, y)
                // One wave, traveling out from the middle. Everything the dot
                // does comes from where it stands and how far along the lap the
                // piece is, so there is no state to keep and nothing to drift.
                let reach = point.distance(to: middle) / (shortSide * 0.5)
                let wave = sin(lap - reach * 3.4)
                let size = step * 0.44 * (0.18 + 0.82 * (wave * 0.5 + 0.5))
                fill(ink.color(at: (wave * 0.5 + 0.5) * 0.9 + reach * 0.1))
                drawCircle(center: point, radius: size)
                x += step
            }
            y += step
        }
    }
}
