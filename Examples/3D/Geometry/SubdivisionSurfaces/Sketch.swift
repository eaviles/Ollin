import Ollin

/// Subdivision surfaces: a chunky low-poly cage refined into a smooth solid
/// with `mesh.subdivided(_:levels:)`.
///
/// Each level splits every face and eases every vertex toward its neighbors,
/// so the faceted cage converges to a soft limit form: the classic way to
/// model something organic out of a handful of boxes and extrusions. The
/// wireframe ghost is the original cage, so you can see how far the smooth
/// surface has melted away from it. `levels` walks the refinement (0 is the
/// cage itself); `scheme` swaps between the quad rules (the rounded-cube
/// look) and the triangle rules, which read the same cage through its
/// triangulation and land on a slightly different limit.
@main
final class SubdivisionSurfaces: Sketch {

    enum Rules: String, CaseIterable, ParamOption { case quads, triangles }

    @Param(0 ... 4, icon: "square.on.square.dashed") var levels = 2
    @Param(icon: "slider.horizontal.3") var scheme = Rules.quads
    @Param(icon: "cube.transparent") var showCage = true

    /// The three control cages: the classic cube, an extruded star, and a
    /// dodecahedron. Coarse on purpose; the interest is how little geometry a
    /// smooth form needs.
    private let cages: [(mesh: Mesh, color: Color)] = [
        (.box(size: 1.7), Color(hex: 0x53D1FF)),
        (.extrude(Profile.star(points: 5, outerRadius: 1.05, innerRadius: 0.48), depth: 0.62),
         Color(hex: 0xFFB13D)),
        (.dodecahedron(radius: 1.0), Color(hex: 0xFF7AB0)),
    ]

    /// Refined copies, rebuilt only when a knob changes; subdivision is cheap
    /// here, but there's no reason to redo it every frame.
    private var smoothed: [Mesh] = []
    private var builtFor: (levels: Int, scheme: Rules)? = nil

    override func draw() {
        background(Color(hex: 0x07090E))
        environment(.courtyard.rotated(time * 0.05).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 28), radius: 8.4, elevation: 0.32)

        if builtFor == nil || builtFor! != (levels, scheme) {
            let rules: SubdivisionScheme = scheme == .quads ? .catmullClark : .loop
            smoothed = cages.map { $0.mesh.subdivided(rules, levels: levels) }
            builtFor = (levels, scheme)
        }

        let spacing = 3.1
        let x0 = -spacing * Double(cages.count - 1) / 2
        for (i, cage) in cages.enumerated() {
            withState {
                translate(x0 + spacing * Double(i), 0, 0)
                rotateY(time * 0.22 + Double(i) * 0.8)
                rotateX(0.24)
                fill(cage.color)
                material(.dielectric(roughness: 0.34))
                drawMesh(smoothed[i])
                if showCage && levels > 0 {
                    wireframe()
                    stroke(cage.color.withAlpha(0.32))
                    strokeWeight(1.1)
                    drawMesh(cage.mesh)
                }
            }
        }

        drawCaption("Subdivision surfaces: a low-poly cage refined smooth; levels walks it")
    }
}
