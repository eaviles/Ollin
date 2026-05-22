import Foundation
import Ollin

/// A circle swept left↔right across the canvas by `sin(time)`. Ported from a
/// small p5.js sketch.
///
/// Two p5-isms translate to plain arithmetic, so no extra framework features
/// are needed:
///
/// - p5's `map(sin(time), -1, 1, 0, width)` remaps -1...1 onto 0...width.
///   Inlined, that's `(sin(time) + 1) / 2 * width`. (When Ollin grows a `map()`
///   helper, this is exactly the kind of call site it should replace.)
/// - p5 sizes circles by *diameter* (`circle(x, y, 60)`); Ollin uses *radius*,
///   so a 60-diameter circle is `radius: 30`.
///
/// `width`/`height` are read live, so the sweep stays centered and full-width
/// if the window is resized.
@main
final class SineSweep: Sketch {
    override func draw() {
        background(.black)
        let x = (sin(time) + 1) / 2 * width
        circle(x: x, y: height / 2, radius: 30)
    }
}
