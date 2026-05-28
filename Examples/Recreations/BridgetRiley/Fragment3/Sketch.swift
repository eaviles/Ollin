//  Recreation after Bridget Riley — "Fragment 3" (1965), one of her black-and-
//  white "Fragments" screenprints on Plexiglas ("horizontal lines bent at
//  altering angles across the surface"). An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import Ollin

/// A field of black-and-white chevron stripes after Bridget Riley's Op-art
/// "Fragment 3" (1965). They're filled polygons; the *curved* look is an
/// illusion from two devices:
///   1. the stripe **thickness swells toward the vertical center** (thin at top
///      and bottom, thick in the middle), which reads as a bulging surface, and
///   2. all stripes share one **zigzag** offset whose amplitude alters gently
///      across the width, so each chevron column differs a little.
///
/// Each black stripe is a chevron strip — one filled `polygon` (a quad) per
/// zigzag segment, so the diagonal edges are true edges (MSAA-smoothed), not
/// rasterized columns. Static, so `setup()` calls `noLoop()`.
@main
final class Fragment3: Sketch {
    override func setup() {
        noStroke()
        noLoop()
    }

    override func draw() {
        background(.white)
        // All lengths scale with the canvas (`scale` = min(width, height) / 1000),
        // so the chevron field keeps its density at any square size.
        let inset = 80 * scale
        let left = inset, right = width - inset
        let top = inset, bottom = height - inset
        let centerY = (top + bottom) / 2, halfHeight = (bottom - top) / 2

        let baseAmplitude = 44 * scale, period = 58 * scale, modDepth = 0.4
        let minThickness = 18 * scale, maxThickness = 30 * scale
        let halfPeriod = period / 2

        func thickness(at y: Double) -> Double {
            let v = max(-1, min(1, (y - centerY) / halfHeight))   // -1 top … 1 bottom
            return minThickness + (maxThickness - minThickness) * cos(v * .pi / 2)
        }
        func offset(at x: Double) -> Double {
            let amp = baseAmplitude * (1 + modDepth * sin(2 * .pi * (x - left) / (right - left)))
            return amp * triangleWave((x - left) / period)
        }

        // Band boundaries from the variable thickness, extended past the block
        // so the zigzag never exposes a gap at the masked edges.
        let slack = baseAmplitude * (1 + modDepth) + maxThickness
        var boundaries: [Double] = []
        var cy = top - slack
        while cy < bottom + slack {
            boundaries.append(cy)
            cy += thickness(at: cy)
        }
        boundaries.append(cy)

        // Zigzag bend points across the width (a peak/valley every half-period),
        // ending at the right edge; the offset is sampled once per bend.
        var xs: [Double] = []
        var vx = left
        while vx < right { xs.append(vx); vx += halfPeriod }
        xs.append(right)
        let offsets = xs.map { offset(at: $0) }

        // Each black stripe is a chevron strip: one filled quad per segment.
        fill(.black)
        var k = 0
        while k + 1 < boundaries.count {
            if k % 2 == 0 {   // every other band is black; the rest is white paper
                let yTop = boundaries[k], yBot = boundaries[k + 1]
                for i in 0 ..< (xs.count - 1) {
                    polygon([
                        Vector2(xs[i],     yTop + offsets[i]),
                        Vector2(xs[i + 1], yTop + offsets[i + 1]),
                        Vector2(xs[i + 1], yBot + offsets[i + 1]),
                        Vector2(xs[i],     yBot + offsets[i]),
                    ])
                }
            }
            k += 1
        }

        // Clean horizontal edges for the block: mask the zigzag overflow.
        fill(.white)
        rect(x: 0, y: 0, width: width, height: top)
        rect(x: 0, y: bottom, width: width, height: height - bottom)
    }

    /// Triangle wave in `-1...1`, period 1: -1 at 0, +1 at 0.5 — sharp peaks.
    private func triangleWave(_ u: Double) -> Double {
        var p = u.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        return p < 0.5 ? (4 * p - 1) : (3 - 4 * p)
    }
}
