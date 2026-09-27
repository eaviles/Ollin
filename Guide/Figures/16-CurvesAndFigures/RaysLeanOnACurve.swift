// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the envelope of a family of lines. On the left the
// tangents of a circle, which lean on that circle and give it back. On the right
// the rays bounced off the far wall of a cup, crowding onto the caustic.
import Ollin
import OllinDiagram

final class RaysLeanOnACurve: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    let accent = Color(hex: 0xE07A5F)
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 64, y: 66, width: 320, height: 250)
        let right = Rectangle(x: 496, y: 66, width: 320, height: 250)

        tangents(in: left)
        cup(in: right)

        frame(left, title: "tangents of a circle")
        frame(right, title: "light bounced off a cup")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("a family of lines leans on a curve none of them is", width / 2, 352)
        textSize(17)
        fill(darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63))
        drawText("the curve runs through the crossings of neighbors, which is how it is found",
                 width / 2, 386)
    }

    /// The self-check: tangents of a circle give the circle back.
    func tangents(in box: Rectangle) {
        let center = box.center
        let radius = 82.0
        let rays = (0 ..< 40).map { i -> Ray2 in
            let angle = Double(i) / 40 * .tau
            return Ray2(origin: center + Vector2(angle: angle, length: radius),
                        direction: Vector2(angle: angle + .pi / 2))
        }
        withClip(box) {
            stroke(Color(white: 0.62))
            strokeWeight(1)
            for ray in rays {
                drawLine(ray.origin - ray.direction * 200, ray.origin + ray.direction * 200)
            }
        }
        noFill()
        stroke(accent)
        strokeWeight(3)
        for run in envelope(of: rays, closed: true) { drawPolyline(run.points, closed: true) }
    }

    /// The cup: a point source, the lit far wall, and the caustic the bounces
    /// crowd onto.
    func cup(in box: Rectangle) {
        let center = box.center
        let radius = 108.0
        let source = LightSource.point(center + Vector2(-radius * 1.25, -radius * 0.35))
        let ring = (0 ..< 600).map { center + Vector2(angle: Double($0) / 600 * .tau, length: radius) }
        // The lit stretch has to be taken as one unbroken run. Filtering the ring
        // leaves the two ends of the arc next to each other in the array whenever
        // it wraps, and the lines between them are not rays at all.
        let lit = ring.map { source.direction(reaching: $0).dot(center - $0) < 0 }
        var wall: [Vector2] = []
        if let start = lit.indices.first(where: { lit[$0] && !lit[($0 + lit.count - 1) % lit.count] }) {
            var at = start
            while lit[at] {
                wall.append(ring[at])
                at = (at + 1) % ring.count
                if at == start { break }
            }
        }
        let rays = reflectedRays(off: wall, from: source)

        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: center, radius: radius)

        withClip(Circle(center: center, radius: radius)) {
            stroke(Color(white: 0.62))
            strokeWeight(1)
            for (index, ray) in rays.enumerated() where index % 9 == 0 {
                drawLine(ray.origin, ray.origin + ray.direction.normalized * radius * 2.2)
            }
        }

        stroke(accent)
        strokeWeight(3)
        for run in envelope(of: rays) {
            let inside = run.points.filter { $0.distance(to: center) <= radius }
            if inside.count >= 2 { drawPolyline(inside) }
        }

        noStroke()
        fill(ink)
        if case .point(let at) = source { drawCircle(center: at, radius: 5) }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
