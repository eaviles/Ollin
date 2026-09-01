import Ollin

/// Parametric and profile 3D shapes — the generative side of the primitive catalog.
///
/// These shapes are *factories*, not fixed forms: the **supershape** (Gielis
/// superformula) and **superellipsoid** sweep through whole families of shapes from
/// a few numbers (here driven by `time`, so they morph), while **extrude** pushes a
/// flat 2D `Profile` into depth and **lathe** revolves a side profile into a vase.
/// Möbius and Klein round out the set with their famous one-sided surfaces, and
/// **tube** sweeps a solid down any 3D curve. (The closed solids — box, sphere,
/// polyhedra, … — are in `3D/Solids`.)
///
/// The morphing shapes are rebuilt each frame (cheap at one shape apiece); the rest
/// are built once. Each takes a `fill` color shaded by the auto-lit default; labels
/// ride via `withBillboard`.
@main
final class ShapeFactory: Sketch {
    // A vase silhouette (x = radius from the axis, y = height) for the lathe.
    private let vase: [Vector2] = (0...24).map { i in
        let t = Double(i) / 24
        return Vector2(0.12 + 0.3 * sin(t * .pi * 0.92) + 0.06, (t - 0.5) * 1.4)
    }
    // A wavy closed loop for the swept tube.
    private let loop: [Vector3] = (0..<140).map { i in
        let t = Double(i) / 140 * 2 * .pi
        let r = 0.75 + 0.16 * sin(t * 5)
        return Vector3(r * cos(t), 0.3 * sin(t * 3), r * sin(t))
    }
    private var fixed: [(name: String, mesh: Mesh)] = []

    override func setup() {
        fixed = [
            ("möbius",      .mobius(radius: 0.62, width: 0.42)),
            ("klein",       .klein(scale: 0.26)),
            ("extrude star", .extrude(Profile.star(points: 5, outerRadius: 0.75, innerRadius: 0.33), depth: 0.5)),
            ("extrude gear", .extrude(Profile.polygon(sides: 8, radius: 0.78), depth: 0.5)),
            ("lathe vase",  .lathe(vase, segments: 44)),
            ("tube loop",   .tube(along: loop, radius: 0.12, sides: 10, closed: true)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x07080D))
        cameraShowcase(.sway(amplitude: 0.16, period: .tau / 0.18), target: .zero, radius: 13,
                    elevation: 0.18, fieldOfView: .pi / 3.4)

        // The two morphing shapes, rebuilt from time-driven parameters.
        let wobble = unipolar(sin(time * 0.4))                // 0…1
        let supershape = Mesh.supershape(radius: 0.75, m: 4 + wobble * 8,
                                         n1: 0.3 + wobble * 0.5, n2: 1.7, n3: 1.7,
                                         segments: 96, rings: 48)
        let e = 0.2 + wobble * 1.4                              // box → sphere → octahedron-ish
        let superellipsoid = Mesh.superellipsoid(radius: 0.8, e1: e, e2: e, segments: 56, rings: 28)

        let cells: [(name: String, mesh: Mesh)] =
            [("supershape", supershape), ("superellipsoid", superellipsoid)] + fixed

        let columns = 4, spacing = 3.1
        let rows = (cells.count + columns - 1) / columns
        let x0 = -spacing * Double(columns - 1) / 2
        let y0 = spacing * Double(rows - 1) / 2

        for (i, cell) in cells.enumerated() {
            let col = i % columns, row = i / columns
            let hue = Double(i) / Double(cells.count)
            withState {
                translate(x0 + spacing * Double(col), y0 - spacing * Double(row), 0)
                withState {
                    rotateY(time * 0.45 + Double(i) * 0.7)
                    rotateX(sin(time * 0.3 + Double(i)) * 0.25)
                    fill(Color(hue: hue, saturation: 0.58, brightness: 0.95))
                    specular(0.4)
                    specularSharpness(48)
                    drawMesh(cell.mesh)
                }
                withBillboard(at: Vector3(0, 1.5, 0)) {
                    fill(.white)
                    textSize(26)
                    textAlign(.center, .middle)
                    drawText(cell.name, 0, 0)
                }
            }
        }

        drawCaption("Parametric & profile shapes — supershape and superellipsoid morph; extrude & lathe build from 2D")
    }
}
