import Foundation
import Ollin

/// Single-line (stroke) text — the kind a pen plotter draws. A `StrokeFont`'s
/// glyphs are open pen paths with no fill, so `drawText` strokes them with the
/// current `stroke` (weight, join, cap) and ignores `fill` — the inverse of
/// outline text.
///
/// The bundled default is **Hershey Sans** (public-domain Hershey vector fonts).
/// Everything here is one font, drawn as ink:
/// - a big title whose pen **weight breathes**, with round caps and joins for a
///   soft, drawn-by-hand line;
/// - a fixed caption underneath;
/// - a line of text **riding a wave** and scrolling, to show stroke text works
///   with the same per-glyph / text-on-path surface as every other font kind.
@main
final class StrokeText: Sketch {
    let font = StrokeFont.builtin
    let ink = Color(white: 0.12)

    override func setup() {
        textFont(font)
        strokeCap(.round)
        strokeJoin(.round)
    }

    override func draw() {
        background(Color(white: 0.93))
        stroke(ink)

        // Title: pen weight breathes between a hairline and a fat nib.
        textAlign(.center, .middle)
        textSize(300 * scale)
        strokeWeight((1.5 + (sin(time * 1.6) * 0.5 + 0.5) * 5) * scale)
        drawText("ollin", width / 2, height * 0.42)

        // Caption: a steady thin line.
        textAlign(.center, .top)
        textSize(34 * scale)
        strokeWeight(1.5 * scale)
        drawText("HERSHEY · SINGLE-LINE · PLOTTER TYPE", width / 2, height * 0.6)

        // A line of text scrolling along a gentle wave (text-on-path parity).
        let wave = Path { p in
            let y = height * 0.78
            p.move(to: Vector2(0, y))
            for i in 1...80 {
                let f = Double(i) / 80
                p.curve(to: Vector2(f * width, y + sin(f * .pi * 2 + time) * 60 * scale))
            }
        }
        textSize(40 * scale)
        strokeWeight(2 * scale)
        drawText("drawn with a pen, not a brush · ", along: wave, offset: -time * 90 * scale)
    }
}
