import Ollin

/// The hello-world of Ollin: a black circle outline, breathing on white.
///
/// A single `@main` file is the whole program; `Sketch.main()` boots the
/// window for you. Motion is the default: `draw()` runs continuously, so
/// making the circle breathe is one `time`-driven term in the radius, with no
/// animation setup and no `loop()` call; delete the term and it holds still.
/// `time` is seconds since launch, `sin(time)` walks -1...1, and sizes use
/// `scale` (`shortSide / 1000`), so it breathes the same at any canvas size.
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
