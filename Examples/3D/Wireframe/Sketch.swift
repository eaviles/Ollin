import Ollin

/// Wireframe meshes — a mesh drawn as its triangle edges (the mesh "net") instead of
/// filled surfaces. `wireframe()` is drawing state, like `fill`/`stroke`: turn it on
/// and any mesh after it draws as edges; the faces are see-through.
///
/// The edges take the current `stroke` color and `strokeWeight`. It works on every
/// mesh — a built-in primitive or a loaded model — so it's a free way to see a
/// shape's structure (and the classic look for face/scan meshes).
@main
final class WireframeExample: Sketch {
    // The shapes to show, each its own wire color.
    private let shapes: [(mesh: Mesh, color: Color)] = [
        (.icosphere(radius: 1.0, subdivisions: 2), Color(hex: 0x53D1FF)),
        (.torusKnot(p: 2, q: 3, radius: 0.7, tube: 0.24, segments: 140, sides: 12), Color(hex: 0xFF7AB0)),
        (.supershape(radius: 1.0, m: 7, n1: 0.2, n2: 1.7, n3: 1.7, segments: 64, rings: 32), Color(hex: 0xB6FF6C)),
    ]

    override func draw() {
        background(Color(hex: 0x07080D))
        camera(.orbiting(target: .zero, radius: 9,
                         azimuth: mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.3,
                         elevation: 0.25, fieldOfView: .pi / 4))

        wireframe()                 // every mesh from here draws as edges
        strokeWeight(1.5)

        let spacing = 3.2
        let x0 = -spacing * Double(shapes.count - 1) / 2
        for (i, shape) in shapes.enumerated() {
            withState {
                translate(x0 + spacing * Double(i), 0, 0)
                rotateY(time * 0.5 + Double(i))
                rotateX(0.3)
                stroke(shape.color)
                drawMesh(shape.mesh)
            }
        }

        drawCaption("Wireframe — meshes drawn as their triangle edges; drag to spin")
    }
}
