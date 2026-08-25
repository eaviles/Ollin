import Ollin

/// The limit set of a ring of tangent circles, drawn as living dust.
///
/// Inversion in a circle turns the plane inside out around it; play a few
/// inversions against each other and every orbit condenses onto their limit
/// set, a lace of circles within circles. Here the mirrors are a ring of
/// mutually tangent circles plus one inner circle tangent to them all. The
/// dust resamples every frame, so the lace shimmers while holding its form.
/// Press a key (or click) to change how many circles make the ring.
@main
final class InversionFractal: Sketch {
    private var ringCount = 5

    override func draw() {
        background(Color(hex: 0x0D0F14))
        let center = center
        let ringRadius = width * 0.3

        // A ring of mutually tangent circles: neighbors at center distance
        // 2R·sin(π/N) touch when each radius is R·sin(π/N); the inner circle
        // fills the hole they leave.
        let radius = ringRadius * sin(.pi / Double(ringCount))
        var mirrors: [Circle] = (0 ..< ringCount).map { i in
            let angle = Double(i) / Double(ringCount) * .tau
            return Circle(center: Vector2(center.x + cos(angle) * ringRadius,
                                          center.y + sin(angle) * ringRadius),
                          radius: radius)
        }
        mirrors.append(Circle(center: center, radius: ringRadius - radius))

        noFill()
        stroke(Color(hex: 0x2A3242))
        strokeWeight(1)
        drawCircles(mirrors)

        fill(Color(hex: 0xE8C97D, alpha: 0.55))
        drawPoints(inversionLimitSet(of: mirrors, count: 26_000), size: 1.6)

        drawCaption("\(ringCount + 1) mirrors; click or press a key for a different ring")
    }

    override func mousePressed() { advance() }
    override func keyPressed() { advance() }

    private func advance() {
        ringCount = ringCount == 8 ? 3 : ringCount + 1
    }
}
