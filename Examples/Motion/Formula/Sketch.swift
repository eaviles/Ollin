import Ollin

/// A parameter does not have to be a number. It can be a rule, typed as text and
/// worked out every frame: `drive($radius, "190 + sin(time * tau / 6) * 80")`.
///
/// The five parameters below are all driven that way, and the sketch prints the very
/// text that drives them under the ring, beside what each one holds right now.
/// `wobble` reads the sketch's own noise field, so `noiseSeed()` reproduces it.
/// `edge` is worked out from `radius`, which lands on the same frame, because a
/// parameter named by another is always set first.
///
/// A formula is a track like any other, so it travels in the same file
/// (`--automation`) and the same `loops` and `speed` shape it. See
/// Docs/Helpers/Formula.md.
@main
final class Formulas: Sketch {
    @Param(80...460) var radius = 200.0
    @Param(3...48) var count = 12
    @Param(0...360) var spin = 0.0
    @Param(-80...80) var wobble = 0.0
    @Param(2...40) var edge = 6.0
    @Param var filled = true

    /// The parameters in the order the listing shows them.
    static let shown = ["radius", "count", "spin", "wobble", "edge", "filled"]

    override func setup() {
        noiseSeed(11)
        drive($radius, "190 + sin(time * tau / 6) * 80")
        drive($count, "8 + round(sin(time * tau / 12) * 5)")
        drive($spin, "time * 24")
        drive($wobble, "signedNoise(time * 0.6) * 70")
        drive($edge, "radius / 22")
        drive($filled, "time % 6 < 3")
    }

    override func draw() {
        background(.white)
        drawRing()
        drawListing()
    }

    // MARK: The ring

    private func drawRing() {
        let center = Vector2(width / 2, 380)
        let ring = radius + wobble

        noFill()
        stroke(Color(white: 0.9))
        strokeWeight(1.5 * scale)
        drawCircle(center: center, radius: ring)

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * .tau + spin * .pi / 180
            let at = center + Vector2(angle: angle) * ring
            if filled {
                noStroke()
                fill(Color.coral)
            } else {
                noFill()
                stroke(Color(hex: 0x2E6BE6))
                strokeWeight(edge / 3)
            }
            drawCircle(center: at, radius: edge)
        }
    }

    // MARK: The listing

    /// Read the tracks back and print the text that drives each parameter, so the
    /// picture says what made it.
    private func drawListing() {
        var top = 800.0
        textSize(21 * scale)
        for name in Self.shown {
            guard let track = automation?.track(named: name),
                  let formula = track.formula else { continue }
            noStroke()
            fill(Color(white: 0.55))
            textAlign(.right, .middle)
            drawText(name, 250, top)

            fill(Color(white: 0.2))
            textAlign(.left, .middle)
            drawText(formula.source, 274, top)

            fill(Color(white: 0.6))
            textAlign(.right, .middle)
            drawText(reading(of: name), width - 140, top)
            top += 42
        }
    }

    /// What the parameter holds this frame, rounded to something readable.
    private func reading(of name: String) -> String {
        switch name {
        case "radius": return String(format: "%.1f", radius)
        case "count": return "\(count)"
        case "spin": return String(format: "%.1f", spin)
        case "wobble": return String(format: "%.2f", wobble)
        case "edge": return String(format: "%.2f", edge)
        case "filled": return filled ? "on" : "off"
        default: return ""
        }
    }
}
