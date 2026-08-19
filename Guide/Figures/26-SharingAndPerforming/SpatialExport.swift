// figure: frame=0
//
// Guide listing (Chapter 26): what a spatial export keeps. The left arrangement
// is drawn the ordinary way, with dust hanging around it. The right one is the
// same arrangement after a real round trip: written to a .usdz, opened again
// with Scene(contentsOf:), and drawn back. The surfaces are identical, and the
// dust is gone, because a point cloud is not a surface and a model file holds
// surfaces. The counts in the labels are read from the reopened scene rather
// than typed, so they cannot drift from what the writer actually wrote.
import Foundation
import Ollin

final class SpatialExport: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    /// Where each copy stands, in world units either side of the middle.
    private let offset = 1.9

    /// The reopened model, and how many surfaces came back in it.
    private var reopened: Scene?
    private var meshCount = 0

    override func setup() {
        let scene = Scene(nodes: arrangement())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-guide-spatial.usdz")
        guard scene.write(to: url) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        reopened = Scene(contentsOf: url)
        meshCount = reopened.map(count) ?? 0
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        perspective(eye: Vector3(0, 1.9, 4.4), target: Vector3(0, 0.05, 0))

        // Both copies take their color from the meshes themselves, so the two
        // halves are shaded by exactly the same rules.
        fill(.white)

        withState {
            translate(-offset, 0, 0)
            for node in arrangement() {
                withState {
                    translate(node.position)
                    if let mesh = node.mesh { drawMesh(mesh) }
                }
            }
        }
        motes(around: -offset)

        if let reopened {
            withState {
                translate(offset, 0, 0)
                drawScene(reopened)
            }
        }

        label("drawn", detail: "\(meshCount) surfaces and some dust", at: -offset)
        label("written, then opened again",
              detail: "\(meshCount) surfaces; the dust is not one", at: offset)
    }

    /// The arrangement itself: a few solids, each carrying its own color.
    private func arrangement() -> [SceneNode] {
        let shapes: [(Mesh, Vector3, Color)] = [
            (.icosphere(radius: 0.42, subdivisions: 3), Vector3(-0.75, 0, 0.1),
             Color(hex: 0xE0A33C)),
            (.roundedBox(size: 0.7, radius: 0.15), Vector3(0.05, 0.02, -0.35),
             Color(hex: 0x4E86C6)),
            (.torus(radius: 0.36, tube: 0.13), Vector3(0.8, -0.1, 0.2),
             Color(hex: 0x59A66B)),
        ]
        return shapes.map { shape, place, color in
            var mesh = shape
            mesh.material = MeshMaterial(baseColor: color)
            var node = SceneNode(name: "piece", position: place)
            node.mesh = mesh
            return node
        }
    }

    /// Dust around one copy: a point cloud, which has no surface to write.
    private func motes(around x: Double) {
        var points: [PointCloud.Point] = []
        for i in 0 ..< 260 {
            let a = Double(i) * 2.399
            let r = 0.9 + fract(Double(i) * 0.618) * 0.85
            points.append(.init(position: Vector3(x + cos(a) * r,
                                                  sin(Double(i) * 0.41) * 0.75,
                                                  sin(a) * r * 0.6),
                                color: Color(hex: 0x8A8577), size: 0.022))
        }
        drawPointCloud(PointCloud(points: points))
    }

    /// Every mesh in a scene, however deep the tree goes.
    private func count(_ scene: Scene) -> Int {
        func walk(_ nodes: [SceneNode]) -> Int {
            nodes.reduce(0) { $0 + ($1.mesh == nil ? 0 : 1) + walk($1.children) }
        }
        return walk(scene.nodes)
    }

    private func label(_ title: String, detail: String, at side: Double) {
        guard let anchor = project(Vector3(side, 0, 0)) else { return }
        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textAlign(.center, .top)

            textSize(21)
            fill(Color(hex: 0x2B2B2B))
            drawText(title, anchor.x, height * 0.80)

            textSize(16)
            fill(Color(hex: 0x6B6459))
            drawText(detail, anchor.x, height * 0.875)
        }
    }
}
