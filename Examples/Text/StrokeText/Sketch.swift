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
        strokeWeight((1.5 + unipolar(sin(time * 1.6)) * 5) * scale)
        drawText("ollin", width / 2, height * 0.42)

        // Caption: a steady thin line.
        textAlign(.center, .top)
        textSize(34 * scale)
        strokeWeight(1.5 * scale)
        drawText("HERSHEY · SINGLE-LINE · PLOTTER TYPE", width / 2, height * 0.6)

        // A line of text scrolling along a gentle wave (text-on-path parity).
        // Overhang the path past both screen edges so marquee glyphs enter and
        // leave off-canvas, instead of tilting to the steep end-tangent and
        // vanishing at the visible edge.
        let margin = 220.0 * scale
        let span = width + margin * 2
        let wave = Path { p in
            let y = height * 0.78
            p.move(to: Vector2(-margin, y))
            for i in 1...100 {
                let f = Double(i) / 100
                p.curve(to: Vector2(-margin + f * span, y + sin(f * .pi * 2 + time) * 60 * scale))
            }
        }
        // A seamless marquee: repeat the phrase so it overflows the path, then
        // wrap the scroll offset by one phrase width so it loops forever instead of
        // scrolling off the left and never coming back.
        textSize(40 * scale)
        strokeWeight(2 * scale)
        let phrase = "drawn with a pen, not a brush · "
        let unit = textWidth(phrase)
        let reps = Int((span / max(unit, 1)).rounded(.up)) + 2
        let marquee = String(repeating: phrase, count: reps)
        let scroll = -(time * 90 * scale).truncatingRemainder(dividingBy: unit)
        drawText(marquee, along: wave, offset: scroll)
    }
}
