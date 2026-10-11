// figure: frame=0
//
// Figure for Docs/3D/Sweeps.md: three lofts, each a surface through several flat
// shapes placed along a path. A bottle up a straight spine from a square foot
// through a round belly to a narrow neck; a horn along a bending spine from a star
// to a circle, turning half a turn and shrinking on the way; and a boat hull, a
// sheet through open U-shaped ribs from bow to stern, with no caps.
import Ollin

final class Loft: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    var bottle = Mesh(positions: [], indices: [])
    var horn = Mesh(positions: [], indices: [])
    var hull = Mesh(positions: [], indices: [])

    override func setup() {
        let spine = Curve3D((0...40).map { Vector3(0, -1.4 + Double($0) / 40 * 2.8, 0) })
        func round(_ r: Double) -> [Vector2] { Profile.ellipse(radiusX: r, radiusY: r, segments: 40) }
        bottle = .loft([Profile.rectangle(width: 1.1, height: 1.1), round(0.78), round(0.72), round(0.2), round(0.26), round(0.26)],
                       along: spine, at: [0, 0.3, 0.52, 0.76, 0.9, 1])

        let bend = Curve3D(curveThrough: [Vector3(0, -1.4, 0), Vector3(0.35, -0.3, 0.3), Vector3(-0.25, 0.7, -0.2),
                                          Vector3(0.5, 1.5, 0.2)], segments: 16)
        horn = .loft([Profile.star(points: 6, outerRadius: 0.62, innerRadius: 0.36), round(0.46), round(0.25)],
                     along: bend, scale: { 1 - 0.55 * $0 }, twist: { $0 * .pi })

        func rib(halfBeam: Double, depth: Double, flare: Double) -> Shape {
            Shape(contours: [Contour([Vector2(-halfBeam - flare, 0.7), Vector2(-halfBeam, 0.25),
                                      Vector2(-halfBeam * 0.55, -depth * 0.8), Vector2(0, -depth),
                                      Vector2(halfBeam * 0.55, -depth * 0.8), Vector2(halfBeam, 0.25),
                                      Vector2(halfBeam + flare, 0.7)], closed: false)])
        }
        let keel = Curve3D((0...40).map { Vector3(0, 0, -1.7 + Double($0) / 40 * 3.4) })
        hull = .loft([rib(halfBeam: 0.02, depth: 0.2, flare: 0.02), rib(halfBeam: 0.42, depth: 0.65, flare: 0.2),
                      rib(halfBeam: 0.7, depth: 0.85, flare: 0.18), rib(halfBeam: 0.66, depth: 0.78, flare: 0.12),
                      rib(halfBeam: 0.46, depth: 0.58, flare: 0.08)],
                     along: keel, at: [0, 0.2, 0.5, 0.78, 1])
    }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        camera(.perspective(eye: Vector3(0, 0.9, 7.6), target: Vector3(0, 0, 0), fieldOfView: .pi / 5.2))
        directionalLight(.white, direction: Vector3(-0.4, -0.7, -0.6), intensity: 1.1)
        ambientLight(Color(white: 0.3))
        specular(0.35); specularSharpness(40)

        withState {
            translate(-3.0, 0, 0)
            rotateY(0.4)
            fill(Color(hex: 0x6FC3DF))
            drawMesh(bottle)
        }
        withState {
            translate(0, 0, 0)
            rotateY(-0.3)
            fill(Color(hex: 0xF2B544))
            drawMesh(horn)
        }
        withState {
            translate(3.1, 0.2, 0)
            rotateX(0.18)
            rotateY(-1.25)
            scale(0.8)
            fill(Color(hex: 0xE4572E))
            drawMesh(hull)
        }
    }
}
