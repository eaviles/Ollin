//  Ported from the p5.js sketch week-3/type-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5 — itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.

import Foundation
import Ollin

/// Text metrics, drawn. `textWidth`, `textAscent`, `textDescent`, and `textBounds`
/// turn a word into measurable geometry — and here those numbers are made visible
/// around a measured word: the **baseline** and its **origin** (red), the
/// **ascent** bar up and **descent** bar down (yellow / blue), and the bounding
/// box `textBounds` returns (green). Above it, "hello" is stamped many times along
/// a tight diagonal, each copy a step brighter — an extruded ramp showing `fill`
/// change with nothing else moving. The extrusion length breathes. Uses the bold
/// system font.
@main
final class TextMetrics: Sketch {
    let font = OutlineFont.systemBold

    override func setup() {
        textFont(font)
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.24))   // the source's background(60), in 0…1

        // Extruded ramp: "hello" stamped along a tight 45° diagonal, each copy a
        // step brighter (dark behind, white in front) — `fill` changing while no
        // other state does. Kept still: the copies sit ~1px apart, so animating the
        // depth makes them crawl/shimmer (sub-pixel temporal aliasing).
        textFont(font)
        textAlign(.left, .baseline)
        let size = 84.0 * scale
        textSize(size)
        let steps = 100
        let depth = size * 1.5
        let origin = Vector2(width * 0.13, height * 0.2)
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            fill(Color(white: f))                       // monotonic dark → light
            drawText("hello", origin.x + f * depth, origin.y + f * depth)
        }

        // The measured word, with every metric drawn around it. "heljo" (from the
        // original) is a deliberate metrics test word, not a typo: the j gives a
        // descender so textDescent has something to show, while h/l are ascenders.
        // Its size breathes and every metric below is measured live at that size,
        // so the baseline, bars, and box animate with it — smoothly, since it's one
        // filled word, not the stacked ramp above (which would crawl if animated).
        let word = "heljo"
        let baseline = Vector2(width * 0.13, height * 0.64)
        textSize((116 + 18 * sin(time * 0.9)) * scale)
        fill(.white)
        drawText(word, at: baseline)

        let w = textWidth(word)
        let asc = textAscent()
        let desc = textDescent()

        // Baseline (its length is `textWidth`) in red, with the origin dot.
        stroke(Color(red: 1, green: 0.32, blue: 0.32))
        strokeWeight(2 * scale)
        drawLine(baseline.x, baseline.y, baseline.x + w, baseline.y)
        noStroke()
        fill(Color(red: 1, green: 0.32, blue: 0.32))
        drawCircle(baseline.x, baseline.y, 7 * scale)

        // `textBounds` box (green): the full ascent…descent extent of the word.
        noFill()
        stroke(Color(red: 0.4, green: 1, blue: 0.55))
        strokeWeight(2 * scale)
        drawRect(textBounds(word, at: baseline))

        // Ascent (above the baseline) and descent (below) as bars just past the
        // word's right edge.
        let barX = baseline.x + w + 28 * scale
        stroke(Color(red: 1, green: 0.88, blue: 0.3))
        drawLine(barX, baseline.y, barX, baseline.y - asc)        // ascent, up
        stroke(Color(red: 0.45, green: 0.7, blue: 1))
        drawLine(barX, baseline.y, barX, baseline.y + desc)       // descent, down

        // Legend.
        noStroke()
        textAlign(.left, .top)
        textSize(26 * scale)
        fill(Color(white: 0.85))
        drawText("textWidth · textAscent · textDescent · textBounds",
                 width * 0.13, height * 0.8)
    }
}
