import Foundation
import Ollin

/// A circle swept left↔right across the canvas. `map` remaps `sin(time)`
/// (which swings -1...1) onto 0...width, so the circle slides from edge to
/// edge — half-off each side at the extremes.
///
/// `width`/`height` are read live, so the sweep stays full-width on resize.
@main
final class SineSweep: Sketch {
    override func draw() {
        background(.black)
        let x = map(sin(time), -1, 1, 0, width)
        circle(x: x, y: height / 2, radius: 30)
    }
}
