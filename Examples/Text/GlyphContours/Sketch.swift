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
            .map { $0.resampled(spacing: spacing).points }
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
}
