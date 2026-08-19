// figure: frame=0
//
// Guide figure (Chapter 21): a field turned into geometry. The same chain of
// three metaballs twice, shaded on the left and wireframed on the right, so
// the necks where the balls fuse read as a smooth surface and as the actual
// triangles marching cubes laid down.
import Ollin

final class FieldToMesh: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 0.9, 8.6), target: Vector3(0, -0.1, 0),
                            fieldOfView: .pi / 4.3))
        environment(.studio.lightingOnly())
        lightingPreset(.studio)

        var field = Metaballs()
        field.add(at: Vector3(-0.90, 0.25, 0.00), radius: 0.62)
        field.add(at: Vector3(0.50, -0.20, 0.15), radius: 0.52)
        field.add(at: Vector3(1.40, 0.45, -0.20), radius: 0.40)
        // Deliberately coarse, so the cells are legible on the right. The left
        // panel still reads smooth, because the normals come from the field
        // rather than from the facets.
        let blob = field.mesh(resolution: 26)

        for (index, label) in ["the surface", "the triangles"].enumerated() {
            withState {
                translate(Double(index) * 4.0 - 2.0, 0.25, 0)
                fill(Color(hex: 0xB9C4D2))
                if index == 1 {
                    stroke(Color(hex: 0x8FA7C4))
                    strokeWeight(1)
                    wireframe()
                } else {
                    material(.dielectric(roughness: 0.35))
                }
                drawMesh(blob)
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
