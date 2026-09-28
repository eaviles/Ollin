// figure: frame=0
//
// Guide figure (Chapter 25): what a solid is made of. One coarse icosphere
// three times on one floor. At the left it is the lit solid the chapter has
// been drawing. In the middle it is drawn as a wireframe, so its net of
// triangles shows. At the right it is the solid again with a short tube
// standing out of every vertex along that vertex's normal, the direction the
// surface faces there. The mesh repeats a corner once per triangle that meets
// at it, and every repeat carries the same normal, so the repeated tubes
// coincide and each corner shows one.
import Ollin

final class TrianglesAndNormals: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 600) }

    let ball = Mesh.icosphere(radius: 1, subdivisions: 1)

    override func draw() {
        background(Color(hex: 0x10141B))
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 10.5,
                         azimuth: 0.3, elevation: 0.24, fieldOfView: .pi / 5))

        fill(Color(white: 0.72))
        drawPlane(width: 40, depth: 40)

        // Left: the solid, under the default rig.
        withState {
            translate(-3.3, 1, 0)
            fill(Color(hex: 0xF25F5C))
            drawMesh(ball)
        }

        // Middle: the same mesh as its net of triangles.
        withState {
            translate(0, 1, 0)
            wireframe()
            stroke(Color(hex: 0xBFC7D5)); strokeWeight(1.5)
            drawMesh(ball)
        }

        // Right: the solid again, with its normal standing out of every vertex.
        withState {
            translate(3.3, 1, 0)
            fill(Color(hex: 0xF25F5C))
            drawMesh(ball)
            fill(Color(hex: 0xFFD166))
            for (p, n) in zip(ball.positions, ball.normals) {
                drawTube([p, p + n * 0.42], radius: 0.022, sides: 6)
            }
        }
    }
}
