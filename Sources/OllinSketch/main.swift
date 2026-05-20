import Ollin

/// The hello-world of Ollin: a black circle outline on a white field.
///
/// It's a still image — but the framework underneath is already running a
/// continuous draw loop. To make it move, swap the radius for a function of
/// `time`, e.g. `radius: 120 + sin(time) * 40`, and it just animates.
final class HelloCircle: Sketch {
    override func setup() {
        // optional one-time setup
    }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        circle(x: width / 2, y: height / 2, radius: 120)
    }
}

OllinApp.run(HelloCircle())
