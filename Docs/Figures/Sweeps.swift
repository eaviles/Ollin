// figure: frame=0
//
// Figure for Docs/3D/Sweeps.md: three things a path carries. A star swept round a
// closed knot, turning one whole turn on the way; a square swept up a spiral,
// tapering and turning a whole turn, capped; and a ribbon between two loops, its
// rungs placed by an even pace of area and colored one hue a rung.
import Ollin

final class Sweeps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    var knot = Mesh(positions: [], indices: [])
    var horn = Mesh(positions: [], indices: [])
    var ribbon = Mesh(positions: [], indices: [])

    override func setup() {
        let loop = Curve3D((0..<300).map { k -> Vector3 in
            let t = Double(k) / 300 * .tau
            let r = 0.85 + 0.35 * cos(3 * t)
            return Vector3(r * cos(2 * t), r * sin(2 * t), 0.4 * sin(3 * t))
        }, closed: true)
        knot = .sweep(Profile.star(points: 5, outerRadius: 0.2, innerRadius: 0.09),
                      along: loop, twist: { $0 * .tau })

        let spiral = Curve3D((0...160).map { k -> Vector3 in
            let f = Double(k) / 160
            let a = f * 1.3 * .tau
            let r = 0.75 - 0.3 * f
            return Vector3(r * cos(a), -1.35 + 2.6 * f, r * sin(a))
        })
        horn = .sweep(Profile.rectangle(width: 0.5, height: 0.5), along: spiral,
                      scale: { 1 - 0.8 * $0 }, twist: { $0 * .tau })

        func lower(_ t: Double) -> Vector3 { Vector3(1.1 * cos(t), 0.6 * sin(2 * t), 0.55 * sin(t)) }
        func upper(_ t: Double) -> Vector3 {
            Vector3(0.8 * cos(t + 0.5), 0.6 * sin(2 * t) + 0.5 + 0.2 * cos(3 * t), 0.8 * sin(t + 0.5))
        }
        let pace = Pace(byAreaBetween: lower, and: upper, period: .tau)
        let rungs = 180
        let ts = (0..<rungs).map { pace.parameter(at: Double($0) / Double(rungs)) }
        ribbon = .strip(between: ts.map(lower), and: ts.map(upper),
                        colors: (0..<rungs).map {
                            Color(hue: Double($0) / Double(rungs), saturation: 0.6, brightness: 1)
                        },
                        closed: true)
    }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        camera(.perspective(eye: Vector3(0, 0.5, 7.4), target: Vector3(0, 0, 0), fieldOfView: .pi / 5.2))
        directionalLight(.white, direction: Vector3(-0.4, -0.7, -0.6), intensity: 1.1)
        ambientLight(Color(white: 0.32))
        specular(0.35); specularSharpness(40)

        withState {
            translate(-3.1, 0.05, 0)
            rotateX(0.55)
            rotateZ(0.2)
            fill(Color(hex: 0xF2B544))
            drawMesh(knot)
        }
        withState {
            translate(0, -0.05, 0)
            rotateX(0.4)
            rotateY(0.5)
            fill(Color(hex: 0x6FC3DF))
            drawMesh(horn)
        }
        withState {
            translate(3.1, -0.2, 0)
            rotateX(0.35)
            rotateY(-0.3)
            fill(.white)
            drawMesh(ribbon)
        }
    }
}
