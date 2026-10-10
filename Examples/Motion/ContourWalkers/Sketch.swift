import Ollin

/// Walkers that read the slope of a field: each one steps along the contour it
/// stands on, turned a little uphill, so it spirals in toward a peak, or
/// downhill into a hollow with `Climb` below zero.
///
/// The field is a `RadialBasis` surface fitted through nine pins whose heights
/// breathe slowly, refitted every frame (nine points are a tiny solve).
/// `gradient(at:)` gives each walker the way uphill, exactly, from the fitted
/// bumps' own derivatives, and the perpendicular to it runs along the contour.
/// The contour lines are `isolines` of the same field. Switch `Field` to noise
/// and the slope comes from `gradient(at:field:)` instead, the central
/// difference that works for any function a sketch writes.
///
/// A walker that reaches a peak or a hollow, where the slope runs out, or that
/// leaves the map starts again somewhere else.
@main
final class ContourWalkers: Sketch {
    enum Field: String, CaseIterable, ParamOption { case fitted, noise }

    @Param var field: Field = .fitted
    @Param("Climb", -0.4...0.4) var climb = 0.12
    @Param("Walkers", 50...800) var count = 420

    private let paper = Color(hex: 0x14161B)
    private let ink = Color(hex: 0x3A4150)
    private let colors = Ramp.shades(of: Color(hex: 0x3E8E9A), lightness: 0.35...0.95)

    private var pins: [Vector2] = []
    private var trails: [[Vector2]] = []
    private var surface: RadialBasis<Vector2, Double>?

    private var frame: Rectangle { canvasRectangle.inset(by: 70) }

    override func setup() {
        randomSeed(4)
        // Nine pins on a jittered three-by-three grid, so the hills and
        // hollows spread over the whole map.
        pins = (0 ..< 9).map { i in
            let cell = Vector2(Double(i % 3) + 0.5, Double(i / 3) + 0.5) / 3
            return Vector2(frame.x + frame.width * cell.x + random(-90, 90),
                           frame.y + frame.height * cell.y + random(-90, 90))
        }
        trails = (0 ..< 800).map { _ in [spot()] }
    }

    override func draw() {
        background(paper)
        let heights = pins.indices.map { i in 0.5 + 0.45 * sin(time * 0.25 + Double(i) * 1.7) }
        surface = RadialBasis(points: pins, values: heights)

        // The contour lines the walkers follow.
        noFill()
        stroke(ink)
        strokeWeight(1.2 * scale)
        let levels = Array(stride(from: -0.6, through: 1.6, by: 0.08))
        for group in isolines(at: levels, in: frame, resolution: 90, field: height) {
            for line in group { drawPolyline(line.points, closed: line.isClosed) }
        }

        // Each walker takes one step: along the contour, turned uphill by `climb`.
        let turn = climb * .pi / 2
        for i in 0 ..< count {
            var trail = trails[i]
            let p = trail.last!
            let slope = field == .fitted ? surface?.gradient(at: p) ?? .zero
                                         : gradient(at: p, field: height)
            if slope.length < 1e-5 || !frame.contains(p) || trail.count > 900 {
                trails[i] = [spot()]
                continue
            }
            let along = slope.perpendicular.normalized
            let up = slope.normalized
            trail.append(p + (along * cos(turn) + up * sin(turn)) * 2.2)
            if trail.count > 40 { trail.removeFirst(trail.count - 40) }
            trails[i] = trail

            stroke(colors.color(at: height(p)).withAlpha(0.9))
            strokeWeight(2.2 * scale)
            drawPolyline(trail)
        }

        // The pins the fitted surface passes through.
        if field == .fitted {
            stroke(Color(white: 0.9))
            strokeWeight(1.5 * scale)
            for pin in pins { drawCircle(center: pin, radius: 7) }
        }

        drawCaption(field == .fitted ? "a fitted surface, climbed by its exact gradient"
                                     : "a noise field, climbed by central differences")
    }

    /// The height at a point, in roughly 0...1, from whichever field is chosen.
    private func height(_ p: Vector2) -> Double {
        if field == .fitted { return surface?.value(at: p) ?? 0 }
        return fbm(p.x * 0.0028, p.y * 0.0028, time * 0.03, octaves: 3)
    }

    private func spot() -> Vector2 {
        Vector2(random(frame.x, frame.x + frame.width), random(frame.y, frame.y + frame.height))
    }
}
