import Foundation
import Ollin

/// Motion is the default. `draw()` runs continuously, so making the circle
/// breathe is one `time`-driven term — no animation setup, no `loop()` call.
///
/// `time` is seconds since launch; `sin(time)` walks -1...1, so the radius
/// oscillates between 80 and 160 points.
@main
final class Breathing: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        circle(x: width / 2, y: height / 2, radius: 120 + sin(time) * 40)
    }
}
