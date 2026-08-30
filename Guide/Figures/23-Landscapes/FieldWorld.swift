// figure: frame=120 unstable
//
// Marked unstable for the reason the GPU sims are: the cull pass compacts the
// surviving copies with atomics, so their draw order is decided by the GPU and
// varies between runs. The seed is pinned and the world is identical; what
// moves is which of two overlapping solids wins a tie, and it stays inside
// three counts of 255 over about 0.02% of the frame.
// Guide diagram (Chapter 23): a quarter of a million solids in a retained
// MeshField, drawn with one call and GPU-culled per copy under a low flying
// camera, the horizon closed by fog.
import Ollin

final class FieldWorld_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 540) }

    private let field = MeshField()

    override func setup() {
        seed(4_242)
        let reach = 280.0
        func scatter(_ count: Int, make: (Double, Double) -> MeshInstance) -> [MeshInstance] {
            var copies: [MeshInstance] = []
            copies.reserveCapacity(count)
            for _ in 0 ..< count {
                copies.append(make(random(-reach, reach), random(-reach, reach)))
            }
            return copies
        }
        let stoneGray = Color(hue: 0.08, saturation: 0.08, brightness: 0.62)
        let mossGreen = Color(hue: 0.32, saturation: 0.45, brightness: 0.5)
        let pineGreen = Color(hue: 0.36, saturation: 0.55, brightness: 0.42)
        field.place(Mesh.box(width: 0.5, height: 0.35, depth: 0.5),
                    at: scatter(90_000) { x, z in
            MeshInstance(position: Vector3(x, 0.17, z),
                         rotation: Vector3(0, random(.tau), 0),
                         scale: random(0.5, 1.6),
                         color: Color.mix(stoneGray, mossGreen, random(0.5)))
        })
        field.place(Mesh.sphere(radius: 0.3, segments: 10, rings: 6),
                    at: scatter(80_000) { x, z in
            MeshInstance(position: Vector3(x, 0.24, z),
                         scale: Vector3(random(0.7, 1.4), random(0.5, 0.9), random(0.7, 1.4)),
                         color: Color.mix(mossGreen, pineGreen, random(1)))
        })
        field.place(Mesh.cone(radius: 0.55, height: 2.2, segments: 10),
                    at: scatter(50_000) { x, z in
            MeshInstance(position: Vector3(x, 1.1, z),
                         scale: Vector3(1, random(0.7, 1.8), 1),
                         color: Color.mix(pineGreen, mossGreen, random(0.6)))
        })
        field.place(Mesh.sphere(radius: 0.7, segments: 12, rings: 8),
                    at: scatter(15_000) { x, z in
            MeshInstance(position: Vector3(x, 0.45, z),
                         scale: Vector3(random(0.8, 1.6), random(0.6, 1.1), random(0.8, 1.6)),
                         color: stoneGray)
        })
        field.place(Mesh.box(width: 0.45, height: 3.2, depth: 0.3),
                    at: scatter(5_000) { x, z in
            MeshInstance(position: Vector3(x, 1.6, z),
                         rotation: Vector3(random(-0.05, 0.05), random(.tau), random(-0.05, 0.05)),
                         scale: random(0.7, 1.3),
                         color: Color.mix(stoneGray, Color(white: 0.7), random(0.5)))
        })
    }

    override func draw() {
        background(Color(hex: 0x0D1017))
        let t = time * 0.05
        let eye = Vector3(cos(t * .tau) * 130, 4.2, sin(t * .tau) * 130)
        let ahead = Vector3(cos(t * .tau + 0.12) * 128, 1.4, sin(t * .tau + 0.12) * 128)
        camera(Camera3D(eye: eye, target: ahead, far: 110))
        ambientLight(Color(white: 0.16))
        directionalLight(Color(hue: 0.09, saturation: 0.2, brightness: 1.0),
                         direction: Vector3(-0.45, -0.8, -0.4), intensity: 1.0)
        directionalLight(Color(white: 0.45), direction: Vector3(0.5, 0.35, 0.55), intensity: 0.25)
        castShadows()
        fog(Color(hex: 0x0D1017), density: 0.042)
        withState {
            fill(Color(hue: 0.3, saturation: 0.2, brightness: 0.32))
            specular(0.03)
            drawPlane(width: 580, depth: 580)
        }
        specular(0.12)
        shininess(24)
        drawMeshField(field)
    }
}
