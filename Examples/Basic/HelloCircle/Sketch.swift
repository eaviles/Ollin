import Ollin

/// The hello-world of Ollin: a black circle outline, ~3px, centered on white.
///
/// A single `@main` file is the whole program — `Sketch.main()` boots the
/// window for you. It's a still image, but the draw loop is already running
/// underneath; see `Motion/Breathing` for the same circle, animated.
@main
final class HelloCircle: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        circle(x: width / 2, y: height / 2, radius: 120)
    }
}
