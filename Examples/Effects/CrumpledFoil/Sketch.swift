import Ollin

/// A whole canvas of crumpled holographic foil that breathes. The sheet is a
/// `FacetField` over a jittered lattice, triangulated once and lifted again
/// every frame by a crumple that drifts plus a slow wave rolling across it, so
/// the creases move. `.holographicFoil` takes that sheet: a stepped rainbow
/// runs across it and breaks at every crease (each facet shifts the bands by
/// its tilt), the creases light up or darken as the light turns, and the
/// facets that face the light hardest glint at their corners. The light drifts
/// around the sheet and the bands sweep across it on their own clocks.
///
/// The crease switch draws the sheet's creases in geometry over the filter's
/// fill: they land on the filter's own creases, since the GPU reads the same
/// facets the sketch holds, so a plotter gets the same sheet as lines.
@main
final class CrumpledFoil: Sketch {
    @Param("Crinkle", 0 ... 1.5, icon: "scribble") var crinkle = 0.7
    @Param("Spacing", 28 ... 120, icon: "square.grid.3x3") var spacing = 64.0
    @Param("Band angle", -3.14 ... 3.14, icon: "line.diagonal") var bandAngle = -0.6
    @Param("Band width", 12 ... 80, icon: "rectangle.split.3x1") var bandWidth = 36.0
    @Param("Light drift", 0 ... 1.5, icon: "sun.max") var lightDrift = 0.25
    @Param("Sweep", 0 ... 3, icon: "wind") var sweep = 0.7
    @Param("Creases in ink", icon: "pencil.line") var drawsCreases = false

    private var lattice: Delaunay?
    private var latticeSpacing = 0.0

    override func setup() {
        noiseSeed(7)
    }

    override func draw() {
        // The lattice once per spacing: the points and the triangles hold
        // still, and only the heights move.
        if lattice == nil || latticeSpacing != spacing {
            lattice = Delaunay(FacetField.latticePoints(in: canvasRectangle, spacing: spacing, seed: 7))
            latticeSpacing = spacing
        }
        guard let lattice else { return }

        let t = time
        let swing = crinkle * spacing
        let broad = spacing * 2.8, fine = spacing * 0.9
        let sheet = FacetField(lattice) { p in
            let low = signedNoise(p.x / broad, p.y / broad, t * 0.1)
            let high = signedNoise(p.x / fine + 31, p.y / fine + 17, t * 0.16)
            // A slow wave rolling across the sheet, so it breathes as one.
            let wave = sin(p.x / 170 + p.y / 260 - t * 0.8) * 0.4
            return swing * (1.1 * low + 0.45 * high + wave)
        }

        let foil = makeRenderTarget()
        withTarget(foil) { background(.white) }
        drawImage(foil.filtered(.holographicFoil(facets: sheet, bandWidth: bandWidth, bandAngle: bandAngle,
                                                 lightAngle: -2.2 + t * lightDrift,
                                                 phase: t * sweep)).image, 0, 0)

        if drawsCreases {
            noFill()
            stroke(Color(white: 0.08, alpha: 0.7))
            strokeWeight(1.2 * scale)
            for edge in sheet.edges { drawLine(edge) }
        }
    }
}
