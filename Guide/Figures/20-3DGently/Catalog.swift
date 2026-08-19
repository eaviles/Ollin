// figure: frame=0
//
// Guide contact sheet (Chapter 20): the built-in solid primitives, each a
// `Mesh` on a facing grid, shaded by the auto-lit default and labeled with a
// billboard.
import Ollin

final class Catalog: Sketch {
    var shapes: [(name: String, mesh: Mesh)] = []

    override func setup() {
        shapes = [
            ("box",          .box(size: 1.15)),
            ("sphere",       .sphere(radius: 0.72)),
            ("icosphere",    .icosphere(radius: 0.72, subdivisions: 2)),
            ("cylinder",     .cylinder(radius: 0.56, height: 1.35)),
            ("cone",         .cone(radius: 0.7, height: 1.45)),
            ("capsule",      .capsule(radius: 0.35, height: 0.8)),
            ("rounded box",  .roundedBox(size: 1.15, radius: 0.28)),
            ("torus",        .torus(radius: 0.56, tube: 0.24)),
            ("tetrahedron",  .tetrahedron(radius: 0.8)),
            ("octahedron",   .octahedron(radius: 0.8)),
            ("icosahedron",  .icosahedron(radius: 0.8)),
            ("dodecahedron", .dodecahedron(radius: 0.8)),
            ("pyramid",      .pyramid(width: 1.25, depth: 1.25, height: 1.45)),
            ("helix",        .helix(radius: 0.48, tube: 0.11, turns: 3, height: 1.45,
                                    segments: 160, sides: 10)),
            ("torus knot",   .torusKnot(radius: 0.6, tube: 0.165, segments: 150, sides: 12)),
            ("plane",        .plane(width: 1.35, depth: 1.35)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x07080D))
        camera(.perspective(eye: Vector3(0, 0, 14.4), target: .zero, fieldOfView: .pi / 3.4))
        translate(0, -0.3, 0)

        let columns = 4, spacing = 3.0
        let rows = (shapes.count + columns - 1) / columns
        let x0 = -spacing * Double(columns - 1) / 2
        let y0 = spacing * Double(rows - 1) / 2

        for (i, shape) in shapes.enumerated() {
            withState {
                translate(x0 + spacing * Double(i % columns),
                          y0 - spacing * Double(i / columns), 0)
                withState {
                    rotateY(0.55 + Double(i) * 0.4)
                    rotateX(0.32)
                    fill(Color(hue: Double(i) / Double(shapes.count),
                               saturation: 0.55, brightness: 0.95))
                    specular(0.4); shininess(48)
                    drawMesh(shape.mesh)
                }
                withBillboard(at: Vector3(0, 1.3, 0)) {
                    fill(.white)
                    textSize(26)
                    textAlign(.center, .middle)
                    drawText(shape.name, 0, 0)
                }
            }
        }
    }
}
