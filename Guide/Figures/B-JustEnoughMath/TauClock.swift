// figure: frame=0
//
// Guide diagram (Appendix B): angles as fractions of tau. One dial with the
// quarter-turn marks labeled and an accent arc showing a small angle, plus
// three mini dials for common fractions.
import Ollin

final class TauClock: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        // The big dial.
        let center = Vector2(280, 250)
        let radius = 160.0
        noFill()
        stroke(faint)
        strokeWeight(2.5)
        drawCircle(center: center, radius: radius)

        // Quarter-turn marks and labels. Angles run clockwise on screen
        // because y grows downward.
        let quarters: [(Double, String)] = [
            (0, "0"), (.tau / 4, "tau / 4"), (.tau / 2, "tau / 2"), (.tau * 3 / 4, "3 tau / 4"),
        ]
        for (angle, label) in quarters {
            let rim = center + Vector2(angle: angle, length: radius)
            let tickOut = center + Vector2(angle: angle, length: radius + 12)
            stroke(ink)
            strokeWeight(2.5)
            drawLine(rim, tickOut)
            noStroke()
            fill(ink)
            // The left label needs extra room so it clears its tick.
            let distance = angle == .tau / 2 ? radius + 56 : radius + 34
            let at = center + Vector2(angle: angle, length: distance)
            textAlign(.center, .middle)
            drawText(label, at.x, at.y)
        }

        // An accent wedge for one small angle, tau / 8.
        let small = Double.tau / 8
        stroke(accent)
        strokeWeight(3)
        drawLine(center, center + Vector2(angle: 0, length: radius))
        drawLine(center, center + Vector2(angle: small, length: radius))
        noFill()
        drawArc(center.x, center.y, 74, 74, start: 0, stop: small, mode: .open)
        arrowhead(on: center, radius: 74, at: small)
        noStroke()
        fill(accent)
        let wedgeLabel = center + Vector2(angle: small / 2, length: 108)
        textAlign(.left, .middle)
        drawText("tau / 8", wedgeLabel.x + 4, wedgeLabel.y)

        // A faint rim arrow showing which way angles grow.
        stroke(faint)
        strokeWeight(2.5)
        noFill()
        drawArc(center.x, center.y, radius - 26, radius - 26,
                start: .tau * 0.56, stop: .tau * 0.70, mode: .open)
        arrowhead(on: center, radius: radius - 26, at: .tau * 0.70, color: faint)

        // Three mini dials for common fractions of a turn.
        let minis: [(Double, String)] = [(.tau / 12, "tau / 12"), (.tau / 6, "tau / 6"), (.tau / 3, "tau / 3")]
        for (i, mini) in minis.enumerated() {
            let c = Vector2(690, 108 + Double(i) * 150)
            let r = 52.0
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawCircle(center: c, radius: r)
            stroke(faint)
            drawLine(c, c + Vector2(angle: 0, length: r))
            stroke(accent)
            strokeWeight(3)
            drawLine(c, c + Vector2(angle: mini.0, length: r))
            noStroke()
            fill(ink)
            textAlign(.left, .middle)
            drawText(mini.1, c.x + r + 22, c.y)
        }

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("a full turn is tau, so fractions of tau read as fractions of a turn",
                 width / 2, 468)
        drawText("y points down, so angles grow clockwise from 3 o'clock",
                 width / 2, 498)
    }

    func arrowhead(on center: Vector2, radius: Double, at angle: Double, color: Color? = nil) {
        let tip = center + Vector2(angle: angle, length: radius)
        let tangent = Vector2(angle: angle + .tau / 4, length: 1)
        stroke(color ?? accent)
        strokeWeight(3)
        for side in [-1.0, 1.0] {
            let wing = tip - tangent * 14 + Vector2(angle: angle, length: side * 7)
            drawLine(tip, wing)
        }
    }
}
