import Ollin

/// Schottky groups, toured across their parameter space.
///
/// Four circles, paired off in touching pairs. Each pairing turns the plane
/// outside one circle into the inside of its partner, so applying the pairings
/// in every order nests circles inside circles forever, and the lace they leave
/// behind is the whole group drawn at once.
///
/// Because each pair *touches*, its generator holds the tangency point fixed
/// and barely contracts near it, which is what keeps the picture full. Leaning
/// the pairs about those points swings the family through its parameter space
/// without ever giving that up: the round limit set opens into swept arcs
/// gathering on two cusps, then closes again. Click or press a key to hold a
/// frame still.
@main
final class Schottky: Sketch {
    override var loopDuration: Double? { 20 }

    private let paper = Color(hex: 0xF3F0E7)
    private let ink = Color(hex: 0xA83C51)
    private var running = true
    private var held = 0.0

    override func draw() {
        background(paper)

        let phase = running ? pingPong(over: 20) : held
        held = phase
        let lean = (phase * 2 - 1) * 0.95

        let pairings = schottkyCuspedPairs(in: canvasRectangle, lean: lean)
        let circles = schottkyCircles(pairing: pairings, minRadius: 0.4, maxDepth: 90)

        // The limit set is what the eye follows, so frame on that rather than on
        // the pairing circles, which swing far wider as the pairs lean. A coarse
        // walk is plenty for a bounding box.
        let frame = fit(from: bounds(of: schottkyLimitSet(pairing: pairings, minRadius: 8)),
                        into: canvasRectangle.inset(by: 70))

        noFill()
        stroke(ink.withAlpha(0.45))
        strokeWeight(0.7)
        drawCircles(circles.map(frame))

        drawCaption("lean \(String(format: "%+.2f", lean)), \(circles.count) circles"
                    + (running ? "" : ", held"))
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
}
