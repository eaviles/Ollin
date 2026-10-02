// figure: frame=0
//
// Guide figure (Chapter 27): why a sweep wants frames that do not twist. The same
// flat ribbon is laid along the same S-shaped path in space twice. On the left it
// follows the curve's own frame, which turns over where the path stops bending one
// way and starts bending the other; on the right it follows Curve3D's frames,
// which turn only as far as the path bends. One edge of each ribbon is orange
// and the other blue, so a turn over shows as the colors changing sides.
import Ollin

final class FramesThatDoNotTwist: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    var curvesOwn = Mesh(positions: [], indices: [])
    var rotationMinimizing = Mesh(positions: [], indices: [])

    override func setup() {
        let points = (0...200).map { k -> Vector3 in
            let u = Double(k) / 100 - 1
            return Vector3(1.75 * u, 0.7 * sin(.pi * u), 0.2 * sin(2 * .pi * u))
        }
        let path = Curve3D(points)
        let width = 0.24

        // The curve's own (Frenet) frame: the normal points the way the tangent
        // is turning, so it swings round where the bend changes side.
        var across: [Vector3] = []
        for i in points.indices {
            let before = path.frames[max(i - 1, 0)].tangent
            let after = path.frames[min(i + 1, points.count - 1)].tangent
            let t = path.frames[i].tangent
            let turning = (after - before) - t * (after - before).dot(t)
            across.append(turning.lengthSquared > 1e-14 ? turning.normalized : across.last ?? .unitY)
        }
        curvesOwn = .strip(between: points.indices.map { points[$0] + across[$0] * width },
                           and: points.indices.map { points[$0] - across[$0] * width })
        // Curve3D's frames, turned once at the start to agree with the curve's
        // own frame there, so the two ribbons begin the same way.
        let first = path.frames[0]
        let start = atan2(across[0].dot(first.binormal), across[0].dot(first.normal))
        let offset = Vector2(cos(start), sin(start)) * width
        rotationMinimizing = .strip(between: path.frames.map { $0.point(offset) },
                                    and: path.frames.map { $0.point(offset * -1) })
        // A strip's vertices alternate between its two lines, so the even ones
        // are one edge and the odd ones the other.
        for i in 0..<2 {
            var mesh = i == 0 ? curvesOwn : rotationMinimizing
            mesh.colors = mesh.positions.indices.map { $0 % 2 == 0 ? Color(hex: 0xF29E4C) : Color(hex: 0x4C9AF2) }
            if i == 0 { curvesOwn = mesh } else { rotationMinimizing = mesh }
        }
    }

    override func draw() {
        background(Color(hex: 0x0B0C12))
        camera(.perspective(eye: Vector3(0, 1.0, 7.6), target: Vector3(0, -0.15, 0), fieldOfView: .pi / 5.4))
        directionalLight(.white, direction: Vector3(-0.3, -0.6, -0.7), intensity: 0.6)
        headlight(intensity: 0.4)
        ambientLight(Color(white: 0.55))

        for (x, mesh, label) in [(-2.15, curvesOwn, "the curve's own frame"),
                                 (2.15, rotationMinimizing, "Curve3D's frames")] {
            withState {
                translate(x, 0.1, 0)
                rotateY(-0.35)
                fill(.white)
                drawMesh(mesh)
            }
            withBillboard(at: Vector3(x, -1.35, 0)) {
                fill(Color(white: 0.85))
                textSize(22)
                textAlign(.center, .middle)
                drawText(label, 0, 0)
            }
        }
    }
}
