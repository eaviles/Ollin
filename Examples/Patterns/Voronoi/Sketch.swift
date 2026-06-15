import Ollin

/// Voronoi tessellation — the "stochastic crystallization" look. A field of
/// sites is partitioned into cells, each the region of the canvas closest to its
/// site. The sites drift on a slow noise flow so the crystal field breathes, and
/// the cursor is a live site too, so the cells crystallize around it as you move
/// the mouse.
///
/// Each cell is an ordinary convex `Shape`, so it fills, strokes, and would
/// export or hatch like anything drawn by hand:
///
/// ```swift
/// for cell in voronoi(sites).cells { fill(color); drawShape(cell) }
/// ```
///
/// The starting sites are evened out with a few rounds of Lloyd relaxation
/// (`lloyd`), which nudges each site to its cell's centroid for a calmer, more
/// organic spacing than raw random scatter.
@main
final class Voronoi_Example: Sketch {
    private var sites: [Vector2] = []

    override func draw() {
        if sites.isEmpty {
            seed(7)
            let scattered = (0..<150).map { _ in randomVector(in: canvasRectangle) }
            sites = lloyd(scattered, iterations: 6)
        }

        background(Color(white: 0.06))

        // Drift each site on a slow, bounded noise flow.
        var live = sites.map { s -> Vector2 in
            let dx = signedNoise(s.x * 0.0015, s.y * 0.0015, time * 0.12)
            let dy = signedNoise(s.y * 0.0015, s.x * 0.0015, time * 0.12 + 17)
            return s + Vector2(dx, dy) * 30
        }
        // A live site under the cursor, so cells crystallize around the mouse.
        let cursor = Vector2(mouseX, mouseY)
        if canvasRectangle.contains(cursor) { live.append(cursor) }

        // A focal point sweeping the field gives the colors a living radial flow.
        let focus = canvasRectangle.center
            + Vector2(cos(time * 0.3), sin(time * 0.4)) * (width * 0.32)
        let maxDistance = Vector2(width, height).length * 0.5

        for cell in voronoi(live).cells {
            guard let center = cell.contours.first?.points.centroid else { continue }
            let t = min(center.distance(to: focus) / maxDistance, 1)
            fill(Colormap.turbo.color(at: t))
            stroke(Color(white: 0.06)); strokeWeight(1.5 * scale)
            drawShape(cell)
        }

        // The sites themselves, as faint dots.
        noStroke(); fill(Color(white: 0.95, alpha: 0.45))
        drawPoints(live, size: 3 * scale)
    }
}
