import Ollin

/// Solid 3D primitives — the built-in shapes drawn through a `Camera3D`.
///
/// Each shape is a `Mesh`, drawn through the same camera with depth testing — like
/// the point-cloud and transform examples, but with filled surfaces that depth-test
/// against each other. They sit on a facing grid, each spinning on its own while the
/// camera sways over the field.
///
/// The meshes are built **once** in `setup()` and drawn every frame with `drawMesh`
/// — the recommended pattern for anything but the simplest shapes, since generating
/// a sphere or a swept torus knot each frame is wasted work when the geometry never
/// changes (`drawBox`, `drawSphere`, … are the build-it-each-frame convenience).
///
/// Until the light/material model lands, a surface is colored by its normal (the
/// "normal material" look): a face's hue is its direction in space, which also makes
/// the geometry easy to read. A 2D label rides above each shape via `withBillboard`.
@main
final class Solids3D: Sketch {
    private var shapes: [(name: String, mesh: Mesh)] = []

    override func setup() {
        shapes = [
            ("cube",         .box(size: 1.3)),
            ("sphere",       .sphere(radius: 0.8)),
            ("cylinder",     .cylinder(radius: 0.62, height: 1.5)),
            ("cone",         .cone(radius: 0.8, height: 1.6)),
            ("torus",        .torus(radius: 0.62, tube: 0.27)),
            ("pyramid",      .pyramid(width: 1.4, depth: 1.4, height: 1.6)),
            ("helix",        .helix(radius: 0.55, tube: 0.12, turns: 3, height: 1.6)),
            ("icosahedron",  .icosahedron(radius: 0.9)),
            ("dodecahedron", .dodecahedron(radius: 0.9)),
            ("torus knot",   .torusKnot(p: 2, q: 3, radius: 0.7, tube: 0.18)),
            ("plane",        .plane(width: 1.5, depth: 1.5)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x07080D))

        // A catalog wall: the shapes sit on an x–y grid facing the camera, which
        // hovers in front and sways gently. Laying them in a plane (rather than a
        // floor) keeps the rows from stacking front-to-back, so every label sits
        // cleanly above its shape. Each shape still spins so every face turns by.
        camera(.orbiting(target: .zero, radius: 13,
                         azimuth: sin(time * 0.18) * 0.16, elevation: 0.12,
                         fieldOfView: .pi / 3.4))

        let columns = 4, spacing = 3.0
        let rows = (shapes.count + columns - 1) / columns
        let x0 = -spacing * Double(columns - 1) / 2
        let y0 = spacing * Double(rows - 1) / 2     // first row on top

        for (i, shape) in shapes.enumerated() {
            let col = i % columns, row = i / columns
            let x = x0 + spacing * Double(col)
            let y = y0 - spacing * Double(row)
            withState {
                translate(x, y, 0)
                withState {
                    rotateY(time * 0.55 + Double(i) * 0.6)
                    rotateX(sin(time * 0.35 + Double(i)) * 0.3)
                    drawMesh(shape.mesh)
                }
                // The shape's name, floating above it and occluded by anything nearer.
                withBillboard(at: Vector3(0, 1.3, 0)) {
                    fill(.white)
                    textSize(26)
                    textAlign(.center, .middle)
                    drawText(shape.name, 0, 0)
                }
            }
        }

        drawCaption("Solid 3D primitives — eleven shapes, each colored by its surface normal")
    }
}
