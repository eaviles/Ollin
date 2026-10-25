// figure: frame=0
//
// Guide figure (Chapter 28): a loft, a surface through several flat shapes. On the
// left, the four sections of a bottle float at their places up a straight spine as
// outlines: a square foot, a round belly, a narrow neck, and a lip. On the right,
// the loft through them, the skin blending from the square to the circles with
// the square's corners fading out on the way up.
import Ollin

final class LoftedBottle: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let stations = [0.0, 0.34, 0.74, 1.0]
    var sections: [[Vector2]] = []
    var spine = Curve3D([Vector3(0, -1.2, 0), Vector3(0, 1.2, 0)])
    var bottle = Mesh(positions: [], indices: [])

    override func setup() {
        func round(_ r: Double) -> [Vector2] { Profile.ellipse(radiusX: r, radiusY: r, segments: 40) }
        sections = [Profile.rectangle(width: 1.0, height: 1.0), round(0.7), round(0.2), round(0.27)]
        spine = Curve3D((0...40).map { Vector3(0, -1.2 + Double($0) / 40 * 2.4, 0) })
        bottle = .loft(sections, along: spine, at: stations)
    }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        camera(.perspective(eye: Vector3(0, 1.6, 7.0), target: Vector3(0, 0, 0), fieldOfView: .pi / 5.6))
        directionalLight(.white, direction: Vector3(-0.4, -0.7, -0.6), intensity: 1.1)
        ambientLight(Color(white: 0.3))
        specular(0.35); specularSharpness(40)

        withState {
            translate(-1.7, 0, 0)
            rotateY(0.35)
            noFill()
            stroke(Color(hex: 0xF2B544))
            strokeWeight(2.5)
            for (outline, s) in zip(sections, stations) {
                let frame = spine.frame(at: s)
                drawPolyline(outline.map { frame.point($0) }, closed: true)
            }
            stroke(Color(white: 0.35))
            strokeWeight(1)
            drawLine(spine.point(at: 0), spine.point(at: 1))
        }
        withState {
            translate(1.7, 0, 0)
            rotateY(0.35)
            noStroke()
            fill(Color(hex: 0x6FC3DF))
            drawMesh(bottle)
        }
    }
}
