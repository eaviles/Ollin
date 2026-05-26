//  Recreation after Bridget Riley — "Fragment 3" (1965), one of her black-and-
//  white "Fragments" screenprints on Plexiglas ("horizontal lines bent at
//  altering angles across the surface"). An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import CoreGraphics
import Ollin

/// A field of black-and-white chevron stripes — horizontal bands bent into a
/// zigzag — after Bridget Riley's Op-art "Fragment 3" (1965). Every band shares
/// one triangle-wave offset, so the stripes stay parallel as they zigzag.
///
/// Rendered by column rasterization: for each thin vertical slice, the stacked
/// black bands are shifted by the zigzag offset and drawn as `rect`s. Ollin has
/// no filled-polygon `Shape` yet, so this approximates the diagonal edges with
/// fine columns. The image is static, so `setup()` calls `noLoop()`.
@main
final class Fragment3: Sketch {
    override var preferredSize: CGSize { CGSize(width: 800, height: 600) }

    override func setup() {
        noStroke()
        noLoop()
    }

    override func draw() {
        background(.white)
        let inset = 80.0
        let left = inset, right = width - inset
        let top = inset, bottom = height - inset
        let bandHeight = 22.0, amplitude = 44.0, period = 100.0, dx = 2.0

        // Each thin column is the stack of black bands, shifted vertically by a
        // shared triangle wave — so the parallel stripes zigzag across the field.
        fill(.black)
        var x = left
        while x < right {
            let w = min(dx, right - x)
            let offset = amplitude * triangleWave((x - left) / period)
            var y = top - amplitude - 2 * bandHeight
            while y < bottom + amplitude + 2 * bandHeight {
                rect(x: x, y: y + offset, width: w, height: bandHeight)
                y += 2 * bandHeight
            }
            x += dx
        }

        // Clean horizontal edges for the block: mask the zigzag overflow.
        fill(.white)
        rect(x: 0, y: 0, width: width, height: top)
        rect(x: 0, y: bottom, width: width, height: height - bottom)
    }

    /// Triangle wave in `-1...1`, period 1: -1 at 0, +1 at 0.5.
    private func triangleWave(_ u: Double) -> Double {
        var p = u.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        return p < 0.5 ? (4 * p - 1) : (3 - 4 * p)
    }
}
