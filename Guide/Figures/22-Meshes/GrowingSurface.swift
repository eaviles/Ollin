// figure: frame=0
//
// Guide figure (Chapter 22): a surface that grows more area than it has room
// for. The same sphere three times: the mesh it starts from, even growth
// folding it uniformly all over, and growth restricted to a band around the
// equator, which ruffles into a skirt and leaves the poles smooth.
import Ollin

final class GrowingSurface: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let start = Mesh.icosphere(radius: 0.85, subdivisions: 3)
    lazy var even = grown(.uniform, amount: 0.5)
    lazy var rim = grown(.field { position, _ in
        1 - smoothstep(0.1, 0.5, abs(position.y))
    }, amount: 0.7)

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 1.7, 13.0), target: Vector3(0, 0.45, 0),
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        withState {
            translate(-3.9, 0.2, 0)
            fill(Color(hex: 0xE8B24A))
            material(.matte)
            drawMesh(start)
            label("the starting mesh")
        }

        withState {
            translate(0, 0.2, 0)
            fill(Color(hex: 0xE8794A))
            material(.matte)
            drawMesh(even)
            label("everywhere")
        }

        withState {
            translate(3.9, 0.2, 0)
            fill(Color(hex: 0xE8794A))
            material(.matte)
            drawMesh(rim)
            label("at the equator")
        }
    }

    /// A sphere grown to a fixed step count under one driver. Seeded, so the
    /// figure renders the same form every time.
    private func grown(_ driver: GrowthDriver, amount: Double) -> Mesh {
        let growth = MeshGrowth(mesh: start, driver: driver, edgeLength: 0.11, seed: 4)
        growth.growthRate = amount
        growth.maxVertices = 4200
        growth.step(140)
        return growth.mesh
    }

    private func label(_ text: String) {
        withBillboard(at: Vector3(0, -1.9, 0)) {
            noStroke()
            fill(.white)
            textSize(21)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
