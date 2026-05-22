import Foundation
import Ollin

/// The hello-world of Ollin, breathing: a black circle outline on a white
/// field whose radius oscillates with `time`.
///
/// `draw()` runs continuously at the display's refresh rate, so motion is the
/// default — `radius: 120 + sin(time) * 40` is the whole animation. Swap it
/// back to a constant for a still image, or call `noLoop()`.
final class HelloCircle: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        circle(x: width / 2, y: height / 2, radius: 120 + sin(time) * 40)
    }
}

OllinApp.run(HelloCircle())
