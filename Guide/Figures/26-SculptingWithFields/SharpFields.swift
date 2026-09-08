// figure: frame=0
//
// Guide figure (Chapter 26): the same field, a block with a hole bored through
// it, meshed twice on the same coarse grid. Marching cubes on the left rounds
// every corner off to the size of a cell; dual contouring on the right puts
// each cell's vertex where the field's normals meet, so the corners and the
// rim of the bore come back sharp.
import Ollin

final class SharpFields: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    private func field(_ p: Vector3) -> Double {
        let q = Vector3(abs(p.x) - 1, abs(p.y) - 1, abs(p.z) - 1)
        let block = Vector3(max(q.x, 0), max(q.y, 0), max(q.z, 0)).length
            + min(max(q.x, max(q.y, q.z)), 0)
        let hole = (p.x * p.x + p.y * p.y).squareRoot() - 0.5
        return -max(block, -hole)
    }

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 2.2, 8.4), target: Vector3(0, -0.15, 0),
                            fieldOfView: .pi / 4.3))
        environment(.studio.lightingOnly())
        lightingPreset(.studio)

        let box = Box3(min: Vector3(-1.3, -1.3, -1.3), max: Vector3(1.3, 1.3, 1.3))
        let methods: [(IsosurfaceMethod, String)] = [(.marchingCubes, "marching cubes"),
                                                     (.dualContouring, "dual contouring")]
        for (index, (method, label)) in methods.enumerated() {
            // Deliberately coarse, so the difference is the placement of the
            // vertices and not the number of them.
            let mesh = isosurface(at: 0, in: box, resolution: 14, method: method, field: field)
            withState {
                translate(Double(index) * 4.0 - 2.0, 0.2, 0)
                rotateY(0.55)
                rotateX(0.25)
                fill(Color(hex: 0xD9C08A))
                material(.dielectric(roughness: 0.45))
                drawMesh(mesh)
            }
            withState {
                translate(Double(index) * 4.0 - 2.0, 0.2, 0)
                withBillboard(at: Vector3(0, -2.0, 0)) {
                    noStroke()
                    fill(.white)
                    textSize(22)
                    textAlign(.center, .middle)
                    drawText(label, 0, 0)
                }
            }
        }
    }
}
