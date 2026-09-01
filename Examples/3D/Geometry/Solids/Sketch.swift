import Ollin

/// Solid 3D primitives — the built-in closed shapes, drawn through a `Camera3D`.
///
/// Each is a `Mesh`, built once in `setup()` and drawn every frame with `drawMesh`
/// (the recommended pattern — generating a sphere or swept knot each frame is
/// wasted work when the geometry never changes; `drawBox`/`drawSphere`/… are the
/// build-it-each-frame convenience). They sit on a facing grid, each spinning while
/// the camera sways. The parametric and profile generators (supershape, Möbius,
/// extrude, lathe, …) have their own example in `3D/ShapeFactory`.
///
/// Each solid takes a `fill` color and is shaded by the auto-lit default — a solid
/// looks 3D out of the box, no lights to set up — with a soft specular highlight.
/// A 2D label rides above each shape via `withBillboard`.
@main
final class Solids3D: Sketch {
    private var shapes: [(name: String, mesh: Mesh)] = []

    override func setup() {
        shapes = [
            ("cube",         .box(size: 1.2)),
            ("sphere",       .sphere(radius: 0.75)),
            ("icosphere",    .icosphere(radius: 0.75, subdivisions: 2)),
            ("cylinder",     .cylinder(radius: 0.58, height: 1.4)),
            ("cone",         .cone(radius: 0.72, height: 1.5)),
            ("capsule",      .capsule(radius: 0.36, height: 0.8)),
            ("rounded box",  .roundedBox(size: 1.2, radius: 0.3)),
            ("torus",        .torus(radius: 0.58, tube: 0.25)),
            ("tetrahedron",  .tetrahedron(radius: 0.82)),
            ("octahedron",   .octahedron(radius: 0.82)),
            ("icosahedron",  .icosahedron(radius: 0.82)),
            ("dodecahedron", .dodecahedron(radius: 0.82)),
            ("pyramid",      .pyramid(width: 1.3, depth: 1.3, height: 1.5)),
            ("helix",        .helix(radius: 0.5, tube: 0.11, turns: 3, height: 1.5, segments: 160, sides: 10)),
            ("torus knot",   .torusKnot(p: 2, q: 3, radius: 0.62, tube: 0.17, segments: 150, sides: 12)),
            ("plane",        .plane(width: 1.4, depth: 1.4)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x07080D))

        // A catalog wall: shapes on an x–y grid facing a gently swaying camera, so
        // the rows don't stack front-to-back and every label sits above its shape.
        cameraShowcase(.sway(amplitude: 0.14, period: .tau / 0.18), target: .zero, radius: 15,
                    elevation: 0.12, fieldOfView: .pi / 3.4)

        let columns = 4, spacing = 3.0
        let rows = (shapes.count + columns - 1) / columns
        let x0 = -spacing * Double(columns - 1) / 2
        let y0 = spacing * Double(rows - 1) / 2

        for (i, shape) in shapes.enumerated() {
            let col = i % columns, row = i / columns
            // A hue per shape, lit by the default rig with a gentle highlight.
            let hue = Double(i) / Double(shapes.count)
            withState {
                translate(x0 + spacing * Double(col), y0 - spacing * Double(row), 0)
                withState {
                    rotateY(time * 0.5 + Double(i) * 0.6)
                    rotateX(sin(time * 0.35 + Double(i)) * 0.3)
                    fill(Color(hue: hue, saturation: 0.6, brightness: 0.95))
                    specular(0.4)
                    specularSharpness(48)
                    drawMesh(shape.mesh)
                }
                withBillboard(at: Vector3(0, 1.35, 0)) {
                    fill(.white)
                    textSize(24)
                    textAlign(.center, .middle)
                    drawText(shape.name, 0, 0)
                }
            }
        }

        drawCaption("Solid 3D primitives — sixteen shapes, shaded by the auto-lit default")
    }
}
