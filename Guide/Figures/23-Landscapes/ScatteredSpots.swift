// figure: frame=0
//
// Guide figure (Chapter 23): where the copies go. The same globe three times,
// wearing the same number of trees, picked three ways: from the mesh's vertex
// list (which crowds the poles, where the rings are small, and doubles up),
// over the surface at random (which clumps and leaves clearings), and over the
// surface keeping their distance.
import Ollin

final class ScatteredSpots: Sketch {
    override var canvasSize: CanvasSize { .size(1000, 370) }

    let globe = Mesh.sphere(radius: 1, segments: 36, rings: 18)
    let tree = Mesh.cone(radius: 0.05, height: 0.16, segments: 8)

    let count = 240
    var fromVertices: [MeshInstance] = []
    var plain: [MeshInstance] = []
    var even: [MeshInstance] = []

    override func setup() {
        seed(4)
        fromVertices = stand(on: (0 ..< count).map { _ in
            let i = Int(random(Double(globe.positions.count)))
            return SurfaceSample(position: globe.positions[i], normal: globe.normals[i],
                                 uv: .zero, triangle: 0, barycentric: Vector3(1, 0, 0))
        })
        plain = stand(on: surfacePoints(on: globe, count: count, scatter: .random))
        even = stand(on: surfacePoints(on: globe, count: count))
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 1.9, 6.0), target: Vector3(0, 0.05, 0),
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        panel(at: -2.95, trees: fromVertices, label: "the vertex list")
        panel(at: 0, trees: plain, label: "over the surface")
        panel(at: 2.95, trees: even, label: "over it, evenly")
    }

    /// One globe wearing one of the three scatters.
    private func panel(at x: Double, trees: [MeshInstance], label text: String) {
        withState {
            translate(x, 0, 0)
            fill(Color(hex: 0x2E4A6B))
            material(.matte)
            drawMesh(globe)
            fill(Color(hex: 0x7FD48A))
            drawMesh(tree, instances: trees)
            label(text)
        }
    }

    /// A tree standing on each spot, lifted half its height so its base meets
    /// the skin, and spun so the field does not read as clones.
    private func stand(on spots: [SurfaceSample]) -> [MeshInstance] {
        spots.map {
            MeshInstance(position: $0.position + $0.normal * 0.075,
                         rotation: $0.alignment(spin: random(.tau)),
                         scale: 0.75 + random(0.5))
        }
    }

    private func label(_ text: String) {
        withBillboard(at: Vector3(0, -1.45, 0)) {
            noStroke()
            fill(.white)
            textSize(21)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
