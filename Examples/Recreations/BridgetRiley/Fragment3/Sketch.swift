//  Recreation after Bridget Riley — "Fragment 3" (1965), one of her black-and-
//  white "Fragments" screenprints on Plexiglas ("horizontal lines bent at
//  altering angles across the surface"). An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import CoreGraphics
import Ollin

/// A field of black-and-white chevron stripes after Bridget Riley's Op-art
/// "Fragment 3" (1965). They're straight-edged polygons; the *curved* look is an
/// illusion built from two devices:
///   1. the stripe **thickness swells toward the vertical center** (thin at top
///      and bottom, thick in the middle), which reads as a bulging surface, and
///   2. all stripes share one **zigzag** offset whose amplitude alters gently
///      across the width, so each chevron column differs a little.
///
/// Rendered by column rasterization: band boundaries are precomputed from the
/// vertical thickness envelope, then each thin vertical slice draws the black
/// bands shifted by the zigzag. Ollin has no filled-polygon `Shape` yet, so fine
/// columns approximate the diagonals. Static, so `setup()` calls `noLoop()`.
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
        let centerY = (top + bottom) / 2, halfHeight = (bottom - top) / 2

        // Zigzag (straight-leg chevrons); amplitude alters gently across x so
        // each column differs.
        let baseAmplitude = 30.0, period = 110.0, modDepth = 0.2, dx = 1.0
        // Stripe thickness swells toward the vertical center — the bulge illusion.
        let minThickness = 14.0, maxThickness = 38.0

        func thickness(at y: Double) -> Double {
            let v = max(-1, min(1, (y - centerY) / halfHeight))   // -1 top … 1 bottom
            return minThickness + (maxThickness - minThickness) * cos(v * .pi / 2)
        }
        func offset(at x: Double) -> Double {
            let amp = baseAmplitude * (1 + modDepth * sin(2 * .pi * (x - left) / (right - left)))
            return amp * triangleWave((x - left) / period)
        }

        // Precompute band boundaries (variable thickness), extended past the
        // block so the zigzag never exposes a gap at the masked edges.
        let slack = baseAmplitude * (1 + modDepth) + maxThickness
        var boundaries: [Double] = []
        var cy = top - slack
        while cy < bottom + slack {
            boundaries.append(cy)
            cy += thickness(at: cy)
        }
        boundaries.append(cy)

        fill(.black)
        var x = left
        while x < right {
            let w = min(dx, right - x)
            let dy = offset(at: x)
            var k = 0
            while k + 1 < boundaries.count {
                if k % 2 == 0 {   // every other band is black; the rest is white paper
                    rect(x: x, y: boundaries[k] + dy,
                         width: w, height: boundaries[k + 1] - boundaries[k])
                }
                k += 1
            }
            x += dx
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
