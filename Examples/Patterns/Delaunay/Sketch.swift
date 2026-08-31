import Ollin

/// The triangle half of the tessellation pair: `delaunay(_:)` meshes a
/// drifting point set into the triangulation that keeps its triangles as
/// well-shaped as the points allow, stroked here as a live wireframe. (The
/// dual view of the same mesh is the Voronoi example, which carves one cell
/// per site instead.)
///
/// The second layer reads the mesh's adjacency back: `neighbors(of:)` names
/// the sites sharing a triangle edge with a chosen one, which are exactly the
/// sites whose Voronoi cells would border its cell. Move the mouse to choose
/// the site under it (a slow orbit stands in while the pointer is away): its
/// star of triangles glows, the shared edges light up as spokes, and the
/// neighbors brighten.
@main
final class Delaunay_Example: Sketch {
    private var sites: [Vector2] = []

    override func draw() {
        if sites.isEmpty {
            seed(9)
            let scattered = (0..<110).map { _ in randomVector(in: canvasRectangle) }
            sites = lloyd(scattered, iterations: 4)
        }

        background(Color(white: 0.06))

        // Drift each site on a slow, bounded noise flow.
        let live = sites.map { s -> Vector2 in
            let dx = signedNoise(s.x * 0.0015, s.y * 0.0015, time * 0.12)
            let dy = signedNoise(s.y * 0.0015, s.x * 0.0015, time * 0.12 + 17)
            return s + Vector2(dx, dy) * 30
        }

        let mesh = delaunay(live)

        // The chosen site: the one nearest the pointer, or a slow orbit.
        let probe: Vector2 = canvasRectangle.contains(mouse)
            ? mouse
            : center + Vector2(angle: time * 0.21, length: shortSide * 0.27)
        guard let chosen = live.indices.min(by: {
            live[$0].distanceSquared(to: probe) < live[$1].distanceSquared(to: probe)
        }) else { return }

        // Its star of triangles, glowing under the mesh.
        noStroke()
        fill(Color(hex: 0xF2C14E, alpha: 0.12))
        var k = 0
        while k + 2 < mesh.indices.count {
            let (a, b, c) = (mesh.indices[k], mesh.indices[k + 1], mesh.indices[k + 2])
            if a == chosen || b == chosen || c == chosen {
                drawShape(Shape([live[a], live[b], live[c]]))
            }
            k += 3
        }

        // The whole triangulation, stroked.
        noFill()
        stroke(Color(white: 0.34))
        strokeWeight(1.2 * scale)
        for triangle in mesh.triangles { drawShape(triangle.shape) }

        // The neighbor spokes: one shared triangle edge per neighbor.
        let ring = mesh.neighbors(of: chosen)
        stroke(Color(hex: 0xF2C14E))
        strokeWeight(2.5 * scale)
        for j in ring { drawLine(live[chosen], live[j]) }

        noStroke()
        fill(Color(white: 0.85, alpha: 0.5))
        drawPoints(live, size: 4 * scale)
        fill(Color(hex: 0xF2C14E))
        drawPoints(ring.map { live[$0] }, size: 7 * scale)
        fill(Color(hex: 0xFF7B54))
        drawCircle(center: live[chosen], radius: 6 * scale)

        drawCaption("\(ring.count) Delaunay neighbors, the sites whose Voronoi cells would border the marked one")
    }
}
