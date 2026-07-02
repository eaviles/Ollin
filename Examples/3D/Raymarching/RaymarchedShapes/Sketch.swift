import Ollin
import Foundation

// A tour of the raymarched 3D SDF primitives beyond the first four (sphere/box/torus/
// capsule): a rounded box, a cylinder, a cone, an octahedron, and an ellipsoid in a row,
// each its own field sphere-traced into the shared depth buffer so they occlude one
// another. Above and behind sits a cone smooth-melted into an ellipsoid with a cylinder
// bored through, so the new shapes show up through the combine ops too. The camera sways
// gently so the whole catalog stays framed.
@main
final class RaymarchedShapes: Sketch {
    override func draw() {
        background(Color(hex: 0x0f1014))
        let t = time

        cameraShowcase(.sway(amplitude: 0.12, period: .tau / 0.25), target: Vector3(0, 0.3, 0), radius: 9.5,
                    elevation: 0.22, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.5),
                         intensity: 1.15, softness: 0.25)
        ambientLight(Color(white: 0.17))
        material(.glossy)

        // The five new primitives in a row, each turning on its own axis.
        let row: [SDF3D] = [
            SDF3D.roundBox(size: 1.0, radius: 0.26).colored(Color(hex: 0xff6b6b)),
            SDF3D.cylinder(radius: 0.5, height: 1.4).colored(Color(hex: 0xffd166)),
            SDF3D.cone(radius: 0.7, height: 1.5).colored(Color(hex: 0x06d6a0)),
            SDF3D.octahedron(radius: 0.78).colored(Color(hex: 0x4ea8ff)),
            SDF3D.ellipsoid(rx: 0.45, ry: 0.8, rz: 0.45).colored(Color(hex: 0xc77dff)),
        ]
        let span = Double(row.count - 1)
        for (i, shape) in row.enumerated() {
            let x = (Double(i) - span / 2) * 1.5
            // Spin in place, then place: rotate before translate (the reverse orbits the origin).
            drawSDF3D(shape.rotatedY(t * 0.6 + Double(i)).at(x: x, y: -0.4, z: 0))
        }

        // Above and behind: a cone smooth-melted into an ellipsoid, with a cylinder bored
        // out, so the new shapes carry through the combine ops too.
        let melt = SDF3D.ellipsoid(rx: 1.0, ry: 0.65, rz: 0.85).colored(Color(hex: 0x4ea8ff))
            .smoothUnion(SDF3D.cone(radius: 0.55, height: 1.7).at(x: 0, y: 0.85, z: 0)
                .colored(Color(hex: 0xff6b6b)), k: 0.45)
            .smoothSubtract(SDF3D.cylinder(radius: 0.3, height: 3.0).rotatedX(.pi / 2), k: 0.12)
        drawSDF3D(melt.rotatedY(t * 0.4).at(x: 0, y: 1.5, z: -1.4))
    }
}
