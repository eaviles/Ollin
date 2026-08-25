//  Based on elements of @eaviles's sketch 2023.023. Reworked for Ollin's API.

import Ollin

/// Stacked rows of white ellipse outlines in two drifting columns. Each ring's
/// horizontal position, size, and vertical squash are read from a `signedNoise`
/// field sampled against its row `y` and `time`, so the whole field breathes and
/// wanders without ever repeating. The fill matches the background, so each
/// ellipse's disk hides the rings behind it — overlapping outlines occlude
/// front-to-back instead of all showing through.
@main
final class EllipseField: Sketch {
    override func setup() {
        fill(.black)   // opaque centers, so each ellipse occludes the ones behind it
        stroke(.white)
    }

    override func draw() {
        background(.black)
        let dim = shortSide / 100
        strokeWeight(dim * 0.25)

        // Rows run from just above the top to just below the bottom, so ellipses
        // enter and leave the frame instead of clipping at the edges.
        let margin = 0.125
        let minY = -height * margin
        let maxY = height * (1 + margin)
        let rows = 72.0
        let jump = (maxY - minY) / rows

        var y = minY
        while y <= maxY {
            ring(seed: 1000, offset: -width / 6, y: y)   // left column
            ring(seed: 2000, offset:  width / 6, y: y)   // right column
            y += jump
        }
    }

    /// One ellipse for a row. `seed` decorrelates the two columns by sampling
    /// different cells of the noise field; `offset` shifts the column sideways.
    private func ring(seed: Int, offset: Double, y: Double) {
        let t = time * 0.12

        // Horizontal position: a slow wander across the middle band, plus a
        // finer, faster jitter layered on top.
        var n = signedNoise(Double(seed), t * 2, y * 0.002)
        var x = map(n, -1, 1, width * 0.3, width * 0.7) + offset
        n = signedNoise(Double(seed), t * 2, y * 0.02)
        x += map(n, -1, 1, 0, width * 0.025)

        // Size and vertical squash, each from its own slice of the field.
        n = signedNoise(Double(seed + 1), t, -y * 0.0017)
        let rx = map(n, -1, 1, width * 0.05, width * 0.13)
        n = signedNoise(Double(seed + 4), t, y * 0.004)
        let squash = map(n, -1, 1, 0.4, 1.0)

        drawEllipse(x, y, rx, rx * squash)
    }
}
