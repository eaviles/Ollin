// figure: frame=0
//
// Guide figure (Chapter 21): the two ways to wear the phone's body stream. Left,
// the joints as dots, the skeleton every slice of the stream could always draw.
// Right, the same pose worn by solids: capsule bones, a torso that leans, a head
// that turns, each part stood at its joint by the joint's own orientation. The
// blue forearm is the honest part: the camera never saw those joints, the rig
// filled them in, and the stream says so.
//
// The pose is staged rather than tracked, the way this chapter's other figures
// stage a depth camera: the same PhoneBody a phone fills in, built by hand from a
// PhonePoseSample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class BodyAsFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let seenColor = Color(hex: 0xEDE7DA)
    let filledColor = Color(hex: 0x5C6B8A)

    /// A mid-stride pose: one arm raised, the head turned, the left forearm
    /// deliberately marked as rig-filled.
    static func stagedBody() -> PhoneBody {
        func j(_ x: Float, _ y: Float, _ z: Float,
               turn: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
               seen: Bool = true) -> PhoneJointSample {
            PhoneJointSample(position: SIMD3<Float>(x, y, z), orientation: turn.vector, tracked: seen)
        }
        let headTurn = simd_quatf(angle: 0.55, axis: SIMD3<Float>(0, 1, 0))
        let lean = simd_quatf(angle: 0.14, axis: SIMD3<Float>(0, 0, 1))
        return PhoneBody(PhonePoseSample(
            tracked: true, timestamp: 0, scaleFactor: 0.95,
            joints: [
                .root: j(0, 0, 0), .hips: j(0, 0.02, 0),
                .spine: j(0, 0.25, 0, turn: lean), .chest: j(0.02, 0.42, 0, turn: lean),
                .neck: j(0.03, 0.52, 0), .head: j(0.04, 0.63, 0, turn: headTurn),
                .leftShoulder: j(-0.16, 0.46, 0), .leftElbow: j(-0.30, 0.24, 0.05),
                .leftWrist: j(-0.33, 0.02, 0.12, seen: false),
                .leftHand: j(-0.34, -0.06, 0.15, seen: false),
                .rightShoulder: j(0.19, 0.47, 0), .rightElbow: j(0.34, 0.60, -0.03),
                .rightWrist: j(0.36, 0.82, -0.05), .rightHand: j(0.36, 0.92, -0.06),
                .leftHip: j(-0.09, -0.04, 0), .leftKnee: j(-0.11, -0.46, 0.12),
                .leftAnkle: j(-0.12, -0.84, 0.02), .leftFoot: j(-0.12, -0.90, 0.14),
                .rightHip: j(0.09, -0.04, 0), .rightKnee: j(0.10, -0.48, -0.10),
                .rightAnkle: j(0.11, -0.88, -0.16), .rightFoot: j(0.11, -0.92, -0.04),
            ]))
    }

    lazy var body = Self.stagedBody()

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0, -0.12, 0), radius: 3.4,
                         azimuth: 0, elevation: 0.12, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.0).lightingOnly())

        let xs: [Double] = [-0.85, 0.85]
        // Left: the joints as dots, the way LiftedPose and the first body slice draw.
        withState {
            translate(xs[0], 0, 0)
            drawPointCloud(body.cloud(jointSize: 0.045, boneSize: 0.016, color: seenColor))
        }
        // Right: the same pose worn by solids, each part stood at its joint.
        withState {
            translate(xs[1], 0, 0)
            drawMannequin()
        }

        drawLabels(at: xs)
    }

    private func drawMannequin() {
        let s = body.scaleFactor
        for (a, b) in PhoneBody.skeleton {
            guard let pa = body.position(a), let pb = body.position(b) else { continue }
            let seen = body.isJointTracked(a) && body.isJointTracked(b)
            withState {
                material(.clay)
                fill(seen ? seenColor : filledColor)
                drawCapsule(from: pa, to: pb, radius: 0.032 * s)
            }
        }
        part(at: .spine) {
            drawRoundedBox(width: 0.30 * s, height: 0.34 * s, depth: 0.16 * s, radius: 0.05 * s)
        }
        part(at: .head) {
            drawSphere(radius: 0.11 * s)
            translate(0, 0.02 * s, 0.10 * s)
            drawSphere(radius: 0.035 * s)
        }
        for hand: PhoneJoint in [.leftHand, .rightHand] {
            part(at: hand) {
                drawRoundedBox(width: 0.05 * s, height: 0.11 * s, depth: 0.03 * s, radius: 0.012 * s)
            }
        }
    }

    /// One solid part stood at a joint: the joint's pose goes onto the stack whole.
    private func part(at joint: PhoneJoint, _ piece: () -> Void) {
        guard let pose = body.modelTransform(joint) else { return }
        withState {
            material(.clay)
            fill(body.isJointTracked(joint) ? seenColor : filledColor)
            transform(pose)
            piece()
        }
    }

    private func drawLabels(at xs: [Double]) {
        withState {
            noStroke()
            fill(Color(white: 0.82))
            textFont(OutlineFont.system)
            textSize(19)
            textAlign(.center)
            let captions = ["the joints, as dots", "the same pose, worn by solids"]
            for (i, caption) in captions.enumerated() {
                drawText(caption, at: Vector2(width * (i == 0 ? 0.27 : 0.73), 452))
            }
            textSize(16)
            let cy = 488.0
            fill(seenColor)
            drawCircleMarker(at: Vector2(width * 0.5 - 190, cy - 5))
            fill(Color(white: 0.7))
            textAlign(.left)
            drawText("seen by the camera", at: Vector2(width * 0.5 - 176, cy))
            fill(filledColor)
            drawCircleMarker(at: Vector2(width * 0.5 + 40, cy - 5))
            fill(Color(white: 0.7))
            drawText("filled in by the rig", at: Vector2(width * 0.5 + 54, cy))
        }
    }

    private func drawCircleMarker(at p: Vector2) {
        drawCircle(p.x, p.y, 7)
    }
}
