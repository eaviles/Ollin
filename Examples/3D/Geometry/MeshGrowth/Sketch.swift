import Ollin

/// Mesh growth: a surface that makes more of itself than it has room for.
///
/// The rule is one sentence long. Push the vertices of a mesh apart, faster in
/// some places than others, and keep the triangles a fixed size by splitting the
/// ones that stretch. The surface gains area; the area has nowhere to go; it
/// folds. Everything here comes from that, including the parts that look
/// designed.
///
/// Nothing pushes the surface outward, so it cannot answer new area by inflating
/// like a balloon. It folds every time. What `driver` changes is *where* it
/// folds and how big the folds are. **Even** grows everywhere at once and folds
/// uniformly all over, the brain-coral look, and is the baseline worth starting
/// from. **Curvature** grows what already bulges, so a bulge becomes a bigger
/// bulge and the form breaks into lobes. **Chemistry** runs a reaction-diffusion
/// pattern in the surface and grows where it collects: the pattern decides where
/// to grow and the growth gives the pattern more room to spread, which is the
/// branching coral. **Rim** grows only near the equator, the way a leaf grows at
/// its margin, and ruffles into a skirt.
///
/// `coarseness` is the triangle size, so it sets how fine the folds can be, and
/// it is where the cost lives. `detail` caps the vertex count: growth stops when
/// it is reached, so it decides how far the form develops before it settles.
@main
final class MeshGrowthDemo: Sketch {

    enum Rule: String, CaseIterable, ParamOption {
        case chemistry, curvature, rim, even
    }

    @Param(icon: "leaf") var driver = Rule.chemistry
    @Param(0.05 ... 0.16, icon: "triangle") var coarseness = 0.085
    @Param(2000 ... 14000, icon: "circle.grid.3x3") var detail = 9000.0
    @Param(icon: "sparkles") var polished = false

    private var growth: MeshGrowth?
    private var builtFor: (driver: Rule, coarseness: Double)?

    override func draw() {
        background(Color(hex: 0x0A0B10))
        environment(.courtyard.rotated(time * 0.05).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 34), radius: 4.2, elevation: 0.34)

        // Rebuilt only when a knob changes the form's whole history. Growth is
        // cumulative, so changing the rule halfway would leave a shape that is
        // neither one thing nor the other.
        if builtFor == nil || builtFor! != (driver, coarseness) {
            growth = makeGrowth()
            builtFor = (driver, coarseness)
        }
        guard let growth else { return }

        growth.maxVertices = Int(detail)
        // A few steps a frame: enough to watch it develop, slow enough to see it
        // happen rather than arriving at the answer.
        growth.step(2)

        fill(polished ? Color(hex: 0xE7EBF2) : Color(hex: 0xE2603A))
        material(polished ? .metal(roughness: 0.22) : .dielectric(roughness: 0.45))
        castShadows()
        drawMesh(growth.mesh)

        drawStatus("\(growth.vertexCount) vertices, step \(growth.stepCount)")
        drawCaption("Mesh growth: a surface folding because it is making more area than it has room for")
    }

    private func makeGrowth() -> MeshGrowth {
        let seedMesh = Mesh.icosphere(radius: 0.75, subdivisions: 3)
        switch driver {
        case .chemistry:
            let growth = MeshGrowth(mesh: seedMesh, driver: .chemical(.coral),
                                    edgeLength: coarseness, seed: UInt64(variation))
            // The chemistry's pattern covers only part of the surface where the
            // other drivers push everywhere, so it earns a faster rate; the
            // settle hands it a formed pattern to grow from on the first step.
            growth.growthAmount = 0.85
            growth.settleSteps = 60
            return growth

        case .curvature:
            return MeshGrowth(mesh: seedMesh, driver: .curvature,
                              edgeLength: coarseness, seed: UInt64(variation))

        case .rim:
            // Grow only near the equator. The band is soft-edged so the folds
            // start gradually instead of tearing away from a hard line.
            let growth = MeshGrowth(mesh: seedMesh,
                                    driver: .field { position, _ in
                                        1 - smoothstep(0.05, 0.45, abs(position.y))
                                    },
                                    edgeLength: coarseness, seed: UInt64(variation))
            growth.growthAmount = 0.9
            return growth

        case .even:
            return MeshGrowth(mesh: seedMesh, driver: .uniform,
                              edgeLength: coarseness, seed: UInt64(variation))
        }
    }
}
