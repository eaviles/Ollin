// figure: frame=90
//
// Guide diagram (Chapter 23): a field of pillars drawn as ONE instanced mesh
// call. Each copy carries its own position, height, and tint; the wave and the
// coloring live entirely in the per-copy placement list, and the mesh's
// vertices upload once.
import Ollin

final class InstancedField_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 540) }

    private let pillar = Mesh.box(width: 0.11, height: 1, depth: 0.11)
    private var seats: [(x: Double, z: Double, r: Double, a: Double)] = []

    override func setup() {
        seed(90_210)
        var r = 1.4
        while r < 9.5 {
            let count = Int(r * 50)
            for i in 0 ..< count {
                let a = Double(i) / Double(count) * .tau + random(-0.02, 0.02)
                let rr = r + random(-0.06, 0.06)
                seats.append((cos(a) * rr, sin(a) * rr, rr, a))
            }
            r += 0.22
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1016))
        camera(Camera3D(eye: Vector3(11, 7.5, 13), target: Vector3(0, 0.7, 0),
                        projection: .perspective(fieldOfView: .pi / 4.6)))
        ambientLight(Color(white: 0.14))
        directionalLight(Color(hue: 0.09, saturation: 0.22, brightness: 1.0),
                         direction: Vector3(-0.5, -0.85, -0.35), intensity: 1.0)
        directionalLight(Color(white: 0.5), direction: Vector3(0.55, 0.35, 0.5), intensity: 0.25)
        castShadows()

        withState {
            fill(Color(white: 0.78))
            specular(0.05)
            drawPlane(width: 26, depth: 26)
        }

        specular(0.25)
        shininess(36)

        let low = Color(hex: 0x27435F)
        let high = Color(hex: 0xF2B75C)
        var copies: [MeshInstance] = []
        copies.reserveCapacity(seats.count)
        for seat in seats {
            let crest = sin(seat.r * 1.15 - time * 1.6) * 0.5 + 0.5
            let swirl = sin(seat.a * 3 + time * 0.7) * 0.5 + 0.5
            let h = 0.25 + crest * (1.4 + swirl * 1.1)
            copies.append(MeshInstance(position: Vector3(seat.x, h / 2, seat.z),
                                       scale: Vector3(1, h, 1),
                                       color: Color.mix(low, high, t: (h - 0.25) / 2.5)))
        }
        drawMesh(pillar, instances: copies)
    }
}
