import Ollin

/// A circle for every fraction, and none of them ever overlap.
///
/// Give the fraction `p/q` a circle of radius `1/(2q²)` sitting on the number line
/// at `p/q`. Do it for every fraction at once. Nothing in that rule says the
/// circles should fit together, and yet they never overlap, and two of them touch
/// exactly when their fractions are neighbors, meaning `ps - qr` is `1` or `-1`.
/// Lester Ford wrote them down in 1938.
///
/// The top band is the whole run from 0 to 1. The bottom band is the slice the
/// marker names, opened out to the full width, and it travels over the loop. The
/// two bands are the same picture at different scales, which is the point: the
/// arrangement repeats wherever you look, because a fraction's neighbors always
/// sit where the rule puts them.
///
/// Watch the marker cross 0.618, the golden ratio less one. The circles thin out
/// there and never close over it. That is the number fractions approximate worst,
/// so nothing with a small denominator ever lands near it.
///
/// A slice this narrow makes the halves and thirds thousands of units across, so a
/// circle wider than its band is left out: drawing it would paint over everything
/// and say nothing. Hold the mouse to join every pair that touches.
@main
final class FordCircles_Example: Sketch {
    override var loopDuration: Double? { 18 }

    private let order = 40
    private let span = 0.075

    override func draw() {
        background(Color(hex: 0x0A0D14))

        let whole = Rectangle(x: 0, y: 0, width: width, height: height / 2)
        let detail = Rectangle(x: 0, y: height / 2, width: width, height: height / 2)
        let start = loopProgress(over: 18) * (1 - span)

        // The whole line, at the one scale that makes the circles touch: the unit
        // interval across the width, and the radii scaled by that same width.
        withClip(whole) {
            draw(fordCircles(order: order, in: whole), inside: whole)
        }

        // The same rule seen through a narrow window. A narrow window is a wide
        // rectangle hanging off both sides of the canvas.
        let scale = width / span
        let line = Rectangle(x: -start * scale, y: detail.y, width: scale, height: detail.height)
        let near = fordCircles(order: order, in: line, interval: start ... (start + span))
            .filter { $0.circle.radius <= detail.height * 8 }
        withClip(detail) {
            draw(near, inside: detail)

            if mouseIsPressed {
                stroke(Color(hex: 0xFFFFFF, alpha: 0.45))
                strokeWeight(1)
                for i in near.indices {
                    for j in (i + 1) ..< near.count where near[i].touches(near[j]) {
                        drawLine(near[i].circle.center, near[j].circle.center)
                    }
                }
            }
        }

        // What the lower band is looking at.
        noFill()
        stroke(Color(hex: 0xFFFFFF, alpha: 0.55))
        strokeWeight(2)
        drawRect(Rectangle(x: start * width, y: whole.height - 40,
                           width: span * width, height: 40))

        drawCaption("\(near.count) circles between \(String(format: "%.3f", start)) and "
            + "\(String(format: "%.3f", start + span)), out of \(fareySequence(order: order).count) "
            + "fractions with a denominator of \(order) or less")
    }

    private func draw(_ circles: [FordCircle], inside band: Rectangle) {
        strokeWeight(1.5)
        for ford in circles {
            // Small denominators are the big circles and the good approximations,
            // so the ramp runs by denominator rather than by position.
            let q = Double(ford.fraction.denominator)
            let paint = CosinePalette.rainbow.color(at: 0.55 + (1 - 1 / q) * 0.4)
            fill(paint.withAlpha(0.14))
            stroke(paint)
            drawCircle(ford.circle)
        }
    }
}
