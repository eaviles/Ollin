import Foundation
import Ollin

/// Normalized coordinates: `uv(u, v)` maps the 0…1 square onto the canvas.
/// `uv(0, 0)` is the top-left corner, `uv(1, 1)` the bottom-right, and
/// `uv(0.5, 0.5)` the center, so a composition is stated as proportions and
/// never reads `width` or `height`. Everything in this scene is placed that
/// way: a sun arcing across the sky, mountains on the lower third, stars
/// scattered in normalized space. `Rectangle.point(u:v:)` is the same idea
/// for any rectangle, with `uv(of:)` as its inverse.
@main
final class NormalizedCoordinates: Sketch {
    override var loopDuration: Double? { 8 }
    private var stars: [Vector2] = []

    override func setup() {
        seed(7)
        stars = (0 ..< 70).map { _ in uv(random(), random(0.6)) }
    }

    override func draw() {
        let t = loopProgress(over: 8)     // the sun's sweep, left to right
        let daylight = sin(t * .pi)       // 0 at both horizons, 1 at noon

        // The sky brightens with the sun's height.
        background(Color.mix(Color(hex: 0x0B1526), Color(hex: 0x8EC9E8), daylight))
        noStroke()

        // Stars hold their normalized places and fade out by day.
        fill(Color(white: 1, alpha: 0.8 * (1 - daylight)))
        for star in stars { drawCircle(star.x, star.y, 3 * scale) }

        // The sun rises from uv(0, 0.62), peaks at uv(0.5, 0.2), and sets.
        let sun = uv(t, 0.62 - 0.42 * daylight)
        fill(Color.mix(Color(hex: 0xFF7043), Color(hex: 0xFFD166), daylight))
        drawCircle(center: sun, radius: 42 * scale)

        // Mountains and ground: polygons whose corners are plain proportions.
        fill(Color(hex: 0x1D3A52))
        drawPolygon([uv(-0.05, 0.66), uv(0.28, 0.34), uv(0.58, 0.66)])
        fill(Color(hex: 0x16304A))
        drawPolygon([uv(0.42, 0.66), uv(0.72, 0.42), uv(1.05, 0.66)])
        fill(Color(hex: 0x102338))
        drawPolygon([uv(0, 0.66), uv(1, 0.66), uv(1, 1), uv(0, 1)])
    }
}
