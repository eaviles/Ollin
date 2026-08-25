//  Recreation after Bridget Riley — "Current" (1964), synthetic polymer paint on
//  composition board (MoMA): the whole surface filled with closely spaced,
//  parallel undulating lines whose wavelength tightens toward the center, so the
//  eye reads a rippling, shimmering field. An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import Ollin

/// A field of parallel wavy lines after Bridget Riley's Op-art "Current" (1964).
///
/// Each line is a smooth curve drawn straight from a handful of sampled points
/// with `drawCurve` — Ollin reads the points and fairs a Catmull-Rom spline
/// through them, so a sine sampled coarsely comes back as a clean wave with no
/// tessellation on our part.
///
/// The shimmer comes from two devices true to the painting:
///   1. the horizontal **wavelength tightens toward the vertical center** (the
///      waves look like they speed up through the middle), and
///   2. the whole field **drifts** sideways over time, which Riley's still board
///      only implies but motion makes literal.
@main
final class Current: Sketch {
    @Param(20...140) var lines = 86.0       // number of horizontal lines
    @Param(0...40) var amplitude = 15.0     // wave height (px, before scale)
    @Param(1...18) var waves = 7.0          // waves across the width at the edges
    @Param(0...2) var swell = 1.0           // extra waves through the center
    @Param(0...4) var drift = 0.7           // sideways drift speed

    override func setup() {
        noFill()
    }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(1.6 * scale)

        // All lengths scale with the canvas (`scale` = shortSide / 1000),
        // so the line field keeps its density at any export size.
        let inset = 70 * scale
        let left = inset, right = width - inset
        let top = inset, bottom = height - inset
        let centerY = (top + bottom) / 2
        let halfHeight = (bottom - top) / 2

        let rows = Int(lines)
        let gap = (bottom - top) / Double(rows)
        let amp = amplitude * scale
        let samples = 60
        let phase = time * drift

        for r in 0...rows {
            let y0 = top + Double(r) * gap
            let v = (y0 - centerY) / halfHeight          // -1 (top) … 1 (bottom)
            // Wavelength tightens toward the middle: more cycles where |v| → 0.
            let cycles = waves * (1 + swell * (1 - abs(v)))

            var points: [Vector2] = []
            points.reserveCapacity(samples + 1)
            for s in 0...samples {
                let t = Double(s) / Double(samples)
                let x = left + (right - left) * t
                // Reference the cycles from mid-width so the wavelength spread
                // fans symmetrically out to both edges (coherent center), and
                // offset each row a little so the lines never all align.
                let y = y0 + amp * sin(cycles * (t - 0.5) * .tau + phase + v * 0.9)
                points.append(Vector2(x, y))
            }
            drawCurve(points)
        }
    }
}
