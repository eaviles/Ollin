//  Recreation after Bridget Riley — "Fragment 3" (1965), one of her black-and-
//  white "Fragments" screenprints on Plexiglas ("horizontal lines bent at
//  altering angles across the surface"). An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import CoreGraphics
import Ollin

/// A field of black-and-white chevron stripes after Bridget Riley's Op-art
/// "Fragment 3" (1965). Every band shares one zigzag offset, so the stripes stay
/// parallel — but the zigzag's amplitude is modulated by a slow sine across the
/// width, so the chevrons swell and compress (Riley's "altering angles" and the
/// optical undulation), while the peaks stay sharp.
///
/// Rendered by column rasterization: each thin vertical slice is the stack of
/// black bands shifted by the offset, drawn as `rect`s. Ollin has no
/// filled-polygon `Shape` yet, so fine columns approximate the diagonals. Static,
/// so `setup()` calls `noLoop()`. The constants in `draw()` are the dials.
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

        let bandHeight = 26.0       // stripe thickness
        let baseAmplitude = 46.0    // how tall the zigzag swings
        let period = 120.0          // chevron width (→ ~5 across)
        let modDepth = 0.45         // how much the swing swells/shrinks (0 = uniform)
        let modCycles = 2.0         // number of those swells across the width
        let dx = 1.0                // column width (smaller = crisper diagonals)

        let span = right - left
        let maxAmplitude = baseAmplitude * (1 + modDepth)

        fill(.black)
        var x = left
        while x < right {
            let w = min(dx, right - x)
            let amplitude = baseAmplitude
                * (1 + modDepth * sin(2 * .pi * modCycles * (x - left) / span))
            let offset = amplitude * triangleWave((x - left) / period)
            var y = top - maxAmplitude - 2 * bandHeight
            while y < bottom + maxAmplitude + 2 * bandHeight {
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

    /// Triangle wave in `-1...1`, period 1: -1 at 0, +1 at 0.5 — sharp peaks.
    private func triangleWave(_ u: Double) -> Double {
        var p = u.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        return p < 0.5 ? (4 * p - 1) : (3 - 4 * p)
    }
}
