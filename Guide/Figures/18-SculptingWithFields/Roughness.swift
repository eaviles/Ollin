// figure: frame=0
//
// Guide figure (Chapter 18): the roughness dial on a physically based metal.
// Five identical spheres under one environment, from mirror-polished to matte.
// The leftmost reflects the studio it is standing in; the rightmost only
// borrows its average brightness.
import Ollin

final class Roughness: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.72, subdivisions: 4)

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 0.5, 8.2), target: Vector3(0, 0.15, 0),
                            fieldOfView: .pi / 4.3))
        // Lighting only: the spheres still reflect the studio, but its backdrop
        // stays out of the way so the roughness run is the whole picture.
        environment(.studio.lightingOnly())
        toneMap(.aces, exposure: 1.15)

        let roughnesses = [0.02, 0.15, 0.32, 0.6, 1.0]
        for (index, roughness) in roughnesses.enumerated() {
            withState {
                translate(Double(index) * 1.72 - 3.44, 0.35, 0)
                fill(Color(hex: 0xC9CDD4))
                material(.metal(roughness: roughness))
                drawMesh(ball)
                withBillboard(at: Vector3(0, -1.35, 0)) {
                    noStroke()
                    fill(.white)
                    textSize(22)
                    textAlign(.center, .middle)
                    drawText("\(roughness)", 0, 0)
                }
            }
        }
    }
}
