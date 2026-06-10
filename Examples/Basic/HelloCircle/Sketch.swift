import Ollin

/// The hello-world of Ollin: a black circle outline, breathing on white.
///
/// A single `@main` file is the whole program — `Sketch.main()` boots the
/// window for you. The draw loop is already running, so the motion is one
/// `time`-driven term in the radius; delete it and the circle holds still.
@main
final class HelloCircle: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3.75 * scale)
        drawCircle(width / 2, height / 2, (150 + sin(time) * 40) * scale)
    }
}
