// figure: frame=0
//
// Figure for Docs/3D/HiddenLines.md: hidden-line solids. On white paper, a
// row of solids drawn under featureEdges: a box with its twelve edges and no
// diagonals, a cylinder with its two rims and its silhouette, a sphere with
// its outline alone, a cone, and a torus whose inner and outer outlines both
// show; behind them a block of small boxes drawn as one instanced draw, the
// near ones hiding the edges of the far ones.
import Ollin

final class HiddenLines: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    override func draw() {
        background(.white)
        camera(.perspective(eye: Vector3(0.4, 2.5, 6.0), target: Vector3(0, 0.9, -1.6), fieldOfView: .pi / 5.0))
        noLights()
        fill(.white)
        stroke(Color(white: 0.1))
        strokeWeight(1.4)
        featureEdges()

        // The block behind: 9 by 4 by 5 small boxes, each turned its own way.
        var copies: [MeshInstance] = []
        for i in 0 ..< 9 {
            for j in 0 ..< 4 {
                for k in 0 ..< 5 {
                    let p = Vector3(Double(i) * 0.62 - 2.48, Double(j) * 0.55 + 0.35, Double(k) * 0.6 - 5.4)
                    let a = noise(Double(i) * 0.7, Double(j) * 0.7, Double(k) * 0.7) * 4
                    copies.append(MeshInstance(position: p, rotation: Vector3(a, a * 1.3, a * 0.4), scale: 0.3))
                }
            }
        }
        drawMesh(.box(size: 1), instances: copies)

        // The row in front.
        withState { translate(-2.6, 0.5, 0.2); rotateY(0.6); drawBox(size: 0.95) }
        withState { translate(-1.25, 0.55, -0.3); drawCylinder(radius: 0.42, height: 1.1, segments: 48) }
        withState { translate(0.05, 0.55, 0.25); drawSphere(radius: 0.55, segments: 48, rings: 24) }
        withState { translate(1.3, 0.55, -0.35); drawCone(radius: 0.5, height: 1.1, segments: 48) }
        withState { translate(2.6, 0.5, 0.15); rotateX(1.1); drawTorus(radius: 0.5, tube: 0.17, segments: 64, sides: 24) }
    }
}
