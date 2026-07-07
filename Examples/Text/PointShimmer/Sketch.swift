//  Ported from the p5.js sketch week-3/type-5 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// A word dissolved into a field of points that shimmer. `textToShapes` gives the
/// glyph contours; resampling them at an even spacing turns the type into clean,
/// regularly spaced dots. Each point is
/// then nudged sideways by a sine of its own height, so the letters wobble like
/// type seen through heat haze — the wave travels with time and its amplitude
/// breathes. Uses the bold system font.
@main
final class PointShimmer: Sketch {
    // A face whose counters are separate contours, so the dots trace e/a cleanly.
    // SF draws them as one self-touching outline, whose internal aperture edges
    // dot into a glitch.
    let font = OutlineFont(name: "Helvetica Neue Bold") ?? .systemBold
    var dots: [Vector2] = []

    override func setup() {
        textFont(font)
        textAlign(.center, .middle)
        textSize(300 * scale)
        // Sample the outline once (the word and size don't change), centered on the
        // origin so the shimmer is symmetric — the original sketch's setup-time
        // sampling.
        dots = textToShapes("hello", 0, 0)
            .flatMap(\.contours)
            .flatMap { $0.resampled(spacing: 7 * scale).points }
    }

    override func draw() {
        background(Color(white: 0.24))
        noStroke()
        fill(.white)

        // Gentle shear — a heat-haze wobble, kept small so the small inner contours
        // (the e's aperture, the o's ring) stay intact instead of scattering.
        let amp = map(sin(time * 0.7), -1, 1, 4, 15) * scale
        withState {
            translate(width / 2, height / 2)
            let shimmered = dots.map { p in
                Vector2(p.x + amp * sin(p.y * 0.04 + time * 2), p.y)
            }
            drawPoints(shimmered, size: 6 * scale)
        }
    }
}
