// figure: frame=0
//
// Guide figure (Chapter 27): the face stream's eyes and gaze made visible. A
// staged face stands as a wireframe shell, turned slightly one way, while its
// eyes look another: an eyeball at each streamed eye pose, a pupil riding its
// gaze direction, a beam from each eye to the look-at point, and a warm bead
// where the two beams converge.
//
// The face is staged rather than tracked, the way this chapter's other figures
// stage a sensor: the same PhoneFace a phone fills in, built by hand through its
// staging initializer so the figure renders anywhere. The shell is a plain
// spherical cap standing in for the tracked mesh, which needs a real face.
import Foundation
import simd
import Ollin
import OllinPhone

final class GazeAsBeams: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let netColor = Color(hex: 0x9FB4D8)
    let beadColor = Color(hex: 0xFFB060)

    /// A face-shaped shell out of plain numbers: a spherical cap facing +z,
    /// taller than it is deep, with the grid triangulated the usual way.
    static func shellMesh() -> (points: [Vector3], indices: [UInt32]) {
        let cols = 15, rows = 13
        let r = 0.10
        var points: [Vector3] = []
        for j in 0..<rows {
            let phi = -1.05 + Double(j) / Double(rows - 1) * 2.2
            for i in 0..<cols {
                let theta = -1.25 + Double(i) / Double(cols - 1) * 2.5
                points.append(Vector3(r * sin(theta) * cos(phi),
                                      r * 1.12 * sin(phi),
                                      r * 0.92 * cos(theta) * cos(phi)))
            }
        }
        var indices: [UInt32] = []
        for j in 0..<(rows - 1) {
            for i in 0..<(cols - 1) {
                let a = UInt32(j * cols + i), b = a + 1
                let c = a + UInt32(cols), d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return (points, indices)
    }

    /// The staged face: head turned a little to its left, eyes converging on a
    /// point well off to its right, so the look and the face point apart.
    static func stagedFace() -> PhoneFace {
        let shell = shellMesh()
        let lookAt = Vector3(0.30, 0.05, 0.55)
        func eyeQuat(from eye: Vector3) -> SIMD4<Float> {
            let d = (lookAt - eye).normalized
            let q = simd_quatf(from: SIMD3<Float>(0, 0, 1),
                               to: SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
            return q.vector
        }
        let left = Vector3(0.033, 0.035, 0.088)
        let right = Vector3(-0.033, 0.035, 0.088)
        return PhoneFace(
            headOrientation: simd_quatf(angle: -0.15, axis: SIMD3<Float>(0, 1, 0)).vector,
            headPosition: Vector3(0, 0.02, 0),
            meshPoints: shell.points, triangleIndices: shell.indices,
            leftEyeOrientation: eyeQuat(from: left), leftEyePosition: left,
            rightEyeOrientation: eyeQuat(from: right), rightEyePosition: right,
            lookAtPoint: lookAt)
    }

    lazy var face = Self.stagedFace()

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0.11, 0.055, 0.28), radius: 0.62,
                         azimuth: 0.55, elevation: 0.14, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.0).lightingOnly())

        // The shell stands under the full head pose, so the eyes sit inside it.
        withState {
            transform(face.headTransform)
            wireframe()
            strokeWeight(1.1)
            stroke(netColor)
            drawMesh(face.mesh())
        }
        // A nose marker, so the way the head points reads apart from the gaze.
        withState {
            transform(face.headTransform)
            translate(0, -0.012, 0.094)
            material(.clay)
            fill(netColor)
            drawSphere(radius: 0.011)
        }

        let target = face.worldLookAtPoint
        for eye in PhoneEye.allCases {
            let at = face.worldEyePosition(eye)
            let gaze = face.worldGazeDirection(eye)
            withState {
                material(.clay)
                fill(.white)
                translate(at)
                drawSphere(radius: 0.015)
            }
            withState {
                material(.matte)
                fill(Color(white: 0.08))
                translate(at + gaze * 0.0135)
                drawSphere(radius: 0.006)
            }
            withState {
                material(.matte)
                fill(beadColor)
                drawCapsule(from: at + gaze * 0.018, to: target, radius: 0.0016)
            }
        }

        // The bead where the two beams meet.
        withState {
            material(.glossy)
            fill(beadColor)
            translate(target)
            drawSphere(radius: 0.008)
        }
    }
}
