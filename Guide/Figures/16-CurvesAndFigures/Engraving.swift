// figure: frame=0
//
// Guide payoff (Chapter 16): an engraved plate in two inks, every line of it
// a figure from a rule. A guilloche rosette braids at the center with a
// spirograph turning in its eye, a spirolateral knot holds each corner, the
// frame's corners ease in along clothoids, and a ribbon threaded by Hobby's
// spline waves under the rosette. None of it reads `random` or `noise`, so
// the plate renders the same every time with no seed to pin.
import Ollin

final class Engraving: Sketch {
    let paper = Color(hex: 0xF2ECDD)
    let green = Color(hex: 0x1F4A3C)
    let red = Color(hex: 0xA3402B)
    let middle = Vector2(540, 470)

    var frames: [[Vector2]] = []
    var knots: [[Vector2]] = []
    var eye: [Vector2] = []

    override func setup() {
        // Two frames, their corners eased in the way a road takes a turn.
        frames = []
        for (inset, radius) in [(60.0, 70.0), (78.0, 52.0)] {
            let edge = bounds.inset(by: .all(inset))
            let corners = [edge.topLeft, edge.topRight, edge.bottomRight, edge.bottomLeft]
            let route = clothoidCorners(corners, radius: radius, easement: radius * 0.8,
                                        closed: true)
            frames.append(route.contour(closed: true).points)
        }

        // A square knot of seven steps in each corner.
        let walk = spirolateral(order: 7).points
        knots = [Vector2(160, 160), Vector2(920, 160),
                 Vector2(160, 920), Vector2(920, 920)].map { spot in
            fitted(walk, in: Rectangle(center: spot, width: 116, height: 116))
        }

        // The spirograph for the rosette's eye, scaled to sit inside it.
        eye = hypotrochoid(ring: 84, wheel: 33, pen: 26).points.map { $0 * 0.93 }
    }

    override func draw() {
        background(paper)
        noFill()

        stroke(green)
        strokeWeight(2.4)
        drawPolyline(frames[0], closed: true)
        strokeWeight(1.2)
        drawPolyline(frames[1], closed: true)

        stroke(red)
        strokeWeight(1.8)
        for knot in knots { drawPolyline(knot, closed: true) }

        // The rosette: a coarse cam and a fine one, the braid crawling slowly.
        let rings = guilloche(rings: 40, innerRadius: 105, outerRadius: 300,
                              rosettes: [Rosette(bumps: 12, amplitude: 16, phase: time * 0.1),
                                         Rosette(bumps: 48, amplitude: 2.5)],
                              twist: .pi / 90 + sin(time * 0.2) * 0.01)
        stroke(green)
        strokeWeight(1)
        withState(at: middle) {
            for ring in rings { drawPolyline(ring.points, closed: true) }
        }

        stroke(red)
        strokeWeight(1.2)
        withState(at: middle, rotation: time * 0.05) {
            drawPolyline(eye, closed: true)
        }

        // The ribbon: six lines through the same six dots, spread apart in
        // the middle and drawn together at the ends.
        stroke(green)
        strokeWeight(1.3)
        let xs: [Double] = [250, 360, 470, 610, 730, 830]
        let ys: [Double] = [905, 872, 900, 878, 912, 886]
        for line in 0..<6 {
            let dots = xs.indices.map { i -> Vector2 in
                let along = Double(i) / Double(xs.count - 1)
                let spread = (Double(line) - 2.5) * 7 * (0.35 + 0.65 * sin(.pi * along))
                let wave = sin(time * 0.8 + Double(i) * 1.1) * 6
                return Vector2(xs[i], ys[i] + spread + wave)
            }
            drawCurve(dots, spline: .hobby)
        }
    }
}
