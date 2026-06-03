import Foundation
import Ollin

/// Text on a path. `drawText(_:along:)` lays each glyph along a curve, rotating it
/// to the path's tangent so the baseline follows the line. The path is an
/// undulating wave that breathes over time, and the message scrolls along it —
/// animate `offset` and glyphs flow on and off the ends. Uses the bold system
/// font; the path is an ordinary `Path`, so any curve works.
@main
final class TextOnPath: Sketch {
    let font = OutlineFont.systemBold
    let message = "ollin · creative coding on a curve · "

    override func setup() { textFont(font) }

    override func draw() {
        background(Color(white: 0.06))
        textFont(font)
        textSize(46 * scale)
        textAlign(.left, .baseline)

        // An undulating path across the canvas, breathing over time.
        let path = Path { p in
            let segments = 80
            for i in 0...segments {
                let f = Double(i) / Double(segments)
                let point = Vector2(f * width,
                                    height / 2 + sin(f * .pi * 3 + time * 0.8) * (height * 0.18))
                if i == 0 { p.move(to: point) } else { p.curve(to: point) }
            }
        }

        // The path itself, faint.
        noFill()
        stroke(Color(white: 1, alpha: 0.1))
        strokeWeight(2 * scale)
        drawShape(path.shape)

        // The message riding it, scrolling seamlessly (the text is periodic, so a
        // scroll of one message-width loops without a seam).
        noStroke()
        fill(.white)
        let span = textWidth(message)
        let scroll = (time * 130 * scale).truncatingRemainder(dividingBy: span)
        drawText(String(repeating: message, count: 6), along: path, offset: -scroll)
    }
}
