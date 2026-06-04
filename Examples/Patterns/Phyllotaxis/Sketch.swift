import Ollin

/// A sunflower seed-head as a batch call. Each frame builds the phyllotaxis
/// spiral — successive points placed at the golden angle, marching outward by
/// `sqrt(i)` — into an array of `Circle`s, then draws the whole field with one
/// `drawCircles(_:)`. The batch shares the current fill and rides the transform
/// stack, so the single call is the only draw in the loop: the seeds spin slowly
/// and the count breathes, growing out from the center and receding.
@main
final class Phyllotaxis: Sketch {
    // The golden angle, π(3 − √5) ≈ 137.5°, is what spaces the seeds evenly.
    let goldenAngle = Double.pi * (3 - Double(5).squareRoot())

    override func setup() {
        noStroke()
        fill(.white)
    }

    override func draw() {
        background(.black)
        let s = min(width, height)
        let spacing = s * 0.02
        let count = Int(map(sin(time * 0.4), -1, 1, 300, 1000))

        var seeds: [Circle] = []
        seeds.reserveCapacity(count)
        for i in 0..<count {
            let angle = Double(i) * goldenAngle
            let r = spacing * Double(i).squareRoot()
            let radius = map(Double(i), 0, Double(count), s * 0.004, s * 0.018)
            seeds.append(Circle(x: cos(angle) * r, y: sin(angle) * r, radius: radius))
        }

        withState {
            translate(width / 2, height / 2)
            rotate(time * 0.05)
            drawCircles(seeds)
        }
    }
}
