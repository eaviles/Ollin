import Ollin

/// 2000 dots a frame, each placed with `randomGaussian()`: the horizontal offset
/// from center is normally distributed, so they pile up in the middle and thin
/// out toward the edges — the bell curve made visible. It's unseeded, so the
/// cloud shimmers as it re-rolls every frame. Compare `RandomBand`, which spreads
/// its dots evenly across the width.
@main
final class Gaussian: Sketch {
    override func setup() {
        noStroke()
        fill(Color(white: 1, alpha: 0.25))
    }

    override func draw() {
        background(.black)
        for _ in 0..<2000 {
            let x = width / 2 + randomGaussian() * 120
            let y = random(height)
            circle(x, y, 2)
        }
    }
}
