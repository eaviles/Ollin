// figure: frame=0
//
// Guide figure (Chapter 24): anisotropy on a physically based metal. The same
// steel four times under one studio: the round isotropic highlight, the streak
// a brushed finish pulls it into, the quarter-turn that spins the streak, and
// the ready-made preset on a ring, where the streak follows the machining.
import Ollin

final class BrushedRing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.72, subdivisions: 4)

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 0.5, 8.2), target: Vector3(0, 0.15, 0),
                            fieldOfView: .pi / 4.3))
        environment(.studio.lightingOnly())
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.2, -0.4, -0.9),
                         intensity: 0.9)
        toneMap(.aces, exposure: 1.15)

        let steel = Color(hex: 0xC9CDD4)
        let cells: [(String, Material)] = [
            ("isotropic", Material(shading: .physicallyBased, metallic: 1, roughness: 0.4)),
            ("brushed 0.8", Material(shading: .physicallyBased, metallic: 1,
                                     roughness: 0.4, anisotropy: 0.8)),
            ("turned 90°", Material(shading: .physicallyBased, metallic: 1, roughness: 0.4,
                                    anisotropy: 0.8, anisotropyRotation: .pi / 2)),
            ("ring", .brushedMetal),
        ]
        for (index, cell) in cells.enumerated() {
            withState {
                translate(Double(index) * 2.15 - 3.22, 0.35, 0)
                fill(steel)
                material(cell.1)
                if index == 3 {
                    withState {
                        rotateX(.pi / 2 - 0.5)
                        drawTorus(radius: 0.52, tube: 0.24)
                    }
                } else {
                    drawMesh(ball)
                }
                withBillboard(at: Vector3(0, -1.35, 0)) {
                    noStroke()
                    fill(.white)
                    textSize(22)
                    textAlign(.center, .middle)
                    drawText(cell.0, 0, 0)
                }
            }
        }
    }
}
