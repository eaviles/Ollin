import Ollin

/// Repeated insets read as topographic contour lines: a breathing blob is
/// offset inward over and over — `offset(by: -spacing, join: .round)` — until
/// the region pinches out, and each surviving ring is stroked. Where the blob
/// narrows, rings crowd together and vanish sooner, exactly like contour lines
/// climbing a steep slope. Pure line work, so it plots straight to a pen:
///
/// ```sh
/// swift run Example-Patterns-Topography --export-svg /tmp/topography.svg
/// ```
@main
final class Topography_Example: Sketch {
    private let ink = Color(red: 0.13, green: 0.2, blue: 0.32)

    override func draw() {
        background(Color(red: 0.96, green: 0.95, blue: 0.91))

        // A closed curve through points whose radii drift with noise — the
        // landform whose "elevation" the insets trace.
        let lobes = 10
        let baseRadius = shortSide * 0.36
        let rim = (0..<lobes).map { k in
            let a = 2 * Double.pi * Double(k) / Double(lobes)
            let wobble = noise(cos(a) + 2, sin(a) + 2, time * 0.18)
            let radius = baseRadius * (0.45 + 0.95 * wobble)
            return center + Vector2(angle: a) * radius
        }
        var ring = Shape(curveThrough: rim)

        noFill(); stroke(ink)
        let spacing = 13.0 * scale
        var level = 0
        while !ring.contours.isEmpty && level < 40 {
            strokeWeight((level == 0 ? 2.6 : 1.1) * scale)
            drawShape(ring)
            ring = ring.offset(by: -spacing, join: .round)
            level += 1
        }
    }
}
