// figure: frame=0
//
// Figure for Docs/Generators/SurfaceSampling.md (spherePoints): the same globe
// three times, wearing the same number of dots placed three ways. Rings of
// latitude and longitude crowd the pole, where the rings are short; points
// drawn at random clump and leave clearings; the lattice keeps every dot the
// same distance from its neighbors, the pole included. Each globe is tipped
// toward the camera so its pole is in view.
import Foundation
import Ollin

final class SphereLattice: Sketch {
    override var canvasSize: CanvasSize { .size(1000, 370) }

    let globe = Mesh.sphere(radius: 1, segments: 48, rings: 24)
    let dot = Mesh.icosphere(radius: 0.03, subdivisions: 1)

    let count = 400
    var rings: [MeshInstance] = []
    var scattered: [MeshInstance] = []
    var lattice: [MeshInstance] = []

    override func setup() {
        seed(4)
        // Sixteen rings of twenty-five: equal steps in both angles.
        var onRings: [Vector3] = []
        for i in 0 ..< 16 {
            let polar = (Double(i) + 0.5) / 16 * .pi
            for j in 0 ..< 25 {
                let around = Double(j) / 25 * .tau
                onRings.append(Vector3(sin(polar) * cos(around), cos(polar), sin(polar) * sin(around)))
            }
        }
        let atRandom: [Vector3] = (0 ..< count).map { _ in
            let y = random(-1, 1), around = random(.tau)
            let ring = (1 - y * y).squareRoot()
            return Vector3(cos(around) * ring, y, sin(around) * ring)
        }
        rings = dots(at: onRings)
        scattered = dots(at: atRandom)
        lattice = dots(at: spherePoints(count: count))
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.6, 6.4), target: Vector3(0, -0.12, 0),
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        panel(at: -2.95, dots: rings, label: "rings of latitude")
        panel(at: 0, dots: scattered, label: "at random")
        panel(at: 2.95, dots: lattice, label: "spherePoints")
    }

    private func panel(at x: Double, dots: [MeshInstance], label text: String) {
        withState {
            translate(x, 0, 0)
            fill(Color(hex: 0x2E4A6B))
            material(.matte)
            drawMesh(globe)
            fill(Color(hex: 0xFFD166))
            drawMesh(dot, instances: dots)
            withBillboard(at: Vector3(0, -1.42, 0)) {
                noStroke()
                fill(.white)
                textSize(21)
                textAlign(.center, .middle)
                drawText(text, 0, 0)
            }
        }
    }

    /// A dot on each point, the globe tipped so its pole leans to the camera.
    private func dots(at points: [Vector3]) -> [MeshInstance] {
        let tip = 0.95
        return points.map { p in
            MeshInstance(position: Vector3(p.x, p.y * cos(tip) - p.z * sin(tip), p.y * sin(tip) + p.z * cos(tip)),
                         scale: 1)
        }
    }
}
