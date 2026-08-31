import Ollin

/// Blue noise handed to the tessellator. `poissonDisk(radius:)` lays down
/// points no two closer than the radius (Bridson's dart-throwing), the
/// distribution that reads as *natural* coverage: plain random scatter
/// clusters and leaves holes, blue noise never does. The points are ordinary
/// `[Vector2]`, so they feed anything, and here they feed `voronoi(_:)`, which
/// carves the canvas into one convex cell per site.
///
/// The strikingly even cell sizes are the demonstration: random sites make a
/// diagram of slivers and sprawls, blue-noise sites make a calm foam with no
/// Lloyd relaxation needed. Each site is overlaid as a bright dot on its own
/// cell, so the spacing itself still reads.
///
/// The layout is computed once and held (it is a pure function of the seed,
/// so the same seed always lays the dots down the same way); the cells are
/// ordinary `Shape`s, ready for fill, stroke, the booleans, and SVG export.
@main
final class BlueNoise: Sketch {
    private var sites: [Vector2] = []
    private var cells: [Shape] = []

    override func draw() {
        if sites.isEmpty {
            seed(9)
            sites = poissonDisk(radius: 36 * scale)
            cells = voronoi(sites).cells
        }

        background(Color(hex: 0x11141C))

        // The cells: a quiet per-cell tint, seamed by background-colored
        // strokes so the near-equal areas read as a foam.
        let shallow = Color(hex: 0x1D2B3F)
        let deep = Color(hex: 0x33557E)
        stroke(Color(hex: 0x11141C))
        strokeWeight(2 * scale)
        for (site, cell) in zip(sites, cells) {
            let t = (signedNoise(site.x * 0.0018, site.y * 0.0018) + 1) * 0.5
            fill(Color.mix(shallow, deep, t))
            drawShape(cell)
        }

        // The sites themselves, one dot per cell: the even scatter beside the
        // even cells it produced.
        noStroke()
        fill(Color(hex: 0xE8ECF4))
        for site in sites {
            drawCircle(center: site, radius: 3 * scale)
        }
    }
}
