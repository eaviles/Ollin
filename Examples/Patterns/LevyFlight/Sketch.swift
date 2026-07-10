import Ollin

/// A Lévy flight: scribble, scribble, *leap*.
///
/// `levyFlight` draws its step lengths from a heavy-tailed power law, so most
/// steps are tiny (the walk grinds away inside a little cluster) and a rare
/// few are enormous (it suddenly darts across the canvas and starts a new
/// cluster). That clustered-then-jumping rhythm is how foraging animals
/// search and how eyes scan a scene, and as a mark it reads instantly:
/// islands of dense texture strung together by long strokes.
///
/// The path is seeded and computed once, then scaled to fit the canvas (fit
/// the *points*, never `scale()`, which would fatten the stroke too). A
/// traveler retraces it out and back over the loop: watch it dwell inside a
/// cluster, then flash along a jump.
@main
final class LevyFlight: Sketch {
    private var path: [Vector2] = []

    override var loopDuration: Double? { 24 }

    override func setup() {
        seed(4)
        let raw = levyFlight(from: Vector2(0, 0), steps: 1400,
                             minStep: 4, maxStep: 420, exponent: 1.8)
        path = fit(raw, into: canvasRectangle.inset(by: 90))
    }

    override func draw() {
        background(Color(hex: 0x0E1116))

        // The whole journey, faint: the map the traveler moves over.
        noFill()
        stroke(Color(hex: 0x47536D))
        strokeWeight(1)
        drawPolyline(path)

        // The traveler: an index-space head (every step takes the same time,
        // so a long jump is a fast dart) trailing a fading comet tail.
        let head = pingPong(over: 24) * Double(path.count - 1)
        let trail = 90
        let headIndex = Int(head)
        stroke(Color(hex: 0x6FD3FF))
        for k in max(headIndex - trail, 1) ... max(headIndex, 1) {
            let age = Double(headIndex - k) / Double(trail)
            stroke(Color(hex: 0x6FD3FF).withAlpha((1 - age) * 0.9))
            strokeWeight(1 + (1 - age) * 2.2)
            drawLine(path[k - 1], path[k])
        }

        let tip = path[headIndex].lerp(to: path[min(headIndex + 1, path.count - 1)],
                                       head - Double(headIndex))
        noStroke()
        fill(Color(hex: 0x6FD3FF).withAlpha(0.35))
        drawCircle(center: tip, radius: 12 * scale)
        fill(.white)
        drawCircle(center: tip, radius: 4 * scale)

        drawCaption("power-law steps: mostly tiny, occasionally enormous")
    }

    /// Uniformly scale-and-center a path into a frame.
    private func fit(_ points: [Vector2], into frame: Rectangle) -> [Vector2] {
        guard let first = points.first else { return [] }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let spanX = max(maxX - minX, 1e-9), spanY = max(maxY - minY, 1e-9)
        let s = min(frame.width / spanX, frame.height / spanY)
        let offsetX = frame.x + (frame.width - spanX * s) / 2
        let offsetY = frame.y + (frame.height - spanY * s) / 2
        return points.map { Vector2(offsetX + ($0.x - minX) * s, offsetY + ($0.y - minY) * s) }
    }
}
