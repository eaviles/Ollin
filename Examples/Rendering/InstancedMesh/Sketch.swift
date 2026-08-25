import Ollin

/// A field of 12,000 pillars from ONE mesh and ONE draw call. Each copy is a
/// `MeshInstance`: a position, a rotation, a scale, and a tint. The mesh's
/// vertices upload once; the GPU places every copy, so the whole field costs
/// about what a single box costs the CPU. The pillars ride a traveling wave
/// (the instance list is rebuilt each frame, which is just 12,000 small
/// structs), they shade like any solid mesh, and they drop real shadows onto
/// the floor.
///
/// Flip the **instanced** knob off to draw the same field the ordinary way,
/// one `drawMesh` per pillar, and watch the frame time in the inspector: that
/// gap is the per-copy CPU cost instancing removes.
@main
final class InstancedMesh: Sketch {

    @Param var instanced = true   // off = one drawMesh call per pillar

    private let pillar = Mesh.box(width: 0.11, height: 1, depth: 0.11)
    private var seats: [(position: Vector3, radius: Double, angle: Double)] = []

    override func setup() {
        seed(90_210)
        // A polar field: rings of seats from the center out, jittered a little
        // so the grid reads organic. Built once; only heights change per frame.
        var r = 1.4
        while r < 10.5 {
            let count = Int(r * 50)
            for i in 0 ..< count {
                let a = Double(i) / Double(count) * .tau + random(-0.02, 0.02)
                let rr = r + random(-0.06, 0.06)
                seats.append((Vector3(cos(a) * rr, 0, sin(a) * rr), rr, a))
            }
            r += 0.22
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1016))

        cameraShowcase(.turntable(period: .tau / 0.12), target: Vector3(0, 0.9, 0),
                       radius: 15, elevation: 0.55, fieldOfView: .pi / 4.2)

        ambientLight(Color(white: 0.14))
        directionalLight(Color(hue: 0.09, saturation: 0.22, brightness: 1.0),
                         direction: Vector3(-0.5, -0.85, -0.35), intensity: 1.0)
        directionalLight(Color(white: 0.5), direction: Vector3(0.55, 0.35, 0.5), intensity: 0.25,
                         castsShadow: false)   // a fill: one shadow pass, not two
        castShadows()

        // The floor that catches the field's shadows.
        withState {
            fill(Color(white: 0.78))
            specular(0.05)
            drawPlane(width: 26, depth: 26)
        }

        specular(0.25)
        shininess(36)

        // One traveling wave over the polar field: each pillar's height follows
        // a crest moving outward, and its tint follows its height.
        let low = Color(hex: 0x27435F)
        let high = Color(hex: 0xF2B75C)
        func height(_ seat: (position: Vector3, radius: Double, angle: Double)) -> Double {
            let crest = unipolar(sin(seat.radius * 1.15 - time * 1.6))
            let swirl = unipolar(sin(seat.angle * 3 + time * 0.7))
            return 0.25 + crest * (1.6 + swirl * 1.2)
        }

        if instanced {
            var instances: [MeshInstance] = []
            instances.reserveCapacity(seats.count)
            for seat in seats {
                let h = height(seat)
                instances.append(MeshInstance(
                    position: Vector3(seat.position.x, h / 2, seat.position.z),
                    scale: Vector3(1, h, 1),
                    color: Color.mix(low, high, t: (h - 0.25) / 2.8)))
            }
            drawMesh(pillar, instances: instances)
        } else {
            for seat in seats {
                let h = height(seat)
                withState {
                    translate(seat.position.x, h / 2, seat.position.z)
                    scale(1, h, 1)
                    fill(Color.mix(low, high, t: (h - 0.25) / 2.8))
                    drawMesh(pillar)
                }
            }
        }

        drawCaption("Instanced meshes: 12,000 pillars, one draw call")
    }
}
