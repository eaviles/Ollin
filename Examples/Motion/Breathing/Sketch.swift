import Foundation
import Ollin

/// Motion is the default. `draw()` runs continuously, so making the circle
/// breathe is one `time`-driven term — no animation setup, no `loop()` call.
///
/// `time` is seconds since launch; `sin(time)` walks -1...1, so the radius
/// oscillates between ⅔ and 1⅓ of its base. Sizes use `scale`
/// (`min(width, height) / 1000`), so it breathes the same at any canvas size.
@main
final class Breathing: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3.75 * scale)
        drawCircle(width / 2, height / 2, (150 + sin(time) * 50) * scale)
    }
}
