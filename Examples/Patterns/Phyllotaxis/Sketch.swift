import Ollin

/// A sunflower seed-head as a batch call. Each frame asks
/// `phyllotaxis(count:spacing:)` for the spiral (successive points placed at
/// the golden angle, marching outward by `sqrt(i)`), sizes each seed by its
/// age, and draws the whole field with one `drawCircles(_:)`. The batch
/// shares the current fill and rides the transform stack, so the single call
/// is the only draw in the loop: the seeds spin slowly and the count
/// breathes, growing out from the center and receding.
@main
final class Phyllotaxis: Sketch {
    override func setup() {
        noStroke()
        fill(.white)
    }

    override func draw() {
        background(.black)
        let s = min(width, height)
        let count = Int(map(sin(time * 0.4), -1, 1, 300, 1000))

        let seeds = phyllotaxis(count: count, spacing: s * 0.02).enumerated()
            .map { i, p in
                Circle(x: p.x, y: p.y,
                       radius: map(Double(i), 0, Double(count), s * 0.004, s * 0.018))
            }

        withState {
            translate(width / 2, height / 2)
            rotate(time * 0.05)
            drawCircles(seeds)
        }
    }
}
