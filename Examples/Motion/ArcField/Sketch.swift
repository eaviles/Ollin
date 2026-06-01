//  Based on elements of @eaviles's sketch 2023.023. Reworked for Ollin's API.

import Ollin

/// The arc cousin of EllipseField. Instead of whole ellipses, each row draws a
/// chord-closed elliptical *arc*: `signedNoise` sets not just the position, size,
/// and vertical squash but also where the arc starts and how far it sweeps, so
/// the rings open and close into crescents as the field drifts. Black fill on
/// black background, so each segment still occludes the ones behind it.
@main
final class ArcField: Sketch {
    override func setup() {
        fill(.black)   // opaque centers, so each arc occludes the ones behind it
        stroke(.white)
    }

    override func draw() {
        background(.black)
        let dim = min(width, height) / 100
        strokeWeight(dim * 0.25)

        let margin = 0.125
        let minY = -height * margin
        let maxY = height * (1 + margin)
        let rows = 160.0
        let jump = (maxY - minY) / rows

        var y = minY
        while y <= maxY {
            arc(seed: 1000, offset: -width / 6, y: y)   // left column
            arc(seed: 2000, offset:  width / 6, y: y)   // right column
            y += jump
        }
    }

    /// One arc for a row. `seed` decorrelates the two columns by sampling
    /// different cells of the noise field; `offset` shifts the column sideways.
    private func arc(seed: Int, offset: Double, y: Double) {
        let t = time * 0.07

        // Horizontal position: a slow wander across the middle band, plus a
        // finer, faster jitter layered on top.
        var n = signedNoise(Double(seed), t * 2, y * 0.002)
        var x = map(n, -1, 1, width * 0.3, width * 0.7) + offset
        n = signedNoise(Double(seed), t * 2, y * 0.02)
        x += map(n, -1, 1, 0, width * 0.025)

        // Size and vertical squash.
        n = signedNoise(Double(seed + 1), t, -y * 0.0017)
        let rx = map(n, -1, 1, width * 0.05, width * 0.13)
        n = signedNoise(Double(seed + 4), t, y * 0.004)
        let squash = map(n, -1, 1, 0.4, 1.0)

        // Arc span: where it begins and how far it sweeps.
        n = signedNoise(Double(seed + 2), -t, y * 0.0014)
        let begin = map(n, -1, 1, 0, .tau)
        n = signedNoise(Double(seed + 3), -t, -y * 0.002)
        let sweep = map(n, -1, 1, .pi * 0.25, .tau * 0.85)

        drawArc(x, y, rx, rx * squash, start: begin, stop: begin + sweep, mode: .chord)
    }
}
