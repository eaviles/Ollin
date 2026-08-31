import Ollin

/// The bright curve in the bottom of a cup.
///
/// Light crosses the cup, hits the far wall, and bounces. No single ray is the
/// bright line you see: the line is where the bounced rays *crowd*, each one
/// grazing past it and none of them being it. That curve is the envelope of the
/// whole family, and it is what a caustic is.
///
/// The source travels over the loop, from the middle of the cup out past its rim
/// and away. At the middle every ray comes straight back and there is no curve at
/// all. On the rim the curve is a cardioid, with one cusp. Far away the light
/// arrives nearly parallel, and the whole wall lit at once draws the two-cusped
/// nephroid on a coffee surface on a sunny morning.
///
/// Only the stretch of wall the light actually reaches is used, since the far side
/// of a circle is lit and the near side is not, and their two families of bounces
/// lean on different curves. Hold the mouse to put the source under the pointer.
///
/// The curve comes at two levels. `caustic(off:from:closed:)` builds it straight
/// from the wall and the source in one call, the bright stretch inside the cup;
/// the rays themselves are still built by hand with `reflectedRays`, since the
/// glow of individual bounces is the one layer the curve sugar cannot draw, and
/// `drawEnvelope` traces from those same rays, faintly, the whole mathematical
/// curve, which keeps running past the rim.
@main
final class Caustic_Example: Sketch {
    override var loopDuration: Double? { 14 }

    override func draw() {
        background(Color(hex: 0x0A0C12))

        let middle = bounds.center
        let radius = shortSide * 0.36
        let ring = (0 ..< 900).map { middle + Vector2(angle: Double($0) / 900 * .tau, length: radius) }

        let travel = (1 - cos(loopProgress(over: 14) * .tau)) / 2
        let source: LightSource = mouseIsPressed
            ? .point(mouse)
            : .point(middle + Vector2(angle: .pi * 0.82, length: radius * travel * 2.4))

        let wall = litArc(of: ring, from: source, around: middle)
        let whole = wall.count == ring.count

        noFill()
        stroke(Color(white: 0.26))
        strokeWeight(2)
        drawCircle(center: middle, radius: radius)

        // The lit stretch of wall, and the rays leaving it.
        stroke(Color(white: 0.5))
        strokeWeight(3)
        if !whole { drawPolyline(wall) }

        let rays = reflectedRays(off: wall, from: source, closed: whole)
        // Clipped to the cup, since what happens outside it is not the picture.
        withClip(Circle(center: middle, radius: radius)) {
            stroke(Color(hex: 0xFFD166, alpha: 0.16))
            strokeWeight(1)
            for (index, ray) in rays.enumerated() where index % 6 == 0 {
                drawLine(ray.origin, ray.origin + ray.direction.normalized * radius * 2)
            }
        }

        // The whole curve the rays in hand lean on, faint, wherever it runs.
        stroke(Color(hex: 0xFF7B54, alpha: 0.14))
        strokeWeight(1.5)
        drawEnvelope(of: rays, closed: whole)

        // The same curve in one call from the wall and the source, bright where
        // it crosses the cup.
        stroke(Color(hex: 0xFF7B54))
        strokeWeight(3)
        var drawn = 0
        for run in caustic(off: wall, from: source, closed: whole) {
            let inside = run.points.filter { $0.distance(to: middle) <= radius * 1.02 }
            guard inside.count >= 2 else { continue }
            drawPolyline(inside)
            drawn += inside.count
        }

        noStroke()
        fill(Color(hex: 0xFFF3C4))
        if case .point(let at) = source { drawCircle(center: at, radius: 6) }

        var reach = ""
        if case .point(let at) = source {
            let out = at.distance(to: middle) / radius
            if out < 0.03 { reach = "at the middle: every ray comes straight back" }
            else if out < 0.95 { reach = "inside the cup" }
            else if out < 1.06 { reach = "on the rim: a cardioid, with one cusp" }
            else { reach = "well outside, where the light arrives nearly parallel" }
        }
        drawCaption("\(drawn) points on the curve the rays lean on, \(reach)")
    }

    /// The stretch of wall the light reaches, kept as one unbroken run. A ray
    /// arrives at a lit point travelling away from the middle, since it crossed the
    /// cup to get there.
    private func litArc(of ring: [Vector2], from source: LightSource,
                        around middle: Vector2) -> [Vector2] {
        let lit = ring.map { source.direction(reaching: $0).dot(middle - $0) < 0 }
        guard lit.contains(false) else { return ring }
        guard let start = lit.indices.first(where: {
            lit[$0] && !lit[($0 + lit.count - 1) % lit.count]
        }) else { return [] }
        var out: [Vector2] = []
        var at = start
        while lit[at] {
            out.append(ring[at])
            at = (at + 1) % ring.count
            if at == start { break }
        }
        return out
    }
}
