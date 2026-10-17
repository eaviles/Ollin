import Ollin

/// Two fingers on the trackpad. Pinch and the rose grows and shrinks with your
/// fingers (`size *= pinchScale`); turn them and it turns with them
/// (`spin += turnAngle`, then `rotate(spin)`). Both are this frame's change, so
/// the sketch keeps the totals itself, the way it keeps a position from
/// `mouse - previousMouse`.
///
/// The petal count is a dial that clicks. `fingersTurned()` fires once per
/// event with that event's own turn, and every fifteen degrees of it steps the
/// count, a notch at a time, with a tick drawn where it clicked. The rose is
/// one closed curve, r = cos(k * angle) for k = n / 3, drawn as a polyline
/// through enough points to stay smooth at any size.
///
/// The phone showing the sketch (`PhoneDevice.show`) sends its own two-finger
/// pinch and turn to the same two values. Press r to put everything back.
@main
final class PinchAndTurn: Sketch {
    /// The rose's radius, in canvas units.
    var size = 300.0
    /// The rose's turn, in radians.
    var spin = 0.0
    /// The petal numerator: the rose is r = cos(petals / 3 * angle).
    var petals = 7
    /// The turn gathered toward the next notch.
    var notch = 0.0
    /// When the last notch clicked, for the tick that fades after it.
    var clicked = -10.0
    /// Which way the last notch went.
    var clickedClockwise = true

    let step = Double.pi / 12
    let ground = Color(hex: 0x10141C)
    let ink = Color(hex: 0xF2E6C9)
    let accent = Color(hex: 0xE0785A)

    override func draw() {
        background(ground)
        size = min(max(size * pinchScale, 40 * scale), 900 * scale)
        spin += turnAngle

        let center = Vector2(width / 2, height / 2)
        withState {
            translate(center)
            rotate(spin)
            noFill()
            stroke(ink)
            strokeWeight(2.5 * scale)
            drawPolyline(rose(radius: size), closed: true)

            // The rose's own zero line, so the turn is easy to follow.
            stroke(accent)
            strokeWeight(3 * scale)
            drawLine(Vector2(size * 1.06, 0), Vector2(size * 1.2, 0))
        }

        drawDial(at: center)
        drawReadout()
    }

    /// One closed rose of radius `radius`: r = cos(k * angle), k = petals / 3,
    /// traced over the three turns that close it.
    func rose(radius: Double) -> [Vector2] {
        let k = Double(petals) / 3
        let count = 1440
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 3 * .tau
            return Vector2(angle: angle, length: radius * cos(k * angle))
        }
    }

    /// The notches around the rose, and a tick where the last one clicked.
    func drawDial(at center: Vector2) {
        let ring = min(width, height) * 0.46
        noFill()
        stroke(ink.withAlpha(0.18))
        strokeWeight(1.5 * scale)
        for i in 0..<24 {
            let angle = Double(i) * step
            drawLine(center + Vector2(angle: angle, length: ring),
                     center + Vector2(angle: angle, length: ring + 10 * scale))
        }
        let age = time - clicked
        guard age < 0.6 else { return }
        let fade = 1 - age / 0.6
        stroke(accent.withAlpha(fade))
        strokeWeight(4 * scale)
        let angle = spin.truncatingRemainder(dividingBy: .tau)
        drawLine(center + Vector2(angle: angle, length: ring - 6 * scale),
                 center + Vector2(angle: angle, length: ring + 18 * scale))
        noStroke()
        fill(accent.withAlpha(fade))
        textAlign(.center, .center)
        textSize(22 * scale)
        let label = center + Vector2(angle: angle, length: ring + 40 * scale)
        drawText(clickedClockwise ? "+1" : "-1", label.x, label.y)
    }

    func drawReadout() {
        fill(ink.withAlpha(0.75))
        noStroke()
        textAlign(.left, .top)
        textSize(18 * scale)
        let degrees = spin * 180 / .pi
        let lines = [
            "pinchScale \(format(pinchScale, 3))   size \(format(size / scale, 0))",
            "turnAngle \(format(turnAngle * 180 / .pi, 2))°   spin \(format(degrees, 1))°",
            "rose k = \(petals)/3",
        ]
        for (i, line) in lines.enumerated() {
            drawText(line, 28 * scale, (28 + Double(i) * 26) * scale)
        }
        drawCaption("PinchAndTurn: pinch to size it, turn two fingers to spin it and click the dial")
    }

    override func fingersTurned() {
        notch += turnAngle
        while notch >= step {
            notch -= step
            petals = min(petals + 1, 24)
            clicked = time
            clickedClockwise = true
        }
        while notch <= -step {
            notch += step
            petals = max(petals - 1, 1)
            clicked = time
            clickedClockwise = false
        }
    }

    override func keyPressed() {
        guard key == "r" else { return }
        size = 300 * scale
        spin = 0
        petals = 7
        notch = 0
    }

    override func setup() {
        size = 300 * scale
    }

    func format(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }
}
