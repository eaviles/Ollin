//  Ported from the p5.js sketch week-3/type-4 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A word's outline as evenly spaced points, rendered three ways. `textToShapes`
/// gives the glyph contours; resampling each at an even spacing turns the type
/// into clean, regularly spaced points. The
/// same points become a smooth Catmull-Rom **curve** (`drawCurve`), a straight
/// **polygon** outline (`drawPolygon`), and a field of **dots** (`drawPoints`),
/// stacked so you can compare the three modes on identical points. The spacing
/// breathes coarse↔fine with time (the original sketch drove this the same way);
/// coarse is where the rounded curve and the faceted polygon visibly diverge.
/// Uses the bold system font.
@main
final class GlyphContours: Sketch {
    // A face whose counters are *separate* contours, so each strokes cleanly. SF
    // draws e/a/s as one self-touching outline, whose internal aperture edges show
    // up as a glitch when you stroke or dot it (filling hides them).
    let font = OutlineFont(name: "Helvetica Neue Bold") ?? .systemBold
    let word = "hello"

    override func setup() {
        textFont(font)
        strokeJoin(.round)
        strokeCap(.round)
    }

    override func draw() {
        background(Color(white: 0.24))
        textFont(font)
        textAlign(.center, .middle)
        textSize(150 * scale)

        // Each contour resampled at an even spacing that breathes coarse↔fine,
        // centered on the origin so the rows just translate into place. Drawn
        // per-contour (each closed on itself), so a letter's bowl and counter are
        // separate clean loops — no threads between them and no internal edges.
        let spacing = map(sin(time * 0.6), -1, 1, 22, 10) * scale
        let contours = textToShapes(word, 0, 0)
            .flatMap(\.contours)
            .map { resampled($0.points, spacing: spacing, closed: $0.isClosed) }
            .filter { $0.count >= 2 }

        // 1) Each contour as a smooth closed curve — rounded letterforms.
        withState {
            translate(width / 2, height * 0.24)
            noFill()
            stroke(.white)
            strokeWeight(6 * scale)
            for contour in contours { drawCurve(contour, closed: true) }
        }

        // 2) The same points as straight segments — faceted letterforms.
        withState {
            translate(width / 2, height * 0.5)
            noFill()
            stroke(.white)
            strokeWeight(6 * scale)
            for contour in contours where contour.count >= 3 { drawPolygon(contour) }
        }

        // 3) The bare points (markers take `fill`, so paint the dots with it).
        withState {
            translate(width / 2, height * 0.76)
            noStroke()
            fill(.white)
            for contour in contours { drawPoints(contour, size: 8 * scale) }
        }
    }

    /// Resample a polyline at an even arc-length `spacing` — clean, regularly
    /// spaced points instead of Core Text's raw outline vertices (dense on curves,
    /// sparse on straights).
    private func resampled(_ points: [Vector2], spacing: Double, closed: Bool) -> [Vector2] {
        guard points.count >= 2, spacing > 0 else { return points }
        var poly = points
        if closed { poly.append(points[0]) }
        var result = [poly[0]]
        var distSinceLast = 0.0          // arc length accrued since the last emit
        for i in 1..<poly.count {
            let a = poly[i - 1], b = poly[i]
            let segLen = (b - a).length
            guard segLen > 1e-9 else { continue }
            var t = 0.0                  // position along this segment, 0…segLen
            while distSinceLast + (segLen - t) >= spacing {
                t += spacing - distSinceLast
                result.append(a + (b - a) * (t / segLen))
                distSinceLast = 0
            }
            distSinceLast += segLen - t  // carry the unconsumed tail forward
        }
        return result
    }
}
