import Ollin

/// Standing things on a surface, and the shortcut that gets it wrong.
///
/// A globe wears a forest. `surfacePoints` picks the spots over the skin
/// itself, so a spot is as likely anywhere the surface has the same area, and
/// `alignment` turns each tree to stand along the normal it landed on.
///
/// `spread` is the comparison worth watching. `vertices` takes the shortcut of
/// picking from the mesh's vertex list, and the trees line up in the globe's own
/// rows, crowd toward the poles where the rings grow small, and land twice on
/// the same vertex: the reading says the closest pair is 0.000 apart. `plain`
/// picks over the surface, correctly, but with no regard for the trees already
/// placed, so it clumps and leaves clearings. `even` keeps them apart, and the
/// closest pair sits near the spacing the count deserves.
///
/// `stand` turns the alignment off, so every tree points the same way and the
/// globe reads as a pincushion.
@main
final class SurfaceScatter: Sketch {

    enum Spread: String, CaseIterable, ParamOption { case even, plain, vertices }

    @Param(120 ... 2400, icon: "tree") var count = 500
    @Param(icon: "slider.horizontal.3") var spread = Spread.even
    @Param(icon: "arrow.up.and.down") var stand = true
    @Param(icon: "circle.dotted") var showSpots = false

    /// The surface everything lands on. A globe is the honest test: its
    /// triangles are tiny at the poles and wide at the equator, so a scatter
    /// that reads the vertex list cannot help but crowd the top and bottom.
    private let globe = Mesh.sphere(radius: 1.8, segments: 48, rings: 24)
    private let tree = Mesh.cone(radius: 0.1, height: 0.24, segments: 12)

    private var placements: [MeshInstance] = []
    private var spots: [SurfaceSample] = []
    private var closest = 0.0
    private var builtFor: (count: Int, spread: Spread, stand: Bool)?

    override func draw() {
        background(Color(hex: 0x0B0D14))
        environment(.courtyard.rotated(time * 0.04).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 40), radius: 6.2, elevation: 0.5)

        if builtFor == nil || builtFor! != (count, spread, stand) {
            place()
            builtFor = (count, spread, stand)
        }

        castShadows()
        fill(Color(hex: 0x2E4A6B))
        material(.dielectric(roughness: 0.6))
        drawMesh(globe)

        fill(Color(hex: 0x7FD48A))
        material(.dielectric(roughness: 0.5))
        drawMesh(tree, instances: placements)

        if showSpots {
            noStroke()
            drawPointCloud(PointCloud(positions: spots.map(\.position),
                                      color: Color(hex: 0xFFC84A), size: 0.03))
        }

        let gap = String(format: "%.3f", closest)
        drawCaption("\(spread.rawValue) placement: \(placements.count) trees, closest pair \(gap)")
    }

    /// Pick the spots, then turn a tree to stand on each one.
    private func place() {
        seed(11)
        switch spread {
        case .even:
            spots = surfacePoints(on: globe, count: count)
        case .plain:
            spots = surfacePoints(on: globe, count: count, scatter: .random)
        case .vertices:
            // The shortcut: pick from the vertex list and take the normal
            // stored there. Every spot is a real point of the surface, and the
            // covering is still wrong.
            spots = (0 ..< count).map { _ in
                let i = Int(random(Double(globe.positions.count)))
                return SurfaceSample(position: globe.positions[i],
                                     normal: globe.normals[i],
                                     uv: .zero, triangle: 0,
                                     barycentric: Vector3(1, 0, 0))
            }
        }

        placements = spots.map { spot in
            // A cone is built about its middle, so lift it half its height to
            // put its base on the skin.
            let up = stand ? spot.normal : .unitY
            return MeshInstance(position: spot.position + up * 0.11,
                                rotation: stand ? spot.alignment(spin: random(.tau)) : .zero,
                                scale: 0.7 + random(0.5))
        }
        closest = closestPair(spots.map(\.position))
    }

    /// The distance between the two nearest spots, which is the number that
    /// separates an even covering from a clumped one.
    private func closestPair(_ points: [Vector3]) -> Double {
        var best = Double.infinity
        for i in points.indices {
            for j in (i + 1) ..< points.count {
                let d = (points[i] - points[j]).lengthSquared
                if d < best { best = d }
            }
        }
        return best.isFinite ? best.squareRoot() : 0
    }
}
