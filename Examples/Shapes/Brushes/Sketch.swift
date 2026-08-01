import Ollin

/// Marks made by repeating a shape along a path.
///
/// A `strokeBrush` swaps the continuous ribbon a stroke normally draws for a row
/// of stamps. The stamp takes its size from `strokeWeight` and its color from
/// `stroke`, so the brush only decides the *texture*: how far apart the stamps
/// sit, how much they vary in size and angle, and how far they stray off the
/// line. Everything is seeded, so a mark stays put frame to frame.
///
/// The same wave is drawn six ways. The last two are the interesting ones: a
/// brush multiplies with `strokeProfile`, so a scattered mark can taper like any
/// other, and a shape tip lets the stamp be anything you can draw.
@main
final class Brushes: Sketch {
    private let ink = Color(hex: 0x24303C)
    private let paper = Color(hex: 0xF3EFE7)
    private var leaf = Shape(curveThrough: [], closed: true)

    override func setup() {
        // A leaf, used as a tip below: a pointed lens, one edge out and one back.
        var outline: [Vector2] = []
        for i in 0...20 {
            let t = Double(i) / 20
            outline.append(Vector2(-0.5 + t, sin(t * .pi) * 0.3))
        }
        for i in 0...20 {
            let t = 1 - Double(i) / 20
            outline.append(Vector2(-0.5 + t, -sin(t * .pi) * 0.3))
        }
        leaf = Shape(curveThrough: outline, closed: true)
    }

    override func draw() {
        background(paper)
        noFill()
        stroke(ink)

        // The wave drifts, so you can watch the stamps travel with the path
        // instead of boiling in place.
        func wave(_ row: Int) -> [Vector2] {
            let y = height * (0.12 + Double(row) * 0.145)
            return (0...140).map { i in
                let t = Double(i) / 140
                return Vector2(width * 0.08 + t * width * 0.84,
                               y + sin(t * .pi * 2.2 + time * 0.6 + Double(row)) * height * 0.05)
            }
        }

        strokeWeight(width * 0.026)

        strokeBrush(.round)
        drawPolyline(wave(0))
        label("round", 0)

        strokeBrush(.chisel())
        drawPolyline(wave(1))
        label("chisel", 1)

        strokeBrush(.spray(seed: variation))
        drawPolyline(wave(2))
        label("spray", 2)

        strokeBrush(.scatter(seed: variation))
        drawPolyline(wave(3))
        label("scatter", 3)

        // A brush and a width profile multiply, so the stamps shrink toward both
        // ends the way the ribbon would.
        strokeBrush(Brush(.circle, spacing: 0.35, sizeJitter: 0.35, seed: variation))
        strokeProfile(.taper())
        drawPolyline(wave(4))
        noStrokeProfile()
        label("round + taper", 4)

        // Any shape can be a tip.
        strokeBrush(Brush(.shape(leaf), spacing: 0.9, sizeJitter: 0.4,
                          angleJitter: 0.5, scatter: 0.5, seed: variation))
        drawPolyline(wave(5))
        label("shape tip", 5)

        noStrokeBrush()
    }

    private func label(_ text: String, _ row: Int) {
        withState {
            noStrokeBrush()
            noStroke()
            fill(ink.withAlpha(0.55))
            textSize(width * 0.022)
            textAlign(.left, .middle)
            drawText(text, width * 0.08, height * (0.12 + Double(row) * 0.145) - height * 0.075)
        }
    }
}
