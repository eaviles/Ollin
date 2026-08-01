import Ollin

/// A Schottky group's circle orbit, toured around the Apollonian gasket.
///
/// Two complex traces pick a Möbius group, the same recipe behind
/// `kleinianLimitSet`, and the orbit walk draws that group as circles nesting
/// inside circles forever. At traces `(2, 2)` the four pairing discs are
/// mutually tangent and the orbit is the classic gasket packing: a disc laced
/// full of tangent circles, empty pockets where the fundamental domain shows
/// through, and fans crowding into every cusp.
///
/// The loop walks a small arc in trace space, out from the gasket and back:
/// pulling the real part above 2 loosens the packing, and bending the traces
/// complex twists it. Click or press a key to hold a frame still.
@main
final class Schottky: Sketch {
    override var loopDuration: Double? { 24 }

    private let paper = Color(hex: 0xF3F0E7)
    private let ink = Color(hex: 0xA83C51)
    private var running = true
    private var held = 0.0

    override func draw() {
        background(paper)

        let phase = running ? pingPong(over: 24) : held
        held = phase
        let arc = phase * .pi
        let traces = Vector2(2 + 0.10 * (1 + cos(arc)) / 2, 0.07 * sin(arc))

        let box = canvasRectangle
        let circles = schottkyCircles(ta: traces, tb: traces, in: box,
                                      minRadius: 0.4, maxDepth: 150)

        // Frame on the packing itself (the limit set's span), not on the
        // pairing circles, which reach far outside it; and turn the picture a
        // quarter turn so the parabolic fans sit left and right, the way
        // these figures are usually shown.
        let frame = fit(from: bounds(of: schottkyLimitSet(ta: traces, tb: traces,
                                                          in: box, minRadius: 6)),
                        into: box.inset(by: 56))

        noFill()
        stroke(ink.withAlpha(0.45))
        strokeWeight(0.65)
        drawCircles(circles.map { turned(frame($0), about: box.center) })

        drawCaption("traces \(String(format: "%.3f %+.3fi", traces.x, traces.y)), "
                    + "\(circles.count) circles" + (running ? "" : ", held"))
    }

    override func mousePressed() { running.toggle() }
    override func keyPressed() { running.toggle() }

    private func bounds(of points: [Vector2]) -> Rectangle {
        guard let first = points.first else { return canvasRectangle }
        var minimum = first, maximum = first
        for point in points.dropFirst() {
            minimum = Vector2(min(minimum.x, point.x), min(minimum.y, point.y))
            maximum = Vector2(max(maximum.x, point.x), max(maximum.y, point.y))
        }
        return Rectangle(corner: minimum, width: max(maximum.x - minimum.x, 1e-6),
                         height: max(maximum.y - minimum.y, 1e-6))
    }

    /// A similarity carrying `source` into `target`, applied to the circles
    /// themselves rather than through `scale()`, which would thin the stroke
    /// along with the geometry.
    private func fit(from source: Rectangle, into target: Rectangle) -> (Circle) -> Circle {
        let factor = min(target.width / source.width, target.height / source.height)
        let from = source.center, to = target.center
        return { circle in
            Circle(center: to + (circle.center - from) * factor,
                   radius: circle.radius * factor)
        }
    }

    private func turned(_ circle: Circle, about pivot: Vector2) -> Circle {
        let d = circle.center - pivot
        return Circle(center: pivot + Vector2(-d.y, d.x), radius: circle.radius)
    }
}
