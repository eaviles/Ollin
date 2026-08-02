import Ollin

/// From points back to a surface, two ways.
///
/// A knot is sampled into a bare point cloud, and the cloud is turned back
/// into a mesh by both surfacing paths, side by side. On the left, the points
/// themselves. In the middle, `particleSurface`: every point becomes a small
/// ball and nearby balls melt together, which reads as clay pressed over the
/// points and asks nothing of them. On the right, `reconstructSurface`: the
/// original surface is rebuilt from the samples, and where the samples stop
/// (cut a notch to see it) the rebuilt surface honestly stops too instead of
/// guessing a cap.
///
/// `density` is how many samples the cloud keeps; watch the reconstruction
/// hold on to the form as the skin goes lumpy when samples get scarce.
/// `robustFit` swaps the reconstruction onto the robust blended fitting:
/// smoother at low density, and the notch's torn rim sheds its stray shreds.
@main
final class SurfaceFromPoints: Sketch {

    @Param(400 ... 8000, icon: "circle.dotted") var density = 3600.0
    @Param(1 ... 4, icon: "drop") var blend = 2.0
    @Param(icon: "scissors") var notch = false
    @Param(icon: "sparkles") var polished = false
    @Param(icon: "wand.and.stars") var robustFit = false

    private var cloud: [Vector3] = []
    private var skin = Mesh(positions: [], indices: [])
    private var rebuilt = Mesh(positions: [], indices: [])
    private var builtFor: (density: Double, blend: Double, notch: Bool, robust: Bool)?

    override func draw() {
        background(Color(hex: 0x0A0B10))
        environment(.courtyard.rotated(time * 0.05).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 36), radius: 5.6, elevation: 0.3)

        if builtFor == nil || builtFor! != (density, blend, notch, robustFit) {
            rebuild()
            builtFor = (density, blend, notch, robustFit)
        }

        withState {
            translate(-2.2, 0, 0)
            drawPointCloud(PointCloud(positions: cloud, color: Color(hex: 0xE8B24A), size: 0.028))
        }

        fill(polished ? Color(hex: 0xE7EBF2) : Color(hex: 0xE2603A))
        material(polished ? .metal(roughness: 0.25) : .dielectric(roughness: 0.45))
        castShadows()
        withState {
            drawMesh(skin)
        }
        withState {
            translate(2.2, 0, 0)
            drawMesh(rebuilt)
        }

        drawStatus("\(cloud.count) points, skin \(skin.positions.count)v, rebuilt \(rebuilt.positions.count)v")
        drawCaption("Surface from points: the samples, a blended skin, and the reconstructed surface")
    }

    private func rebuild() {
        let knot = Mesh.torusKnot(p: 2, q: 3, radius: 0.72, tube: 0.12,
                                  segments: 220, sides: 36)
        cloud = samplePoints(on: knot, count: Int(density))
        if notch {
            // Cut a wedge out of the samples: the reconstruction reports the
            // gap as an open hole, the skin as a dent.
            cloud.removeAll { $0.x > 0.25 && $0.z > 0.25 && $0.y > 0 }
        }
        skin = particleSurface(of: cloud, radius: 0.075, blend: blend, resolution: 88)
        rebuilt = reconstructSurface(of: cloud, resolution: 104,
                                     fitting: robustFit ? .robust : .planes,
                                     keepingLargestComponent: true)
    }

    /// Evenly spread samples over a mesh's surface: triangles picked by area,
    /// a uniform point inside each. Seeded through the sketch's own `random`,
    /// so a `variation` names a cloud exactly.
    private func samplePoints(on mesh: Mesh, count: Int) -> [Vector3] {
        var cumulative: [Double] = []
        cumulative.reserveCapacity(mesh.indices.count / 3)
        var total = 0.0
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[t])]
            let b = mesh.positions[Int(mesh.indices[t + 1])]
            let c = mesh.positions[Int(mesh.indices[t + 2])]
            total += (b - a).cross(c - a).length * 0.5
            cumulative.append(total)
            t += 3
        }
        guard total > 0 else { return [] }

        return (0 ..< count).map { _ in
            let pick = random(0, total)
            var lo = 0, hi = cumulative.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumulative[mid] < pick { lo = mid + 1 } else { hi = mid }
            }
            let a = mesh.positions[Int(mesh.indices[lo * 3])]
            let b = mesh.positions[Int(mesh.indices[lo * 3 + 1])]
            let c = mesh.positions[Int(mesh.indices[lo * 3 + 2])]
            var u = random(0, 1), v = random(0, 1)
            if u + v > 1 { u = 1 - u; v = 1 - v }
            return a + (b - a) * u + (c - a) * v
        }
    }
}
