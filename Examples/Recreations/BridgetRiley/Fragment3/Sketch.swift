//  Recreation after Bridget Riley — "Fragment 3" (1965), one of her black-and-
//  white "Fragments" screenprints on Plexiglas ("horizontal lines bent at
//  altering angles across the surface"). An original Ollin interpretation built
//  from the artwork — not ported from a source sketch. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.

import Foundation
import Ollin

/// A field of black-and-white chevron stripes after Bridget Riley's Op-art
/// "Fragment 3" (1965). They're filled polygons; the *curved* look comes from a
/// few devices:
///   1. the stripe **thickness swells toward the vertical center** (thin at top
///      and bottom, thick in the middle), which reads as a bulging surface,
///   2. the zigzag **amplitude alters across the width**, so each chevron column
///      differs a little, and
///   3. each row's zigzag **slides** so the columns of peaks bow into curves
///      rather than standing straight.
///
/// Riley's print is still, but the eye reads it as moving — so here the field is
/// pinned to a fixed frame (the four corners stay put) and the *interior* sways
/// on both axes:
///   - **X sway**: pinned at the left and right edges, the columns bow side to
///     side; the top and bottom edges are free to shift in X.
///   - **Y sway**: pinned at the top and bottom edges, the rows bow up and down;
///     the left and right edges are free to shift in Y.
///
/// Each sway tapers to zero at the edges it's pinned to, so the zigzag is
/// anchored to the frame and stretches between the edges instead of sliding off
/// behind them. Each black stripe is a chevron strip between two zigzag polylines
/// — one filled `polygon` (a quad) per segment, so the diagonal edges are true
/// (MSAA-smoothed) edges, and the bend *vertices* move so the peaks stay sharp.
/// Tune the motion live with the `@Param` sliders.
@main
final class Fragment3: Sketch {
    @Param(0...160) var xSway = 16.0  // how far the columns bow side to side (px)
    @Param(0...6) var xSpeed = 0.6    // how fast the X sway oscillates
    @Param(0...160) var ySway = 24.0  // how far the rows bow up and down (px)
    @Param(0...6) var ySpeed = 0.5    // how fast the Y sway oscillates

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.white)
        // All lengths scale with the canvas (`scale` = min(width, height) / 1000),
        // so the chevron field keeps its density at any size.
        let inset = 110 * scale
        let left = inset, right = width - inset
        let top = inset, bottom = height - inset
        let centerY = (top + bottom) / 2, halfHeight = (bottom - top) / 2
        let span = right - left

        let baseAmplitude = 32 * scale, period = 60 * scale, modDepth = 0.12
        let minThickness = 22 * scale, maxThickness = 32 * scale
        let halfPeriod = period / 2
        let twist = 1.0                   // half-cycles of bow across the field
        let xMag = xSway * scale          // the X-sway slider, in canvas pixels
        let yMag = ySway * scale          // the Y-sway slider, in canvas pixels

        func thickness(at y: Double) -> Double {
            let v = max(-1, min(1, (y - centerY) / halfHeight))   // -1 top … 1 bottom
            return minThickness + (maxThickness - minThickness) * cos(v * .pi / 2)
        }
        // Fixed in time: the amplitude only varies gently across the width, so the
        // silhouette's peaks return to the same heights every frame.
        func amplitude(atX x: Double) -> Double {
            let u = (x - left) / span
            return baseAmplitude * (1 + modDepth * sin(2 * .pi * 1.5 * u))
        }

        // The rows are inset by the silhouette's vertical reach (peak amplitude),
        // so the top/bottom edges are the zigzag itself with a clean white margin
        // above the highest peak and below the lowest valley.
        let edgeReserve = baseAmplitude * (1 + modDepth)
        let firstBaseline = top + edgeReserve
        let lastBaseline = bottom - edgeReserve
        let vSpan = lastBaseline - firstBaseline

        // Tapers: 0 at the edge the sway is pinned to, 1 in the middle. The X sway
        // is pinned at the left/right (tapered across the width); the Y sway is
        // pinned at the top/bottom (tapered down the height). So the interior
        // transforms while the frame stays put.
        func hTaper(_ x: Double) -> Double { sin(.pi * (x - left) / span) }
        func vTaper(_ y: Double) -> Double { sin(.pi * max(0, min(1, (y - firstBaseline) / vSpan))) }

        // The sway magnitudes, before their tapers. Each varies across the field
        // (so the bow curves) and oscillates over time.
        func xShift(atY y: Double) -> Double {
            let v = max(-1, min(1, (y - centerY) / halfHeight))
            return xMag * sin(v * .pi * twist + time * xSpeed)
        }
        func yShift(atX x: Double) -> Double {
            let u = (x - left) / span
            return yMag * sin(u * .pi * twist + time * ySpeed)
        }

        // Row boundaries (the shared edges between bands), top to bottom.
        var boundaries: [Double] = []
        var cy = firstBaseline
        while cy < lastBaseline {
            boundaries.append(cy)
            cy += thickness(at: cy)
        }
        boundaries.append(cy)

        // A grid of bend points landing exactly on the left and right edges, so
        // those edges are pinned (the X sway tapers to zero there). An even count
        // makes both edges share the same zigzag phase.
        var nHalf = max(2, Int((span / halfPeriod).rounded()))
        if nHalf % 2 == 1 { nHalf += 1 }
        let hp = span / Double(nHalf)

        // Each boundary becomes a polyline of bend points; vertex j is a peak when
        // j is even, a valley when odd. The peak/valley sign is the same in every
        // row, so the chevrons stack. The amplitude is keyed to the fixed grid
        // `baseX`, so a vertex's height doesn't wobble as the interior shifts.
        let rows: [[Vector2]] = boundaries.map { by in
            let rowXShift = xShift(atY: by)
            let rowVTaper = vTaper(by)
            return (0...nHalf).map { j -> Vector2 in
                let baseX = left + Double(j) * hp
                let x = baseX + rowXShift * hTaper(baseX)
                let y = by + (j & 1 == 0 ? 1.0 : -1.0) * amplitude(atX: baseX)
                      + yShift(atX: baseX) * rowVTaper
                return Vector2(x, y)
            }
        }

        // Each black band is the chevron strip between two boundary polylines.
        // The two bow by different amounts, so the band leans — curved columns.
        fill(.black)
        var k = 0
        while k + 1 < boundaries.count {
            if k % 2 == 0 {   // every other band is black; the rest is white paper
                let topRow = rows[k], botRow = rows[k + 1]
                for i in 0 ..< (topRow.count - 1) {
                    polygon([topRow[i], topRow[i + 1], botRow[i + 1], botRow[i]])
                }
            }
            k += 1
        }
    }
}
